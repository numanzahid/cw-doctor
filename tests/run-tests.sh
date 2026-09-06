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

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${ROOT}"/lib/*.sh "${ROOT}"/bin/cw "${ROOT}"/install.sh "${ROOT}"/uninstall.sh && echo "PASS: shellcheck" || fail=1
else
  echo "SKIP: shellcheck not installed"
fi

exit "$fail"
