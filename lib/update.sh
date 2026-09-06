#!/usr/bin/env bash

cw_status_cmd() {
  _cw_toolkit_section "status"
  _cw_toolkit_label "install" "$CW_ROOT"
  _cw_toolkit_label "state" "$CW_STATE_DIR"

  if [[ -d "${CW_ROOT}/.git" ]]; then
    local branch dirty
    branch="$(git -C "$CW_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    if git -C "$CW_ROOT" diff --quiet 2>/dev/null && git -C "$CW_ROOT" diff --cached --quiet 2>/dev/null; then
      dirty="clean"
    else
      dirty="MODIFIED"
    fi
    _cw_toolkit_label "git" "$branch ($dirty)"
  else
    _cw_toolkit_label "git" "MISSING"
  fi

  [[ -f "$CW_STATE_FILE" ]] && _cw_toolkit_label "install-state" "OK" || _cw_toolkit_label "install-state" "MISSING"

  if [[ -f "$CW_ALIASES_FILE" ]] && { grep -q "$CW_MANAGED_BEGIN" "$CW_ALIASES_FILE" 2>/dev/null || \
      grep -q "$CW_MANAGED_BEGIN_LEGACY" "$CW_ALIASES_FILE" 2>/dev/null; }; then
    _cw_toolkit_label "bash_aliases" "OK"
  else
    _cw_toolkit_label "bash_aliases" "MISSING"
  fi

  for link in "${HOME}/.tmux.conf:${CW_ROOT}/config/tmux.conf" "${HOME}/.inputrc:${CW_ROOT}/config/inputrc"; do
    local dest="${link%%:*}" src="${link##*:}"
    if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
      _cw_toolkit_label "$(basename "$dest")" "OK (symlink -> ${src})"
    elif [[ -e "$dest" ]]; then
      _cw_toolkit_label "$(basename "$dest")" "USER-CHANGED"
    else
      _cw_toolkit_label "$(basename "$dest")" "MISSING"
    fi
  done

  _cw_toolkit_section "bundled tools"
  cw_tools_status

  if [[ -f "${CW_ROOT}/config/crawlers.json" ]]; then
    _cw_toolkit_label "crawler list" "OK (${CW_ROOT}/config/crawlers.json)"
  else
    _cw_toolkit_label "crawler list" "MISSING"
  fi
}

cw_status_help() {
  echo "Usage: cw status"
  echo "cw-doctor: install health, paths, and bundled tools."
}

cw_update_cmd() {
  cw_state_acquire_lock
  trap cw_state_release_lock EXIT

  _cw_toolkit_section "update"
  _cw_toolkit_label "install" "$CW_ROOT"
  if [[ -d "${CW_ROOT}/.git" ]]; then
    if ! git -C "$CW_ROOT" diff --quiet 2>/dev/null || ! git -C "$CW_ROOT" diff --cached --quiet 2>/dev/null; then
      _cw_toolkit_die "refusing update: working tree is dirty"
    fi
    git -C "$CW_ROOT" pull --ff-only || _cw_toolkit_warn "git pull failed"
  fi

  cw_tools_install_all
  cw_tools_fetch_crawlers
  cw_state_ensure_managed_block "$CW_ALIASES_FILE" "${CW_ROOT}/config/shell.sh"
  cw_state_migrate_managed_block "$CW_ALIASES_FILE"
  cw_state_log "update completed"
  _cw_toolkit_info "update finished"
  cw_status_cmd
}

cw_update_help() {
  echo "Usage: cw update"
  echo "cw-doctor: manual update (git pull --ff-only, refresh tools and crawler list)."
}
