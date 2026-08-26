# NestJS Coding-Agent Guideline

This document is the NestJS-specific companion to the JavaScript and TypeScript engineering guideline. The language guideline remains authoritative for TypeScript safety, naming, formatting, dependency hygiene, general security, and agent workflow. This document adds Nest application architecture and operations without repeating that baseline.

The terms **MUST**, **SHOULD**, and **AVOID** are normative.

## 1. Scope and Version Discovery

Before changing code, the agent MUST discover the application actually in use rather than assuming current Nest defaults.

- Read repository instructions, `package.json`, the lockfile, `nest-cli.json`, all applicable TypeScript configurations, lint/format/test configuration, ORM schema, container files, and deployment entry points.
- Identify the installed major versions of Node.js, Nest core and platform adapter, Swagger, Config, Passport/JWT, Prisma, test runner, logger, scheduler, throttler, and health libraries. APIs and defaults differ between major versions.
- Determine the package manager from the lockfile and use it consistently.
- Determine whether the repository is a standard application, monorepo, library, microservice, hybrid application, serverless handler, or combination.
- Find every runtime entry point and trace its bootstrap path. Check HTTP, workers, scheduled jobs, command-line processes, microservices, and serverless adapters.
- Determine the HTTP adapter (Express or Fastify) before selecting middleware, upload tooling, request/response types, or adapter-specific APIs.
- Inspect existing global prefixing, URI/header/media-type versioning, validation, serialization, filters, guards, interceptors, logging, CORS, and shutdown behavior before editing them.
- Inspect the public HTTP contract and migration history before changing a DTO, status, envelope, database field, or route.
- Prefer APIs documented for the installed major version. The agent MUST NOT silently upgrade Nest, Prisma, Node.js, or an adapter as part of an unrelated task.

When requirements conflict with an established public contract, preserve compatibility or explicitly implement and document a versioned migration.

## 2. Bootstrap Once, Adapt Across Runtimes

All runtimes MUST share one application configuration function. Do not copy security, pipes, filters, Swagger, CORS, prefixes, or logger setup between `main.ts`, a serverless entry point, tests, and workers.

```ts
// bootstrap/configure-app.ts
export function configureApp(app: INestApplication, config: AppConfig): void {
  app.useLogger(app.get(Logger));
  app.setGlobalPrefix(config.apiPrefix);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );
  app.enableCors(corsOptions(config));
  app.enableShutdownHooks();
}

// main.ts
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  configureApp(app, app.get(APP_CONFIG));
  await app.listen(app.get(APP_CONFIG).port, "0.0.0.0");
}

void bootstrap();
```

- Shared setup MUST be idempotent and receive validated configuration or resolve it through DI.
- Runtime adapters SHOULD only create/cache the app, call shared setup, initialize or listen, and expose the required handler.
- Serverless initialization MUST be cached safely so warm invocations do not rebuild the DI container. It MUST not call `listen()`.
- E2E tests MUST call the same shared setup so production-only global behavior is tested.
- Workers and microservices MUST reuse relevant configuration while omitting HTTP-only middleware deliberately.
- Bootstrap failures MUST be logged once and terminate a process runtime with a non-zero exit. Do not swallow initialization errors.
- Graceful shutdown MUST stop accepting work, allow bounded in-flight completion, close consumers/schedulers, and release database and provider connections. Account for the hosting platform's termination model.
- A feature that must run only in one replica or runtime MUST have explicit deployment ownership or distributed coordination; module initialization is not leader election.
- AVOID reading `process.env` directly throughout bootstrap or at module evaluation time.

## 3. Modules, Dependency Injection, and Provider Lifecycle

### Module boundaries

- Each feature module MUST own a cohesive business capability, its controller(s), application service(s), and internal adapters.
- A module MUST export only tokens that other modules genuinely consume. Providers are private by default.
- Import the module that owns a provider; do not redeclare the same provider in each consuming module.
- Shared infrastructure modules SHOULD expose narrow capabilities. A generic “common” module MUST NOT become a dumping ground.
- `@Global()` MUST be reserved for truly application-wide infrastructure such as validated configuration or the primary logger. Feature services MUST NOT be global.
- Circular dependencies indicate misplaced ownership. Refactor toward an explicit port, domain event, or orchestration service before considering `forwardRef()`.
- Dynamic modules SHOULD use `register`/`registerAsync` and opaque injection tokens when configuration varies by consumer.

