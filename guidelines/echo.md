# Echo HTTP Service Coding-Agent Guideline

This document adds rules for building and changing HTTP services with Echo. Use
the GORM and PostgreSQL companion when the service uses that persistence stack.

Precedence follows `general.md` §2. Where `haikel-go.md` disagrees with this
guide, `haikel-go.md` wins.

## 1. Scope and Version

- Echo is a transport adapter, not the application architecture. Service shape,
  file layout, handler construction, route registration, and handler rhythm
  follow `haikel-go.md` §1 and §3.
- Public routes, methods, status codes, headers, JSON fields, error envelopes,
  and authentication behavior are compatibility contracts.
- External input is untrusted. Parsing, validation, authentication,
  authorization, and limits MUST happen before business effects.
- Middleware order is executable policy. Change it only with impact analysis and
  tests where security depends on it.
- Check `go.mod` before writing code. New services use Echo v5; examples in this
  guide use v5. Keep v4 forms in v4 repositories.

| Concern | v4 | v5 |
| --- | --- | --- |
| Handler signature | `func(c echo.Context) error` (interface) | `func(c *echo.Context) error` (struct) |
| Error handler | `func(err error, c echo.Context)` | `func(c *echo.Context, err error)` |
| Response | `c.Response()` returns `*echo.Response` | `c.Response()` returns `http.ResponseWriter`; use `echo.UnwrapResponse` for `Committed` |
| Banner and port | `e.HideBanner`, `e.HidePort` | `echo.StartConfig{HideBanner, HidePort}` |
| Server limits | `e.Server.ReadTimeout` and friends | `StartConfig.BeforeServeFunc func(*http.Server) error` |
| Start and stop | `e.Start(addr)` plus `e.Shutdown(ctx)` | `StartConfig.Start(ctx, e)` with `GracefulTimeout`; no `e.Shutdown` |
| Body limit | `middleware.BodyLimit("2M")` | `middleware.BodyLimit(2 << 20)` (bytes) |

## 2. Wiring

- Keep `echo.Context` inside the delivery layer. Usecase, repository, and
  provider methods accept `context.Context` from `c.Request().Context()`.
- Construct databases, caches, providers, usecases, handlers, and background
  resources in the composition root (`internal/app`). Never create repositories
  or provider clients in handlers.
- Separate server construction from process execution so tests can build the
  full router without binding a port, contacting providers, running migrations,
  or starting workers.
- Keep route registration free of network, database, filesystem, migration, and
  background-job side effects.
- Return owned closers from wiring when components need cleanup.
- AVOID global mutable Echo instances, loggers, validators, keys, rate limiters,
  or clients.

## 3. Construction, Server Limits, and Lifecycle

Construction is explicit and centralized: set the validator, error handler,
middleware, and routes before serving. Under v5, server limits and banner
settings belong to `StartConfig`.

```go
func run(cfg config.Config, e *echo.Echo, closers []io.Closer) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	startCfg := echo.StartConfig{
		Address:         cfg.HTTPAddress,
		GracefulTimeout: cfg.ShutdownTimeout,
		HidePort:        true,
		HideBanner:      true,
		BeforeServeFunc: func(s *http.Server) error {
			s.ReadHeaderTimeout = cfg.ReadHeaderTimeout
			s.ReadTimeout = cfg.ReadTimeout
			s.WriteTimeout = cfg.WriteTimeout
			s.IdleTimeout = cfg.IdleTimeout
			s.MaxHeaderBytes = cfg.MaxHeaderBytes

			return nil
		},
	}

	err := startCfg.Start(ctx, e)
	for i := len(closers) - 1; i >= 0; i-- {
		err = errors.Join(err, closers[i].Close())
	}

	return err
}
```

- Configure a nonzero `ReadHeaderTimeout` plus bounded read, write, and idle
  timeouts and a finite `MaxHeaderBytes`.
- Validate configuration before constructing the server. Invalid durations,
  limits, origins, keys, or proxy settings fail startup.
