# GORM and PostgreSQL Coding-Agent Guideline

This guide defines how coding agents design, change, and verify GORM-backed PostgreSQL code.

Precedence follows `general.md` §2. Where `haikel-go.md` disagrees with this guide, `haikel-go.md` wins.

## 1. Repository Context and Boundaries

Before editing persistence code, the agent MUST:

1. Read repository instructions, `go.mod`, GORM and PostgreSQL driver versions, configuration, model conventions, repository interfaces, migrations, and focused tests.
2. Trace the complete operation from caller to repository, including transaction ownership, authorization filters, soft deletion, side effects, and response projections.
3. Identify the schema source of truth. Compare models, migration history, constraints, indexes, and deployed compatibility assumptions; do not infer the database solely from structs.
4. Search all callers before changing a repository signature, model field, table name, association, default scope, or migration.
5. Classify schema, locking, idempotency, and monetary changes as high-risk and provide focused database proof.

Repositories MUST own persistence mechanics, including the `Transaction` callback for an atomic unit. Use cases own business policy. Handlers, jobs, and provider adapters MUST NOT issue ad hoc GORM queries when a repository boundary exists.

Keep transport DTOs, domain commands, query filters, and database models distinct when their contracts differ. A request body MUST NOT be mass-assigned into a model.

## 2. Database Handle and Context

- Every operation that performs I/O MUST accept `context.Context` and query through `r.Conn.WithContext(ctx)`.
- Repository constructors receive `*gorm.DB` and store it in an exported `Conn` field; never hide the handle in a package global.
- Code MUST use the repository's supported GORM version. Do not copy APIs or error constants from another major version without checking compatibility.
- A scoped `*gorm.DB` is immutable in intent: retain and pass the returned value from `WithContext`, `Where`, or `Session`.
- Code MUST distinguish the root handle from a transaction handle. A transaction callback MUST never fall back to the root handle.

```go
func (r *OrderRepository) Find(ctx context.Context, id uint64) (*model.Order, error) {
	var order model.Order

	err := r.Conn.WithContext(ctx).
		Where("id = ?", id).
		First(&order).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, domain.ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("find order: %w", err)
	}

	return &order, nil
}
```

## 3. Models, Keys, and Time

Models MUST describe persisted data explicitly. Reuse the repository's shared base model; do not embed `gorm.Model` when its ID type, timestamp names, or deletion behavior differ from the schema.

```go
type Base struct {
	ID        uint           `json:"id" gorm:"primaryKey;autoIncrement"`
	CreatedAt time.Time      `json:"created_at" gorm:"not null"`
	UpdatedAt time.Time      `json:"updated_at" gorm:"not null"`
	DeletedAt gorm.DeletedAt `json:"-" gorm:"index"`
}
```

- Keep the established key type. Do not interchange `uint`, `uint64`, and UUID keys, and use UUIDs for new tables only when the schema already does.
- When a schema uses UUIDs, store them as PostgreSQL `uuid`, not `varchar(36)`, use one UUID package, and generate IDs in one documented place.
- Do not use `BeforeCreate` merely to hide inconsistent ID creation. Hooks MUST be deterministic, local, error-checked, and free of external calls.
- Store instants as `timestamptz` and use UTC at persistence boundaries. Use `timestamp` only for intentionally timezone-free civil values.
- Use `time.Time` for required timestamps and pointers or a nullable type for nullable timestamps. Zero time MUST NOT silently mean NULL.
- Let GORM manage `CreatedAt` and `UpdatedAt` only when that behavior matches the contract. Bulk SQL that bypasses hooks MUST update timestamps deliberately.
- Database defaults, nullability, generated values, and tags MUST agree with migrations.
- Override `TableName()` only for an established schema contract; table naming MUST not depend on mutable state.

## 4. PostgreSQL-Native Types

Choose types by semantics, not convenience:

