# Changelog

All notable changes to this project are documented here. Releases follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `guidelines/tutor.md`: the agent explains while sending the complete code, the
  owner types it by hand, and the agent reviews with a run, ranked findings,
  and the fix for each one. Per-task switches (`tutor off`, `pair`,
  `challenge`, `drill`) and a LeetCode-style drill mode with a hint ladder and
  the full solution after each attempt.
- Every install includes tutor mode by default; `--exclude tutor` or
  `exclude tutor` in `.ai-guideline.conf` opts out.

### Changed

- `general.md` now holds only every-task rules and the single precedence chain
  (§2); setup, documentation, CI, and process guidance moved to the new
  `harness.md`, which defers to a repository's own harness workflow. Every
  guideline header points to that chain.
- Echo guidance targets v5 first, Next.js guidance targets 16, and Zod examples
  use the v4 API. Base and framework guides no longer contradict the `haikel-*`
  owner profiles.
- Docker guidance defaults to a single-host Dokploy profile, adds Bun images,
  and fixes the pnpm, Go builder, and distroless healthcheck examples.
- The agent ignore template anchors root-only build directories, covers more
  secret files, and keeps example env files visible.
- The installer warns when `.agents/` is ignored by Git.

### Added

- A frontend design-system guideline for ReUI on shadcn `base-nova`, Geist Sans
  and Geist Mono, oklch tokens, flat surfaces, and Svelte ports. The installer
  selects it when a workspace has `components.json` and routes UI work to it.
- A TypeSafe AI and Jev decision-system guideline with scoped SDK detection,
  explicit inclusion for HTTP clients, and workspace-specific context profiles.
- `--ignore-agent` selects one coding-agent ignore file instead of generating
  every supported ignore-file variant by default.
- The installer creates a root `GEMINI.md` that imports `AGENTS.md` when the
  project has `.gemini/` or uses `--ignore-agent gemini`, and warns when an
  existing `GEMINI.md` does not import it.
- The `haikel-*` profiles and their base language guidelines now state that the
  profile wins on conflict.
- The Go and TypeScript owner profiles were re-derived from the newest reference
  services: handler route registration, error-to-message mapping, transaction
  helpers, list contracts, React Query hook modules, a shared request client,
  readonly props, ternary-null rendering, and `trailingComma: "all"`.
- Go presentation guidance now makes the reference services' route, input, and
  direct-delegation spacing conventions explicit.
- Shared whitespace conventions now apply those route, input, and delegation
  rules across Go and JavaScript/TypeScript work.
- A project-wide owner preference profile covering complete-scope cleanup,
  semantic code rhythm, preferred React tooling, non-generic interface design,
  natural Indonesian and English writing, verification, and Git delivery.
- Owner-specific JavaScript/TypeScript and Go engineering profiles derived from
  established frontend, backend, and service practices.
- Owner-specific semantic spacing rules for visually grouping authentication,
  validation, execution, persistence, transformation, and test phases.
- A precise Go module style covering domain file placement, import order,
  handler/usecase/repository workflows, vertical GORM chains, and transaction
  phase layout.
- A precise TypeScript frontend style covering ES5 trailing commas, import and
  declaration order, component rhythm, URL state, and feature file ownership.
- Workspace-aware monorepo detection with path-scoped context profiles.
- Explainable evidence, focused workspace installation, and validated stack
  overrides.
- Optional nested workspace instructions with preservation and stale cleanup.

## [1.1.0] - 2026-08-28

### Added

- Task-oriented context profiles composed from each detected project stack.
- Minimal companion loading instructions for single-area and cross-cutting work.

## [1.0.0] - 2026-08-28

### Added

- Project-wide engineering and repository quality-harness guidance.
- JavaScript, TypeScript, Astro, Next.js, and NestJS guidelines.
- Go, Echo, Fiber, GORM, and PostgreSQL guidelines.
- Docker build, runtime, Compose, delivery, and orchestration guidance.
- Stack-detecting local and remote installer with conflict-safe updates.
- Supported coding-agent ignore files with bounded managed blocks.
- Versioned remote payload checksums and installer/source mismatch detection.
- Linux and macOS continuous-integration validation.
- Reproducible tagged-release archive workflow.

[Unreleased]: https://github.com/haikelz/ai-guideline/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/haikelz/ai-guideline/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/haikelz/ai-guideline/releases/tag/v1.0.0
