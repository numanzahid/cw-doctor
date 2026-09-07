#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${HOME}/.local/opt/cw-doctor"

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SOURCE_DIR=""
fi

CW_INSTALL_SRC=""
CW_INSTALL_DEST=""
CW_INSTALL_STAGING=""
CW_INSTALL_PRESERVED=""

_cw_install_preserve_dirs() {
  local dest="$1" tmp="$2"
  local keep
  for keep in .state runtime tools shims; do
    if [[ -d "${dest}/${keep}" ]]; then
      mv "${dest}/${keep}" "${tmp}/"
    fi
  done
}

_cw_install_restore_preserved() {
  local dest="$1" tmp="$2"
  local keep
  for keep in .state runtime tools shims; do
    if [[ -d "${tmp}/${keep}" ]]; then
      mv "${tmp}/${keep}" "${dest}/"
    fi
  done
}

_cw_install_cleanup_temp() {
  if [[ -n "${CW_INSTALL_STAGING:-}" && -d "${CW_INSTALL_STAGING}" ]]; then
    rm -rf "${CW_INSTALL_STAGING}"
  fi
  if [[ -n "${CW_INSTALL_PRESERVED:-}" && -d "${CW_INSTALL_PRESERVED}" ]]; then
    rm -rf "${CW_INSTALL_PRESERVED}"
  fi
  CW_INSTALL_STAGING=""
  CW_INSTALL_PRESERVED=""
}

_cw_install_relocate_abort() {
  local code=$?
  echo "cw-doctor: install relocate failed (exit ${code})" >&2
  if [[ -n "${CW_INSTALL_STAGING:-}" && -d "${CW_INSTALL_STAGING}/tree" ]]; then
    if [[ ! -d "${CW_INSTALL_DEST}" ]]; then
      echo "cw-doctor: recovering install to ${CW_INSTALL_DEST}" >&2
      mkdir -p "$(dirname "${CW_INSTALL_DEST}")"
      mv "${CW_INSTALL_STAGING}/tree" "${CW_INSTALL_DEST}" 2>/dev/null || true
    fi
  fi
  if [[ -n "${CW_INSTALL_PRESERVED:-}" && -d "${CW_INSTALL_PRESERVED}" && -d "${CW_INSTALL_DEST}" ]]; then
    _cw_install_restore_preserved "${CW_INSTALL_DEST}" "${CW_INSTALL_PRESERVED}" 2>/dev/null || true
  fi
  _cw_install_cleanup_temp
  trap - ERR
  exit "${code:-1}"
}

_cw_install_verify_root() {
  local root="$1"
  local label="$2"
  local f
  for f in install.sh uninstall.sh lib/common.sh bin/cw bin/cw-view; do
    if [[ ! -e "${root}/${f}" ]]; then
      echo "cw-doctor: ${label} incomplete at ${root} (missing ${f})" >&2
      exit 1
    fi
  done
}

_cw_install_relocate() {
  local src="$1" dest="$2"
  local parent preserved=0

  if [[ "$src" == "$dest" ]]; then
    return 0
  fi

  if [[ ! -d "$src" ]]; then
    if [[ -d "$dest" ]]; then
      _cw_install_verify_root "$dest" "install target"
      return 0
    fi
    echo "cw-doctor: install source missing: ${src}" >&2
    exit 1
  fi

  _cw_install_verify_root "$src" "install source"

  mkdir -p "$(dirname "$dest")"
  parent="$(dirname "$dest")"

  if [[ -e "$dest" && ! -d "$dest" ]]; then
    echo "cw-doctor: install target exists and is not a directory: ${dest}" >&2
    exit 1
  fi

  CW_INSTALL_SRC="$src"
  CW_INSTALL_DEST="$dest"
  CW_INSTALL_PRESERVED="$(mktemp -d)"
  CW_INSTALL_STAGING="$(mktemp -d "${parent}/.cw-doctor.staging.${USER}.XXXXXX")"
  trap '_cw_install_relocate_abort' ERR

  if [[ -d "$dest" ]]; then
    _cw_install_preserve_dirs "$dest" "$CW_INSTALL_PRESERVED"
    preserved=1
  fi

  if mv "$src" "${CW_INSTALL_STAGING}/tree" 2>/dev/null; then
    :
  else
    mkdir -p "${CW_INSTALL_STAGING}/tree"
    cp -a "${src}/." "${CW_INSTALL_STAGING}/tree/"
    rm -rf "$src"
  fi

  if [[ "$preserved" -eq 1 ]]; then
    _cw_install_restore_preserved "${CW_INSTALL_STAGING}/tree" "$CW_INSTALL_PRESERVED"
  fi

  if [[ -d "$dest" ]]; then
    rm -rf "$dest"
  fi
  mv "${CW_INSTALL_STAGING}/tree" "$dest"

  trap - ERR
  _cw_install_cleanup_temp
  CW_INSTALL_SRC=""
  CW_INSTALL_DEST=""
}