### DI rules

- Constructor injection is the default. Dependencies SHOULD be `private readonly`.
- Inject abstractions/tokens at replaceable boundaries such as clocks, mail, object storage, queues, and external APIs.
- Use `useValue` for immutable values, `useFactory` for constructed values, `useExisting` for aliases, and `useClass` only when class substitution is intended.
- AVOID service locator patterns (`ModuleRef.get` from normal business code), manual `new` for injectable dependencies, barrel-file cycles, and string tokens likely to collide. Prefer exported symbols.
- Global enhancers requiring DI MUST be registered with `APP_GUARD`, `APP_PIPE`, `APP_FILTER`, or `APP_INTERCEPTOR`, not instantiated manually outside the container.

### Lifecycle and scope

- Providers are singleton-scoped by default and MUST be safe for concurrent requests. Never store request/user/mutable workflow state on a singleton.
- Request-scoped providers MUST be exceptional: they propagate scope, increase allocation, and complicate jobs and tests. Prefer explicit request context parameters or AsyncLocalStorage where justified.
- Transient providers SHOULD be used only when each consumer needs independent state.
- Resource-owning providers MUST implement the appropriate lifecycle hooks and make startup/shutdown safe and bounded.
- `onModuleInit` MUST NOT perform unbounded remote work or destructive actions. Readiness should remain false until mandatory dependencies are usable.

## 4. Feature Structure

Prefer vertical feature ownership over top-level folders containing every controller or every service.

```text
src/
  bootstrap/
  config/
  infrastructure/
    database/
    logging/
  features/
    accounts/
      accounts.module.ts
      accounts.controller.ts
      accounts.service.ts
      dto/
      policies/
      repositories/
      accounts.service.spec.ts
```

- Keep transport DTOs, policies, tests, and persistence adapters near the feature they serve.
- Cross-feature orchestration SHOULD live in a clearly owned application service, not in a controller.
- Extract shared code only after the shared concept and owner are clear.
- Preserve an established repository layout when it already enforces equivalent boundaries; do not perform a broad relocation for aesthetics.

## 5. Controllers and Services

Controllers are transport adapters.

- Controllers MUST handle decorators, validated input, authenticated context, status codes, headers, and mapping to response DTOs.
- Controllers MUST delegate business decisions, persistence, hashing, and provider calls.
- Use typed `@Body()`, `@Param()`, `@Query()`, `@Headers()`, and authenticated-principal decorators. AVOID `any`, raw `@Request()`, and raw adapter response objects.
- Use standard Nest return values. `@Res()`/`@Response()` without passthrough takes over response handling and bypasses normal interceptors/serialization; use it only for streaming, redirects, or adapter-specific requirements.
- Route ordering and parameter patterns MUST prevent a dynamic route such as `:id` from capturing a fixed route.
- Status codes MUST match semantics: `201` creation, `202` accepted asynchronous work, `204` no body, `400` malformed input, `401` missing/invalid authentication, `403` authenticated but forbidden, `404` absent resource, and `409` state conflict.
- Services MUST express use cases and enforce invariants independent of HTTP. They SHOULD accept domain-oriented input rather than request/response objects.
- A service MUST not return password hashes, reset-token material, or ORM records containing hidden fields to a controller.
- Split oversized services by capability or boundary, not arbitrary line count. AVOID pass-through “service” layers with no policy, mapping, or ownership value.

## 6. DTOs, Runtime Validation, and Transformation

TypeScript types disappear at runtime. Swagger metadata is documentation, not validation.

- Every untrusted boundary MUST have runtime validation: body, query, path, headers, cookies, files, webhooks, messages, and configuration.
- Choose one coherent validation approach per boundary: class DTOs with `class-validator`/`class-transformer`, a schema pipe (for example Zod), or an established equivalent.
- A global validation pipe MUST reject or strip unknown fields deliberately. For mutation endpoints, prefer rejecting unexpected fields.
- Transformation MUST be explicit. Do not rely on truthiness or broad implicit conversion for booleans, dates, enums, arrays, or identifiers.
- Parse route parameters with specific pipes such as `ParseUUIDPipe`, `ParseIntPipe`, or a validated custom pipe.
- Query pagination MUST define bounds and defaults. List filters MUST reject invalid sort fields and directions.
- Nested class DTOs require nested validation and transformation metadata. Schema-based DTOs require equivalent nested schemas.
- Date/time contracts MUST specify accepted format and timezone. JSON request/response dates are strings; convert them intentionally.
- Create, update, query, internal command, and response DTOs SHOULD be distinct. Patch DTOs may derive from create DTOs only when every inherited rule remains correct.
- DTOs MUST NOT expose client-controlled fields such as role, owner ID, approval state, password hash, or audit timestamps when the server owns them.
- Validation errors MUST follow the documented public error contract and MUST NOT echo secrets.

