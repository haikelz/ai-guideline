# Echo HTTP Service Coding-Agent Guideline

This document is the Echo-specific companion to the Go coding-agent guideline.
The Go guide remains authoritative for language style, package design, context,
errors, concurrency, resource ownership, and general verification. Use the GORM
and PostgreSQL companion when the service uses that persistence stack. This guide
adds rules for building and changing HTTP services with
`github.com/labstack/echo/v4`. Apply repository-local contracts and instructions
first.

## 1. Scope and Operating Principles

- Echo is a transport adapter, not the application architecture.
- Public routes, methods, status codes, headers, JSON fields, error envelopes, and authentication behavior are compatibility contracts.
- External input is untrusted. Parsing, validation, authentication, authorization, and limits MUST happen before business effects.
- Startup and shutdown are part of correctness. A server that starts hidden workers or cannot stop resources cleanly is incomplete.
- Middleware order is executable policy. It MUST be deliberate, documented by tests where security depends on it, and changed only with impact analysis.
- Existing weak patterns MUST NOT be copied merely for consistency. Preserve required behavior while moving new code toward these rules.

## 2. Architecture and Wiring

Use the dependency direction defined in the Go guide:

```text
Echo route/handler -> use-case interface -> domain/repository interfaces -> adapters
                              ^
                       composition root
```

### MUST

- Keep `echo.Context` inside the delivery layer. New use-case, repository, and provider methods MUST accept `context.Context`, usually from `c.Request().Context()`.
- Construct databases, caches, providers, use cases, handlers, middleware dependencies, and background resources in a composition root.
- Inject narrow interfaces into handlers. Handler constructors MUST fail early or panic only for programmer errors such as a required nil dependency; runtime request failures MUST return errors.
- Separate server construction from process execution so tests can build the complete router without binding a port, contacting live providers, running migrations, or starting workers.
- Keep route registration deterministic and free of network, database, filesystem, migration, and background-job side effects.
- Return owned closers or shutdown functions from wiring when components require cleanup.

### SHOULD

- Use a small application structure such as:

```text
cmd/api/main.go                  process lifecycle only
internal/app/wire.go             dependency composition
internal/httpserver/server.go    Echo construction and middleware
internal/httpserver/routes.go    top-level route groups
internal/<domain>/delivery/http  handlers and transport DTOs
```

- Split an oversized composition root into domain registration functions that receive explicit dependencies and route groups.
- Make a router factory usable by tests:

```go
type Dependencies struct {
	Logger  *slog.Logger
	Account account.UseCase
}

func NewServer(cfg Config, deps Dependencies) (*echo.Echo, error) {
	if deps.Logger == nil || deps.Account == nil {
		return nil, errors.New("missing HTTP server dependency")
	}

	e := echo.New()
	configureEcho(e, cfg, deps.Logger)
	registerRoutes(e, deps)
	return e, nil
}
```

### AVOID

- Creating repositories or provider clients in handlers.
- Global mutable Echo instances, loggers, validators, keys, rate limiters, or clients.
- Passing a database handle to every handler when a use-case interface is sufficient.
- Starting the full process merely to inspect routes or generate documentation.
- Route constructors that silently register cron jobs, open consumers, or write route inventories.

## 3. Echo Construction and HTTP Server Settings

Construction MUST be explicit and centralized. Set the validator, binder if customized, error handler, debug/banner behavior, middleware, routes, and `http.Server` limits before serving.

```go
func configureEcho(e *echo.Echo, cfg Config, logger *slog.Logger) {
	e.HideBanner = true
	e.HidePort = true
	e.Debug = false
	e.Validator = NewValidator()
	e.HTTPErrorHandler = NewHTTPErrorHandler(logger)

	e.Server.ReadHeaderTimeout = cfg.ReadHeaderTimeout
	e.Server.ReadTimeout = cfg.ReadTimeout
	e.Server.WriteTimeout = cfg.WriteTimeout
	e.Server.IdleTimeout = cfg.IdleTimeout
	e.Server.MaxHeaderBytes = cfg.MaxHeaderBytes
}
```

### MUST