if [[ -z "$SOURCE_DIR" ]]; then
  if [[ -d "$TARGET_ROOT" ]]; then
    SOURCE_DIR="$TARGET_ROOT"
  else
    echo "cw-doctor: cannot locate install.sh" >&2
    exit 1
  fi
fi

if [[ "$SOURCE_DIR" != "$TARGET_ROOT" && ! -f "${SOURCE_DIR}/lib/common.sh" ]]; then
  if [[ -f "${TARGET_ROOT}/install.sh" && -f "${TARGET_ROOT}/lib/common.sh" ]]; then
    SOURCE_DIR="$TARGET_ROOT"
  else
    echo "cw-doctor: install source incomplete at ${SOURCE_DIR}" >&2
    echo "cw-doctor: clone the repo and run ./install.sh, or reinstall from ${TARGET_ROOT}/install.sh" >&2
    exit 1
  fi
fi

if [[ "$SOURCE_DIR" != "$TARGET_ROOT" ]]; then
  _cw_install_relocate "$SOURCE_DIR" "$TARGET_ROOT"
fi

CW_ROOT="$TARGET_ROOT"
cd "$CW_ROOT"
_cw_install_verify_root "$CW_ROOT" "install target"

# shellcheck source=lib/common.sh
source "${CW_ROOT}/lib/common.sh"
_cw_load_lib platform
_cw_load_lib state
_cw_load_lib tools
_cw_load_lib update

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
cw-doctor first-time install

Usage: ./install.sh

  Moves this repo to ~/.local/opt/cw-doctor (once), sets up shell integration,
  and installs bundled tools.

  After install, use cw update for all ongoing maintenance (git pull, config,
  tools). Use cw update --force to re-download bundled tools.

  Re-run ./install.sh to repair shell hooks without git pull.
EOF
      exit 0
      ;;
    --force)
      echo "cw-doctor: install.sh no longer accepts --force" >&2
      echo "cw-doctor: after install, run: cw update --force" >&2
      echo "cw-doctor: (or: ${TARGET_ROOT}/bin/cw update --force before cw is on PATH)" >&2
      exit 1
      ;;
    *)
      echo "cw-doctor: unknown option: $1 (try: ./install.sh --help)" >&2
      exit 1
      ;;
  esac
done

cw_state_acquire_lock
trap cw_state_release_lock EXIT

cw_state_log "install started in ${CW_ROOT}"
cw_doctor_sync 0
cw_state_log "install finished"

echo ""
_cw_toolkit_info "installed to ${CW_ROOT}"
_cw_toolkit_info "run: source ~/.bash_aliases  (or open a new shell)"
_cw_toolkit_info "then: cw apps"
_cw_toolkit_info "ongoing updates: cw update  (cw update --force to refresh all tools)"
_cw_toolkit_info "reload shell: source ~/.bash_aliases  (or open a new shell)"

"${CW_ROOT}/bin/cw" status
