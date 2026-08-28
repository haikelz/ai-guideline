#!/usr/bin/env bash

set -euo pipefail

readonly BEGIN_MARKER='<!-- AI-GUIDELINES:BEGIN -->'
readonly END_MARKER='<!-- AI-GUIDELINES:END -->'
readonly IGNORE_BEGIN_MARKER='# AI-GUIDELINES-IGNORE:BEGIN'
readonly IGNORE_END_MARKER='# AI-GUIDELINES-IGNORE:END'
readonly MANIFEST_REL='.agents/.ai-guideline-manifest'
readonly CHECKSUMS_FILE='CHECKSUMS.sha256'
readonly DEFAULT_REMOTE_ROOT='https://raw.githubusercontent.com/haikelz/ai-guideline'
readonly INSTALLER_VERSION='1.0.0'

local_source_dir=''
script_path=${BASH_SOURCE[0]:-}
if [[ -n "$script_path" && -f "$script_path" ]]; then
  script_dir=$(cd "$(dirname "$script_path")" && pwd)
  if [[ -f "$script_dir/general.md" && -f "$script_dir/ignores/agent.ignore" ]]; then
    local_source_dir=$script_dir
  fi
fi

source_dir=$local_source_dir
source_tmp=''
manifest_tmp=''
agents_block_tmp=''
managed_tmp=''

cleanup() {
  [[ -z "$source_tmp" ]] || rm -rf "$source_tmp"
  [[ -z "$manifest_tmp" ]] || rm -f "$manifest_tmp"
  [[ -z "$agents_block_tmp" ]] || rm -f "$agents_block_tmp"
  [[ -z "$managed_tmp" ]] || rm -f "$managed_tmp"
}
trap cleanup EXIT

dry_run=0
force=0
skip_ignore_files=0
show_version=0
target_arg='.'
target_seen=0

