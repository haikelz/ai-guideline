#!/usr/bin/env bash

set -euo pipefail

readonly BEGIN_MARKER='<!-- AI-GUIDELINES:BEGIN -->'
readonly END_MARKER='<!-- AI-GUIDELINES:END -->'
readonly IGNORE_BEGIN_MARKER='# AI-GUIDELINES-IGNORE:BEGIN'
readonly IGNORE_END_MARKER='# AI-GUIDELINES-IGNORE:END'
readonly MANIFEST_REL='.agents/.ai-guideline-manifest'
readonly WORKSPACE_STATE_REL='.agents/.ai-guideline-workspaces'
readonly OVERRIDE_CONFIG='.ai-guideline.conf'
readonly CHECKSUMS_FILE='CHECKSUMS.sha256'
readonly DEFAULT_REMOTE_ROOT='https://raw.githubusercontent.com/haikelz/ai-guideline'
readonly INSTALLER_VERSION='1.1.0'

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
workspace_block_tmp=''
workspace_state_tmp=''

cleanup() {
  [[ -z "$source_tmp" ]] || rm -rf "$source_tmp"
  [[ -z "$manifest_tmp" ]] || rm -f "$manifest_tmp"
  [[ -z "$agents_block_tmp" ]] || rm -f "$agents_block_tmp"
  [[ -z "$managed_tmp" ]] || rm -f "$managed_tmp"
  [[ -z "$workspace_block_tmp" ]] || rm -f "$workspace_block_tmp"
  [[ -z "$workspace_state_tmp" ]] || rm -f "$workspace_state_tmp"
}
trap cleanup EXIT

dry_run=0
force=0
skip_ignore_files=0
show_version=0
explain=0
workspace_instructions=0
workspace_arg=''
include_args=()
exclude_args=()
target_arg='.'
target_seen=0

usage() {
  cat <<'EOF'
Usage: install.sh [options] [target-directory]

Detect a project's stack and install the applicable coding-agent guidelines.

Options:
  --dry-run          Print the detected stack and plan without writing.
  --explain          Explain detection evidence without writing.
  --force            Overwrite locally modified installed guidelines.
  --include STACK    Include a supported stack; may be repeated.
  --exclude STACK    Exclude a supported stack; may be repeated.
  --skip-ignore-files Do not create or update coding-agent ignore files.
  --workspace PATH   Install only for one workspace below the target root.
  --workspace-instructions
                     Manage scoped AGENTS.md blocks in detected workspaces.
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
    --explain)
      explain=1
      dry_run=1
      ;;
    --force)
      force=1
      ;;
    --include | --exclude | --workspace)
      option=$1
      if (($# < 2)); then
        printf 'install.sh: %s requires a value\n' "$option" >&2
        exit 2
      fi
      shift
      case "$option" in
        --include) include_args+=("$1") ;;
        --exclude) exclude_args+=("$1") ;;
        --workspace) workspace_arg=$1 ;;
      esac
      ;;
    --include=* | --exclude=* | --workspace=*)
      option=${1%%=*}
      value=${1#*=}
      if [[ -z "$value" ]]; then
        printf 'install.sh: %s requires a value\n' "$option" >&2
        exit 2
      fi
      case "$option" in
        --include) include_args+=("$value") ;;
        --exclude) exclude_args+=("$value") ;;
        --workspace) workspace_arg=$value ;;
      esac
      ;;
    --skip-ignore-files)
      skip_ignore_files=1
      ;;
    --workspace-instructions)
      workspace_instructions=1
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

