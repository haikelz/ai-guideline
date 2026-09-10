#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT
readonly INSTALLER="$ROOT/install.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/ai-guideline-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_no_file() {
  [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_line() {
  grep -Fxq -- "$2" "$1" || fail "$1 does not contain exact line: $2"
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    fail "$1 unexpectedly contains: $2"
  fi
}

assert_count() {
  local actual
  actual=$(grep -Fc -- "$2" "$1" || true)
  [[ "$actual" == "$3" ]] || fail "$1 contains '$2' $actual times; expected $3"
}

assert_text_contains() {
  [[ "$1" == *"$2"* ]] || fail "output does not contain: $2"
}

assert_text_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "output unexpectedly contains: $2"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

next="$work/next-app"
mkdir -p "$next"
cat >"$next/package.json" <<'JSON'
{"private":true,"dependencies":{"next":"15.0.0","react":"19.0.0"}}
JSON
printf '# Existing instructions\n' >"$next/AGENTS.md"
printf '# Existing Cursor policy\nprivate-designs/\n' >"$next/.cursorignore"

"$INSTALLER" --dry-run "$next" >/dev/null
assert_no_file "$next/.agents"
assert_not_contains "$next/.cursorignore" '# AI-GUIDELINES-IGNORE:BEGIN'

"$INSTALLER" --ignore-agent cursor "$next" >/dev/null
assert_file "$next/.agents/general.md"
assert_file "$next/.agents/preferences.md"
assert_file "$next/.agents/guidelines/javascript-typescript.md"
assert_file "$next/.agents/guidelines/haikel-javascript-typescript.md"
assert_file "$next/.agents/guidelines/nextjs.md"
assert_file "$next/.agents/guidelines/docker.md"
assert_no_file "$next/.agents/guidelines/nestjs.md"
assert_contains "$next/AGENTS.md" '# Existing instructions'
assert_count "$next/AGENTS.md" '<!-- AI-GUIDELINES:BEGIN -->' 1
assert_contains "$next/AGENTS.md" 'select the smallest matching context profile'
assert_contains "$next/AGENTS.md" "\`.agents/general.md\` and \`.agents/preferences.md\`"
assert_contains "$next/AGENTS.md" 'Do not read every installed companion by default.'
assert_contains "$next/AGENTS.md" "- **Next.js UI or application work:** \`.agents/guidelines/javascript-typescript.md\`, \`.agents/guidelines/haikel-javascript-typescript.md\`, and \`.agents/guidelines/nextjs.md\`."
assert_not_contains "$next/AGENTS.md" 'NestJS API or service work'
assert_file "$next/.cursorignore"
assert_count "$next/.cursorignore" '# AI-GUIDELINES-IGNORE:BEGIN' 1
for ignore_file in \
  .ignore .geminiignore .aiderignore .continueignore .clineignore \
  .codeiumignore .rooignore .aiignore; do
  assert_no_file "$next/$ignore_file"
done
assert_contains "$next/.cursorignore" '# Existing Cursor policy'
assert_contains "$next/.cursorignore" 'private-designs/'

before=$(sha256_file "$next/AGENTS.md")
ignore_before=$(sha256_file "$next/.cursorignore")
"$INSTALLER" --ignore-agent cursor "$next" >/dev/null
after=$(sha256_file "$next/AGENTS.md")
ignore_after=$(sha256_file "$next/.cursorignore")
[[ "$before" == "$after" ]] || fail 'repeated installation is not deterministic'
[[ "$ignore_before" == "$ignore_after" ]] || fail 'repeated ignore installation is not deterministic'

sed 's/^\.env$/.env-broken/' "$next/.cursorignore" >"$next/.cursorignore.tmp"
mv "$next/.cursorignore.tmp" "$next/.cursorignore"
"$INSTALLER" --ignore-agent cursor "$next" >/dev/null
assert_contains "$next/.cursorignore" '# Existing Cursor policy'
assert_line "$next/.cursorignore" '.env'
assert_not_contains "$next/.cursorignore" '.env-broken'

printf '\nlocal change\n' >>"$next/.agents/guidelines/nextjs.md"
if "$INSTALLER" "$next" >/dev/null 2>&1; then
  fail 'locally modified guideline did not cause a conflict'
fi
"$INSTALLER" --force "$next" >/dev/null
cmp -s "$ROOT/guidelines/nextjs.md" "$next/.agents/guidelines/nextjs.md" || fail 'force did not restore source guideline'

printf '{"private":true,"devDependencies":{"typescript":"6.0.0"}}\n' >"$next/package.json"
"$INSTALLER" "$next" >/dev/null
assert_no_file "$next/.agents/guidelines/nextjs.md"
assert_no_file "$next/.agents/guidelines/docker.md"
assert_not_contains "$next/AGENTS.md" '.agents/guidelines/nextjs.md'
assert_not_contains "$next/AGENTS.md" 'Next.js UI or application work'
assert_count "$next/AGENTS.md" '<!-- AI-GUIDELINES:BEGIN -->' 1

go_app="$work/go-app"
mkdir -p "$go_app"
cat >"$go_app/go.mod" <<'MOD'
module example.test/service

go 1.25

require (
  github.com/labstack/echo/v4 v4.15.0
  gorm.io/driver/postgres v1.6.0
  gorm.io/gorm v1.31.0
)
MOD
"$INSTALLER" "$go_app" >/dev/null
assert_file "$go_app/.agents/guidelines/go.md"
assert_file "$go_app/.agents/guidelines/haikel-go.md"
assert_file "$go_app/.agents/guidelines/echo.md"
assert_file "$go_app/.agents/guidelines/gorm-postgresql.md"
assert_file "$go_app/.agents/guidelines/docker.md"
assert_no_file "$go_app/.agents/guidelines/javascript-typescript.md"
assert_contains "$go_app/AGENTS.md" "- **Echo HTTP work:** \`.agents/guidelines/go.md\`, \`.agents/guidelines/haikel-go.md\`, and \`.agents/guidelines/echo.md\`."
assert_contains "$go_app/AGENTS.md" '- **GORM or PostgreSQL persistence work:'
assert_contains "$go_app/AGENTS.md" '- **Container, Compose, delivery, or runtime work:'

fiber_app="$work/fiber-app"
mkdir -p "$fiber_app"
cat >"$fiber_app/go.mod" <<'MOD'
module example.test/fiber-service

go 1.24

require github.com/gofiber/fiber/v2 v2.52.9
MOD
"$INSTALLER" "$fiber_app" >/dev/null
assert_file "$fiber_app/.agents/guidelines/go.md"
assert_file "$fiber_app/.agents/guidelines/haikel-go.md"
assert_file "$fiber_app/.agents/guidelines/fiber.md"
assert_file "$fiber_app/.agents/guidelines/docker.md"
assert_no_file "$fiber_app/.agents/guidelines/echo.md"
assert_no_file "$fiber_app/.agents/guidelines/gorm-postgresql.md"
assert_contains "$fiber_app/AGENTS.md" "- **Fiber HTTP work:** \`.agents/guidelines/go.md\`, \`.agents/guidelines/haikel-go.md\`, and \`.agents/guidelines/fiber.md\`."
assert_not_contains "$fiber_app/AGENTS.md" 'Echo HTTP work'

typescript="$work/typescript-library"
mkdir -p "$typescript"
printf '{"private":true,"devDependencies":{"typescript":"6.0.0"}}\n' >"$typescript/package.json"
"$INSTALLER" "$typescript" >/dev/null
assert_file "$typescript/.agents/guidelines/javascript-typescript.md"
assert_file "$typescript/.agents/guidelines/haikel-javascript-typescript.md"
assert_no_file "$typescript/.agents/guidelines/docker.md"

without_ignores="$work/without-ignores"
mkdir -p "$without_ignores"
printf '{"devDependencies":{"typescript":"6.0.0"}}\n' >"$without_ignores/package.json"
"$INSTALLER" "$without_ignores" >/dev/null
assert_file "$without_ignores/.agents/guidelines/javascript-typescript.md"
assert_file "$without_ignores/.agents/guidelines/haikel-javascript-typescript.md"
assert_no_file "$without_ignores/.cursorignore"
assert_no_file "$without_ignores/.ignore"

codex="$work/codex-app"
mkdir -p "$codex"
printf '{"devDependencies":{"typescript":"6.0.0"}}\n' >"$codex/package.json"
"$INSTALLER" --ignore-agent=codex "$codex" >/dev/null
assert_file "$codex/.ignore"
assert_no_file "$codex/.cursorignore"
assert_count "$codex/.ignore" '# AI-GUIDELINES-IGNORE:BEGIN' 1

if "$INSTALLER" --ignore-agent unknown "$codex" >/dev/null 2>&1; then
  fail 'unsupported ignore agent was accepted'
fi

astro="$work/astro-monorepo"
mkdir -p "$astro/apps/web"
printf '{"private":true,"workspaces":["apps/*"]}\n' >"$astro/package.json"
printf '{"dependencies":{"astro":"7.0.0","@astrojs/svelte":"8.0.0"}}\n' >"$astro/apps/web/package.json"
"$INSTALLER" "$astro" >/dev/null
assert_file "$astro/.agents/guidelines/javascript-typescript.md"
assert_file "$astro/.agents/guidelines/haikel-javascript-typescript.md"
assert_file "$astro/.agents/guidelines/astro.md"
assert_file "$astro/.agents/guidelines/docker.md"
assert_no_file "$astro/.agents/guidelines/nextjs.md"

monorepo="$work/mixed monorepo"
mkdir -p \
  "$monorepo/apps/customer portal" \
  "$monorepo/apps/api" \
  "$monorepo/apps/nx-api" \
  "$monorepo/services/gorm-only" \
  "$monorepo/services/postgres-only" \
  "$monorepo/node_modules/ignored-app" \
  "$monorepo/.nx/cache/ignored-app"
printf '{"private":true,"workspaces":["apps/*"]}\n' >"$monorepo/package.json"
printf 'packages:\n  - apps/*\n' >"$monorepo/pnpm-workspace.yaml"
printf '{"dependencies":{"next":"15.0.0"}}\n' >"$monorepo/apps/customer portal/package.json"
printf '{"dependencies":{"@nestjs/core":"11.0.0"}}\n' >"$monorepo/apps/api/package.json"
printf '{"targets":{"serve":{"executor":"@nx/nest:serve"}}}\n' >"$monorepo/apps/nx-api/project.json"
printf 'go 1.25\n\nuse (\n  ./services/gorm-only\n  ./services/postgres-only\n)\n' >"$monorepo/go.work"
printf '# Existing workspace policy\n' >"$monorepo/apps/customer portal/AGENTS.md"
cat >"$monorepo/services/gorm-only/go.mod" <<'MOD'
module example.test/gorm-only

go 1.25

require gorm.io/gorm v1.31.0
MOD
cat >"$monorepo/services/postgres-only/go.mod" <<'MOD'
module example.test/postgres-only

go 1.25

require github.com/jackc/pgx/v5 v5.7.0
MOD
printf '{"dependencies":{"astro":"7.0.0"}}\n' >"$monorepo/node_modules/ignored-app/package.json"
printf '{"dependencies":{"astro":"7.0.0"}}\n' >"$monorepo/.nx/cache/ignored-app/package.json"

explain_output=$("$INSTALLER" --explain "$monorepo")
assert_text_contains "$explain_output" 'Detection evidence:'
assert_text_contains "$explain_output" 'apps/customer portal/package.json -> apps/customer portal: nextjs'
assert_text_contains "$explain_output" 'pnpm-workspace.yaml'
assert_text_contains "$explain_output" 'go.work'
assert_text_contains "$explain_output" 'apps/nx-api/project.json -> apps/nx-api: nestjs'
assert_text_contains "$explain_output" 'apps/customer portal: javascript-typescript nextjs docker'
assert_text_not_contains "$explain_output" 'gorm-postgresql'
assert_text_not_contains "$explain_output" 'astro'
assert_no_file "$monorepo/.agents"

workspace_policy_before=$(sha256_file "$monorepo/apps/customer portal/AGENTS.md")
"$INSTALLER" "$monorepo" >/dev/null
workspace_policy_after=$(sha256_file "$monorepo/apps/customer portal/AGENTS.md")
[[ "$workspace_policy_before" == "$workspace_policy_after" ]] || fail 'default monorepo install changed nested instructions'
assert_no_file "$monorepo/apps/api/AGENTS.md"

"$INSTALLER" --workspace-instructions "$monorepo" >/dev/null
assert_file "$monorepo/.agents/guidelines/nextjs.md"
assert_file "$monorepo/.agents/guidelines/nestjs.md"
assert_file "$monorepo/.agents/guidelines/go.md"
assert_no_file "$monorepo/.agents/guidelines/gorm-postgresql.md"
assert_contains "$monorepo/AGENTS.md" "\`apps/customer portal/**\`: javascript-typescript, nextjs, docker."
assert_contains "$monorepo/apps/customer portal/AGENTS.md" '# Existing workspace policy'
assert_contains "$monorepo/apps/customer portal/AGENTS.md" "Scope: \`apps/customer portal/**\`."
assert_contains "$monorepo/apps/customer portal/AGENTS.md" "\`../../.agents/general.md\`"
assert_contains "$monorepo/apps/customer portal/AGENTS.md" "\`../../.agents/preferences.md\`"
assert_contains "$monorepo/apps/api/AGENTS.md" "\`../../.agents/guidelines/nestjs.md\`"
assert_contains "$monorepo/apps/nx-api/AGENTS.md" "\`../../.agents/guidelines/nestjs.md\`"
assert_contains "$monorepo/.agents/.ai-guideline-workspaces" 'apps/customer portal'
assert_contains "$monorepo/.agents/.ai-guideline-manifest" '# workspace apps/customer portal: javascript-typescript nextjs docker'

monorepo_agents_before=$(sha256_file "$monorepo/apps/customer portal/AGENTS.md")
"$INSTALLER" --workspace-instructions "$monorepo" >/dev/null
monorepo_agents_after=$(sha256_file "$monorepo/apps/customer portal/AGENTS.md")
[[ "$monorepo_agents_before" == "$monorepo_agents_after" ]] || fail 'workspace instructions are not deterministic'

rm "$monorepo/apps/api/package.json"
"$INSTALLER" --workspace-instructions "$monorepo" >/dev/null
assert_no_file "$monorepo/apps/api/AGENTS.md"
assert_not_contains "$monorepo/.agents/.ai-guideline-workspaces" 'apps/api'

mv "$monorepo/apps/customer portal" "$monorepo/apps/customer site"
"$INSTALLER" --workspace-instructions "$monorepo" >/dev/null
assert_contains "$monorepo/apps/customer site/AGENTS.md" '# Existing workspace policy'
assert_contains "$monorepo/apps/customer site/AGENTS.md" "Scope: \`apps/customer site/**\`."
assert_contains "$monorepo/.agents/.ai-guideline-workspaces" 'apps/customer site'
assert_not_contains "$monorepo/.agents/.ai-guideline-workspaces" 'apps/customer portal'

workspace_target="$work/workspace-target"
mkdir -p "$workspace_target/apps/web" "$workspace_target/services/api"
printf '{"dependencies":{"next":"15.0.0"}}\n' >"$workspace_target/apps/web/package.json"
cat >"$workspace_target/services/api/go.mod" <<'MOD'
module example.test/api

go 1.25

require github.com/gofiber/fiber/v2 v2.52.9
MOD
"$INSTALLER" --workspace apps/web "$workspace_target" >/dev/null
assert_file "$workspace_target/apps/web/.agents/guidelines/nextjs.md"
assert_no_file "$workspace_target/apps/web/.agents/guidelines/fiber.md"
assert_no_file "$workspace_target/.agents"
assert_contains "$workspace_target/apps/web/AGENTS.md" '.agents/guidelines/nextjs.md'
if "$INSTALLER" --workspace ../workspace-target "$workspace_target" >/dev/null 2>&1; then
  fail 'workspace path traversal was accepted'
fi
if "$INSTALLER" --workspace apps/web --workspace-instructions "$workspace_target" >/dev/null 2>&1; then
  fail 'conflicting workspace modes were accepted'
fi

overrides="$work/overrides"
mkdir -p "$overrides"
printf '{"devDependencies":{"typescript":"6.0.0"}}\n' >"$overrides/package.json"
printf 'include nextjs\nexclude docker\n' >"$overrides/.ai-guideline.conf"
override_output=$("$INSTALLER" --explain "$overrides")
assert_text_contains "$override_output" 'nextjs'
assert_text_not_contains "$override_output" 'guidelines/docker.md'
"$INSTALLER" "$overrides" >/dev/null
assert_file "$overrides/.agents/guidelines/nextjs.md"
assert_no_file "$overrides/.agents/guidelines/docker.md"

if "$INSTALLER" --include docker "$overrides" >/dev/null 2>&1; then
  fail 'conflicting include and exclude overrides were accepted'
fi
printf 'include unknown-stack\n' >"$overrides/.ai-guideline.conf"
if "$INSTALLER" "$overrides" >/dev/null 2>&1; then
  fail 'unknown configured stack was accepted'
fi
printf 'exclude javascript-typescript\n' >"$overrides/.ai-guideline.conf"
printf '{"dependencies":{"next":"15.0.0"}}\n' >"$overrides/package.json"
if "$INSTALLER" "$overrides" >/dev/null 2>&1; then
  fail 'framework without its language dependency was accepted'
fi

included="$work/included-stack"
mkdir -p "$included"
"$INSTALLER" --include fiber "$included" >/dev/null
assert_file "$included/.agents/guidelines/go.md"
assert_file "$included/.agents/guidelines/fiber.md"
assert_file "$included/.agents/guidelines/docker.md"

malformed_workspace="$work/malformed-workspace"
mkdir -p "$malformed_workspace/apps/web"
printf '{"dependencies":{"next":"15.0.0"}}\n' >"$malformed_workspace/apps/web/package.json"
printf '<!-- AI-GUIDELINES:END -->\n<!-- AI-GUIDELINES:BEGIN -->\n' >"$malformed_workspace/apps/web/AGENTS.md"
if "$INSTALLER" --workspace-instructions "$malformed_workspace" >/dev/null 2>&1; then
  fail 'malformed workspace AGENTS.md markers were accepted'
fi
assert_no_file "$malformed_workspace/.agents"

stale_modified="$work/stale-modified"
mkdir -p "$stale_modified"
printf '{"dependencies":{"@nestjs/core":"11.0.0"}}\n' >"$stale_modified/package.json"
"$INSTALLER" "$stale_modified" >/dev/null
printf '\nlocal policy\n' >>"$stale_modified/.agents/guidelines/nestjs.md"
printf '{"devDependencies":{"typescript":"6.0.0"}}\n' >"$stale_modified/package.json"
"$INSTALLER" "$stale_modified" >/dev/null 2>&1
assert_file "$stale_modified/.agents/guidelines/nestjs.md"
assert_not_contains "$stale_modified/AGENTS.md" '.agents/guidelines/nestjs.md'

malformed="$work/malformed-agents"
mkdir -p "$malformed"
printf '<!-- AI-GUIDELINES:END -->\n<!-- AI-GUIDELINES:BEGIN -->\n' >"$malformed/AGENTS.md"
if "$INSTALLER" "$malformed" >/dev/null 2>&1; then
  fail 'reversed AGENTS.md markers were accepted'
fi
assert_no_file "$malformed/.agents"

malformed_ignore="$work/malformed-ignore"
mkdir -p "$malformed_ignore"
printf '# AI-GUIDELINES-IGNORE:END\n# AI-GUIDELINES-IGNORE:BEGIN\n' >"$malformed_ignore/.cursorignore"
if "$INSTALLER" --ignore-agent cursor "$malformed_ignore" >/dev/null 2>&1; then
  fail 'reversed ignore markers were accepted'
fi
assert_no_file "$malformed_ignore/.agents"

remote="$work/remote-next"
mkdir -p "$remote"
printf '{"dependencies":{"next":"15.0.0"}}\n' >"$remote/package.json"
(
  cd "$work"
  AI_GUIDELINE_BASE_URL="file://$ROOT" bash -s -- --dry-run "$remote" <"$INSTALLER"
) >/dev/null
assert_no_file "$remote/.agents"
(
  cd "$work"
  AI_GUIDELINE_BASE_URL="file://$ROOT" bash -s -- --ignore-agent codex "$remote" <"$INSTALLER"
) >/dev/null
assert_file "$remote/.agents/guidelines/nextjs.md"
assert_file "$remote/.agents/guidelines/docker.md"
assert_file "$remote/.ignore"
assert_no_file "$remote/.cursorignore"

tampered_mirror="$work/tampered-mirror"
tampered_target="$work/tampered-target"
mkdir -p "$tampered_mirror/ignores" "$tampered_target"
cp "$ROOT/VERSION" "$ROOT/CHECKSUMS.sha256" "$ROOT/general.md" "$ROOT/preferences.md" "$tampered_mirror/"
cp "$ROOT/ignores/agent.ignore" "$tampered_mirror/ignores/"
printf '\ntampered payload\n' >>"$tampered_mirror/general.md"
if (
  cd "$work"
  AI_GUIDELINE_BASE_URL="file://$tampered_mirror" \
    bash -s -- "$tampered_target" <"$INSTALLER"
) >/dev/null 2>&1; then
  fail 'remote payload with an invalid checksum was accepted'
fi
assert_no_file "$tampered_target/.agents"

reviewed="$work/reviewed-download"
mkdir -p "$reviewed"
printf '{"dependencies":{"astro":"7.0.0"}}\n' >"$reviewed/package.json"
cp "$INSTALLER" "$work/downloaded-install.sh"
AI_GUIDELINE_BASE_URL="file://$ROOT" \
  bash "$work/downloaded-install.sh" --ignore-agent gemini "$reviewed" >/dev/null
assert_file "$reviewed/.agents/guidelines/astro.md"
assert_file "$reviewed/.agents/guidelines/docker.md"
assert_file "$reviewed/.geminiignore"

printf 'PASS: install.sh\n'
