# board-superpowers / scripts/lib/common.sh
#
# Shared utilities. Source this at the top of any script under scripts/.
# Not self-executable — exit-option discipline belongs to the caller.
#
# Contract with callers:
#   - Caller MUST `set -euo pipefail` before sourcing.
#   - Caller SHOULD source immediately after its shebang + header comment.
#
# Exports (functions):
#   bsp_log <msg>                      — stderr log with script-name prefix
#   bsp_die <msg> [exit_code]          — log + exit (default 1)
#   bsp_require_cmd <cmd> [exit_code]  — fail fast if a command is missing (default 3)
#   bsp_require_arg <flag> <argc>      — assert `$#` has a value after <flag>
#   bsp_parse_owner_number <v> <flag>  — strict OWNER/NUMBER; sets BSP_OWNER, BSP_NUMBER
#   bsp_parse_owner_repo   <v> <flag>  — strict OWNER/REPO;  sets BSP_REPO_OWNER, BSP_REPO_NAME
#   bsp_show_help                      — print the leading comment block of "$0" as help
#   bsp_sanitize_slug <s>              — echo a [a-z0-9-] slug, hyphens collapsed, <= 40 chars
#
# Environment:
#   BOARD_SP_DEBUG=1 enables xtrace in the sourcing script.

# Caller-visible script name — from the top-level caller, not this lib.
# BASH_SOURCE is an array with the outermost script at the highest index.
BSP_SCRIPT_NAME="$(basename "${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}")"
export BSP_SCRIPT_NAME

# Saner default file permissions for anything we create.
umask 022

if [ "${BOARD_SP_DEBUG:-}" = "1" ]; then
  set -x
  export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
fi

bsp_log() {
  printf '%s: %s\n' "$BSP_SCRIPT_NAME" "$*" >&2
}

bsp_die() {
  local msg="$1"
  local code="${2:-1}"
  bsp_log "error: $msg"
  exit "$code"
}

bsp_require_cmd() {
  local cmd="$1"
  local code="${2:-3}"
  command -v "$cmd" >/dev/null 2>&1 \
    || bsp_die "required command not found in PATH: $cmd" "$code"
}

# bsp_require_arg <flag_name> <remaining_argc>
# Usage inside an arg loop:
#   --project) bsp_require_arg --project "$#"; PROJECT="$2"; shift 2 ;;
bsp_require_arg() {
  local flag="$1"
  local argc="$2"
  [ "$argc" -ge 2 ] || bsp_die "$flag requires a value" 2
}

# Strict OWNER/NUMBER parser.
# Accepts exactly one slash. NUMBER must be a positive integer.
# On success sets BSP_OWNER and BSP_NUMBER.
bsp_parse_owner_number() {
  local input="$1"
  local flag="${2:---project}"
  case "$input" in
    */*/*) bsp_die "$flag must be OWNER/NUMBER (no extra slashes), got: $input" 2 ;;
    /*)    bsp_die "$flag must be OWNER/NUMBER (no leading slash), got: $input" 2 ;;
    */)    bsp_die "$flag must be OWNER/NUMBER (no trailing slash), got: $input" 2 ;;
    */*)   : ;;
    *)     bsp_die "$flag must be OWNER/NUMBER, got: $input" 2 ;;
  esac
  BSP_OWNER="${input%/*}"
  BSP_NUMBER="${input#*/}"
  [ -n "$BSP_OWNER" ]  || bsp_die "$flag OWNER is empty, got: $input" 2
  [ -n "$BSP_NUMBER" ] || bsp_die "$flag NUMBER is empty, got: $input" 2
  case "$BSP_NUMBER" in
    ''|*[!0-9]*) bsp_die "$flag NUMBER must be a positive integer, got: $BSP_NUMBER" 2 ;;
  esac
}

# Strict OWNER/REPO parser (for --repo flags).
# On success sets BSP_REPO_OWNER and BSP_REPO_NAME.
bsp_parse_owner_repo() {
  local input="$1"
  local flag="${2:---repo}"
  case "$input" in
    */*/*) bsp_die "$flag must be OWNER/REPO (no extra slashes), got: $input" 2 ;;
    /*)    bsp_die "$flag must be OWNER/REPO (no leading slash), got: $input" 2 ;;
    */)    bsp_die "$flag must be OWNER/REPO (no trailing slash), got: $input" 2 ;;
    */*)   : ;;
    *)     bsp_die "$flag must be OWNER/REPO, got: $input" 2 ;;
  esac
  BSP_REPO_OWNER="${input%/*}"
  BSP_REPO_NAME="${input#*/}"
  [ -n "$BSP_REPO_OWNER" ] || bsp_die "$flag OWNER is empty, got: $input" 2
  [ -n "$BSP_REPO_NAME" ]  || bsp_die "$flag REPO is empty, got: $input" 2
}

# Print the leading "# ..." comment block of $0 as help text.
bsp_show_help() {
  sed -n '/^#!/d; /^# /{ s/^# \{0,1\}//; p; }; /^$/q' "$0"
}

# Normalise a free-form string into a branch-safe slug.
# Pipeline: lowercase, replace disallowed chars with "-", collapse "-" runs,
# strip leading/trailing "-", cap at 40 chars, then re-strip any trailing "-"
# that the cut may have exposed.
bsp_sanitize_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-40 \
    | sed -E 's/-+$//'
}
