# Haikel Go Engineering Profile

This profile records the owner's demonstrated Go service conventions. Load it
with `go.md`, then add the applicable Echo, GORM/PostgreSQL, Docker, and
infrastructure guidelines. Repository-local rules, finance documentation, and
public contracts take precedence.

## 1. Service Shape and Ownership

The preferred service flow is explicit and domain-oriented:

```text
route → HTTP handler → domain usecase → repository interface → GORM/PostgreSQL
```

- Put domain request/filter/response DTOs and interfaces in the domain root.
- Keep HTTP parsing, transport validation, identity extraction, and response
  envelopes in `delivery/http` handlers.
- Keep business invariants, cross-repository orchestration, and provider
  coordination in usecases.
- Keep GORM, SQL, and query construction in repositories.
- Wire dependencies centrally at application startup. Handlers MUST NOT create
  repositories or reach package-global services directly.
- Follow the existing domain boundary for compatible changes. Do not introduce a
  new technical layer, generic repository, or service locator without a proven
  need.

## 2. Formatting, Imports, and Naming

- Target the Go version declared by `go.mod`.
- Run `gofmt -s` for every changed Go file and `goimports` with the module-local
  prefix when the project adopts it. Formatter output is authoritative.
- Treat whitespace as part of readability. The formatter owns indentation and
  alignment; the developer still owns intentional blank lines between semantic
  phases.
- Keep import groups as standard library, third-party, then module-local.
- Use standard Go initialisms: `ID`, `URL`, `HTTP`, `JSON`, `API`, and `DTO`.
- Use concise, lowercase package names; preserve existing legacy names instead
  of renaming a package as incidental cleanup.
- Use DTO suffixes for transport contracts and `Usecase`, `Repository`, and
  `Handler` suffixes where the architecture already makes that ownership useful.
- Constructors should make dependencies explicit and normally return the domain
  interface when callers should depend only on the capability.

```go
func NewBannerUsecase(repo banner.Repository) banner.Usecase {
    return &bannerUsecase{repository: repo}
}
```

### Visual rhythm and semantic spacing

The owner prefers code with deliberate breathing room. Do not compress a
function merely because `gofmt` accepts it. Readability comes from visible
groups of related statements, not from line count.

- Use one blank line between distinct phases. Common phases are authentication,
  input parsing, normalization, validation, dependency calls, error handling,
  result transformation, and response construction.
- Keep an operation adjacent to the error check that handles it. Put the blank
  line after the completed error block, before the next phase.
- After a terminating guard clause, add a blank line before normal-path work
  when the next statement begins a different concern.
- Keep consecutive checks together when they validate the same input or
  invariant. Do not insert a blank line after every `if` mechanically.
- In repositories, visually separate transaction setup, query execution,
  scan/error classification, domain mapping, audit or outbox work, commit, and
  the final return.
- In loops, separate row-local declarations, scanning, error handling,
  transformation, and append/update work when several of those phases exist.
- In tests, use arrange, act, and assert groups. Keep the setup for one scenario
  together rather than scattering blank lines through every assignment.
- Prefer multiline keyed literals, constructor returns, and argument lists when
  a one-line form makes ownership or field grouping harder to scan.
- Use exactly one blank line for a boundary. Never add repeated blank lines,
  blank lines immediately inside braces, or whitespace that separates an
  operation from its error check.

Preferred handler rhythm:

```go
func (h *Handler) Update(c echo.Context) error {
	actor, err := h.authenticate(c)
	if err != nil {
		return respondError(c, err)
	}

	var input UpdateInput
	if err := c.Bind(&input); err != nil {
		return respondError(c, ErrInvalidInput)
	}
	if err := c.Validate(&input); err != nil {
		return respondError(c, err)
	}

	result, err := h.usecase.Update(c.Request().Context(), actor, input)
	if err != nil {
		return respondError(c, err)
	}

	return respondSuccess(c, result)
}
```

Before finishing a broad cleanup, inspect representative handlers, usecases,
repositories, background workers, and tests after formatting. Passing `gofmt`
alone does not prove that their visual rhythm matches this profile.

## 3. HTTP Boundaries and Validation

Handlers should execute one consistent sequence:

1. Read route, query, form, or body input.
2. Bind it into a domain DTO.
3. Run structural validation.
4. Get authenticated actor and role from verified claims.
5. Call one usecase operation.
6. Return the established success or error envelope.

```go
request := &payment.DtoCoinPayment{}
if err := c.Bind(request); err != nil {
    return models.ErrorResponse(c, err.Error())
}
if err := c.Validate(request); err != nil {
    return models.ErrorResponse(c, helper.MappingError(err))
}

result, err := h.paymentUsecase.PayWithCoin(c, request)
if err != nil {
    return models.ErrorResponse(c, err.Error())
}

return models.SuccessResponse(c, result, "Payment successful")
```

- DTO tags MUST match their input boundary: `json`, `form`, `query`, and
  `validate` serve different purposes.
- The handler MUST reject invalid bind/validation input before calling a usecase.
- Server-derived actor IDs, role IDs, and audit fields MUST NOT come from a
  request body.
- Database-dependent rules, ownership, financial thresholds, and state
  transitions belong in usecases, not only handlers.
- Preserve existing route paths, status behavior, response envelope fields, and
  Swagger annotations unless an API contract change is explicit.