- Configure a nonzero `ReadHeaderTimeout`; `ReadTimeout` alone is not a complete slow-header defense.
- Configure bounded read, write, and idle timeouts appropriate to normal requests and known streaming endpoints.
- Set a finite maximum header size.
- Disable debug output in production and avoid exposing framework internals.
- Validate configuration before constructing the server. Invalid durations, limits, origins, keys, or proxy settings MUST fail startup.
- Configure trusted proxy behavior before relying on `RealIP()` for security, auditing, or rate limiting. Trust only known proxy hops and reject spoofable forwarding headers.

### SHOULD

- Use a dedicated listener and `e.StartServer(server)` when custom TLS, base context, or listener control is needed.
- Expose separate liveness and readiness handlers. Liveness SHOULD not depend on fragile downstream systems; readiness SHOULD reflect whether the instance can safely receive traffic.
- Keep health endpoints cheap and redact dependency details from public responses.

### AVOID

- Wildcard timeout values or no timeouts.
- Treating `Recover` as a substitute for eliminating panics.
- Calling `log.Fatal` from reusable server packages; return startup errors to `main`.
- Writing files or mutating schema during API startup unless the explicit deployment contract requires it.

## 4. Deterministic Routes and Groups

Routes MUST be reviewable as a stable API surface. Use explicit groups for versioning and shared policy.

```go
func registerRoutes(e *echo.Echo, deps Dependencies) {
	e.GET("/live", live)
	e.GET("/ready", ready(deps.Readiness))

	v1 := e.Group("/v1")
	public := v1.Group("/public")
	protected := v1.Group("/account", deps.Authenticate)
	protected.Use(deps.RequireActivePrincipal)

	registerPublicRoutes(public, deps)
	registerAccountRoutes(protected, deps)
}
```

### MUST

- Use leading slashes consistently and one canonical path per contract unless aliases are intentional.
- Register the same route set for the same configuration. Any environment-gated diagnostic or documentation route MUST be explicit and tested in both states.
- Apply authentication and other group middleware at the narrowest correct group. Public endpoints MUST not accidentally inherit protected middleware, and protected endpoints MUST not be registered outside it.
- Treat route order as significant when wildcard and parameterized routes overlap. Register specific routes before catch-all routes.
- Preserve trailing-slash behavior intentionally; configure redirect/remove-slash middleware only after checking clients and signatures.
- Detect duplicate method/path registration and maintain a route contract test or generated inventory without running live dependencies.

### SHOULD

- Group by API version and security policy, then delegate registration by domain.
- Give routes stable names when metrics, authorization policy, or reverse URL generation depends on them.
- Sort generated route inventories before comparison because discovery output order should not create noisy diffs.

### AVOID

- Conditional registration based on nondeterministic state.
- A single giant route file that constructs every domain inline.
- Catch-all routes that shadow API or documentation endpoints.
- Using route path strings as the sole authorization policy.

## 5. Middleware Order

Echo middleware is registered outer-to-inner according to Echo's execution model; response unwinding occurs in reverse. Confirm behavior with a focused test rather than assuming another framework's semantics.

A representative global policy is:

```go
e.Use(middleware.RequestID())
e.Use(RequestContextLogger(logger))
e.Use(middleware.Recover())
e.Use(SecurityHeaders(cfg.Security))
e.Use(middleware.CORSWithConfig(cfg.CORS))
e.Use(middleware.BodyLimit(cfg.MaxBodySize))
e.Use(RequestTimeout(cfg.RequestTimeout))
e.Use(AccessLog(logger))
e.Use(Metrics(meter))
```

Authentication and authorization usually belong on protected groups. Rate limiting may be global, per route class, or per authenticated principal; its position MUST match the intended key.

### MUST

- Have exactly one intentional CORS policy. Do not install both configured and default CORS middleware.
- Place panic recovery so panics from downstream middleware and handlers are converted to the standard error path and recorded without leaking stack traces.
- Create or accept a request ID early, validate its length/character set, and generate a trusted ID when absent or invalid.
- Ensure access logging records final status, latency, route template, response size, request ID, and error after downstream execution.
- Use the normalized route template, not the raw URL, for metric labels to avoid high-cardinality telemetry.
- Ensure body limits run before binding or multipart parsing.
- Test security-sensitive order, including CORS preflight, body-limit rejection, authentication, rate limiting, panic recovery, and error logging.

### SHOULD