REPOSITORY_ROOT=$(cd "$target_arg" && pwd)
TARGET=$REPOSITORY_ROOT
if [[ -n "$workspace_arg" ]]; then
  if ((workspace_instructions)); then
    printf 'install.sh: --workspace and --workspace-instructions cannot be combined\n' >&2
    exit 2
  fi
  case "/$workspace_arg/" in
    */../* | */./* | *//*)
      printf 'install.sh: workspace path must be a normalized relative path: %s\n' "$workspace_arg" >&2
      exit 2
      ;;
  esac
  if [[ ! -d "$REPOSITORY_ROOT/$workspace_arg" ]]; then
    printf 'install.sh: workspace is not a directory below the target: %s\n' "$workspace_arg" >&2
    exit 2
  fi
  TARGET=$(cd "$REPOSITORY_ROOT/$workspace_arg" && pwd)
  case "$TARGET/" in
    "$REPOSITORY_ROOT/"*) ;;
    *)
      printf 'install.sh: workspace resolves outside the target: %s\n' "$workspace_arg" >&2
      exit 2
      ;;
  esac
fi
readonly REPOSITORY_ROOT TARGET
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
    -name .nx -o -name .turbo -o -name .vercel -o -name .output -o \
    -name .nuxt -o -name .svelte-kit -o -name .yarn -o \
    -name .pnpm-store -o -name coverage -o -name .cache \
    \) -prune \) -o "$@"
}

contains_word() {
  local words=$1
  local candidate=$2
  [[ " $words " == *" $candidate "* ]]
}

array_contains() {
  local candidate=$1
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$candidate" ]] && return 0
  done
  return 1
}

relative_to_target() {
  local path=$1
  if [[ "$path" == "$TARGET" ]]; then
    printf '.\n'
  else
    printf '%s\n' "${path#"$TARGET/"}"
  fi
}

relative_file() {
  local path=$1
  printf '%s\n' "${path#"$TARGET/"}"
}

workspace_paths=()
workspace_stacks=()
evidence_workspaces=()
evidence_stacks=()
evidence_sources=()
monorepo_markers=()

workspace_index() {
  local path=$1
  local index
  for index in "${!workspace_paths[@]}"; do
    if [[ "${workspace_paths[$index]}" == "$path" ]]; then
      printf '%s\n' "$index"
      return 0
    fi
  done
  return 1
}

add_evidence() {
  local workspace=$1
  local stack=$2
  local source=$3
  local index
  for index in "${!evidence_sources[@]}"; do
    if [[ "${evidence_workspaces[$index]}" == "$workspace" &&
      "${evidence_stacks[$index]}" == "$stack" &&
      "${evidence_sources[$index]}" == "$source" ]]; then
      return
    fi
  done
  evidence_workspaces+=("$workspace")
  evidence_stacks+=("$stack")
  evidence_sources+=("$source")
}

add_workspace_stack() {
  local workspace=$1
  local stack=$2
  local source=$3
  local index
  case "$workspace" in
    *$'\n'* | *$'\t'* | *'`'*)
      printf 'install.sh: workspace path contains an unsupported control or Markdown character: %s\n' "$workspace" >&2
      exit 2
      ;;
  esac
  index=$(workspace_index "$workspace" || true)
  if [[ -z "$index" ]]; then
    workspace_paths+=("$workspace")
    workspace_stacks+=("$stack")
  elif ! contains_word "${workspace_stacks[$index]}" "$stack"; then
    workspace_stacks[index]="${workspace_stacks[index]} $stack"
  fi
  add_evidence "$workspace" "$stack" "$source"
}

remove_workspace_stack() {
  local stack=$1
  local index word remaining
  for index in "${!workspace_stacks[@]}"; do
    remaining=''
    for word in ${workspace_stacks[$index]}; do
      [[ "$word" == "$stack" ]] || remaining="${remaining:+$remaining }$word"
    done
    workspace_stacks[index]=$remaining
  done
}

valid_stack() {
  case "$1" in
    javascript-typescript | astro | nextjs | nestjs | go | echo | fiber | gorm-postgresql | docker) return 0 ;;
    *) return 1 ;;
  esac
}

add_javascript_config() {
  local file=$1
  local stack=${2:-}
  local workspace source
  workspace=$(relative_to_target "$(dirname "$file")")
  source=$(relative_file "$file")
  add_workspace_stack "$workspace" 'javascript-typescript' "$source"
  if [[ -n "$stack" ]]; then
    add_workspace_stack "$workspace" "$stack" "$source"
    add_workspace_stack "$workspace" 'docker' "$source (runtime companion)"
  fi
}

while IFS= read -r -d '' project_file; do
  file_name=${project_file##*/}
  workspace=$(relative_to_target "$(dirname "$project_file")")
  source=$(relative_file "$project_file")
  case "$file_name" in
    package.json)
      add_workspace_stack "$workspace" 'javascript-typescript' "$source"
      if grep -Eq '"workspaces"[[:space:]]*:' "$project_file"; then
        monorepo_markers+=("$source")
      fi
      if grep -Eq '"astro"[[:space:]]*:' "$project_file"; then
        add_workspace_stack "$workspace" 'astro' "$source"
        add_workspace_stack "$workspace" 'docker' "$source (runtime companion)"
      fi
      if grep -Eq '"next"[[:space:]]*:' "$project_file"; then
        add_workspace_stack "$workspace" 'nextjs' "$source"
        add_workspace_stack "$workspace" 'docker' "$source (runtime companion)"
      fi
      if grep -Eq '"@nestjs/core"[[:space:]]*:' "$project_file"; then
        add_workspace_stack "$workspace" 'nestjs' "$source"
        add_workspace_stack "$workspace" 'docker' "$source (runtime companion)"
      fi
      ;;
    project.json)
      add_workspace_stack "$workspace" 'javascript-typescript' "$source"
      if grep -Eq '(@nx/next|next:)' "$project_file"; then
        add_workspace_stack "$workspace" 'nextjs' "$source"
        add_workspace_stack "$workspace" 'docker' "$source (runtime companion)"
      fi
      if grep -Eq '(@nx/nest|nestjs)' "$project_file"; then
        add_workspace_stack "$workspace" 'nestjs' "$source"
        add_workspace_stack "$workspace" 'docker' "$source (runtime companion)"
      fi
      ;;
    tsconfig.json | jsconfig.json) add_javascript_config "$project_file" ;;
    astro.config.*) add_javascript_config "$project_file" 'astro' ;;
    next.config.*) add_javascript_config "$project_file" 'nextjs' ;;
    nest-cli.json) add_javascript_config "$project_file" 'nestjs' ;;
    go.mod)
      add_workspace_stack "$workspace" 'go' "$source"
      add_workspace_stack "$workspace" 'docker' "$source (runtime companion)"
      grep -Eq 'github\.com/labstack/echo(/v[0-9]+)?([[:space:]]|$)' "$project_file" &&
        add_workspace_stack "$workspace" 'echo' "$source"
      grep -Eq 'github\.com/gofiber/fiber(/v[0-9]+)?([[:space:]]|$)' "$project_file" &&
        add_workspace_stack "$workspace" 'fiber' "$source"
      has_local_gorm=0
      has_local_postgres=0
      grep -Eq 'gorm\.io/gorm([[:space:]]|$)' "$project_file" && has_local_gorm=1
      grep -Eq '(gorm\.io/driver/postgres|github\.com/lib/pq|github\.com/jackc/pgx)' "$project_file" && has_local_postgres=1
      if ((has_local_gorm && has_local_postgres)); then
        add_workspace_stack "$workspace" 'gorm-postgresql' "$source"
      fi
      ;;
    Dockerfile* | docker-compose*.yml | docker-compose*.yaml | compose*.yml | compose*.yaml)
      add_workspace_stack "$workspace" 'docker' "$source"
      ;;
    go.work | pnpm-workspace.yaml | nx.json | workspace.json | turbo.json | lerna.json)
      monorepo_markers+=("$source")
      ;;
  esac
