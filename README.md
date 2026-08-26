# AI Engineering Guidelines

These guidelines translate the project owner's engineering preferences into rules
that coding agents can execute across current and future projects. They cover
JavaScript, TypeScript, Go, frontend, backend, databases, infrastructure, financial
transactions, migrations, and deployment.

## Documents

### Project-wide

- [`general.md`](general.md) — repository setup, engineering harness, sources of
  truth, Git-native planning, authority, documentation, verification, CI,
  runbooks, and measured process improvement.

### JavaScript and TypeScript

- [`guidelines/javascript-typescript.md`](guidelines/javascript-typescript.md) —
  language-level JavaScript and TypeScript rules.
- [`guidelines/astro.md`](guidelines/astro.md) — Astro rendering modes,
  file-based routing, content collections, islands, UI integrations, CMS and
  i18n boundaries, web quality, testing, and static deployment.
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

### Infrastructure

- [`guidelines/docker.md`](guidelines/docker.md) — reproducible images,
  multi-stage builds, BuildKit, runtime security, Compose, health checks,
  migrations, CI delivery, and Kubernetes interoperability.

## Automated Installation

`install.sh` recursively detects supported stacks, including applications in a
monorepo, and installs only the applicable documents. Preview the selection
before writing:

```bash
./install.sh --dry-run /path/to/project
```

Install the selected guidelines:

```bash
./install.sh /path/to/project
```

The installer writes this project-local layout:

```text
.agents/
├── general.md
├── .ai-guideline-manifest
└── guidelines/
    └── <detected-stack>.md
```

It also appends or refreshes a bounded block in the target's root `AGENTS.md` so
coding agents can discover the installed files. Content outside these markers is
preserved:

```text
<!-- AI-GUIDELINES:BEGIN -->
...
<!-- AI-GUIDELINES:END -->
```

The manifest records installed content hashes. On later runs, files that still
match their previous installed hash update automatically, and obsolete
unmodified guidelines are removed. A locally modified installed guideline is
never overwritten by default. Review the conflict, preserve the local policy if
it is intentional, or explicitly replace it with:

```bash
./install.sh --force /path/to/project
```

`--dry-run` never changes the target. The installer also rejects malformed
managed markers and refuses to install into this source repository.

### Detection matrix

| Evidence found anywhere in the target | Guidelines selected |
| --- | --- |
| Every project | General |
| `package.json`, `tsconfig.json`, or `jsconfig.json` | JavaScript and TypeScript |
| Astro dependency or `astro.config.*` | JavaScript and TypeScript, Astro, Docker |
| Next.js dependency or `next.config.*` | JavaScript and TypeScript, Next.js, Docker |
| NestJS dependency or `nest-cli.json` | JavaScript and TypeScript, NestJS, Docker |
| `go.mod` | Go, Docker |
| Echo module in `go.mod` | Echo, in addition to Go |
| GORM plus a PostgreSQL driver in `go.mod` | GORM and PostgreSQL, in addition to Go |
| Dockerfile or Compose file | Docker |

Generated output, dependencies, VCS metadata, vendor trees, caches, and an
existing `.agents` directory are excluded from detection. Detection does not
execute project code or read environment files.

## Usage

Use `general.md` as the project-wide baseline, then load only the applicable
language, framework, persistence, and infrastructure companions. These guidelines
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
Next.js guideline. Astro work uses the language guideline plus the Astro
guideline. An Echo service backed by GORM and PostgreSQL uses all three Go
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