- Skip compression for already compressed files, tiny bodies, streaming, and content types where compression creates security or performance risk.
- Skip noisy telemetry only through a narrow, reviewed skipper for liveness endpoints.
- Apply a request deadline globally, then use shorter dependency-specific deadlines where required. Exempt or separately configure streaming and long-running endpoints.

### AVOID

- Duplicated CORS, request logging, recovery, or metrics middleware.
- Reading the body in logging middleware without restoring it and enforcing a bound.
- Logging request or response bodies by default.
- Using untrusted client IP headers directly as limiter keys.
- In-memory rate limits when limits must be consistent across replicas.

## 6. Body, Header, and Time Limits

Limits MUST be layered because no single setting covers all resource-exhaustion paths.

### MUST

- Apply a global body limit and smaller route-specific limits for sensitive or naturally small payloads.
- Set `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout`, and `MaxHeaderBytes` on the underlying server.
- Bound multipart memory with `ParseMultipartForm(maxMemory)` and understand that excess parts may spill to temporary disk.
- Bound uploads independently of `multipart.FileHeader.Size`; enforce the size while reading with `io.LimitedReader` or `http.MaxBytesReader` semantics.
- Return `413 Payload Too Large` for body/upload limit violations and a stable error code.
- Propagate request cancellation. If a client disconnects or the request deadline expires, downstream I/O MUST stop where supported.

### SHOULD

- Set different deadlines for ordinary JSON, uploads, downloads, streaming, and webhooks.
- Return `408 Request Timeout` only when the request itself timed out according to the public contract; use `504 Gateway Timeout` for a bounded downstream timeout when appropriate.
- Account for reverse-proxy limits and ensure edge and application settings agree.

### AVOID

- Using `context.Background()` in a request path.
- Arbitrarily extending a canceled request context.
- Unbounded `io.ReadAll`, multipart parsing, decompression, JSON decoding, exports, or response buffering.
- Assuming a server write timeout safely supports every streaming response.

## 7. Request Context

`echo.Context` is pooled and valid only during the request. `context.Context` carries cancellation, deadlines, and request-scoped values across application boundaries.

### MUST

- Extract `ctx := c.Request().Context()` and pass it to use cases and I/O dependencies.
- Store only small request-scoped metadata such as a typed principal or correlation ID in context. Required business arguments SHOULD remain explicit parameters.
- Use collision-resistant private types for standard context keys.
- Never retain or use `echo.Context` after the handler returns, including from goroutines.
- Never mutate Echo context concurrently.

```go
func (h *Handler) Get(c echo.Context) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return err
	}

	item, err := h.useCase.Get(c.Request().Context(), id)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, ItemResponseFrom(item))
}
```

For work that must outlive a request, enqueue a durable command containing copied, validated values. A managed worker MUST own its independent context, retries, idempotency, and shutdown.

## 8. Binding, Validation, and Parameter Parsing

Echo's default binder can bind multiple sources into one struct. This is convenient but can create precedence and mass-assignment surprises. Prefer source-specific DTOs and explicit parsing for security-sensitive fields.

### MUST

- Use dedicated request DTOs. Never bind directly into persistence models or domain entities.
- Check every `Bind`, parse, and `Validate` error.
- Restrict accepted content types. JSON endpoints SHOULD reject unrelated media types with `415 Unsupported Media Type`.
- Treat unknown JSON fields deliberately. New strict APIs SHOULD reject them; compatibility-sensitive APIs MUST decide based on the existing contract.
- Validate syntactic constraints at the HTTP boundary and cross-field/business rules in the use case.
- Parse path and query values with explicit range checks. Invalid provided values MUST not silently become defaults.
- Distinguish absent optional values from explicit zero/false values with pointers or nullable types where semantics differ.
- Canonicalize values once and reject ambiguous duplicates where relevant, such as repeated authorization-sensitive query parameters.
- Cap pagination limits and use deterministic defaults.