done < <(find_project_files -type f \( \
  -name package.json -o \
  -name project.json -o \
  -name tsconfig.json -o \
  -name jsconfig.json -o \
  -name 'astro.config.*' -o \
  -name 'next.config.*' -o \
  -name nest-cli.json -o \
  -name go.mod -o \
  -name 'Dockerfile*' -o \
  -name 'docker-compose*.yml' -o \
  -name 'docker-compose*.yaml' -o \
  -name 'compose*.yml' -o \
  -name 'compose*.yaml' -o \
  -name go.work -o \
  -name pnpm-workspace.yaml -o \
  -name nx.json -o \
  -name workspace.json -o \
  -name turbo.json -o \
  -name lerna.json \
  \) -print0)

if [[ -f "$REPOSITORY_ROOT/$OVERRIDE_CONFIG" ]]; then
  config_line=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    config_line=$((config_line + 1))
    line=${line%$'\r'}
    read -r directive stack extra <<<"$line"
    [[ -z "${directive:-}" || "$directive" == \#* ]] && continue
    if [[ -n "${extra:-}" || ("$directive" != 'include' && "$directive" != 'exclude') || -z "${stack:-}" ]]; then
      printf 'install.sh: invalid %s line %s; expected "include STACK" or "exclude STACK"\n' \
        "$OVERRIDE_CONFIG" "$config_line" >&2
      exit 2
    fi
    if [[ "$directive" == 'include' ]]; then
      include_args+=("$stack")
    else
      exclude_args+=("$stack")
    fi
  done <"$REPOSITORY_ROOT/$OVERRIDE_CONFIG"
fi

for stack in "${include_args[@]:-}" "${exclude_args[@]:-}"; do
  [[ -z "$stack" ]] && continue
  if ! valid_stack "$stack"; then
    printf 'install.sh: unsupported stack override: %s\n' "$stack" >&2
    exit 2
  fi
done
for stack in "${include_args[@]:-}"; do
  [[ -z "$stack" ]] && continue
  if array_contains "$stack" "${exclude_args[@]:-}"; then
    printf 'install.sh: stack cannot be both included and excluded: %s\n' "$stack" >&2
    exit 2
  fi
  case "$stack" in
    astro | nextjs | nestjs)
      add_workspace_stack '.' 'javascript-typescript' "explicit include: $stack"
      add_workspace_stack '.' "$stack" "explicit include: $stack"
      add_workspace_stack '.' 'docker' "explicit include: $stack (runtime companion)"
      ;;
    echo | fiber | gorm-postgresql)
      add_workspace_stack '.' 'go' "explicit include: $stack"
      add_workspace_stack '.' "$stack" "explicit include: $stack"
      add_workspace_stack '.' 'docker' "explicit include: $stack (runtime companion)"
      ;;
    go)
      add_workspace_stack '.' 'go' 'explicit include: go'
      add_workspace_stack '.' 'docker' 'explicit include: go (runtime companion)'
      ;;
    *) add_workspace_stack '.' "$stack" "explicit include: $stack" ;;
  esac
