#!/usr/bin/env bash
# cw-doctor common helpers

if [[ -z "${CW_ROOT:-}" ]]; then
  CW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

CW_STATE_DIR="${CW_ROOT}/.state"
CW_BIN_DIR="${CW_ROOT}/bin"
CW_TOOLS_DIR="${CW_ROOT}/tools"
CW_MANAGED_BEGIN='# >>> cw >>>'
CW_MANAGED_END='# <<< cw <<<'
CW_MANAGED_BEGIN_LEGACY='# >>> cw-doctor >>>'
CW_MANAGED_END_LEGACY='# <<< cw-doctor <<<'
CW_ALIASES_FILE="${HOME}/.bash_aliases"

# Sample limits (bounded for 1GB servers)
CW_TRAFFIC_SAMPLE_LINES=20000
CW_ERROR_SAMPLE_LINES=10000
CW_PHP_SAMPLE_LINES=20000

_cw_diag_die() {
  echo "error: $*" >&2
  exit 1
}

_cw_toolkit_die() {
  echo "cw-doctor: $*" >&2
  exit 1
}

_cw_die() {
  _cw_diag_die "$@"
}

_cw_warn() {
  echo "warning: $*" >&2
}

_cw_toolkit_warn() {
  echo "cw-doctor: warning: $*" >&2
}

_cw_info() {
  echo "$*"
}

_cw_toolkit_info() {
  echo "cw-doctor: $*"
}

_cw_section() {
  echo ""
  echo "== $* =="
}

_cw_toolkit_section() {
  echo ""
  echo "== cw-doctor: $* =="
}

_cw_label() {
  printf "%-16s %s\n" "$1" "$2"
}

_cw_toolkit_label() {
  _cw_label "$1" "$2"
}

_cw_observed() { echo "OBSERVED: $*"; }
_cw_likely()   { echo "LIKELY: $*"; }
_cw_possible() { echo "POSSIBLE: $*"; }
_cw_not_established() { echo "NOT ESTABLISHED: $*"; }
_cw_unavailable() { echo "UNAVAILABLE TO SSH USER: $*"; }

# Log path diagnostics: missing, denied, empty, or ok (see lib/logs.sh cw_logs_path_status).
_cw_log_path_issue() {
  local status="$1" path="$2" label="$3" detail="${4:-}"
  case "$status" in
    missing)
      _cw_observed "${label}: file not found (${path})"
      ;;
    denied)
      _cw_unavailable "${label}: exists but not readable by SSH user (${path})"
      ;;
    empty)
      if [[ -n "$detail" ]]; then
        _cw_observed "${label}: exists but empty (${detail})"
      else
        _cw_observed "${label}: exists but empty (${path})"
      fi
      ;;
    *)
      _cw_unavailable "${label}: ${detail:-$path}"
      ;;
  esac
}

_cw_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || _cw_die "required command not found: $cmd"
}

_cw_load_lib() {
  local name="$1"
  # shellcheck source=/dev/null
  source "${CW_ROOT}/lib/${name}.sh"
}

_cw_is_tty() {
  [[ -t 0 && -t 1 ]]
}

_cw_is_interactive() {
  [[ -t 0 ]]
}

_cw_user_tty() {
  if [[ -r /dev/tty ]]; then
    printf '%s' /dev/tty
  fi
}

_cw_redact_line() {
  sed -E \
    -e 's/(password|passwd|secret|token|api[_-]?key|authorization|nonce|cookie)=[^&[:space:]]+/REDACTED/gi' \
    -e 's/(Bearer|Basic)[[:space:]]+[A-Za-z0-9._~+/-]+=*/REDACTED/gi'
}

_cw_sanitize_report() {
  sed -E \
    -e '/cw-doctor/Id' \
    -e '/[[:space:]]cw[[:space:]]/Id' \
    -e '/^usage:.*cw /Id' \
    -e '/\bcw (apps|doctor|cpu|traffic|slow|watch|errors|cron|disk|collect|status|update|help)\b/Id' \
    -e "s|${HOME}/\\.local/opt/cw-doctor[^[:space:]]*||g" \
    -e 's|\.local/opt/cw-doctor[^[:space:]]*||g' \
    -e '/install-state/Id' \
    -e '/crawlers\.json/Id' \
    -e '/^error:/Id' \
    -e '/^Suggest:.*collect/Id' \
    -e '/^Next: /Id' \
    -e '/^Use APP id or primary URL/Id' \
    -e '/^Tip: run /Id'
}

_cw_tail_sample() {
  local file="$1" limit="${2:-1000}"
  if [[ ! -r "$file" ]]; then
    return 1
  fi
  tail -n "$limit" "$file"
}

_cw_human_bytes() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
  else
    echo "${bytes} bytes"
  fi
}

_cw_now_ts() {
  date -u +%Y%m%dT%H%M%SZ
}

_cw_help_global() {
  cat <<'EOF'
cw-doctor toolkit

Interactive menu (fzf):
  cw                   Command launcher (pick command, app, options)
  cw menu              Same as bare cw

Admin (install, paths, updates):
  cw status            Install health and paths
  cw update            Manual update
  cw path [APP]        Print app path (pick if APP omitted)
  cw uninstall         Reverse install (or uninstall.sh)

Shell navigation (after install): cda, cdapp, cdlogs, cgo, fcd, fnvim, fbat
  Ctrl+R               fzf fuzzy shell history

Server diagnostics (shareable output; omit APP to pick interactively):
  cw apps [-i]         List applications (-i = pick one, show detail)
  cw doctor [APP]      Server and app health
  cw cpu [APP]         CPU, RAM, processes
  cw traffic [APP]     Access log analysis
  cw slow [APP]        PHP slow log analysis
  cw watch [APP] [mode] Live log tail
  cw logs [APP]        Browse log files (bat/tail)
  cw errors [APP]      Error log summary
  cw cron [APP]        WP cron activity
  cw disk [APP]        Disk usage
  cw collect [APP]     Sanitized report bundle
  cw reports [--open]  Browse past reports
  cw go [APP]          Path picker within an app
  cw wp [APP]          Plugin/theme picker

  cw help              This help
EOF
}