```go
type CreateWidgetRequest struct {
	Name string `json:"name" validate:"required,min=1,max=120"`
}

func (h *Handler) Create(c echo.Context) error {
	if !strings.HasPrefix(c.Request().Header.Get(echo.HeaderContentType), echo.MIMEApplicationJSON) {
		return NewAPIError(http.StatusUnsupportedMediaType, "unsupported_media_type", "expected application/json")
	}

	var req CreateWidgetRequest
	if err := c.Bind(&req); err != nil {
		return NewAPIError(http.StatusBadRequest, "invalid_body", "request body is invalid").WithCause(err)
	}
	if err := c.Validate(&req); err != nil {
		return ValidationAPIError(err)
	}

	principal := PrincipalFromContext(c)
	widget, err := h.useCase.Create(c.Request().Context(), principal.ID, CreateWidgetCommand{
		Name: strings.TrimSpace(req.Name),
	})
	if err != nil {
		return err
	}
	return c.JSON(http.StatusCreated, WidgetResponseFrom(widget))
}
```

```go
func parsePositiveIntQuery(c echo.Context, name string, fallback, maximum int) (int, error) {
	raw := c.QueryParam(name)
	if raw == "" {
		return fallback, nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < 1 || v > maximum {
		return 0, NewAPIError(http.StatusBadRequest, "invalid_query", name+" is out of range")
	}
	return v, nil
}
```

### SHOULD

- Wrap `go-playground/validator` behind Echo's `Validator` interface and translate field errors to stable public field names.
- Avoid exposing Go struct names, validation tags, or translated internals in responses.
- Use a custom binder or direct `json.Decoder` when strict JSON, single-document enforcement, or source precedence matters.

### AVOID

- `value, _ := strconv.Atoi(...)` followed by a default.
- Trusting an owner ID, role, tenant, price, or server-managed field from the body.
- Binding path, query, and body into the same mutable struct when one source can overwrite another.
- Returning raw binder or validator messages to clients.
- Accepting trailing JSON documents unnoticed.

## 9. Thin Handlers and Use Cases

Handlers translate HTTP. Use cases own policy and orchestration.

### Handler responsibilities

1. Parse and validate transport input.
2. Retrieve the verified principal.
3. Invoke authorization middleware or pass identity and resource identifiers to policy-aware use cases.
4. Call one primary use-case operation.
5. Map output to a response DTO and return the documented status.

### MUST

- Keep database queries, transactions, provider selection, state transitions, and business thresholds out of handlers.
- Derive the acting principal from verified authentication state, not request input.
- Pass `context.Context`, typed IDs, and explicit commands to use cases.
- Map domain entities to response DTOs so internal and sensitive fields cannot leak accidentally.
- Make side effects and idempotency use-case concerns, not middleware accidents.

### SHOULD

- Keep handlers short enough that all transport decisions are visible without scrolling through business workflows.
- Share narrowly scoped parsing and response helpers; do not create a generic helper layer that hides control flow.

### AVOID

- A use case that accepts `echo.Context`.
- Returning GORM models directly.
- Calling several repositories from a handler to assemble a response.
- Starting fire-and-forget goroutines from a handler.
- Copying a legacy handler's ignored errors or broad `400` responses.

## 10. Responses and Error Mapping

Define one stable JSON error contract. Domain and infrastructure errors SHOULD be typed or wrapped so a centralized handler can map them with `errors.Is` and `errors.As`.

```go
type ErrorBody struct {
	Code      string            `json:"code"`
	Message   string            `json:"message"`
	RequestID string            `json:"request_id,omitempty"`
	Fields    map[string]string `json:"fields,omitempty"`
}

func NewHTTPErrorHandler(logger *slog.Logger) echo.HTTPErrorHandler {
	return func(err error, c echo.Context) {
		if c.Response().Committed {
			logger.ErrorContext(c.Request().Context(), "request failed after response commit", "error", err)
			return
		}

		apiErr := MapError(err)
		if apiErr.Status >= 500 {
			logger.ErrorContext(c.Request().Context(), "request failed", "error", err)
		}
		if writeErr := c.JSON(apiErr.Status, apiErr.Body(c.Response().Header().Get(echo.HeaderXRequestID))); writeErr != nil {
			logger.ErrorContext(c.Request().Context(), "write error response", "error", writeErr)
		}
	}
}
```

### MUST