- IDs: the established key type; counters: `bigint` when growth warrants it.
- Exact amounts: integer smallest units or constrained `numeric(precision, scale)`; never `real`, `double precision`, Go `float32`, or `float64`.
- Instants: `timestamptz`; calendar dates: `date`; time-of-day: `time` only when timezone semantics are explicit.
- Arbitrary structured data: `jsonb`, with a typed Go representation where feasible. Validate its shape before storage.
- Network addresses: `inet`/`cidr`; ranges: native range types when their operators are needed.
- Enumerated states: a lookup/foreign key, a PostgreSQL enum with an evolution plan, or `text` plus a `CHECK`; do not rely only on Go validation.
- Arrays SHOULD be used only when values are truly atomic to the row and queried with PostgreSQL array semantics. Use a child table for relational entities.
- Nullable values MUST distinguish absent from zero. Do not use sentinel empty strings or zero IDs as NULL substitutes.

Custom types MUST implement scanning/value conversion correctly, preserve NULL, reject malformed values, and have round-trip integration tests.

## 5. Safe Query Construction

All values MUST be bound parameters:

```go
r.Conn.WithContext(ctx).
	Where("company_id = ? AND status = ?", companyID, status).
	Find(&orders)
```

User input MUST NOT be concatenated into SQL, `Where`, `Joins`, `Order`, `Select`, table names, column names, operators, JSON paths, or lock clauses. Placeholders protect values, not identifiers. Dynamic identifiers MUST come from a closed allowlist:

```go
var sortColumns = map[string]string{
	"created_at": "orders.created_at",
	"total":      "orders.total",
}

column, ok := sortColumns[filter.Sort]
if !ok {
	return nil, 0, domain.ErrInvalidSort
}

direction := "ASC"
if filter.Descending {
	direction = "DESC"
}

q = q.Order(column + " " + direction).Order("orders.id ASC")
```

- Empty slices in `IN` predicates MUST have explicit semantics; return an empty result or omit the predicate intentionally.
- LIKE searches MUST decide whether `%` and `_` are wildcards and escape them when literal matching is intended.
- Raw SQL MUST still use context, parameters, explicit selected columns, scan-error checks, and soft-delete/tenant predicates.
- Apply optional filters with `q = q.Where(...)` under an `if` guard. Do not use `Scopes` for filters.

## 6. Filters, Counts, and Pagination

Build the filtered query `q` once, count, then apply ordering and the page. Count MUST include every authorization, tenant, soft-delete, join, and search predicate used by the list. The full list example is in `haikel-go.md` §4.

Counting and then finding on the same `q` is the established pattern. If a chain is reused after a finisher in a way GORM's method-chain safety rules do not cover, derive each branch with `q.Session(&gorm.Session{})`.

- Validate and cap page size; reject or normalize negative limits and offsets.
- Ordering MUST be deterministic and end with a unique tie-breaker.
- `First` and “latest” queries MUST state the intended order; primary-key order is not a substitute.
- Offset pagination is acceptable for bounded lists. Large or changing datasets SHOULD use keyset pagination with all ordering columns encoded in the cursor.
- Keyset predicates MUST match direction and NULL ordering. Cursors MUST be validated and scoped to the same filters.
- Joins that multiply parent rows require a deliberate count strategy such as `COUNT(DISTINCT records.id)` and tests proving count/list parity.

## 7. Soft Deletes

- Models using GORM soft deletion MUST expose a compatible `gorm.DeletedAt` field or follow the established plugin convention.
- Normal reads, updates, associations, counts, existence checks, and uniqueness behavior MUST consistently exclude deleted rows unless restoration/audit explicitly requires `Unscoped()`.
- `Table`, raw SQL, and some joins can bypass default scopes; they MUST include `deleted_at IS NULL` explicitly where required.
- `Unscoped()` MUST be narrowly localized and justified. Never place it in a broadly reused base query.
- Restore and hard-delete operations MUST be explicit, authorized, audited when required, and tested.
- If uniqueness applies only to live rows, use a partial unique index, for example:

```sql
CREATE UNIQUE INDEX CONCURRENTLY users_email_live_uq
ON users (lower(email)) WHERE deleted_at IS NULL;
```

## 8. Associations and Preloading

- Define foreign keys and references explicitly when conventions are not exact. The database MUST enforce important relationships.
- Preload only associations required by the output. AVOID blanket nested preloads and hidden N+1 queries.
- Apply tenant, authorization, ordering, and soft-delete conditions to association queries as needed.
- `Preload` performs separate queries; `Joins` changes row shape and cardinality. Choose deliberately and test pagination/count behavior.
- Saving a parent MUST NOT accidentally create or update its associations. Prefer explicit association writes or `Omit`/selected fields.
- Deletion behavior (`RESTRICT`, `CASCADE`, or `SET NULL`) MUST be a schema decision, not an ORM accident.
- Large one-to-many collections SHOULD be queried and paginated separately.

## 9. Transactions and Transaction Propagation

Use GORM's closure form so panic handling, rollback, and commit errors follow one path. The repository owns the callback; the result shape and helper conventions are in `haikel-go.md` §4.

```go
return r.Conn.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
	order, err := lockOrder(tx, id)
	if err != nil {
		return err
	}

	if err := recordHistory(tx, order.ID, domain.StatusPaid); err != nil {
		return fmt.Errorf("record order history: %w", err)
	}

	return nil
})
```

- The closure MUST return every failure. Returning `nil` commits.
- Every read and write in the atomic unit MUST use `tx`, including audit rows, outbox rows, uniqueness checks, and helpers.
- Helpers that run inside a transaction take `tx *gorm.DB` as the first parameter and no `ctx`. Never let a helper fall back to the root handle or open its own transaction.
- Nested transactions and savepoints MUST be intentional and tested.
- External network calls SHOULD occur before or after the transaction. If an external side effect must follow commit, persist an outbox record atomically and deliver it asynchronously.
- Keep transactions short; do not wait for user input, sleep, perform unbounded computation, or preload irrelevant rows while holding locks.
- Configure isolation only when the invariant requires it. Retry serialization failures and deadlocks at the whole-transaction boundary with a bounded policy.

## 10. Locking and Concurrency

For a read-modify-write invariant, use either a row lock or a single conditional atomic statement.

```go
err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
	Where("id = ?", id).
	First(&wallet).Error
```

```go
res := tx.Model(&model.Wallet{}).
	Where("id = ? AND balance >= ?", id, debit).
	UpdateColumn("balance", gorm.Expr("balance - ?", debit))
if res.Error != nil {
	return fmt.Errorf("debit wallet: %w", res.Error)
}
if res.RowsAffected != 1 {
	return domain.ErrInsufficientFunds
}
```

GORM v2 locks rows only through `clause.Locking`. The v1 form `tx.Set("gorm:query_option", "FOR UPDATE")` does nothing in v2.

- Locks MUST be acquired in a consistent order to reduce deadlocks.
- `SKIP LOCKED` SHOULD be limited to work queues where temporarily skipping work is valid. `NOWAIT` SHOULD map lock contention to an intentional retry/conflict result.
- Optimistic concurrency SHOULD use a version column or state predicate and require exactly one affected row.
- Never infer success only from a nil error when `RowsAffected` is part of correctness.
- Process-local mutexes do not protect data across replicas and MUST NOT replace database concurrency controls.

## 11. Idempotency and Upserts

- Every retriable command, callback, import row, or job SHOULD have a stable idempotency/event key with a unique constraint.
- The stored key MUST be scoped correctly, such as `(tenant_id, provider, event_key)`.
- Duplicate delivery MUST return the original semantic result or a documented no-op; it MUST NOT repeat monetary or external effects.
- Use `clause.OnConflict` with an explicit conflict target and explicit update columns. A broad “upsert everything” can overwrite immutable or newer fields.

```go
err := tx.Clauses(clause.OnConflict{
	Columns:   []clause.Column{{Name: "source"}, {Name: "event_key"}},
	DoNothing: true,
}).Create(&event).Error
```