usage() {
  cat <<'EOF'
Usage: install.sh [options] [target-directory]

Detect a project's stack and install the applicable coding-agent guidelines.

Options:
  --dry-run          Print the detected stack and plan without writing.
  --force            Overwrite locally modified installed guidelines.
  --skip-ignore-files Do not create or update coding-agent ignore files.
  --version          Print the installer version and exit.
  -h, --help         Show this help text.

Installed layout:
  .agents/general.md
  .agents/guidelines/*.md
  AGENTS.md managed link block
  Supported coding-agent ignore files in the project root
EOF
}

while (($#)); do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --force)
      force=1
      ;;
    --skip-ignore-files)
      skip_ignore_files=1
      ;;
    --version)
      show_version=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      if (($# > 1)); then
        printf 'install.sh: expected at most one target directory\n' >&2
        exit 2
      fi
      if (($# == 1)); then
        target_arg=$1
        target_seen=1
      fi
      break
      ;;
    -*)
      printf 'install.sh: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      if ((target_seen)); then
        printf 'install.sh: expected at most one target directory\n' >&2
        exit 2
      fi
      target_arg=$1
      target_seen=1
      ;;
  esac
  shift
done

if ((show_version)); then
  printf 'ai-guideline installer %s\n' "$INSTALLER_VERSION"
  exit 0
fi

if [[ ! -d "$target_arg" ]]; then
  printf 'install.sh: target is not a directory: %s\n' "$target_arg" >&2
  exit 2
fi

TARGET=$(cd "$target_arg" && pwd)
readonly TARGET
if [[ -n "$local_source_dir" && "$TARGET" == "$local_source_dir" ]]; then
  printf 'install.sh: refusing to install into the guideline source repository\n' >&2
  exit 2
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'install.sh: sha256sum or shasum is required\n' >&2
    exit 2
  fi
}

verify_checksum() {
  local file=$1
  local source_rel=$2
  local checksums=$3
  local expected actual

  expected=$(awk -v path="$source_rel" '$2 == path { print $1; found=1; exit } END { if (!found) exit 1 }' "$checksums" || true)
  if ! printf '%s\n' "$expected" | grep -Eq '^[0-9a-f]{64}$'; then
    printf 'install.sh: no valid checksum for %s\n' "$source_rel" >&2
    exit 2
  fi

  actual=$(sha256_file "$file")
  if [[ "$actual" != "$expected" ]]; then
    printf 'install.sh: checksum mismatch for %s\n' "$source_rel" >&2
    exit 2
  fi
}

find_project_files() {
  find "$TARGET" \
    \( -type d \( \
    -name .git -o -name .agents -o -name node_modules -o -name vendor -o \
    -name dist -o -name build -o -name .next -o -name .astro -o \
    -name coverage -o -name .cache \
    \) -prune \) -o "$@"
}

has_file_named() {
  [[ -n $(find_project_files -type f -name "$1" -print -quit) ]]
}

selected=()
detected=()

add_selected() {
  local candidate=$1
  local existing
  for existing in "${selected[@]:-}"; do
    [[ "$existing" == "$candidate" ]] && return
  done
  selected+=("$candidate")
}

add_detected() {
  local candidate=$1
  local existing
  for existing in "${detected[@]:-}"; do
    [[ "$existing" == "$candidate" ]] && return
  done
  detected+=("$candidate")
}

has_javascript=0
has_astro=0
has_next=0
has_nest=0
has_go=0
has_echo=0
has_fiber=0
has_gorm=0
has_postgres=0
has_docker=0

while IFS= read -r -d '' manifest; do
  has_javascript=1
  grep -Eq '"astro"[[:space:]]*:' "$manifest" && has_astro=1
  grep -Eq '"next"[[:space:]]*:' "$manifest" && has_next=1
  grep -Eq '"@nestjs/core"[[:space:]]*:' "$manifest" && has_nest=1
done < <(find_project_files -type f -name package.json -print0)

if has_file_named 'tsconfig.json' || has_file_named 'jsconfig.json'; then
  has_javascript=1
fi
if has_file_named 'astro.config.*'; then
  has_javascript=1
  has_astro=1
fi
if has_file_named 'next.config.*'; then
  has_javascript=1
  has_next=1
fi
if has_file_named 'nest-cli.json'; then
  has_javascript=1
  has_nest=1
fi

while IFS= read -r -d '' mod; do
  has_go=1
  grep -Eq 'github\.com/labstack/echo(/v[0-9]+)?([[:space:]]|$)' "$mod" && has_echo=1
  grep -Eq 'github\.com/gofiber/fiber(/v[0-9]+)?([[:space:]]|$)' "$mod" && has_fiber=1
  grep -Eq 'gorm\.io/gorm([[:space:]]|$)' "$mod" && has_gorm=1
  grep -Eq '(gorm\.io/driver/postgres|github\.com/lib/pq|github\.com/jackc/pgx)' "$mod" && has_postgres=1
done < <(find_project_files -type f -name go.mod -print0)

if has_file_named 'Dockerfile*' ||
  has_file_named 'docker-compose*.yml' ||
  has_file_named 'docker-compose*.yaml' ||
  has_file_named 'compose*.yml' ||
  has_file_named 'compose*.yaml'; then
  has_docker=1
fi

add_selected 'general.md'

if ((has_javascript)); then
  add_detected 'javascript-typescript'
  add_selected 'guidelines/javascript-typescript.md'
fi
if ((has_astro)); then
  add_detected 'astro'
  add_selected 'guidelines/astro.md'
  has_docker=1
fi
if ((has_next)); then
  add_detected 'nextjs'
  add_selected 'guidelines/nextjs.md'
  has_docker=1
fi
if ((has_nest)); then
  add_detected 'nestjs'
  add_selected 'guidelines/nestjs.md'
  has_docker=1
fi
if ((has_go)); then
  add_detected 'go'
  add_selected 'guidelines/go.md'
  has_docker=1
fi
if ((has_echo)); then
  add_detected 'echo'
  add_selected 'guidelines/echo.md'
fi
if ((has_fiber)); then
  add_detected 'fiber'
  add_selected 'guidelines/fiber.md'
fi
if ((has_gorm && has_postgres)); then
  add_detected 'gorm-postgresql'
  add_selected 'guidelines/gorm-postgresql.md'
fi
if ((has_docker)); then
  add_detected 'docker'
  add_selected 'guidelines/docker.md'
fi

ignore_files=(
  '.cursorignore'
  '.ignore'
  '.geminiignore'
  '.aiderignore'
  '.continueignore'
  '.clineignore'
  '.codeiumignore'
  '.rooignore'
  '.aiignore'
)

if [[ -z "$source_dir" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    printf 'install.sh: curl is required when running without a local guideline checkout\n' >&2
    exit 2
  fi
  source_tmp=$(mktemp -d "${TMPDIR:-/tmp}/ai-guideline-source.XXXXXX")
  source_dir=$source_tmp
  repository_ref=${AI_GUIDELINE_REF:-master}
  remote_base_url=${AI_GUIDELINE_BASE_URL:-"$DEFAULT_REMOTE_ROOT/$repository_ref"}
  remote_base_url=${remote_base_url%/}
  case "$remote_base_url" in
    https://* | file://*) ;;
    *)
      printf 'install.sh: AI_GUIDELINE_BASE_URL must use https:// or file://\n' >&2
      exit 2
      ;;
  esac

  for metadata_file in VERSION "$CHECKSUMS_FILE"; do
    if ! curl -fsSL --retry 3 "$remote_base_url/$metadata_file" -o "$source_dir/$metadata_file"; then
      printf 'install.sh: failed to download %s\n' "$metadata_file" >&2
      exit 2
    fi
  done
  verify_checksum "$source_dir/VERSION" 'VERSION' "$source_dir/$CHECKSUMS_FILE"
  if [[ -n "$script_path" && -f "$script_path" ]]; then
    verify_checksum "$script_path" 'install.sh' "$source_dir/$CHECKSUMS_FILE"
  fi

  for source_rel in "${selected[@]}"; do
    mkdir -p "$source_dir/$(dirname "$source_rel")"
    if ! curl -fsSL --retry 3 "$remote_base_url/$source_rel" -o "$source_dir/$source_rel"; then
      printf 'install.sh: failed to download %s\n' "$source_rel" >&2
      exit 2
    fi
    verify_checksum "$source_dir/$source_rel" "$source_rel" "$source_dir/$CHECKSUMS_FILE"
  done
  if ((!skip_ignore_files)); then
    mkdir -p "$source_dir/ignores"
    if ! curl -fsSL --retry 3 "$remote_base_url/ignores/agent.ignore" -o "$source_dir/ignores/agent.ignore"; then
      printf 'install.sh: failed to download ignores/agent.ignore\n' >&2
      exit 2
    fi
    verify_checksum \
      "$source_dir/ignores/agent.ignore" \
      'ignores/agent.ignore' \
      "$source_dir/$CHECKSUMS_FILE"
  fi
fi

if [[ ! -f "$source_dir/VERSION" ]]; then
  printf 'install.sh: VERSION is missing from the guideline source\n' >&2
  exit 2
fi
source_version=$(tr -d '\r\n' <"$source_dir/VERSION")
if [[ "$source_version" != "$INSTALLER_VERSION" ]]; then
  printf 'install.sh: installer version %s does not match source version %s\n' \
    "$INSTALLER_VERSION" "$source_version" >&2
  exit 2
fi

destination_for() {
  case "$1" in
    general.md) printf '%s/.agents/general.md\n' "$TARGET" ;;
    guidelines/astro.md | \
      guidelines/docker.md | \
      guidelines/echo.md | \
      guidelines/fiber.md | \
      guidelines/go.md | \
      guidelines/gorm-postgresql.md | \
      guidelines/javascript-typescript.md | \
      guidelines/nestjs.md | \
      guidelines/nextjs.md)
      printf '%s/.agents/%s\n' "$TARGET" "$1"
      ;;
    *)
      printf 'install.sh: unsupported source path: %s\n' "$1" >&2
      exit 2
      ;;
  esac
}

old_hash_for() {
  local source_rel=$1
  local manifest="$TARGET/$MANIFEST_REL"
  [[ -f "$manifest" ]] || return 1
  awk -v path="$source_rel" '$1 == path { print $2; found=1; exit } END { if (!found) exit 1 }' "$manifest"
}

is_selected() {
  local candidate=$1
  local item
  for item in "${selected[@]}"; do
    [[ "$item" == "$candidate" ]] && return 0
  done
  return 1
}

conflicts=()
for source_rel in "${selected[@]}"; do
  source_path="$source_dir/$source_rel"
  destination=$(destination_for "$source_rel")
  if [[ ! -f "$source_path" ]]; then
    printf 'install.sh: guideline source is missing: %s\n' "$source_rel" >&2
    exit 2
  fi
  if [[ -f "$destination" ]] && ! cmp -s "$source_path" "$destination"; then
    current_hash=$(sha256_file "$destination")
    old_hash=$(old_hash_for "$source_rel" || true)
    if [[ -z "$old_hash" || "$current_hash" != "$old_hash" ]]; then
      conflicts+=("${destination#"$TARGET/"}")
    fi
  fi
done

validate_managed_block() {
  local file=$1
  local begin_marker=$2
  local end_marker=$3
  [[ -f "$file" ]] || return 0

  local begin_count end_count begin_line end_line
  begin_count=$(grep -Fxc "$begin_marker" "$file" || true)
  end_count=$(grep -Fxc "$end_marker" "$file" || true)
  if [[ "$begin_count" != "$end_count" || "$begin_count" -gt 1 ]]; then
    printf 'install.sh: malformed managed block in %s\n' "$file" >&2
    exit 2
  fi
  if [[ "$begin_count" == 1 ]]; then
    begin_line=$(grep -Fnx "$begin_marker" "$file" | cut -d: -f1)
    end_line=$(grep -Fnx "$end_marker" "$file" | cut -d: -f1)
    if ((begin_line >= end_line)); then
      printf 'install.sh: malformed managed block in %s\n' "$file" >&2
      exit 2
    fi
  fi
}

agents_file="$TARGET/AGENTS.md"
validate_managed_block "$agents_file" "$BEGIN_MARKER" "$END_MARKER"

if ((!skip_ignore_files)); then
  if [[ ! -f "$source_dir/ignores/agent.ignore" ]]; then
    printf 'install.sh: ignore template source is missing: ignores/agent.ignore\n' >&2
    exit 2
  fi
  validate_managed_block \
    "$source_dir/ignores/agent.ignore" \
    "$IGNORE_BEGIN_MARKER" \
    "$IGNORE_END_MARKER"
  for ignore_file in "${ignore_files[@]}"; do
    validate_managed_block "$TARGET/$ignore_file" "$IGNORE_BEGIN_MARKER" "$IGNORE_END_MARKER"
  done
fi

if ((${#conflicts[@]})) && ((!force)); then
  printf 'install.sh: locally modified guideline files would be overwritten:\n' >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  printf 'Re-run with --force to replace them.\n' >&2
  exit 3
fi

printf 'Target: %s\n' "$TARGET"
printf 'Version: %s\n' "$source_version"
if [[ -n "$local_source_dir" ]]; then
  printf 'Source: local checkout\n'
else
  printf 'Source: %s\n' "$remote_base_url"
fi
if ((${#detected[@]})); then
  printf 'Detected: '
  for index in "${!detected[@]}"; do
    ((index > 0)) && printf ', '
    printf '%s' "${detected[$index]}"
  done
  printf '\n'
else
  printf 'Detected: no supported stack; installing general guidance only\n'
fi
printf 'Guidelines:\n'
printf '  %s\n' "${selected[@]}"
if ((!skip_ignore_files)); then
  printf 'Agent ignore files:\n'
  printf '  %s\n' "${ignore_files[@]}"
fi

if ((dry_run)); then
  printf 'Dry run: no files changed.\n'
  exit 0
fi

mkdir -p "$TARGET/.agents/guidelines"

for source_rel in "${selected[@]}"; do
  source_path="$source_dir/$source_rel"
  destination=$(destination_for "$source_rel")
  if [[ ! -f "$destination" ]] || ! cmp -s "$source_path" "$destination"; then
    cp "$source_path" "$destination"
  fi
done

old_manifest="$TARGET/$MANIFEST_REL"
if [[ -f "$old_manifest" ]]; then
  while read -r stale_rel stale_hash extra; do
    [[ -n "$stale_rel" && "$stale_rel" != \#* ]] || continue
    [[ -z "${extra:-}" ]] || continue
    is_selected "$stale_rel" && continue
    stale_destination=$(destination_for "$stale_rel")
    if [[ -f "$stale_destination" ]]; then
      current_hash=$(sha256_file "$stale_destination")
      if [[ "$current_hash" == "$stale_hash" || "$force" == 1 ]]; then
        rm "$stale_destination"
      else
        printf 'Preserved locally modified stale guideline: %s\n' "${stale_destination#"$TARGET/"}" >&2
      fi
    fi
  done <"$old_manifest"
fi

manifest_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-guideline-manifest.XXXXXX")
agents_block_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-guideline-block.XXXXXX")

{
  printf '# ai-guideline installer manifest v1\n'
  for source_rel in "${selected[@]}"; do
    printf '%s %s\n' "$source_rel" "$(sha256_file "$source_dir/$source_rel")"
  done
} >"$manifest_tmp"
cat "$manifest_tmp" >"$old_manifest"

{
  printf '%s\n' "$BEGIN_MARKER"
  printf '## AI Engineering Guidelines\n\n'
  printf '%s\n\n' "Read \`.agents/general.md\` for every task. Read only the applicable companion guidelines below; repository-local contracts and instructions remain authoritative."
  for source_rel in "${selected[@]}"; do
    [[ "$source_rel" == 'general.md' ]] && continue
    printf -- "- \`%s\`\n" ".agents/$source_rel"
  done
  printf '%s\n' "$END_MARKER"
} >"$agents_block_tmp"

write_managed_block() {
  local file=$1
  local block=$2
  local begin_marker=$3
  local end_marker=$4

  managed_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-guideline-managed.XXXXXX")
  if [[ -f "$file" ]] && grep -Fqx "$begin_marker" "$file"; then
    awk -v begin="$begin_marker" -v end="$end_marker" -v block="$block" '
    $0 == begin {
      while ((getline line < block) > 0) print line
      close(block)
      skipping=1
      next
    }
    $0 == end { skipping=0; next }
    !skipping { print }
    ' "$file" >"$managed_tmp"
  else
    if [[ -f "$file" && -s "$file" ]]; then
      cat "$file" >"$managed_tmp"
      printf '\n' >>"$managed_tmp"
    fi
    cat "$block" >>"$managed_tmp"
  fi
  cat "$managed_tmp" >"$file"
  rm -f "$managed_tmp"
  managed_tmp=''
}

write_managed_block "$agents_file" "$agents_block_tmp" "$BEGIN_MARKER" "$END_MARKER"

if ((!skip_ignore_files)); then
  for ignore_file in "${ignore_files[@]}"; do
    write_managed_block \
      "$TARGET/$ignore_file" \
      "$source_dir/ignores/agent.ignore" \
      "$IGNORE_BEGIN_MARKER" \
      "$IGNORE_END_MARKER"
  done
fi

printf 'Installation complete.\n'