- Map errors deliberately: malformed input to `400`, missing/invalid credentials to `401`, denied permission to `403`, absent resources to `404`, state/uniqueness conflicts to `409`, size violations to `413`, unsupported media to `415`, semantic validation to `422` if that is the contract, rate limits to `429`, and unexpected failures to `500`.
- Include `WWW-Authenticate` on applicable `401` responses and `Retry-After` when a meaningful value is available for `429` or temporary unavailability.
- Preserve the original error for server-side logs while returning a safe public message.
- Avoid writing a second response after `c.Response().Committed`.
- Use the correct success statuses: `201` for creation when appropriate, `202` for accepted asynchronous work, `204` with no body, and redirects only when intentional.
- Set cache headers deliberately for sensitive, user-specific, and downloadable responses.

### SHOULD

- Include a stable machine-readable code and request ID in errors.
- Centralize response-envelope construction without hiding status selection.
- Use `Location` on resource creation when a canonical URL exists.

### AVOID

- Returning `err.Error()` to clients.
- Mapping all use-case errors to `400` or `500`.
- Error string comparisons.
- Returning stack traces, SQL, provider payloads, filesystem paths, or token details.
- Sending a body with `204 No Content`.

## 11. JWT Authentication, Roles, and Ownership

JWT verification establishes token validity, not endpoint authorization.

### MUST

- Restrict accepted signing algorithms and validate signature, expiration, not-before, issuer, and audience as required by the trust model.
- Use separate verifier configurations for distinct issuers or principal classes. Do not choose a key from an untrusted claim without a constrained lookup policy.
- Convert library claims into one validated application `Principal` type in authentication middleware.
- Handle missing or malformed claims with checked conversions; never use panic-prone type assertions.
- Apply explicit permission or role checks to protected operations.
- Enforce resource ownership or tenant membership using trusted principal identity and persisted resource data. A matching role alone is insufficient for owner-scoped resources.
- Derive actor IDs from the principal. Ignore or reject client-supplied actor IDs.
- Return `401` for absent/invalid authentication and `403` for an authenticated principal lacking permission.
- Test missing token, malformed token, wrong algorithm, expired token, wrong issuer/audience, wrong role, wrong owner, disabled principal, and valid access.

```go
type Principal struct {
	ID          uuid.UUID
	Permissions map[string]struct{}
}

func RequirePermission(permission string) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			principal, ok := PrincipalFromContextOK(c)
			if !ok {
				return NewAPIError(http.StatusUnauthorized, "unauthenticated", "authentication required")
			}
			if _, ok := principal.Permissions[permission]; !ok {
				return NewAPIError(http.StatusForbidden, "forbidden", "access denied")
			}
			return next(c)
		}
	}
}
```

### SHOULD

- Keep token parsing in middleware and fine-grained ownership policy in the use case where persisted state is available.
- Prefer capabilities/permissions over scattered role-name string checks.
- Consider revocation, key rotation, and maximum token age for high-risk operations.

### AVOID

- Treating successful JWT middleware as sufficient authorization.
- Trusting a role or owner field from query/body input.
- Logging bearer tokens or complete claims.
- Returning different not-found behavior that leaks resource existence unless the contract permits it.

## 12. CORS, Security Headers, and Rate Limiting

### CORS

- CORS MUST be configured once with explicit allowed origins, methods, and headers.
- Credentialed CORS MUST NOT use `*` as the allowed origin.
- Dynamic origin checks MUST use exact normalized allowlist matching, not suffix or substring matching.
- Preflight responses MUST be tested, including denied origins and requested headers.
- CORS is a browser policy and MUST NOT be treated as authentication or CSRF protection.

### Security headers

- Set `X-Content-Type-Options: nosniff`, an appropriate `Referrer-Policy`, frame protection through CSP `frame-ancestors` or a compatible header, and a reviewed Content Security Policy for HTML/documentation surfaces.
- Enable HSTS only when HTTPS is guaranteed for the host and deployment implications are understood.
- Set `Cache-Control: no-store` on token and highly sensitive responses where appropriate.
- Cookie authentication MUST use `Secure`, `HttpOnly`, an appropriate `SameSite` mode, scoped path/domain, and CSRF protection for state-changing requests.
- Default framework security middleware MUST be reviewed and supplemented; its presence is not proof of a complete policy.

### Rate limiting

