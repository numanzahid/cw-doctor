#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${HOME}/.local/opt/cw-doctor"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$SOURCE_DIR" != "$TARGET_ROOT" ]]; then
  mkdir -p "$(dirname "$TARGET_ROOT")"
  if [[ -e "$TARGET_ROOT" && ! -d "$TARGET_ROOT" ]]; then
    echo "cw-doctor: install target exists and is not a directory: $TARGET_ROOT" >&2
    exit 1
  fi
  if [[ -d "$TARGET_ROOT" ]]; then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete --exclude '.git' --exclude '.state' --exclude 'runtime' --exclude 'tools' \
        "${SOURCE_DIR}/" "${TARGET_ROOT}/"
    else
      cp -a "${SOURCE_DIR}/." "${TARGET_ROOT}/"
    fi
  else
    mkdir -p "$TARGET_ROOT"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --exclude '.git' "${SOURCE_DIR}/" "${TARGET_ROOT}/"
    else
      cp -a "${SOURCE_DIR}/." "${TARGET_ROOT}/"
    fi
  fi
  exec "${TARGET_ROOT}/install.sh"
fi

CW_ROOT="$TARGET_ROOT"
# shellcheck source=lib/common.sh
source "${CW_ROOT}/lib/common.sh"
_cw_load_lib platform
_cw_load_lib state
_cw_load_lib tools

cw_state_acquire_lock
trap cw_state_release_lock EXIT

cw_state_log "install started from ${SOURCE_DIR:-in-place}"
cw_platform_preflight
cw_state_init

cw_state_ensure_managed_block "$CW_ALIASES_FILE" "${CW_ROOT}/config/shell.sh"
cw_state_migrate_managed_block "$CW_ALIASES_FILE"
cw_state_safe_symlink "${CW_ROOT}/config/tmux.conf" "${HOME}/.tmux.conf" || true
cw_state_safe_symlink "${CW_ROOT}/config/inputrc" "${HOME}/.inputrc" || true

chmod +x "${CW_ROOT}/bin/cw" "${CW_ROOT}/uninstall.sh" 2>/dev/null || true

cw_tools_install_all
cw_tools_fetch_crawlers

if [[ ! -L "${HOME}/.local/bin/cw" ]]; then
  mkdir -p "${HOME}/.local/bin"
  ln -sf "${CW_ROOT}/bin/cw" "${HOME}/.local/bin/cw"
  cw_state_record local-bin-symlink "${HOME}/.local/bin/cw" "${CW_ROOT}/bin/cw"
fi

cw_state_log "install finished"
echo ""
_cw_toolkit_info "installed to ${CW_ROOT}"
_cw_toolkit_info "state directory ${CW_STATE_DIR}"
_cw_toolkit_info "run: source ~/.bash_aliases  (or open a new shell)"
_cw_toolkit_info "then: cw apps"

"${CW_ROOT}/bin/cw" status