```ts
export class ListItemsQueryDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 20;
}
```

## 7. Swagger and OpenAPI

- The generated OpenAPI document MUST describe actual runtime behavior: paths, prefix/version, security, content types, validation constraints, nullability, pagination, status codes, and error bodies.
- Define request and response DTOs explicitly. Do not document ORM entities or use `any` schemas.
- Use `@ApiPropertyOptional` for optional fields and ensure runtime optionality agrees. Add enum, format, minimum/maximum, array, and nested-type metadata where inference is insufficient.
- Security scheme names in `DocumentBuilder` and `@ApiBearerAuth()` MUST match exactly.
- Role or ownership rules belong in descriptions and guards; a client-provided role header is not authorization.
- Swagger setup SHOULD use validated server URLs. Access to interactive docs SHOULD be disabled or protected in production according to risk.
- AVOID remote custom JavaScript/CSS for documentation unless required and governed by the content-security policy and supply-chain policy.
- CI SHOULD generate and validate the OpenAPI document. Contract-sensitive systems SHOULD diff it and fail on unapproved breaking changes.
- Examples MUST be fictional, non-secret, and valid against the schema.

## 8. Authentication and Authorization

### Guards and principals

- Authentication MUST run before authorization. Prefer one composable policy: public-route metadata, authentication guard, then role/permission/ownership checks.
- A guard MUST deny by default when required metadata or principal data is malformed.
- Use `Reflector.getAllAndOverride` or `getAllAndMerge` intentionally for class- and method-level metadata.
- Role checks MUST test whether the principal has at least one required role. Roles SHOULD be typed constants/enums, not scattered strings.
- Ownership MUST be checked against the loaded resource or a constrained query. Never trust owner/user IDs from the body, query, or header.
- For sensitive operations, fetch the current principal or authorization version from trusted storage when stale token claims could grant continued access.
- Expose a small typed principal (`subject`, roles/permissions, session identifier), not an entire database user or JWT payload.

```ts
const record = await prisma.record.findFirst({
  where: { id: recordId, ownerId: principal.subject },
});
if (!record) throw new NotFoundException();
```

This constrained lookup avoids leaking whether another user's resource exists. Use `ForbiddenException` instead when the contract deliberately distinguishes existence from permission.

### JWT and sessions

- JWT verification MUST pin the expected algorithm and validate issuer, audience, signature, and expiration as applicable.
- Secrets/keys and expirations MUST come from validated typed configuration through async module registration.
- Access-token payloads MUST be minimal. Never include password hashes, sensitive profile data, or mutable authorization state without a revocation/version strategy.
- Use distinct keys or strict `typ`/audience validation for access, refresh, email-verification, and password-reset tokens. One token class MUST NOT be accepted as another.
- Refresh tokens SHOULD be rotated, stored only as hashes, bound to a session, and revoked on logout, password change, compromise, or reuse detection.
- If tokens use cookies, apply `httpOnly`, `secure`, appropriate `sameSite`, narrow path/domain, and CSRF protection where needed. If tokens use authorization headers, document that contract consistently.
- Authentication failures SHOULD avoid account enumeration and SHOULD use timing-safe credential verification patterns.

### Password reset

- Reset requests MUST return the same observable response whether the account exists or not.
- Reset codes/tokens MUST be random, short-lived, single-use, rate-limited, and stored hashed when server-side state is used.
- A successful password reset MUST hash the new password with the approved adaptive algorithm, invalidate the reset grant, and SHOULD revoke existing sessions.
- Never log or return reset codes/tokens except through the intended delivery/verification flow.
- Side effects such as email SHOULD be queued or bounded; failures must not reveal account existence.

