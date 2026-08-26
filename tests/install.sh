#!/usr/bin/env bash

set -euo pipefail

readonly ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
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
  grep -Fq "$2" "$1" || fail "$1 does not contain: $2"
}

assert_not_contains() {
  if grep -Fq "$2" "$1"; then
    fail "$1 unexpectedly contains: $2"
  fi
}

assert_count() {
  local actual
  actual=$(grep -Fc "$2" "$1" || true)
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
cat > "$next/package.json" <<'JSON'
{"private":true,"dependencies":{"next":"15.0.0","react":"19.0.0"}}
JSON
printf '# Existing instructions\n' > "$next/AGENTS.md"

"$INSTALLER" --dry-run "$next" >/dev/null
assert_no_file "$next/.agents"

"$INSTALLER" "$next" >/dev/null
assert_file "$next/.agents/general.md"
assert_file "$next/.agents/guidelines/javascript-typescript.md"
assert_file "$next/.agents/guidelines/nextjs.md"
assert_file "$next/.agents/guidelines/docker.md"
assert_no_file "$next/.agents/guidelines/nestjs.md"
assert_contains "$next/AGENTS.md" '# Existing instructions'
assert_count "$next/AGENTS.md" '<!-- AI-GUIDELINES:BEGIN -->' 1

before=$(sha256_file "$next/AGENTS.md")
"$INSTALLER" "$next" >/dev/null
after=$(sha256_file "$next/AGENTS.md")
[[ "$before" == "$after" ]] || fail 'repeated installation is not deterministic'

printf '\nlocal change\n' >> "$next/.agents/guidelines/nextjs.md"
if "$INSTALLER" "$next" >/dev/null 2>&1; then
  fail 'locally modified guideline did not cause a conflict'
fi
"$INSTALLER" --force "$next" >/dev/null
cmp -s "$ROOT/guidelines/nextjs.md" "$next/.agents/guidelines/nextjs.md" || fail 'force did not restore source guideline'

printf '{"private":true,"devDependencies":{"typescript":"6.0.0"}}\n' > "$next/package.json"
"$INSTALLER" "$next" >/dev/null
assert_no_file "$next/.agents/guidelines/nextjs.md"
assert_no_file "$next/.agents/guidelines/docker.md"
assert_not_contains "$next/AGENTS.md" '.agents/guidelines/nextjs.md'
assert_count "$next/AGENTS.md" '<!-- AI-GUIDELINES:BEGIN -->' 1

go_app="$work/go-app"
mkdir -p "$go_app"
cat > "$go_app/go.mod" <<'MOD'
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

typescript="$work/typescript-library"
mkdir -p "$typescript"
printf '{"private":true,"devDependencies":{"typescript":"6.0.0"}}\n' > "$typescript/package.json"
"$INSTALLER" "$typescript" >/dev/null
assert_file "$typescript/.agents/guidelines/javascript-typescript.md"
assert_no_file "$typescript/.agents/guidelines/docker.md"

astro="$work/astro-monorepo"
mkdir -p "$astro/apps/web"
printf '{"private":true,"workspaces":["apps/*"]}\n' > "$astro/package.json"
printf '{"dependencies":{"astro":"7.0.0","@astrojs/svelte":"8.0.0"}}\n' > "$astro/apps/web/package.json"
"$INSTALLER" "$astro" >/dev/null
assert_file "$astro/.agents/guidelines/javascript-typescript.md"
assert_file "$astro/.agents/guidelines/astro.md"
assert_file "$astro/.agents/guidelines/docker.md"
assert_no_file "$astro/.agents/guidelines/nextjs.md"

stale_modified="$work/stale-modified"
mkdir -p "$stale_modified"
printf '{"dependencies":{"@nestjs/core":"11.0.0"}}\n' > "$stale_modified/package.json"
"$INSTALLER" "$stale_modified" >/dev/null
printf '\nlocal policy\n' >> "$stale_modified/.agents/guidelines/nestjs.md"
printf '{"devDependencies":{"typescript":"6.0.0"}}\n' > "$stale_modified/package.json"
"$INSTALLER" "$stale_modified" >/dev/null 2>&1
assert_file "$stale_modified/.agents/guidelines/nestjs.md"
assert_not_contains "$stale_modified/AGENTS.md" '.agents/guidelines/nestjs.md'

malformed="$work/malformed-agents"
mkdir -p "$malformed"
printf '<!-- AI-GUIDELINES:END -->\n<!-- AI-GUIDELINES:BEGIN -->\n' > "$malformed/AGENTS.md"
if "$INSTALLER" "$malformed" >/dev/null 2>&1; then
  fail 'reversed AGENTS.md markers were accepted'
fi
assert_no_file "$malformed/.agents"

printf 'PASS: install.sh\n'