- Configure trusted proxy behavior before relying on `RealIP()` for security,
  auditing, or rate limiting.
- Stop background workers, schedulers, consumers, telemetry exporters, pools,
  and clients through real close methods, in reverse dependency order, and wait
  for owned goroutines. A log line is not cleanup.
- Never call `log.Fatal` or `os.Exit` from reusable packages or cleanup code;
  return errors to `main`.
- Never run migrations or write files during API startup.
- Separate job ownership from API replicas, or use distributed leases, before
  running the same schedule on several replicas.

## 4. Routes and Groups

- The handler constructor registers its own routes, with one sub-group per
  permission (`haikel-go.md` §3). Do not add separate `register*Routes`
  functions.
- Apply authentication at the narrowest correct group. Public endpoints MUST NOT
  inherit protected middleware, and protected endpoints MUST NOT sit outside it.
- Register specific routes before overlapping wildcard routes.
- Register the same route set for the same configuration. Environment-gated
  diagnostic or documentation routes are explicit and tested in both states.
- Preserve trailing-slash behavior intentionally.
- Never use route path strings as the sole authorization policy.

## 5. Middleware Order

Echo runs middleware outer to inner and unwinds responses in reverse. A
representative global order:

```go
e.Use(middleware.RequestID())
e.Use(middleware.Recover())
e.Use(middleware.CORSWithConfig(cfg.CORS))
e.Use(middleware.BodyLimit(cfg.MaxBodyBytes))
e.Use(appmiddleware.AccessLog())
```

- Install exactly one CORS policy. Never combine default and configured CORS.
- Place recovery so downstream panics reach the standard error path without
  leaking stack traces.
- Validate or generate the request ID early.
- Access logs record final status, latency, route template, request ID, and
  error after downstream execution. Metric labels use the route template, never
  the raw URL.
- Body limits run before binding or multipart parsing.
- Never log request or response bodies by default, and never use untrusted
  forwarding headers as limiter keys.

## 6. Limits and Request Context

- Apply a global body limit and smaller route-specific limits for sensitive or
  small payloads. Return `413` with a stable message for violations.
- Bound multipart memory and enforce upload size while reading with
  `io.LimitedReader` or `http.MaxBytesReader`, not from `FileHeader.Size`.
- Pass `c.Request().Context()` to usecases and I/O. Never use
  `context.Background()` in a request path.
- `echo.Context` is pooled. Never retain or use it after the handler returns,
  including from goroutines.
- Work that must outlive a request goes to a durable queue with copied,
  validated values and a managed worker.

## 7. Binding, Validation, and Parameters

- Bind into dedicated request DTOs (`domain.Dto...`). Never bind into
  persistence models or domain entities.
- Check every `Bind`, parse, and `Validate` error. Wrap `go-playground/validator`
  behind Echo's `Validator` interface and translate field errors to stable
  public field names.
- Validate syntax at the HTTP boundary and cross-field or business rules in the
  usecase.
- Parse path and query values with explicit range checks. A provided invalid
  value MUST NOT silently become a default; never write
  `value, _ := strconv.Atoi(...)`.
- Distinguish absent optional values from explicit zero or false with pointers
  where semantics differ.
- Cap pagination limits with deterministic defaults.
- Never trust an owner ID, role, tenant, price, or server-managed field from the
  body. Derive the actor from the principal.
- Never bind path, query, and body into one struct when one source can overwrite
  another.

The handler shape, variable names, sentinel mapping, and envelope helpers are in
`haikel-go.md` §2 and §3.

## 8. Responses and Errors

- Follow the repository's envelope helpers. Handlers map known domain sentinels
  with `errors.Is` to a status and message, give unclassified errors a fixed
  fallback message, and log them once. Never return `err.Error()`, stack
  traces, SQL, provider payloads, or token details to clients.
- Preserve existing envelopes and status behavior; do not turn a focused change
  into an API-wide status migration.
- For a new versioned API, map deliberately: malformed input `400`, missing or
  invalid credentials `401`, denied permission `403`, absent resource `404`,
  state or uniqueness conflict `409`, size violation `413`, unsupported media
  `415`, rate limit `429`, unexpected failure `500`.