- Rate limits MUST identify what they protect: edge traffic, IPs, credentials, principals, tenants, or specific operations.
- Sensitive endpoints SHOULD use stricter per-operation limits and abuse monitoring.
- Distributed services MUST use a shared or edge-enforced limiter when cross-replica consistency is required.
- Limiter stores MUST have bounded key cardinality, expiration, and failure behavior.
- Trusted proxy configuration MUST precede IP-based limiting.
- `429` responses SHOULD be stable and include `Retry-After` when calculable.
- Tests MUST cover burst boundaries, reset behavior, distinct keys, spoofed forwarding headers, and store failure policy.

### AVOID

- Permissive wildcard CORS copied into production.
- Reflecting any `Origin` while allowing credentials.
- A single unexplained requests-per-second value for every endpoint.
- Unlimited login, reset, upload, export, or webhook traffic.
- Assuming an in-memory limiter protects a multi-instance deployment globally.

## 13. File Uploads and Downloads

Uploads are hostile byte streams, regardless of filename or declared content type.

### MUST

- Enforce request and per-file size limits while reading.
- Limit file count, form field count, field lengths, and decompressed/processed output size.
- Treat `FileHeader.Filename` as display metadata only. Generate storage keys server-side with random identifiers and a controlled extension.
- Normalize and validate extensions, but verify content using magic-byte detection and, where needed, a safe decoder. Do not trust `Content-Type` alone.
- Allowlist required media types and reject polyglots or malformed files when the risk warrants it.
- Prevent path traversal; never join an untrusted filename directly into a filesystem or object key.
- Close opened files and clean temporary files on every path.
- Stream to storage with context cancellation rather than buffering the entire file.
- Keep uploaded objects private by default. Use short-lived signed URLs or an authorized download handler for sensitive content.
- Set safe download headers, including a controlled `Content-Type`, `X-Content-Type-Options`, and sanitized `Content-Disposition`.
- Delete a previous object only after the replacement and business update succeed, or use a compensating cleanup workflow.

```go
func copyBounded(dst io.Writer, src io.Reader, max int64) error {
	r := &io.LimitedReader{R: src, N: max + 1}
	n, err := io.Copy(dst, r)
	if err != nil {
		return fmt.Errorf("copy upload: %w", err)
	}
	if n > max {
		return ErrUploadTooLarge
	}
	return nil
}
```

### SHOULD

- Scan untrusted documents where the threat model requires it and quarantine until scanning completes.
- Strip active metadata or re-encode images when safe and required.
- Record uploader identity, object ID, size, detected type, checksum, and scan state without logging content.
- Test empty files, oversized files, forged media types, traversal filenames, duplicate names, partial storage failure, cancellation, and cleanup failure.

### AVOID

- Deriving object keys from names with `strings.Split` alone.
- Trusting `FileHeader.Size` as enforcement.
- Returning raw storage errors or internal bucket names.
- Serving user uploads inline from the application origin without a reviewed content policy.

## 14. OpenAPI Generation and Route Contracts

OpenAPI is a generated public contract, not decorative comments.

### MUST

- Use the repository-configured generator and canonical application entry point. Generated files MUST NOT be hand-edited.
- Keep annotations or schema definitions adjacent to the handler/DTO they describe when the generator supports it.
- Document path/query/header/body parameters, required fields, formats, bounds, content types, success statuses, error envelopes, authentication schemes, and upload fields accurately.
- Regenerate documentation whenever routes, DTOs, statuses, security, or envelopes change.
- Diff generated output and fail CI when committed output is stale.
- Keep documentation UI disabled or access-controlled in production unless public exposure is intentional.
- Test that documented routes and runtime routes do not drift, allowing only explicit infrastructure exclusions.

Representative command shape:

```bash
swag init -g cmd/api/main.go -o internal/httpserver/openapi/generated
git diff -- internal/httpserver/openapi/generated
```

The actual command, entry point, and output directory MUST come from the repository, not this example.

### SHOULD

- Validate the generated specification with an OpenAPI linter.
- Define reusable error and pagination schemas rather than contradictory copies.
- Avoid documenting internal-only headers or fields as client-controlled.

### AVOID

- Running the production server to generate or discover routes.
- Annotations that claim every failure is `500` or omit authorization failures.
- Persisting authorization tokens in a publicly deployed documentation UI by default.
- Treating successful generation as proof that runtime behavior matches the specification.

## 15. Structured Logging and Telemetry

### MUST