- Regenerate Swagger from handlers; never hand-edit generated documentation.

## 4. Context, GORM, and Repository Work

- Pass the request context through blocking work. In Echo/GORM code, use
  `db.WithContext(c.Request().Context())` for new and touched queries.
- Use parameterized GORM predicates. Apply a deterministic ordering before
  offset/limit pagination.
- Keep count and list filters identical. Preserve soft-delete semantics in joins
  and raw SQL explicitly.
- Use `errors.Is(err, gorm.ErrRecordNotFound)` for missing records; never match
  error strings.
- Preserve table key types. Do not casually interchange `UUID`, `uint`, and
  `uint64` identifiers.
- Use exact integer currency units, never `float32` or `float64`, for money.
- Use explicit update maps/columns for state transitions. Use `gorm.Expr` or a
  guarded update predicate for atomic counter and balance changes.
- Check rows affected when an update depends on an expected prior state.

## 5. Finance and Transaction Invariants

Financial behavior is correctness-critical. One money mutation and every
corresponding ledger, history, log, or journal entry MUST commit or roll back in
the same PostgreSQL transaction.

This rule applies to payments, callbacks, wallets, top-ups, settlement,
commissions, withdrawals, refunds, bank accounts, and journals.

```go
return db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
    if err := repository.UpdateBalanceTx(tx, walletID, amount); err != nil {
        return fmt.Errorf("update wallet balance: %w", err)
    }
    if err := repository.CreateLedgerTx(tx, ledger); err != nil {
        return fmt.Errorf("create wallet ledger: %w", err)
    }
    return nil
})
```

- Pass the exact outer `*gorm.DB` to every transaction-aware repository method.
  Never call a repository method that opens a separate base-connection
  transaction from inside an outer financial transaction.
- Return every error from the transaction callback to guarantee rollback.
- Callbacks and retryable operations MUST be idempotent. Use stable, unique event
  keys or an equivalent durable deduplication rule.
- Do not perform irreversible external side effects inside a database transaction
  unless a durable outbox/idempotency design makes retry behavior safe.
- Ownership and chart-of-account semantics are distinct. Never model an
  accounting account as a pseudo-wallet owner simply to simplify a query.

## 6. Authentication, Errors, and Logging

- JWT verification authenticates the request; authorization still requires role
  and resource-ownership checks.
- Treat missing or malformed claims as unauthorized. Do not use unchecked type
  assertions for security-sensitive claim values.
- Wrap operational errors with context and `%w`; use `errors.Is`/`errors.As` for
  classification.
- Preserve established public error envelopes for compatibility. Do not turn a
  focused change into an unrequested API-wide status-code migration.
- Log at the boundary that owns the response, retry, or operation failure. Use
  structured fields for stable identifiers, operation, state, and provider.
- Never log secrets, access tokens, raw payment callbacks, credentials, or full
  personally identifiable payloads.
- Use `Warn` for intentional best-effort degradation and `Error` for a failed
  operation. Never suppress an error silently unless the contract explicitly
  permits it and the decision is observable.

## 7. Configuration, Migrations, and Runtime

- Parse configuration once through the established configuration boundary;
  validate required production settings before dependent work begins.
- Add new settings to the typed config and example environment file. Never put
  real credentials in examples, logs, tests, source, or generated artifacts.
- PostgreSQL schema changes MUST use the approved migration command and ordered
  migration registry. Application startup MUST NOT modify production schema.
- Prefer backward-compatible expand/contract migrations and test rerun/failure
  behavior. Build the migration command when migration code changes.
- Preserve startup, shutdown, health-check, timeout, middleware, and deployment
  invariants unless the task explicitly changes them.
- New dependencies should be injected. Avoid extending package-global state,
  especially for provider clients, logging, and persistent connections.

## 8. Tests and Proof

- Use focused, table-driven tests for rule matrices and exact financial
  boundaries: below, at, and above a threshold.
- Prefer small fakes that satisfy the domain interface for usecase tests. Assert
  result, error, and meaningful side effects/call count.
- Handler tests should construct an Echo context and stub the usecase boundary.
- Finance, callback, and state-transition changes MUST test rollback,
  idempotency, duplicate events, prior-state guards, ownership, and ledger
  consistency.
- Tests MUST not invoke live Firebase, S3, Redis, Kafka, payment providers, or
  customer endpoints. Restore package globals after tests that alter them and do
  not run conflicting global-state tests in parallel.
- Run the repository formatter, focused tests, `go test ./...`, `go vet ./...`,
  and the relevant command build. Do not rely on stale Makefile targets without
  verifying they point at the active command.

## 9. Legacy Patterns to Avoid Extending

- Do not reproduce nested base-connection transactions in a financial usecase;
  they can commit independently from the intended outer transaction.
- Do not write raw provider callback payloads to local files. Prefer redacted,
  structured audit data under a reviewed retention policy.
- Do not assume all existing HTTP errors use ideal status codes; preserve the
  contract locally while keeping new versioned APIs precise.
- Do not extend unchecked JWT claim assertions, Echo context leakage into new
  infrastructure, ignored errors, manual timestamps without need, or temporary
  environment-specific response rewriting.
- Do not depend on cron execution from every API replica or assume a configured
  Kafka topic implies an active consumer. Verify operational ownership first.
