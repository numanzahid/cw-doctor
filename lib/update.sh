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
  if last="$(cw_state_tools_last_install_read 2>/dev/null)"; then
    local age="" ts_path
    ts_path="$(cw_state_tools_last_install_path)"
    age="$(cw_state_tools_age_days 2>/dev/null || true)"
    if [[ -n "$age" ]]; then
      _cw_toolkit_label "tools installed" "${last} (${age}d ago; ${ts_path})"
    else
      _cw_toolkit_label "tools installed" "${last} (${ts_path})"
    fi
  else
    _cw_toolkit_label "tools installed" "never (run cw update --force)"
  fi
  cw_tools_status

  if [[ -f "${CW_ROOT}/config/crawlers.json" ]]; then
    _cw_toolkit_label "crawler list" "OK (${CW_ROOT}/config/crawlers.json)"
  else
    _cw_toolkit_label "crawler list" "MISSING"
  fi
}

# Shell integration, config, and bundled tools. Does not git pull.
cw_doctor_sync() {
  local force="${1:-0}"
  cw_platform_preflight
  cw_state_init
  cw_state_ensure_managed_block "$CW_ALIASES_FILE" "${CW_ROOT}/config/shell.sh"
  cw_state_migrate_managed_block "$CW_ALIASES_FILE"
  cw_state_safe_symlink "${CW_ROOT}/config/tmux.conf" "${HOME}/.tmux.conf" || true
  cw_state_safe_symlink "${CW_ROOT}/config/inputrc" "${HOME}/.inputrc" || true
  chmod +x "${CW_ROOT}/bin/cw" "${CW_ROOT}/bin/cw-view" "${CW_ROOT}/uninstall.sh" 2>/dev/null || true
  cw_tools_install_all "$force"
  cw_tools_fetch_crawlers
  if [[ ! -L "${HOME}/.local/bin/cw" ]]; then
    mkdir -p "${HOME}/.local/bin"
    ln -sf "${CW_ROOT}/bin/cw" "${HOME}/.local/bin/cw"
    cw_state_record local-bin-symlink "${HOME}/.local/bin/cw" "${CW_ROOT}/bin/cw"
  fi
}

cw_status_help() {
  echo "Usage: cw status"
  echo "cw-doctor: install health, paths, and bundled tools."
}

_cw_update_git_dirty() {
  local repo="$1"
  ! git -C "$repo" diff --quiet 2>/dev/null || return 0
  ! git -C "$repo" diff --cached --quiet 2>/dev/null || return 0
  return 1
}

cw_update_git_pull() {
  local force="${1:-0}"
  local repo="${CW_ROOT}"
  local branch upstream ans

  [[ -d "${repo}/.git" ]] || return 0

  if ! _cw_update_git_dirty "$repo"; then
    _cw_toolkit_info "git pull --ff-only"
    git -C "$repo" pull --ff-only || _cw_toolkit_warn "git pull failed"
    return 0
  fi

  if [[ "$force" -eq 0 ]]; then
    _cw_toolkit_die "refusing update: working tree is dirty (use cw update --force to discard and pull)"
  fi

  if ! _cw_is_interactive; then
    _cw_toolkit_die "working tree is dirty; run cw update --force in an interactive terminal to confirm discard"
  fi

  _cw_toolkit_warn "local changes in ${repo} will be discarded:"
  git -C "$repo" status -s | head -20 >&2
  printf "Discard local changes and pull latest? [y/N] " >&2
  if [[ -r /dev/tty ]]; then
    read -r ans </dev/tty
  else
    read -r ans
  fi
  if [[ ! "$ans" =~ ^[yY]([eE][sS])?$ ]]; then
    _cw_toolkit_die "update cancelled"
  fi

  _cw_toolkit_info "git fetch + reset --hard to upstream"
  git -C "$repo" fetch origin || _cw_toolkit_die "git fetch failed"
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  upstream="$(git -C "$repo" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    git -C "$repo" reset --hard "$upstream" || _cw_toolkit_die "git reset failed"
  else
    git -C "$repo" reset --hard "origin/${branch}" || _cw_toolkit_die "git reset failed"
  fi
}

cw_update_cmd() {
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        force=1
        shift
        ;;
      -h|--help)
        cw_update_help
        return 0
        ;;
      *)
        _cw_toolkit_die "unknown option: $1 (try: cw update --help)"
        ;;
    esac
  done

  cw_state_acquire_lock
  trap cw_state_release_lock EXIT

  _cw_toolkit_section "update"
  _cw_toolkit_label "install" "$CW_ROOT"

  cw_update_git_pull "$force"
  cw_doctor_sync "$force"
  cw_state_log "update completed (force=${force})"
  _cw_toolkit_info "update finished"
  _cw_toolkit_info "reload shell helpers: source ~/.bash_aliases  (or open a new shell)"
  cw_status_cmd
}

cw_update_help() {
  cat <<EOF
Usage: cw update [--force]

  Pull latest cw-doctor code (git), refresh shell integration and config,
  and install bundled tools (rg, fzf, bat, nvim, ...).

  Tool downloads are skipped when all tools were installed within the last
  ${CW_TOOLS_REFRESH_DAYS} days (timestamp: .state/tools-last-install).
  Use --force to re-download them anyway.

  With --force, if the git working tree has local changes, you will be asked
  to confirm discarding them before reset --hard to upstream.

  First-time setup: run ./install.sh once, then use cw update from then on.
EOF
}
