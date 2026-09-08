#!/usr/bin/env bash
# Delegate to cw uninstall (works from any working directory).
set -euo pipefail

_cw_self="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  _cw_self="$(readlink -f "$_cw_self" 2>/dev/null || echo "$_cw_self")"
fi
CW_ROOT="$(cd "$(dirname "$_cw_self")" && pwd)"
exec "${CW_ROOT}/bin/cw" uninstall "$@"
