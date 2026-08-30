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
- [`preferences.md`](preferences.md) — owner's cross-stack quality profile for
  code rhythm, complete-scope cleanup, frontend libraries, interface design,
  natural writing, verification, and Git delivery.
- [`ignores/README.md`](ignores/README.md) — supported coding-agent ignore files,
  shared exclusions, tool mappings, and security limitations.
- [`CHANGELOG.md`](CHANGELOG.md) — version history and notable behavior changes.
- [`RELEASING.md`](RELEASING.md) — versioning, validation, tagging, and release
  procedure.

### JavaScript and TypeScript

- [`guidelines/javascript-typescript.md`](guidelines/javascript-typescript.md) —
  language-level JavaScript and TypeScript rules.
- [`guidelines/haikel-javascript-typescript.md`](guidelines/haikel-javascript-typescript.md) —
  owner's TypeScript profile: formatting, typed boundaries, React/Next structure,
  data fetching, NestJS layering, and verification.
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
- [`guidelines/haikel-go.md`](guidelines/haikel-go.md) — owner's Go service
  profile: domain layers, Echo handlers, GORM access, finance invariants,
  observability, migration safety, and verification.
- [`guidelines/echo.md`](guidelines/echo.md) — Echo routing, middleware, HTTP
  boundaries, authentication, security, and lifecycle.
- [`guidelines/fiber.md`](guidelines/fiber.md) — Fiber app construction, routing,
  middleware, request lifetime, HTTP contracts, security, testing, and graceful
  shutdown.
- [`guidelines/gorm-postgresql.md`](guidelines/gorm-postgresql.md) — GORM,
  PostgreSQL, repositories, transactions, locking, exact money, and migrations.

### Infrastructure

- [`guidelines/docker.md`](guidelines/docker.md) — reproducible images,
  multi-stage builds, BuildKit, runtime security, Compose, health checks,
  migrations, CI delivery, and Kubernetes interoperability.

## Automated Installation

`install.sh` recursively detects supported stacks, including applications in a
monorepo, evaluates each workspace independently, and installs only the
applicable documents. Preview the selection before writing:

```bash
./install.sh --dry-run /path/to/project
```

Install the selected guidelines:

```bash
./install.sh /path/to/project
```

### Install directly with `curl`

From the target project's root, preview a remote installation:

```bash
curl -fsSL https://raw.githubusercontent.com/haikelz/ai-guideline/master/install.sh \
  | bash -s -- --dry-run .
```

Then install:

```bash
curl -fsSL https://raw.githubusercontent.com/haikelz/ai-guideline/master/install.sh \
  | bash -s -- .
```

To install into another directory, replace `.` with its path. Arguments after
`bash -s --` are passed to the installer, so options can be combined:

```bash
curl -fsSL https://raw.githubusercontent.com/haikelz/ai-guideline/master/install.sh \
  | bash -s -- --force /path/to/project
```

The piped installer downloads only the detected guidelines and the ignore-file
template over HTTPS. For reproducible automation, pin both the installer and its
downloaded files to a reviewed tag or commit:

```bash
REF='<tag-or-full-commit-sha>'
curl -fsSL "https://raw.githubusercontent.com/haikelz/ai-guideline/$REF/install.sh" \
  | AI_GUIDELINE_REF="$REF" bash -s -- .
```

Review-first installation is safer than piping an uninspected moving branch:

```bash
curl -fsSLo /tmp/ai-guideline-install.sh \
  https://raw.githubusercontent.com/haikelz/ai-guideline/master/install.sh
less /tmp/ai-guideline-install.sh
bash /tmp/ai-guideline-install.sh --dry-run .
bash /tmp/ai-guideline-install.sh .
rm /tmp/ai-guideline-install.sh
```

The installer reports its embedded version with `./install.sh --version`. Remote
mode downloads `VERSION` and `CHECKSUMS.sha256`, verifies every selected
guideline and ignore template before writing to the target, and rejects an
installer/source version mismatch. A downloaded installer also verifies its own
checksum. A piped script cannot verify itself before execution, and checksums
from the same source provide integrity rather than source authenticity. For
automation, prefer an immutable reviewed tag and verify the downloaded script
before running it.

`AI_GUIDELINE_BASE_URL` can point the downloaded installer at another HTTPS raw
content mirror. `AI_GUIDELINE_REF` defaults to the moving `master` branch; set it
to an immutable release tag or full commit SHA for reproducible installation.

The installer writes this project-local layout:

