#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT
readonly OUTPUT="$ROOT/CHECKSUMS.sha256"
mode=${1:-write}

case "$mode" in
  write | --check) ;;
  *)
    printf 'Usage: %s [--check]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf '%s: sha256sum or shasum is required\n' "${0##*/}" >&2
    exit 2
  fi
}

files=(
  'VERSION'
  'install.sh'
  'general.md'
  'preferences.md'
  'ignores/agent.ignore'
)
while IFS= read -r guideline; do
  files+=("$guideline")
done < <(cd "$ROOT" && printf '%s\n' guidelines/*.md | LC_ALL=C sort)

tmp=$(mktemp "${TMPDIR:-/tmp}/ai-guideline-checksums.XXXXXX")
trap 'rm -f "$tmp"' EXIT

for file in "${files[@]}"; do
  if [[ ! -f "$ROOT/$file" ]]; then
    printf '%s: release payload is missing: %s\n' "${0##*/}" "$file" >&2
    exit 2
  fi
  printf '%s  %s\n' "$(sha256_file "$ROOT/$file")" "$file" >>"$tmp"
done

if [[ "$mode" == '--check' ]]; then
  if [[ ! -f "$OUTPUT" ]] || ! cmp -s "$tmp" "$OUTPUT"; then
    printf 'CHECKSUMS.sha256 is stale; run ./scripts/generate-checksums.sh\n' >&2
    [[ ! -f "$OUTPUT" ]] || diff -u "$OUTPUT" "$tmp" >&2 || true
    exit 1
  fi
  printf 'PASS: CHECKSUMS.sha256\n'
  exit 0
fi

cat "$tmp" >"$OUTPUT"
printf 'Updated %s\n' "$OUTPUT"