- Use structured logging consistently. Include timestamp through the logger, level, operation, HTTP method, normalized route, status, duration, request ID, and safe principal/resource identifiers where useful.
- Log unexpected server errors once at the boundary with their wrapped cause. Avoid duplicate logging at every layer.
- Redact authorization headers, cookies, API keys, signatures, secrets, request bodies, and unnecessary personal data.
- Use bounded-cardinality metric labels. Never label by raw path, request ID, email, token, or arbitrary user input.
- Propagate trace context through request contexts and outbound calls.
- Record panic events safely, then return the normal internal-error envelope if the response is not committed.
- Flush and shut down telemetry providers with a bounded context.
- Expose telemetry endpoints only when intentionally registered and secured; installed middleware alone does not prove metrics are available.

### SHOULD

- Record request/response byte counts, cancellation, timeout class, and limiter decisions.
- Sample traces according to an environment-reviewed policy and cost budget.
- Add spans around meaningful external boundaries, not every helper function.
- Keep health-check logging low-noise without suppressing failures.

### AVOID

- Logging raw request/response payloads in general access logs.
- Sending `err.Error()` alone without operation and correlation context.
- High-cardinality route and error labels.
- Assuming a shutdown log proves that exporters flushed successfully.

## 16. Graceful Shutdown and Background Resources

The process lifecycle MUST own every long-lived resource it starts.

### MUST

- Start the HTTP server in a way that returns startup failures to the lifecycle owner.
- Listen for termination signals with `signal.NotifyContext` or equivalent.
- Stop accepting new scheduled/background work before draining HTTP requests when that ordering prevents new work during shutdown.
- Call `Echo.Shutdown` with a bounded context and distinguish `http.ErrServerClosed` from real failures.
- Stop workers, schedulers, consumers, WebSocket hubs, telemetry exporters, database pools, cache clients, and provider transports through real close methods.
- Wait for owned goroutines with `errgroup`, `WaitGroup`, or component-specific joins. Logs are not cleanup.
- Make shutdown idempotent and test it.
- Give background work cancellation, bounded concurrency, retries, idempotency, and observability.

```go
func run(ctx context.Context, e *echo.Echo, addr string, resources []io.Closer) error {
	errCh := make(chan error, 1)
	go func() {
		err := e.Start(addr)
		if errors.Is(err, http.ErrServerClosed) {
			err = nil
		}
		errCh <- err
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	shutdownErr := e.Shutdown(shutdownCtx)
	for i := len(resources) - 1; i >= 0; i-- {
		shutdownErr = errors.Join(shutdownErr, resources[i].Close())
	}
	return shutdownErr
}
```

### SHOULD

- Mark readiness false before draining and allow load balancers time to observe it.
- Close resources in reverse dependency order.
- Separate job ownership from API replicas or use distributed leases before running the same schedule on multiple replicas.
- Use a second, short forced-close phase only when graceful shutdown exceeds its deadline.

### AVOID

- `os.Exit` inside cleanup code, because deferred cleanup will not run.
- Fire-and-forget goroutines.
- Starting one scheduler per replica without an ownership strategy.
- Reporting successful shutdown when a component has no implemented stop path.
- Using request contexts for durable background jobs after returning `202`.

## 17. HTTP and Security Testing

Use `httptest` against the real Echo router and middleware whenever practical. Unit tests for helpers do not replace transport contract tests.

```go
func TestGetWidgetRejectsInvalidID(t *testing.T) {
	e := echo.New()
	e.HTTPErrorHandler = NewHTTPErrorHandler(slog.New(slog.NewTextHandler(io.Discard, nil)))
	registerWidgetRoutes(e.Group("/v1"), stubWidgetUseCase{})

	req := httptest.NewRequest(http.MethodGet, "/v1/widgets/not-an-id", nil)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}
```

### MUST

- Test through `e.ServeHTTP` for routing, middleware, bind/validation behavior, status, headers, and response shape.
- Use table-driven tests for methods, content types, malformed bodies, unknown fields if strict, missing fields, boundary values, invalid paths/queries, and oversized bodies.
- Test authentication and authorization matrices: missing/invalid/expired token, wrong issuer or audience, wrong role or permission, wrong owner or tenant, and valid access.
- Assert that rejected requests do not call the use case or produce side effects.
- Test CORS allowed and denied origins, credential behavior, and preflight headers.
- Test security headers on success and error responses.
- Test rate-limit boundaries and key isolation with an injected clock/store where possible.
- Test panic recovery and ensure no stack or internal error leaks.
- Test upload size enforcement while streaming, media spoofing, traversal names, storage failure, and cleanup.
- Test request cancellation/deadline propagation to the use-case fake.
- Test graceful shutdown and that every owned worker/resource stops.
- Keep tests offline, deterministic, and independent of order.