```text
.cursorignore
.ignore
.geminiignore
.aiderignore
.continueignore
.clineignore
.codeiumignore
.rooignore
.aiignore
AGENTS.md
.agents/
├── general.md
├── preferences.md
├── .ai-guideline-manifest
├── .ai-guideline-workspaces  # only with --workspace-instructions
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

### Context profiles

The managed `AGENTS.md` block composes task-oriented context profiles from the
detected stack. Every task reads `general.md` and `preferences.md`, then loads
only the smallest matching companion set. For example, a repository containing
a Next.js app and Docker configuration receives separate profiles for JavaScript
or TypeScript, Next.js application work, and container or delivery work. A
UI-only task does not load the Docker guideline, and a Docker-only task does not
load the Next.js guideline.

Profiles are navigational pointers, not copies of policy. Cross-cutting work uses
the union of only the affected profiles. This keeps agent context focused while
preserving one source of truth for each language, framework, persistence, or
infrastructure rule.

### Monorepo workflows

The default remains fast and centralized: run the installer once at the
repository root. It installs the union of required documents in root `.agents`,
records each workspace's final stack decision in the manifest, and adds path
scopes to the managed root `AGENTS.md` block. Composite detection is local to a
workspace, so GORM in one Go module and a PostgreSQL driver in another do not
incorrectly select the combined persistence guideline.

Explain every decision without writing:

```bash
./install.sh --explain /path/to/monorepo
```

The report maps evidence files to workspace paths and final stack profiles. It
also reports recognized workspace metadata such as `go.work`,
`pnpm-workspace.yaml`, `nx.json`, `turbo.json`, and `lerna.json`.

For the fastest focused setup, install only inside one workspace:

```bash
./install.sh --workspace apps/web /path/to/monorepo
./install.sh --workspace services/worker /path/to/monorepo
```

This writes `.agents`, `AGENTS.md`, and ignore files inside the selected
workspace and does not change the monorepo root or sibling workspaces.

Create package-scoped instructions only when closer instructions are useful:

```bash
./install.sh --workspace-instructions /path/to/monorepo
```

This option writes bounded managed blocks to detected workspace `AGENTS.md`
files. Existing content is preserved, paths point to the shared root `.agents`,
repeated runs are deterministic, and stale managed blocks are removed when a
workspace disappears from detection. Without this option, nested `AGENTS.md`
files are not modified.

### Detection overrides

Use repeated command-line overrides for one run:

```bash
./install.sh --include fiber --exclude docker /path/to/project
```

For durable repository decisions, create `.ai-guideline.conf` at the target
repository root with one non-executable directive per line:

```text
# Supported directives are include and exclude.
include nextjs
exclude docker
```

Supported names are `javascript-typescript`, `astro`, `nextjs`, `nestjs`, `go`,
`echo`, `fiber`, `gorm-postgresql`, and `docker`. Unknown names, malformed lines,
duplicate include/exclude conflicts, and framework selections without their
language dependency are rejected before files are written. An explicit Docker
exclusion is allowed when a project does not use containers.

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

### Coding-agent ignore files

By default, the installer creates or updates the supported ignore files listed
above. They share a conservative block for secrets, credentials, dependencies,
generated output, caches, local state, logs, temporary files, and compiled
binaries. Existing project-specific content is preserved outside these markers:

```text
# AI-GUIDELINES-IGNORE:BEGIN
...
# AI-GUIDELINES-IGNORE:END
```

Skip ignore-file installation when a project manages these policies elsewhere:

```bash
./install.sh --skip-ignore-files /path/to/project
```

OpenCode does not support `.opencodeignore`; its supported generic file is
`.ignore`, which is also used by Codex file discovery. Unsupported names such as
`.claudeignore`, `.codexignore`, `.copilotignore`, and `.ampignore` are not
created. See the [ignore-file reference](ignores/README.md) for the complete
agent mapping and enforcement limitations. Ignore files reduce accidental
context and indexing, but they are not security sandboxes and may be bypassed by
terminal or plugin tools.

### Detection matrix

| Evidence found in one workspace | Guidelines selected |
| --- | --- |
| Every project | General |
| `package.json`, `tsconfig.json`, or `jsconfig.json` | JavaScript and TypeScript |
| Astro dependency or `astro.config.*` | JavaScript and TypeScript, Astro, Docker |
| Next.js dependency or `next.config.*` | JavaScript and TypeScript, Next.js, Docker |
| NestJS dependency or `nest-cli.json` | JavaScript and TypeScript, NestJS, Docker |
| `go.mod` | Go, Docker |
| Echo module in `go.mod` | Echo, in addition to Go |
| Fiber module in `go.mod` | Fiber, in addition to Go |
| GORM plus a PostgreSQL driver in the same `go.mod` | GORM and PostgreSQL, in addition to Go |
| Dockerfile or Compose file | Docker |

Generated output, dependencies, VCS metadata, vendor trees, caches, and an
existing `.agents` directory are excluded from detection. Detection does not
execute project code or read environment files. Paths containing spaces are
supported; paths containing control characters or Markdown backticks are
rejected when generating scoped instructions.

## Usage

Use `general.md` and `preferences.md` as the project-wide baseline, then load
only the applicable language, framework, persistence, and infrastructure
companions. These guidelines do not replace repository-local rules. The order
of precedence is:

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
guideline. An Echo or Fiber service uses the Go guideline plus its HTTP framework
companion; add the GORM and PostgreSQL companion when that persistence stack is
present. Do not load unrelated framework documents merely because they exist.

## Releases

The current release is recorded in [`VERSION`](VERSION). Release payload hashes
are published in [`CHECKSUMS.sha256`](CHECKSUMS.sha256), and Linux plus macOS CI
validates shell portability, repository contracts, Markdown, checksums, and the
installer suite. See the [release process](RELEASING.md) before changing a
version or publishing a tag.

## Core Principles

1. **Correct before elegant.** Understand ownership, contracts, and invariants
   before changing an implementation.
2. **Simple but explicit.** Choose the solution with the fewest layers, helpers,
   and names that still makes intent clear.
3. **Mechanically consistent, semantically readable.** Formatters and linters own
   mechanical policy; deliberate source structure and semantic spacing still
   require human review.
4. **Typed and validated boundaries.** Never trust external input.
5. **Visible business invariants.** Place policy in the domain or use case, enforce
   it in the database where possible, and prove it with tests.
6. **Intentional compatibility.** Do not accidentally change routes, schemas,
   envelopes, status codes, or public behavior.
7. **Verification is part of implementation.** A change is not complete until the
   relevant formatter, static analysis, tests, and build have run.
8. **Never conceal failure.** Do not ignore errors, misrepresent test results, or
   add special cases merely to make a test pass.