## 9. Prisma and Persistence Integration

This section governs Nest integration; schema design and general database rules remain in the language guideline.

- Provide one process-level `PrismaClient` through an infrastructure/database module. Feature modules MUST inject that provider instead of creating clients.
- Connect/disconnect through lifecycle hooks appropriate to the installed Prisma version and runtime. Serverless runtimes MUST reuse the client across warm invocations.
- In development hot reload, follow the repository's established safe singleton strategy to avoid connection exhaustion.
- Services SHOULD select only required fields. Public response mapping MUST explicitly exclude secrets.
- Translate known Prisma errors at the persistence/application boundary: unique conflicts to `409`, missing records to `404` where appropriate, and malformed requests to `400`. Unknown database errors remain internal `500` errors.
- Never expose Prisma codes, SQL, stack traces, or raw metadata to clients. Preserve the original error as a logged cause with safe context.
- Multi-write invariants MUST use `$transaction`. Every participating write MUST use the transaction client, not the root client.

```ts
await prisma.$transaction(async (tx) => {
  await tx.account.update({ where: { id }, data: { balance: { decrement: sum } } });
  await tx.ledgerEntry.create({ data: { accountId: id, amount: sum } });
});
```

- Keep interactive transactions short. Do not send email, upload files, call HTTP providers, or wait on queues inside them. Use an outbox or post-commit workflow for reliable side effects.
- Concurrency-sensitive changes MUST use constraints, atomic operations, isolation/locking where supported, or optimistic concurrency. A read-then-write check alone is not safe.
- Pagination MUST use deterministic ordering and a stable tie-breaker. Prefer cursor pagination for large/changing datasets.
- Migration files already applied to any shared environment MUST NOT be edited. Create a new descriptively named migration.
- Development may use migration creation; CI/staging/production MUST use non-interactive migration deployment. `db push` MUST NOT replace migration deployment in shared environments.
- Destructive migrations MUST use an expand/backfill/contract plan and account for old and new application versions during rollout.
- Prisma generation MUST occur deterministically during install/build or CI as established by the repository. Do not commit generated clients unless repository policy requires it.
- Seeders MUST be explicit, idempotent where practical, environment-safe, and unable to load production secrets or destructive sample data accidentally.

## 10. Typed Configuration

- Environment variables MUST be validated once at startup and transformed into a typed configuration object.
- Required values MUST fail fast. Parse ports, durations, booleans, URL lists, log levels, and byte limits; do not leave them as unchecked strings.
- Use `ConfigModule.forRoot({ isGlobal: true, cache: true, validate })` or a typed `registerAs`/`ConfigType` equivalent.
- Feature modules SHOULD inject their configuration namespace or an opaque typed token rather than repeatedly requesting arbitrary strings.
- Use `getOrThrow` when string-key access is unavoidable. The argument is the configuration key, never the environment value.
- AVOID `process.env` outside the configuration/bootstrap boundary and AVOID reading it during module import before validation.
- Secrets MUST NOT have insecure production defaults, appear in source, logs, Swagger examples, test snapshots, image layers, or client-visible responses.
- Configuration MUST distinguish build-time and runtime concerns. Deployments MUST document which values are required before boot.

```ts
export const authConfig = registerAs("auth", () => ({
  issuer: process.env.JWT_ISSUER!,
  audience: process.env.JWT_AUDIENCE!,
  secret: process.env.JWT_SECRET!,
}));

type AuthConfig = ConfigType<typeof authConfig>;
```

The non-null assertions above are acceptable only behind startup schema validation; otherwise they are forbidden.

## 11. Exceptions, Filters, and Response Contracts

- Throw Nest semantic exceptions or typed application errors; do not throw generic `Error` for expected client outcomes or construct arbitrary numeric `HttpException`s throughout services.
- One global exception filter SHOULD normalize errors into a stable response contract while retaining Nest's standard fields when compatibility requires them.
- The contract SHOULD contain a stable machine-readable code, human-safe message, status, request/correlation ID, and structured field errors when relevant.

```json
{
  "statusCode": 422,
  "code": "VALIDATION_FAILED",
  "message": "The request is invalid.",
  "errors": [{ "field": "email", "code": "INVALID_EMAIL" }],
  "requestId": "..."
}
```