- If inserted-versus-existing matters, prove it with `RowsAffected`, `RETURNING`, or a follow-up read inside the same transaction.
- Never implement idempotency as “SELECT, then INSERT” without a unique constraint; concurrent requests can both pass the check.

## 12. Exact Money and Accounting Invariants

- Money MUST use integer minor units when currency scale is fixed, or an exact decimal/numeric representation with explicit scale and rounding rules. Floating point is prohibited.
- Amounts MUST carry or imply one unambiguous currency. Arithmetic across currencies requires an explicit conversion event and rate provenance.
- Conversion, tax, fee, allocation, and rounding rules MUST be centralized and tested at boundaries, including negative values and overflow.
- A balance mutation and its immutable ledger/journal entries MUST commit in one PostgreSQL transaction.
- Balanced accounting entries MUST satisfy total debits equals total credits per journal and currency before commit. Enforce structural invariants with constraints and deferred triggers where appropriate.
- Ledger entries SHOULD be append-only. Corrections use reversing/adjusting entries; do not rewrite history.
- Idempotency keys, account IDs, event time, effective time, amount, currency, and source reference SHOULD be retained for audit and reconciliation.
- Current balance MUST be derived from authoritative entries or updated atomically with them. Never overwrite a current balance from a stale snapshot.
- Negative balances, account status, and permitted transitions MUST be enforced atomically, not by an unlocked pre-check.
- Use checked arithmetic in Go; reject values outside the database column's precision/range.

## 13. Constraints and Indexes

- Enforce `NOT NULL`, foreign keys, uniqueness, valid ranges, and state relationships in PostgreSQL whenever expressible. Application validation improves errors but does not replace constraints.
- Constraint and index names SHOULD be stable and explicit so migrations and error classification can reference them.
- Indexes MUST serve observed filters, joins, uniqueness, or ordering. Column order MUST reflect equality predicates first, then range/order needs; verify rather than guessing.
- Consider partial and expression indexes for stable predicates such as live rows or normalized identifiers.
- AVOID redundant indexes: a unique index already supports lookup, and every index adds write and vacuum cost.
- Prove important or regressed queries with `EXPLAIN (ANALYZE, BUFFERS)` on representative, anonymized data, not tiny fixtures.
- Create production indexes `CONCURRENTLY` when blocking writes is unacceptable; it cannot run inside a transaction.

## 14. Error Classification

Repositories MUST preserve causes with `%w` and classify only conditions callers can act on:

- `gorm.ErrRecordNotFound` → domain not found.
- PostgreSQL unique violation (`23505`) → conflict or idempotent duplicate, identified by a known constraint.
- Foreign-key violation (`23503`) → invalid relationship or conflict.
- Check violation (`23514`) and not-null violation (`23502`) → invalid state/input or an internal mapping defect, depending on origin.
- Serialization failure (`40001`) and deadlock (`40P01`) → retry the complete transaction with bounded backoff.
- Context cancellation/deadline → preserve `context.Canceled`/`context.DeadlineExceeded`.

Use `errors.Is` and `errors.As` with the driver error type. With pgx, that is `*pgconn.PgError` from `github.com/jackc/pgx/v5/pgconn`:

```go
var pgErr *pgconn.PgError
if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "orders_number_key" {
	return nil, domain.ErrDuplicateNumber
}
```

Never compare error strings, expose SQL details to clients, or map every database error to “not found.” Unknown errors remain internal failures and SHOULD be logged with operation and stable identifiers, never bound values containing secrets or personal data.

## 15. Connection Pool and Lifecycle

GORM wraps `database/sql`; configure and close the underlying pool:

- Configure the underlying `database/sql` pool from typed configuration (`SetMaxOpenConns`, `SetMaxIdleConns`, `SetConnMaxLifetime`, `SetConnMaxIdleTime`), budgeted across every replica and job below the database connection limit. `MaxIdleConns` MUST NOT exceed `MaxOpenConns`.
- Ping with a bounded context at startup. Create one long-lived pool per database role, never per request, and close it once at shutdown.