done
for stack in "${exclude_args[@]:-}"; do
  [[ -z "$stack" ]] || remove_workspace_stack "$stack"
done

stack_order=(javascript-typescript astro nextjs nestjs go echo fiber gorm-postgresql docker)
for index in "${!workspace_stacks[@]}"; do
  stacks=${workspace_stacks[$index]}
  ordered_stacks=''
  for stack in "${stack_order[@]}"; do
    contains_word "$stacks" "$stack" || continue
    ordered_stacks="${ordered_stacks:+$ordered_stacks }$stack"
  done
  workspace_stacks[index]=$ordered_stacks
done

all_stacks=''
for stacks in "${workspace_stacks[@]:-}"; do
  for stack in $stacks; do
    contains_word "$all_stacks" "$stack" || all_stacks="${all_stacks:+$all_stacks }$stack"
  done
done
for framework in astro nextjs nestjs; do
  if contains_word "$all_stacks" "$framework" && ! contains_word "$all_stacks" 'javascript-typescript'; then
    printf 'install.sh: %s requires javascript-typescript; exclude both or neither\n' "$framework" >&2
    exit 2
  fi
done
for framework in echo fiber gorm-postgresql; do
  if contains_word "$all_stacks" "$framework" && ! contains_word "$all_stacks" 'go'; then
    printf 'install.sh: %s requires go; exclude both or neither\n' "$framework" >&2
    exit 2
  fi
done

selected=('general.md' 'preferences.md')
detected=()
add_selected() {
  local candidate=$1
  array_contains "$candidate" "${selected[@]}" || selected+=("$candidate")
}
add_detected() {
  local candidate=$1
  array_contains "$candidate" "${detected[@]:-}" || detected+=("$candidate")
}

if contains_word "$all_stacks" 'javascript-typescript'; then
  add_detected 'javascript-typescript'
  add_selected 'guidelines/javascript-typescript.md'
  add_selected 'guidelines/haikel-javascript-typescript.md'
fi
if contains_word "$all_stacks" 'astro'; then
  add_detected 'astro'
  add_selected 'guidelines/astro.md'
fi
if contains_word "$all_stacks" 'nextjs'; then
  add_detected 'nextjs'
  add_selected 'guidelines/nextjs.md'
fi
if contains_word "$all_stacks" 'nestjs'; then
  add_detected 'nestjs'
  add_selected 'guidelines/nestjs.md'
fi
if contains_word "$all_stacks" 'go'; then
  add_detected 'go'
  add_selected 'guidelines/go.md'
  add_selected 'guidelines/haikel-go.md'
fi
if contains_word "$all_stacks" 'echo'; then
  add_detected 'echo'
  add_selected 'guidelines/echo.md'