- A filter MUST handle both string and object payloads returned by `HttpException.getResponse()`.
- Unknown exceptions MUST return a generic `500` response and be logged with stack/cause exactly once.
- Filters MUST not import adapter-specific response types unless the application intentionally targets that adapter.
- Preserve status codes and headers such as `Retry-After` from throttling or upstream translation.
- Response serialization SHOULD use explicit response DTOs/mappers. If `ClassSerializerInterceptor` is used, verify nested objects and plain ORM records are actually transformed.
- Success envelopes MUST be consistent. Do not put a second status code inside a body unless it is part of an existing contract.
- AVOID broad `@Catch()` filters that convert every error to `500`, duplicate logging at every layer, or expose `exception.message` for unknown errors.

## 12. Logging, Metrics, Health, and Jobs

### Pino and logging

- Use Nest's logger abstraction backed by Pino (or the repository's structured logger) and buffer early bootstrap logs until it is installed.
- Logs MUST be structured and include operation, request/correlation ID, stable entity IDs, outcome, duration, and safe error context.
- Request IDs SHOULD accept only a trusted/validated upstream header or generate a new ID, then return it in the response.
- Configure redaction for authorization, cookies, passwords, tokens, API keys, and sensitive body fields. AVOID logging request/response bodies by default.
- Production SHOULD emit machine-readable JSON; local pretty printing must be a development-only transport and dependency.
- Avoid high-volume duplicate success logs and `console.*` in application code.

### Metrics

- Record request count, duration, and status using bounded labels such as method, route template, and status class/code.
- Metrics MUST use the matched route template, not raw URLs or identifiers. Never label by user, email, token, error message, or unbounded tenant ID.
- Observe both successful and failed/cancelled requests. Exclude or deliberately account for the metrics endpoint itself.
- Business metrics SHOULD represent decisions and outcomes, not implementation call counts.

### Health and readiness

- Liveness MUST answer whether the process/event loop is alive and MUST not depend on every remote service.
- Readiness MUST answer whether this instance can serve traffic and may check mandatory dependencies with strict timeouts.
- Startup health SHOULD remain unready through migrations/warm-up when those are prerequisites.
- Health responses MUST not expose credentials, connection strings, raw provider errors, or infrastructure internals.
- Kubernetes/container probes and shutdown timing MUST agree with the app's endpoint paths and grace periods.

### Scheduled and queued jobs

- Jobs MUST be idempotent or protected by a stable deduplication key.
- In multi-replica deployments, scheduling MUST use a distributed lock, a single scheduler deployment, or a queue with correct delivery semantics.
- Jobs MUST define timeout, retry/backoff, maximum attempts, and dead-letter/failure handling. Retries MUST distinguish transient from permanent failures.
- Pass minimal identifiers in job payloads and reload current state in the worker. Version long-lived payload contracts.
- Jobs MUST propagate correlation/trace context, log safe outcomes, and expose queue depth/failure/latency metrics.
- AVOID untracked fire-and-forget promises from controllers or cron handlers.

## 13. HTTP and Input Security

### Helmet, CORS, and throttling

- Helmet MUST be installed before routes. Disable an individual protection only for a documented compatibility reason; do not disable the entire content-security policy casually.
- CORS origins MUST come from validated configuration and use an explicit allowlist. Credentials MUST NOT be combined with wildcard origins.
- Allow only required methods and headers. `Set-Cookie` is a response header and does not belong in request `allowedHeaders`; exposing it does not make it readable to browser JavaScript.
- CORS is a browser policy, not authentication or authorization.
- Apply global baseline throttling and stricter named limits to login, reset, verification, registration, uploads, and expensive endpoints.
- Throttling SHOULD use a shared store in multi-instance deployments and a trustworthy client identity. Configure proxy trust narrowly before relying on forwarded IP headers.
- Return `429` with useful retry semantics without disclosing account existence.

### Uploads

- Set request, field, file-count, and per-file size limits at the adapter/multipart layer before buffering.
- Validate extension only as a hint; inspect MIME and file signature/magic bytes. Generate server-owned object names and prevent path traversal.
- Do not trust client filenames or place uploads in a publicly executable path.
- Prefer streaming/direct-to-object-storage workflows for large files. Clean temporary files on success, validation failure, provider failure, and cancellation.
- Apply authorization before accepting expensive upload work. Scan risky files and serve them with safe content disposition and content type.
- Store only required metadata and do not return provider credentials or privileged URLs. Signed URLs MUST be short-lived and scoped.
- Adapter-specific upload interceptors (for example Multer on Express) MUST not be used under another adapter without a compatible implementation.