## 16. Migrations and Production Schema Safety

- Maintain an explicit, ordered, immutable migration registry. Versions MUST be unique and applied exactly once; never edit an applied migration.
- The dedicated migrator MUST acquire a PostgreSQL advisory lock before reading/applying the registry. Lock identity MUST be stable and shared by every migrator instance.
- A migration record MUST be committed atomically with its transactional schema changes. Non-transactional steps need resumable, verifiable state and explicit recovery instructions.
- Production application startup MUST be schema-read-only: no `AutoMigrate`, table creation, index creation, sequence repair, or migration execution. It MAY verify that the expected registry version is present using read-only queries.
- `AutoMigrate` MAY be used only for disposable local/test databases when repository policy permits; it is not a production migration strategy.
- Use expand/contract: add nullable/default-compatible structures, deploy code that handles old and new forms, backfill, switch reads/writes, enforce constraints, then remove old structures in a later release.
- Backfills MUST be idempotent, restartable, bounded in batches, observable, and safe under concurrent writes. Use stable keyset progress, short transactions, and throttling.
- Adding a default, `NOT NULL`, foreign key, or validation to a large table MUST consider lock and rewrite behavior. Prefer `NOT VALID` plus later `VALIDATE CONSTRAINT` where suitable.
- Destructive or irreversible migrations require backup verification, restore rehearsal, stopped writers or an explicit online plan, and a roll-forward strategy.
- Migrator and application artifacts SHOULD come from the same revision. Deployment MUST gate application rollout on successful migration verification.
- Migration down-functions MUST NOT imply safety where data loss or incompatible deployed code makes rollback unsafe.

## 17. PostgreSQL Integration Tests

ORM mocks cannot prove SQL syntax, constraints, locking, isolation, scan behavior, query plans, or PostgreSQL types. Relevant changes MUST have integration tests against a real, supported PostgreSQL version.

- Each test run MUST use an isolated temporary database or schema with a unique name. Parallel tests MUST not share mutable rows or migration state.
- Apply the real ordered migrations, not a hand-built approximation. Test setup MUST fail on migration errors.
- Use ephemeral containers or a dedicated local test instance; never connect tests to shared, staging, or production databases.
- Configuration MUST make destructive-test targets unmistakable. Tests MUST refuse unsafe database names/hosts where feasible.
- Clean up with database/schema drop after closing connections. Cleanup errors SHOULD be reported without hiding the primary failure.
- Seed minimal deterministic fixtures through SQL/repositories. Do not copy sensitive database dumps.
- Test rollback at each failure point, duplicate idempotency keys, concurrent writers, lock behavior, affected-row predicates, soft deletion, association loading, count/list parity, nullable/native type round trips, and constraint error classification as applicable.
- Concurrency tests MUST use separate database connections, synchronization barriers, and bounded contexts; sleeps alone are not reliable coordination.
- Tests SHOULD run in CI with the supported PostgreSQL major version and SHOULD include a migration-from-previous-schema test for risky releases.

## 18. Verification

Run the command list in `haikel-go.md` §8, plus a build of the migration entrypoint when migration code changes. For persistence changes, also verify:

1. SQL and values are parameterized; dynamic identifiers are allowlisted.
2. Context, tenant/ownership predicates, soft deletion, count parity, and deterministic ordering are preserved.
3. Every operation in a transaction uses `tx`; affected-row checks and retries preserve the invariant.
4. Models, migrations, defaults, constraints, and indexes agree.
5. Migration ordering, advisory locking, expand/contract compatibility, backfill restartability, and production read-only startup are proven.
6. Focused PostgreSQL integration tests cover failure, rollback, duplicate, and concurrency paths.
7. Important changed queries have representative plan evidence when scale or latency can be affected.
8. The diff contains no secrets, dumps, debug SQL with sensitive values, generated noise, or unrelated formatting.