- Use `201` for creation, `202` for accepted asynchronous work, and `204` with
  no body.
- Never write a second response after the response is committed.

A central error handler only catches what handlers return unmapped:

```go
func NewHTTPErrorHandler() echo.HTTPErrorHandler {
	return func(c *echo.Context, err error) {
		if res, unwrapErr := echo.UnwrapResponse(c.Response()); unwrapErr == nil && res.Committed {
			log.Error().Err(err).Msg("request failed after response commit")
			return
		}

		log.Error().Err(err).Str("path", c.Path()).Msg("unhandled request error")
		if writeErr := model.InternalError(c); writeErr != nil {
			log.Error().Err(writeErr).Msg("write error response")
		}
	}
}
```

Use the repository logger in place of the logger shown.

## 9. Authentication, Roles, and Ownership

- Restrict accepted signing algorithms and validate signature, expiry,
  not-before, issuer, and audience as the trust model requires.
- Convert claims into one validated principal in authentication middleware.
  Handle missing or malformed claims with checked conversions, never unchecked
  type assertions.
- Apply explicit permission checks to protected operations, preferably through
  per-permission route groups.
- Enforce resource ownership or tenant membership from trusted principal
  identity and persisted data. A matching role alone is insufficient.
- Return `401` for absent or invalid authentication and `403` for an
  authenticated principal without permission.
- Never log bearer tokens or complete claims.

## 10. CORS, Security Headers, and Rate Limits

- Configure CORS once with explicit origins, methods, and headers. Credentialed
  CORS MUST NOT use `*` or reflect arbitrary origins; match origins exactly.
- Set `X-Content-Type-Options: nosniff`, a `Referrer-Policy`, frame protection,
  and a reviewed CSP for HTML and documentation surfaces. Enable HSTS only when
  HTTPS is guaranteed.
- Cookie authentication uses `Secure`, `HttpOnly`, an appropriate `SameSite`,
  and CSRF protection for state-changing requests.
- Rate limits name what they protect. Use a shared or edge limiter when limits
  must hold across replicas, and configure trusted proxies before IP limits.

## 11. Uploads and Downloads

- Enforce request and per-file size limits while reading, and limit file count
  and field lengths.
- Treat `FileHeader.Filename` as display metadata. Generate storage keys
  server-side with random identifiers and a controlled extension.
- Verify content with magic-byte detection; never trust `Content-Type` alone.
- Stream to storage with context cancellation and clean up temporary files on
  every path.
- Keep uploaded objects private by default; serve them through signed URLs or an
  authorized handler with safe `Content-Type` and `Content-Disposition`.
- Delete a previous object only after the replacement and business update
  succeed.

## 12. OpenAPI

- Every handler carries a `// <Method> godoc` block (`haikel-go.md` §3).
- Regenerate with the repository's generator and entrypoint whenever routes,
  DTOs, statuses, security, or envelopes change. Never hand-edit generated
  output, and diff it before finishing.
- Document only outcomes the handler can return, including authorization
  failures.
- Keep documentation UI disabled or access-controlled in production unless
  public exposure is intentional.

## 13. HTTP Testing

- Test through the router: register the handler on an `echo.New()` group and
  call `e.ServeHTTP` with `httptest`. This covers routing, middleware, binding,
  status, and response shape.
- Cover malformed bodies, missing fields, boundary values, invalid path or query
  values, and oversized bodies.
- Cover the authentication and authorization matrix: missing, invalid, and
  expired token, wrong permission, wrong owner or tenant, and valid access.
- Assert that rejected requests do not call the usecase.
- Keep tests offline and deterministic. Never call live providers or use real
  credentials.

## 14. Verification

Run the command list in `haikel-go.md` §8. For transport changes, also check
route inventory, middleware protection, the generated OpenAPI diff, and
response compatibility, and inspect the diff for debug routes, permissive CORS,
and raw error leakage.