## 14. Testing Strategy

Tests MUST verify behavior, contracts, and security boundaries rather than only provider construction.

### Unit tests

- Instantiate focused services with `Test.createTestingModule` or direct construction when DI behavior is irrelevant.
- Mock only true boundaries: repositories/Prisma facade, clock, randomness, mail, storage, queue, and external clients.
- Typed mocks MUST implement real methods and realistic return shapes. Reset state between tests.
- Cover success, validation/policy failure, missing data, conflicts, provider failure, and concurrency/idempotency rules relevant to the change.
- Guards MUST be tested for missing principal, malformed metadata, each allowed role/permission, denial, and class/method override behavior.

### Integration tests

- Test module wiring, validation pipes, filters, serialization, Prisma queries, constraints, and transaction behavior against disposable infrastructure where those are the risk.
- Use a separate test database with deterministic setup and isolation. Tests MUST never point at development or production data.
- Apply migrations to the test database rather than synthesizing a divergent schema.
- Provider integrations SHOULD use local fakes or contract fixtures, not live email/SMS/storage services.

### E2E tests

- Create the application through the production module and shared bootstrap configuration, then call `app.init()` and close it reliably.
- Use the adapter server with Supertest or the established equivalent.
- Cover representative public, authenticated, role-restricted, ownership-restricted, validation, throttling, upload, error-envelope, and health paths.
- Assert status, headers, and response shape. Avoid brittle assertions on irrelevant generated values.
- Override external providers through Nest testing APIs; do not alter production modules solely to make tests convenient.

### Test quality

- Time, random IDs, and token expiry SHOULD be controllable through injected clocks/randomness or fake timers.
- Security tests MUST verify that hidden fields, stack traces, and existence information do not leak.
- Transaction tests SHOULD prove rollback, not merely that `$transaction` was called.
- Keep unit tests parallel-safe; serialize only suites sharing unavoidable infrastructure.

## 15. Build, Docker, and CI

- Build with the lockfile's package manager and frozen/immutable install mode.
- The build MUST generate Prisma artifacts before TypeScript compilation when required and MUST compile every runtime entry point.
- `start:prod` MUST target the actual emitted entry file. CI SHOULD smoke-start the built artifact rather than relying only on TypeScript compilation.
- Container builds SHOULD use pinned supported Node.js images, multi-stage builds, `.dockerignore`, and a non-root runtime user.
- The runtime image MUST contain only production dependencies and required artifacts: compiled output, Prisma engine/client/schema or migrations when the deployment runs them, certificates, and declared assets.
- Do not copy source secrets, `.env` files, test fixtures with credentials, package-manager caches, or an unrestricted build context into the runtime image.
- Handle OS signals directly and avoid unnecessary shell wrappers. Define an application health check or platform probes matching actual endpoints.
- Run database migrations as a controlled release step or one-shot job, not concurrently in every application replica. Application startup MUST NOT create development migrations.
- CI MUST use service containers or isolated managed dependencies for integration tests and must provide only scoped test credentials.
- CI SHOULD run, in order where practical: immutable install, generated-code check, formatting check, lint without mutation, type-check/build, unit tests, integration/E2E tests, migration validation, OpenAPI validation, vulnerability/license policy checks, and container build/smoke scan.
- Cache package downloads, not mutable `node_modules` across incompatible Node.js/platform versions.
- Generated output and coverage MUST follow repository policy and MUST NOT be committed accidentally.

## 16. Anti-Patterns

AVOID all of the following:

- Duplicated bootstrap configuration across HTTP, serverless, tests, or workers.
- Controllers containing business rules, Prisma calls, password hashing, transactions, or provider orchestration.
- DTO classes decorated only for Swagger and assumed to be validated.
- `any` for request users, responses, exception filters, metrics interceptors, or provider payloads.
- Reading `process.env` in strategies/services or passing an environment value into `ConfigService.get()` as though it were a key.
- Registering the same database/provider service in many modules, producing multiple clients.
- Global feature modules and catch-all shared modules.
- Circular imports hidden with `forwardRef()` instead of corrected ownership.
- Request-scoped providers used as a default request-context mechanism.
- Client-controlled role, owner, status, price, audit, or security fields.
- JWTs containing full user records, password material, or reset grants accepted as access tokens.
- Authentication without resource-level authorization.
- Long-lived/reusable plaintext reset codes or different reset responses for existing and absent accounts.
- Mutating request DTOs to construct persisted data.
- Catching errors only to throw generic `500` errors, losing status and cause.
- Returning raw Prisma/provider errors or ORM records from controllers.
- External network calls inside database transactions.
- Raw request paths, user IDs, or error messages as metric labels.
- In-memory throttling, job locks, OTPs, or session state treated as shared in a multi-instance deployment.
- Cron jobs running once per replica without coordination.
- Unbounded uploads buffered in memory and trusted by MIME/extension alone.
- Wildcard credentialed CORS, broad proxy trust, disabled Helmet protections without rationale, or Swagger exposed by accident.
- Unit tests that assert only `toBeDefined()`, mock the subject under test, or call live providers.
- Editing applied migrations, using `db push` in production, or running migration creation at application startup.
- Shipping development dependencies, secrets, or root execution in the runtime container.

## 17. Completion Checklist

Before declaring a NestJS change complete, the agent MUST confirm:

### Discovery and design

- [ ] Applicable instructions, versions, adapter, runtimes, scripts, and public contracts were identified.
- [ ] The change belongs to the selected module/layer and does not introduce a circular or global dependency.
- [ ] Every runtime uses the same relevant bootstrap behavior.

### Contracts and security

- [ ] Every new external input is runtime-validated and transformed deliberately.
- [ ] DTO validation, Swagger schemas, response DTOs, status codes, and actual behavior agree.
- [ ] Authentication, roles/permissions, and ownership are all enforced where required.
- [ ] Secrets, hidden fields, tokens, PII, ORM errors, and stack traces cannot leak through responses or logs.
- [ ] CORS, Helmet, throttling, uploads, cookies, and proxy behavior remain secure for the deployment topology.

### Data and operations

- [ ] Prisma uses the injected lifecycle-managed client and explicit safe selects.
- [ ] Atomic workflows use a transaction correctly; external effects are outside it or use an outbox.
- [ ] Migrations are additive/rollout-safe, descriptively named, and deployment-compatible.
- [ ] Logs are structured/redacted; metrics have bounded cardinality; health semantics are correct.
- [ ] Jobs are idempotent, bounded, observable, and coordinated across replicas.
- [ ] Startup and graceful shutdown work in each affected runtime.

### Tests and delivery

- [ ] Focused unit tests cover changed policies and failure paths.
- [ ] Integration/E2E tests cover affected wiring, validation, authorization, persistence, and contract behavior.
- [ ] Test infrastructure is isolated and no live provider or non-test database was used.
- [ ] Built artifacts and container entry points match deployment configuration.
- [ ] The diff contains no unrelated formatting, generated debris, debug logging, secrets, or accidental migration edits.

## 18. Verification

Use repository scripts and the lockfile package manager. Prefer non-mutating final checks; never use lint auto-fix as verification.

```bash
# Replace these with repository-defined equivalents.
pnpm exec prettier --check "src/**/*.ts" "test/**/*.ts"
pnpm exec eslint "{src,test,apps,libs}/**/*.ts"
pnpm exec tsc --noEmit
pnpm test -- --runInBand
pnpm run test:e2e
pnpm run build
```

Depending on the change, also verify:

- application startup and graceful shutdown from compiled output;
- OpenAPI generation and contract diff;
- test-database migration from empty and upgrade from the supported prior state;
- transaction rollback and concurrent conflict behavior;
- production container build, non-root user, entry point, health probe, and signal handling;
- both cold and warm behavior for a serverless entry point;
- liveness/readiness under dependency failure;
- scheduler/worker deduplication and retry behavior;
- upload rejection for oversized, malformed, spoofed, and unauthorized files;
- redaction and metric label cardinality with representative requests.

Run focused checks first, then the broadest checks warranted by the blast radius. If a required check cannot run, report the exact command, reason, and remaining risk. Completion means the implementation, public contract, security controls, tests, operations, and deployment artifact agree—not merely that compilation succeeds.
