# AI Engineering Guidelines

These guidelines translate the project owner's engineering preferences into rules
that coding agents can execute across current and future projects. They cover
JavaScript, TypeScript, Go, frontend, backend, databases, infrastructure, financial
transactions, migrations, and deployment.

## Documents

### JavaScript and TypeScript

- [`guidelines/javascript-typescript.md`](guidelines/javascript-typescript.md) —
  language-level JavaScript and TypeScript rules.
- [`guidelines/nextjs.md`](guidelines/nextjs.md) — Next.js App Router, React,
  client/server boundaries, state, forms, UI, accessibility, and deployment.
- [`guidelines/nestjs.md`](guidelines/nestjs.md) — NestJS modules, dependency
  injection, HTTP contracts, authentication, persistence integration, and
  operations.

### Go

- [`guidelines/go.md`](guidelines/go.md) — language-level Go rules.
- [`guidelines/echo.md`](guidelines/echo.md) — Echo routing, middleware, HTTP
  boundaries, authentication, security, and lifecycle.
- [`guidelines/gorm-postgresql.md`](guidelines/gorm-postgresql.md) — GORM,
  PostgreSQL, repositories, transactions, locking, exact money, and migrations.

## Usage

Provide the relevant document to a coding agent as its baseline. These guidelines
do not replace repository-local rules. The order of precedence is:

1. The current requirements and acceptance criteria.
2. Repository-local rules such as `AGENTS.md`, `CLAUDE.md`, ADRs, and domain
   documentation.
3. The codebase's architecture, public contracts, formatter, linter, and dominant
   conventions.
4. The applicable language, framework, and persistence guidelines in this
   directory.

When an existing codebase conflicts with these guidelines, the agent must
distinguish contracts that must remain compatible from technical debt that must not
be copied into new code. Do not refactor outside the task's scope merely to make the
code uniform.

For framework work, load both the language guideline and the relevant companion.
For example, Next.js work uses the JavaScript and TypeScript guideline plus the
Next.js guideline. An Echo service backed by GORM and PostgreSQL uses all three Go
documents. Do not load unrelated framework documents merely because they exist.

## Core Principles

1. **Correct before elegant.** Understand ownership, contracts, and invariants
   before changing an implementation.
2. **Simple but explicit.** Choose the solution with the fewest layers, helpers,
   and names that still makes intent clear.
3. **Mechanically consistent.** Formatters and linters are the source of truth; do
   not rely on manual formatting preferences.
4. **Typed and validated boundaries.** Never trust external input.
5. **Visible business invariants.** Place policy in the domain or use case, enforce
   it in the database where possible, and prove it with tests.
6. **Intentional compatibility.** Do not accidentally change routes, schemas,
   envelopes, status codes, or public behavior.
7. **Verification is part of implementation.** A change is not complete until the
   relevant formatter, static analysis, tests, and build have run.
8. **Never conceal failure.** Do not ignore errors, misrepresent test results, or
   add special cases merely to make a test pass.