fi
if contains_word "$all_stacks" 'fiber'; then
  add_detected 'fiber'
  add_selected 'guidelines/fiber.md'
fi
if contains_word "$all_stacks" 'gorm-postgresql'; then
  add_detected 'gorm-postgresql'
  add_selected 'guidelines/gorm-postgresql.md'
fi
if contains_word "$all_stacks" 'docker'; then
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
    preferences.md) printf '%s/.agents/preferences.md\n' "$TARGET" ;;
    guidelines/astro.md | \
      guidelines/docker.md | \
      guidelines/echo.md | \
      guidelines/fiber.md | \
      guidelines/go.md | \
      guidelines/gorm-postgresql.md | \
      guidelines/haikel-go.md | \
      guidelines/haikel-javascript-typescript.md | \
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

valid_workspace_state_path() {
  local path=$1
  [[ -n "$path" && "$path" != '.' && "$path" != /* ]] || return 1
  case "/$path/" in
    */../* | */./* | *//* | *$'\n'* | *$'\t'* | *'`'*) return 1 ;;
  esac
  return 0
}

if ((workspace_instructions)); then
  for index in "${!workspace_paths[@]}"; do
    workspace=${workspace_paths[$index]}
    [[ "$workspace" != '.' && -n "${workspace_stacks[$index]}" ]] || continue
    if ! valid_workspace_state_path "$workspace"; then
      printf 'install.sh: unsafe workspace instruction path: %s\n' "$workspace" >&2
      exit 2
    fi
    validate_managed_block "$TARGET/$workspace/AGENTS.md" "$BEGIN_MARKER" "$END_MARKER"
  done
  if [[ -f "$TARGET/$WORKSPACE_STATE_REL" ]]; then
    while IFS= read -r workspace; do
      [[ -n "$workspace" && "$workspace" != \#* ]] || continue
      if ! valid_workspace_state_path "$workspace"; then
        printf 'install.sh: unsafe path in %s: %s\n' "$WORKSPACE_STATE_REL" "$workspace" >&2
        exit 2
      fi
      validate_managed_block "$TARGET/$workspace/AGENTS.md" "$BEGIN_MARKER" "$END_MARKER"
    done <"$TARGET/$WORKSPACE_STATE_REL"
  fi
fi

if ((${#conflicts[@]})) && ((!force)); then
  printf 'install.sh: locally modified guideline files would be overwritten:\n' >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  printf 'Re-run with --force to replace them.\n' >&2
  exit 3
fi

printf 'Target: %s\n' "$TARGET"
if [[ "$TARGET" != "$REPOSITORY_ROOT" ]]; then
  printf 'Repository root: %s\n' "$REPOSITORY_ROOT"
  printf 'Workspace: %s\n' "$workspace_arg"
fi
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
if ((explain)); then
  printf 'Detection evidence:\n'
  if ((${#evidence_sources[@]})); then
    for index in "${!evidence_sources[@]}"; do
      printf '  %s -> %s: %s\n' \
        "${evidence_sources[$index]}" \
        "${evidence_workspaces[$index]}" \
        "${evidence_stacks[$index]}"
    done
  else
    printf '  none\n'
  fi
  if ((${#monorepo_markers[@]})); then
    printf 'Workspace metadata:\n'
    printf '  %s\n' "${monorepo_markers[@]}"
  fi
  printf 'Workspace profiles:\n'
  workspace_count=0
  for index in "${!workspace_paths[@]}"; do
    [[ -n "${workspace_stacks[$index]}" ]] || continue
    workspace_count=$((workspace_count + 1))
    printf '  %s: %s\n' "${workspace_paths[$index]}" "${workspace_stacks[$index]}"
  done
  ((workspace_count > 0)) || printf '  none\n'
fi
printf 'Guidelines:\n'
printf '  %s\n' "${selected[@]}"
if ((!skip_ignore_files)); then
  printf 'Agent ignore files:\n'
  printf '  %s\n' "${ignore_files[@]}"
fi
if ((workspace_instructions)); then
  printf 'Workspace instruction files:\n'
  workspace_count=0
  for index in "${!workspace_paths[@]}"; do
    [[ "${workspace_paths[$index]}" != '.' && -n "${workspace_stacks[$index]}" ]] || continue
    workspace_count=$((workspace_count + 1))
    printf '  %s/AGENTS.md\n' "${workspace_paths[$index]}"
  done
  ((workspace_count > 0)) || printf '  none\n'
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
  printf '# ai-guideline installer manifest v2\n'
  for index in "${!workspace_paths[@]}"; do
    [[ -n "${workspace_stacks[$index]}" ]] || continue
    printf '# workspace %s: %s\n' "${workspace_paths[$index]}" "${workspace_stacks[$index]}"
  done
  for source_rel in "${selected[@]}"; do
    printf '%s %s\n' "$source_rel" "$(sha256_file "$source_dir/$source_rel")"
  done
} >"$manifest_tmp"
cat "$manifest_tmp" >"$old_manifest"

markdown_path() {
  local prefix=$1
  local path=$2
  printf '\140%s/%s\140' "$prefix" "$path"
}

render_context_profiles() {
  local stacks=$1
  local prefix=$2
  printf '%s\n' '- **Repository setup, documentation, planning, or process:** no companion guideline.'
  if contains_word "$stacks" 'javascript-typescript'; then
    printf -- '- **JavaScript or TypeScript language/library work:** %s and %s.\n' \
      "$(markdown_path "$prefix" 'guidelines/javascript-typescript.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-javascript-typescript.md')"
  fi
  if contains_word "$stacks" 'astro'; then
    printf -- '- **Astro UI or application work:** %s, %s, and %s.\n' \
      "$(markdown_path "$prefix" 'guidelines/javascript-typescript.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-javascript-typescript.md')" \
      "$(markdown_path "$prefix" 'guidelines/astro.md')"
  fi
  if contains_word "$stacks" 'nextjs'; then
    printf -- '- **Next.js UI or application work:** %s, %s, and %s.\n' \
      "$(markdown_path "$prefix" 'guidelines/javascript-typescript.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-javascript-typescript.md')" \
      "$(markdown_path "$prefix" 'guidelines/nextjs.md')"
  fi
  if contains_word "$stacks" 'nestjs'; then
    printf -- '- **NestJS API or service work:** %s, %s, and %s.\n' \
      "$(markdown_path "$prefix" 'guidelines/javascript-typescript.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-javascript-typescript.md')" \
      "$(markdown_path "$prefix" 'guidelines/nestjs.md')"
  fi
  if contains_word "$stacks" 'go'; then
    printf -- '- **Go language, package, or service work:** %s and %s.\n' \
      "$(markdown_path "$prefix" 'guidelines/go.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-go.md')"
  fi
  if contains_word "$stacks" 'echo'; then
    printf -- '- **Echo HTTP work:** %s, %s, and %s.\n' \
      "$(markdown_path "$prefix" 'guidelines/go.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-go.md')" \
      "$(markdown_path "$prefix" 'guidelines/echo.md')"
  fi
  if contains_word "$stacks" 'fiber'; then
    printf -- '- **Fiber HTTP work:** %s, %s, and %s.\n' \
      "$(markdown_path "$prefix" 'guidelines/go.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-go.md')" \
      "$(markdown_path "$prefix" 'guidelines/fiber.md')"
  fi
  if contains_word "$stacks" 'gorm-postgresql'; then
    printf -- '- **GORM or PostgreSQL persistence work:** %s, %s, and %s; add the applicable HTTP profile only when transport behavior also changes.\n' \
      "$(markdown_path "$prefix" 'guidelines/go.md')" \
      "$(markdown_path "$prefix" 'guidelines/haikel-go.md')" \
      "$(markdown_path "$prefix" 'guidelines/gorm-postgresql.md')"
  fi
  if contains_word "$stacks" 'docker'; then
    printf -- '- **Container, Compose, delivery, or runtime work:** %s; add an application profile only when its build or runtime behavior also changes.\n' \
      "$(markdown_path "$prefix" 'guidelines/docker.md')"
  fi
  printf '%s\n' '- **Cross-cutting work:** use the union of only the affected profiles and state why each additional document is needed.'
}

relative_agents_dir() {
  local workspace=$1
  local rest=$workspace
  local prefix=''
  while [[ -n "$rest" ]]; do
    prefix="../$prefix"
    if [[ "$rest" == */* ]]; then
      rest=${rest#*/}
    else
      rest=''
    fi
  done
  printf '%s.agents\n' "$prefix"
}

{
  printf '%s\n' "$BEGIN_MARKER"
  printf '## AI Engineering Guidelines\n\n'
  printf '%s\n\n' "Read \`.agents/general.md\` and \`.agents/preferences.md\` for every task. Then select the smallest matching context profile below. Do not read every installed companion by default. Repository-local contracts and instructions remain authoritative."
  render_context_profiles "$all_stacks" '.agents'
  workspace_count=0
  for index in "${!workspace_paths[@]}"; do
    [[ "${workspace_paths[$index]}" != '.' && -n "${workspace_stacks[$index]}" ]] || continue
    workspace_count=$((workspace_count + 1))
  done
  if ((workspace_count)); then
    printf '\n### Workspace scopes\n\n'
    printf '%s\n\n' "Match the changed path first, then use only that workspace's applicable profile."
    for index in "${!workspace_paths[@]}"; do
      [[ "${workspace_paths[$index]}" != '.' && -n "${workspace_stacks[$index]}" ]] || continue
      formatted_stacks=${workspace_stacks[$index]// /, }
      printf -- '- %s: %s.\n' \
        "$(printf '\140%s/**\140' "${workspace_paths[$index]}")" \
        "$formatted_stacks"
    done
  fi
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

remove_managed_block() {
  local file=$1
  local begin_marker=$2
  local end_marker=$3
  [[ -f "$file" ]] || return 0

  managed_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-guideline-managed.XXXXXX")
  awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin { skipping=1; next }
  $0 == end { skipping=0; next }
  !skipping { print }
  ' "$file" >"$managed_tmp"
  if [[ -s "$managed_tmp" ]]; then
    cat "$managed_tmp" >"$file"
  else
    rm -f "$file"
  fi
  rm -f "$managed_tmp"
  managed_tmp=''
}

workspace_is_desired() {
  local candidate=$1
  local index
  for index in "${!workspace_paths[@]}"; do
    if [[ "${workspace_paths[$index]}" == "$candidate" &&
      "$candidate" != '.' && -n "${workspace_stacks[$index]}" ]]; then
      return 0
    fi
  done
  return 1
}

write_managed_block "$agents_file" "$agents_block_tmp" "$BEGIN_MARKER" "$END_MARKER"

if ((workspace_instructions)); then
  workspace_state_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-guideline-workspaces.XXXXXX")
  printf '# ai-guideline workspace instructions v1\n' >"$workspace_state_tmp"

  if [[ -f "$TARGET/$WORKSPACE_STATE_REL" ]]; then
    while IFS= read -r workspace; do
      [[ -n "$workspace" && "$workspace" != \#* ]] || continue
      workspace_is_desired "$workspace" && continue
      remove_managed_block "$TARGET/$workspace/AGENTS.md" "$BEGIN_MARKER" "$END_MARKER"
    done <"$TARGET/$WORKSPACE_STATE_REL"
  fi

  for index in "${!workspace_paths[@]}"; do
    workspace=${workspace_paths[$index]}
    stacks=${workspace_stacks[$index]}
    [[ "$workspace" != '.' && -n "$stacks" ]] || continue
    workspace_block_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-guideline-workspace-block.XXXXXX")
    guidelines_dir=$(relative_agents_dir "$workspace")
    {
      printf '%s\n' "$BEGIN_MARKER"
      printf '## AI Engineering Guidelines — Workspace\n\n'
      printf 'Scope: %s. Read %s and %s for every task in this workspace, then select the smallest matching profile.\n\n' \
        "$(printf '\140%s/**\140' "$workspace")" \
        "$(markdown_path "$guidelines_dir" 'general.md')" \
        "$(markdown_path "$guidelines_dir" 'preferences.md')"
      render_context_profiles "$stacks" "$guidelines_dir"
      printf '%s\n' "$END_MARKER"
    } >"$workspace_block_tmp"
    write_managed_block \
      "$TARGET/$workspace/AGENTS.md" \
      "$workspace_block_tmp" \
      "$BEGIN_MARKER" \
      "$END_MARKER"
    rm -f "$workspace_block_tmp"
    workspace_block_tmp=''
    printf '%s\n' "$workspace" >>"$workspace_state_tmp"
  done
  cat "$workspace_state_tmp" >"$TARGET/$WORKSPACE_STATE_REL"
  rm -f "$workspace_state_tmp"
  workspace_state_tmp=''
fi

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
