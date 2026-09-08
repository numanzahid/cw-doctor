#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CW_ROOT="$ROOT"
# shellcheck source=/dev/null
source "${CW_ROOT}/lib/common.sh"
_cw_load_lib logs

fail=0

assert_contains() {
  local hay="$1" needle="$2" label="$3"
  if echo "$hay" | grep -q "$needle"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (missing: $needle)" >&2
    fail=1
  fi
}

fp="$(cw_logs_fingerprint_combined "${ROOT}/tests/fixtures/access-combined.log")"
assert_contains "$fp" "combined" "access fingerprint"

fp2="$(cw_logs_fingerprint_php_access "${ROOT}/tests/fixtures/php-app-access.log")"
assert_contains "$fp2" "php-fpm-cpu" "php-app fingerprint"

LOGDIR_PHP="${ROOT}/tests/fixtures/php-access-rotate"
mkdir -p "$LOGDIR_PHP"
active_php="${LOGDIR_PHP}/php-app.access.log"
rot_php="${LOGDIR_PHP}/php-app.access.log.1"
: > "$active_php"
cp "${ROOT}/tests/fixtures/php-app-access.log" "$rot_php"
fp3="$(cw_logs_fingerprint_php_access "$active_php")"
assert_contains "$fp3" "php-fpm-cpu" "php-app fingerprint from rotated file when active empty"
php_status="$(cw_logs_path_status "$active_php" || true)"
assert_contains "$php_status" "ok|" "php-app path status when rotated has lines"
rm -rf "$LOGDIR_PHP"

empty_php="${ROOT}/tests/fixtures/php-app-empty.log"
: > "$empty_php"
empty_status="$(cw_logs_path_status "$empty_php" || true)"
assert_contains "$empty_status" "empty|" "php-app path status when truly empty"
rm -f "$empty_php"

_cw_load_lib apps
_cw_load_lib platform
_cw_load_lib pick
TMP_HOME="$(mktemp -d)"
APP_DIR="${TMP_HOME}/applications/testapp123456"
mkdir -p "${APP_DIR}/conf" "${APP_DIR}/public_html" "${APP_DIR}/logs"
printf 'server_name example.com www.example.com;\n' > "${APP_DIR}/conf/server.nginx"
export HOME="$TMP_HOME"
path_web="$(cw_path_cmd example.com)"
path_logs="$(cw_path_cmd www.example.com --logs)"
if [[ "$path_web" == "${APP_DIR}/public_html" && "$path_logs" == "${APP_DIR}/logs" ]]; then
  echo "PASS: cw path resolves domain"
else
  echo "FAIL: cw path resolves domain (web=$path_web logs=$path_logs)" >&2
  fail=1
fi
rm -rf "$TMP_HOME"
unset HOME
export CW_ROOT="$ROOT"

LOGDIR="${ROOT}/tests/fixtures/log-rotate-case"
mkdir -p "$LOGDIR"
active="${LOGDIR}/nginx-app.status.log"
rot="${LOGDIR}/nginx-app.status.log.1"
: > "$active"
for i in $(seq 1 30); do echo "active-$i" >> "$active"; done
: > "$rot"
for i in $(seq 1 100); do echo "rot-$i" >> "$rot"; done
sample="$(cw_logs_sample_file "$active" 50)"
sample_lines="$(echo "$sample" | wc -l | tr -d ' ')"
if [[ "$sample_lines" == "50" ]] && echo "$sample" | head -1 | grep -q '^rot-81$' && echo "$sample" | tail -1 | grep -q '^active-30$'; then
  echo "PASS: log sample includes rotated files"
else
  echo "FAIL: log sample includes rotated files (lines=$sample_lines meta=${CW_LOGS_LAST_SAMPLE_META})" >&2
  fail=1
fi
rm -rf "$LOGDIR"

_cw_load_lib state
_cw_load_lib tools
TOOLS_TEST_HOME="$(mktemp -d)"
export CW_STATE_DIR="${TOOLS_TEST_HOME}/.state"
export CW_ROOT="${TOOLS_TEST_HOME}/cw"
export CW_BIN_DIR="${CW_ROOT}/bin"
export CW_SHIMS_DIR="${CW_ROOT}/shims"
export CW_TOOLS_DIR="${CW_ROOT}/tools"
mkdir -p "$CW_BIN_DIR" "$CW_SHIMS_DIR" "${CW_ROOT}/manifest" "$CW_STATE_DIR"
cp "${ROOT}/manifest/tools.list" "${CW_ROOT}/manifest/tools.list"
if cw_tools_refresh_needed 0; then
  echo "PASS: tools refresh needed when never installed"
else
  echo "FAIL: tools refresh needed when never installed" >&2
  fail=1
fi
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "${CW_STATE_DIR}/tools-updated"
name=""
while IFS= read -r name; do
  [[ -z "$name" || "$name" =~ ^# ]] && continue
  printf '#!/bin/sh\n' > "$(cw_tools_shim_path "$name")"
  chmod +x "$(cw_tools_shim_path "$name")"
  printf '%s\n' "$ts" > "$(cw_state_tool_last_update_path "$name")"
done < "${CW_ROOT}/manifest/tools.list"
if cw_tools_refresh_needed 0; then
  echo "FAIL: tools refresh should skip when fresh and present" >&2
  fail=1
else
  echo "PASS: tools refresh skips when fresh and present"
fi
if cw_tools_refresh_needed 1; then
  echo "PASS: tools refresh forced"
else
  echo "FAIL: tools refresh forced" >&2
  fail=1
fi
rm -rf "$TOOLS_TEST_HOME"
export CW_ROOT="$ROOT"
export CW_STATE_DIR="${ROOT}/.state"
export CW_BIN_DIR="${ROOT}/bin"
export CW_SHIMS_DIR="${ROOT}/shims"
export CW_TOOLS_DIR="${ROOT}/tools"
unset CW_STATE_DIR 2>/dev/null || true

_cw_load_lib update
GIT_TEST_DIR="$(mktemp -d)"
git init -q "$GIT_TEST_DIR"
printf 'test\n' > "${GIT_TEST_DIR}/tracked.txt"
git -C "$GIT_TEST_DIR" add tracked.txt
git -C "$GIT_TEST_DIR" -c user.email=test@example.com -c user.name=test commit -q -m init
if _cw_update_git_clean "$GIT_TEST_DIR"; then
  echo "PASS: update git clean on clean tree"
else
  echo "FAIL: update git clean on clean tree" >&2
  fail=1
fi
printf 'dirty\n' >> "${GIT_TEST_DIR}/tracked.txt"
if ! _cw_update_git_clean "$GIT_TEST_DIR"; then
  echo "PASS: update git clean on dirty tree"
else
  echo "FAIL: update git clean on dirty tree" >&2
  fail=1
fi
rm -rf "$GIT_TEST_DIR"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${ROOT}"/lib/*.sh "${ROOT}"/bin/cw "${ROOT}"/install.sh "${ROOT}"/uninstall.sh && echo "PASS: shellcheck" || fail=1
else
  echo "SKIP: shellcheck not installed"
fi

exit "$fail"
