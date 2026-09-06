#!/usr/bin/env bash
set -euo pipefail

CW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${CW_ROOT}/lib/common.sh"
_cw_load_lib state

purge=false
if [[ "${1:-}" == "--purge" ]]; then
  purge=true
fi

_cw_toolkit_section "uninstall"
_cw_toolkit_label "install" "$CW_ROOT"
_cw_toolkit_label "state" "$CW_STATE_DIR"

if [[ "$purge" == false ]]; then
  _cw_toolkit_info "reports preserved under ${CW_STATE_DIR}/reports/"
  _cw_toolkit_info "use --purge to remove the install directory"
fi

cw_state_reverse

if [[ -L "${HOME}/.local/bin/cw" ]]; then
  rm -f "${HOME}/.local/bin/cw"
fi

if [[ "$purge" == true ]]; then
  _cw_toolkit_info "removing ${CW_ROOT}"
  rm -rf "$CW_ROOT"
else
  _cw_toolkit_info "shell integration removed; install files remain at ${CW_ROOT}"
fi

_cw_toolkit_info "done"
