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

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${ROOT}"/lib/*.sh "${ROOT}"/bin/cw "${ROOT}"/install.sh "${ROOT}"/uninstall.sh && echo "PASS: shellcheck" || fail=1
else
  echo "SKIP: shellcheck not installed"
fi

exit "$fail"
