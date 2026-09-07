#!/usr/bin/env bash
# Delegate to cw uninstall (works from any working directory).
set -euo pipefail

CW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${CW_ROOT}/bin/cw" uninstall "$@"