### SHOULD

- Add route snapshots or contract assertions for method/path/middleware protection.
- Fuzz parsers, custom binders, claim conversion, filenames, webhook signatures, and error mapping.
- Run race tests for custom middleware, limiters, shared fakes, WebSocket hubs, and workers.
- Test through `httptest.NewServer` when behavior depends on a real listener, redirects, streaming, or client cancellation.
- Assert JSON using decoded structures rather than brittle whitespace comparisons.

### AVOID

- Calling handler methods directly as the only HTTP proof.
- Tests that install a fake authenticated principal without separately testing authentication middleware.
- Broad mocks that merely reproduce implementation details.
- Parallel tests that mutate package globals, Echo defaults, or shared limiter stores.
- Live provider calls, real credentials, or production-like data in tests.

## 18. Generic Verification

Before changing an Echo service, the coding agent MUST inspect the local instructions, Go module, entry point, server construction, route registration, middleware, error envelope, authentication setup, OpenAPI workflow, and relevant handler/use-case/tests. It MUST identify public-contract and security impact before editing.

After changing it, run the repository-defined commands. A generic baseline is:

```bash
gofmt -s -w <changed-go-files>
goimports -w <changed-go-files> # when configured; use repository-required flags
go test ./path/to/changed/packages/...
go test ./...
go vet ./...
go build ./<api-entrypoint>
golangci-lint run ./...
git diff --check
```

When applicable, also run:

```bash
go test -race -count=1 ./path/to/concurrent/packages/...
<repository-openapi-generation-command>
<repository-openapi-lint-command>
```

### MUST

- Prefer focused tests first, then repository-wide proof.
- Verify route inventory, middleware protection, generated OpenAPI diffs, and response compatibility for transport changes.
- Inspect the final diff for secrets, debug routes, permissive CORS, raw error leakage, generated-file drift, accidental route changes, and unrelated formatting.
- Report exact commands and results. Distinguish newly introduced failures from pre-existing failures.
- Use fakes, local test servers, and dry-run paths; do not start a service against shared data or live providers merely to inspect it.

### SHOULD

- Add static checks that generated OpenAPI is current and route contracts are deterministic.
- Benchmark middleware or upload paths when a change affects allocation, buffering, compression, or rate limiting.

## 19. Prohibited Anti-Patterns

Coding agents MUST NOT introduce or perpetuate these patterns in new Echo code:

- Passing `echo.Context` beyond the HTTP delivery layer when `context.Context` suffices.
- Retaining or using pooled Echo contexts after a handler returns.
- Ignoring `Bind`, `Validate`, parsing, claim, body read, response write, or close errors.
- Binding request data directly into database models.
- Trusting body/query actor IDs, roles, tenant IDs, prices, or server-managed fields.
- Unsafe JWT claim assertions or unrestricted signing algorithms.
- Equating JWT verification with role, permission, ownership, or tenant authorization.
- Mapping every error to `400`, leaking raw errors, or string-matching errors.
- Installing default and configured CORS middleware together.
- Wildcard credentialed CORS or reflecting arbitrary origins.
- Missing body, header, multipart, upload, pagination, timeout, or concurrency limits.
- Reading or logging unbounded bodies.
- Using raw URLs as metric labels or untrusted proxy headers as identity.
- Trusting upload filenames, extensions, declared types, or reported sizes.
- Constructing databases/providers in handlers or hiding them in package globals.
- Starting workers, migrations, live clients, or filesystem writes during route registration.
- Fire-and-forget request goroutines or unowned schedulers.
- Hand-editing generated OpenAPI files or documenting behavior that runtime tests contradict.
- Treating installed telemetry middleware, emitted shutdown logs, or a compiling router as proof that the service is operationally complete.
- Copying weak legacy patterns, commented-out authorization, duplicated middleware, stale annotations, or ignored errors for superficial consistency.
