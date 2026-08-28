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

"$INSTALLER" "$next" >/dev/null
assert_file "$next/.agents/general.md"
assert_file "$next/.agents/guidelines/javascript-typescript.md"
assert_file "$next/.agents/guidelines/nextjs.md"
assert_file "$next/.agents/guidelines/docker.md"
assert_no_file "$next/.agents/guidelines/nestjs.md"
assert_contains "$next/AGENTS.md" '# Existing instructions'
assert_count "$next/AGENTS.md" '<!-- AI-GUIDELINES:BEGIN -->' 1
assert_contains "$next/AGENTS.md" 'select the smallest matching context profile'
assert_contains "$next/AGENTS.md" 'Do not read every installed companion by default.'
assert_contains "$next/AGENTS.md" "- **Next.js UI or application work:** \`.agents/guidelines/javascript-typescript.md\` and \`.agents/guidelines/nextjs.md\`."
assert_not_contains "$next/AGENTS.md" 'NestJS API or service work'
for ignore_file in \
  .cursorignore .ignore .geminiignore .aiderignore .continueignore \
  .clineignore .codeiumignore .rooignore .aiignore; do
  assert_file "$next/$ignore_file"
  assert_count "$next/$ignore_file" '# AI-GUIDELINES-IGNORE:BEGIN' 1
done
assert_contains "$next/.cursorignore" '# Existing Cursor policy'
assert_contains "$next/.cursorignore" 'private-designs/'

before=$(sha256_file "$next/AGENTS.md")
ignore_before=$(sha256_file "$next/.cursorignore")
"$INSTALLER" "$next" >/dev/null
after=$(sha256_file "$next/AGENTS.md")
ignore_after=$(sha256_file "$next/.cursorignore")
[[ "$before" == "$after" ]] || fail 'repeated installation is not deterministic'
[[ "$ignore_before" == "$ignore_after" ]] || fail 'repeated ignore installation is not deterministic'

sed 's/^\.env$/.env-broken/' "$next/.cursorignore" >"$next/.cursorignore.tmp"
mv "$next/.cursorignore.tmp" "$next/.cursorignore"
"$INSTALLER" "$next" >/dev/null
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
assert_file "$go_app/.agents/guidelines/echo.md"
assert_file "$go_app/.agents/guidelines/gorm-postgresql.md"
assert_file "$go_app/.agents/guidelines/docker.md"
assert_no_file "$go_app/.agents/guidelines/javascript-typescript.md"
assert_contains "$go_app/AGENTS.md" "- **Echo HTTP work:** \`.agents/guidelines/go.md\` and \`.agents/guidelines/echo.md\`."
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
assert_file "$fiber_app/.agents/guidelines/fiber.md"
assert_file "$fiber_app/.agents/guidelines/docker.md"
assert_no_file "$fiber_app/.agents/guidelines/echo.md"
assert_no_file "$fiber_app/.agents/guidelines/gorm-postgresql.md"
assert_contains "$fiber_app/AGENTS.md" "- **Fiber HTTP work:** \`.agents/guidelines/go.md\` and \`.agents/guidelines/fiber.md\`."
assert_not_contains "$fiber_app/AGENTS.md" 'Echo HTTP work'

typescript="$work/typescript-library"
mkdir -p "$typescript"
printf '{"private":true,"devDependencies":{"typescript":"6.0.0"}}\n' >"$typescript/package.json"
"$INSTALLER" "$typescript" >/dev/null
assert_file "$typescript/.agents/guidelines/javascript-typescript.md"
assert_no_file "$typescript/.agents/guidelines/docker.md"

without_ignores="$work/without-ignores"
mkdir -p "$without_ignores"
printf '{"devDependencies":{"typescript":"6.0.0"}}\n' >"$without_ignores/package.json"
"$INSTALLER" --skip-ignore-files "$without_ignores" >/dev/null
assert_file "$without_ignores/.agents/guidelines/javascript-typescript.md"
assert_no_file "$without_ignores/.cursorignore"
assert_no_file "$without_ignores/.ignore"

astro="$work/astro-monorepo"
mkdir -p "$astro/apps/web"
printf '{"private":true,"workspaces":["apps/*"]}\n' >"$astro/package.json"
printf '{"dependencies":{"astro":"7.0.0","@astrojs/svelte":"8.0.0"}}\n' >"$astro/apps/web/package.json"
"$INSTALLER" "$astro" >/dev/null
assert_file "$astro/.agents/guidelines/javascript-typescript.md"
assert_file "$astro/.agents/guidelines/astro.md"
assert_file "$astro/.agents/guidelines/docker.md"
assert_no_file "$astro/.agents/guidelines/nextjs.md"

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
if "$INSTALLER" "$malformed_ignore" >/dev/null 2>&1; then
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
  AI_GUIDELINE_BASE_URL="file://$ROOT" bash -s -- "$remote" <"$INSTALLER"
) >/dev/null
assert_file "$remote/.agents/guidelines/nextjs.md"
assert_file "$remote/.agents/guidelines/docker.md"
assert_file "$remote/.cursorignore"
assert_file "$remote/.ignore"

tampered_mirror="$work/tampered-mirror"
tampered_target="$work/tampered-target"
mkdir -p "$tampered_mirror/ignores" "$tampered_target"
cp "$ROOT/VERSION" "$ROOT/CHECKSUMS.sha256" "$ROOT/general.md" "$tampered_mirror/"
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
  bash "$work/downloaded-install.sh" "$reviewed" >/dev/null
assert_file "$reviewed/.agents/guidelines/astro.md"
assert_file "$reviewed/.agents/guidelines/docker.md"
assert_file "$reviewed/.geminiignore"

printf 'PASS: install.sh\n'
