#!/usr/bin/env bash
# Install state tracking for reversible uninstall

CW_STATE_FILE="${CW_STATE_DIR}/install-state"
CW_INSTALL_LOG="${CW_STATE_DIR}/install.log"
CW_INSTALL_LOCK="${CW_STATE_DIR}/install.lock"

cw_state_tools_last_install_path() {
  printf '%s/tools-last-install' "$CW_STATE_DIR"
}

cw_state_init() {
  mkdir -p "${CW_STATE_DIR}" "${CW_STATE_DIR}/backups" "${CW_STATE_DIR}/reports"
  chmod 700 "${CW_STATE_DIR}" 2>/dev/null || true
  if [[ ! -f "$CW_STATE_FILE" ]]; then
    : > "$CW_STATE_FILE"
    chmod 600 "$CW_STATE_FILE" 2>/dev/null || true
  fi
}

cw_state_log() {
  cw_state_init
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$CW_INSTALL_LOG"
}

cw_state_record() {
  local kind="$1" path="$2" extra="${3:-}"
  cw_state_init
  printf '%s\t%s\t%s\n' "$kind" "$path" "$extra" >> "$CW_STATE_FILE"
  chmod 600 "$CW_STATE_FILE" 2>/dev/null || true
}

cw_state_acquire_lock() {
  cw_state_init
  if [[ -f "$CW_INSTALL_LOCK" ]]; then
    local pid
    pid="$(cat "$CW_INSTALL_LOCK" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      _cw_toolkit_die "another install/update is running (pid $pid)"
    fi
  fi
  echo "$$" > "$CW_INSTALL_LOCK"
  cw_state_record lock "$CW_INSTALL_LOCK" "$$"
}

cw_state_release_lock() {
  rm -f "$CW_INSTALL_LOCK"
}

cw_state_tools_last_install_read() {
  local path
  cw_state_init
  path="$(cw_state_tools_last_install_path)"
  [[ -f "$path" ]] || return 1
  tr -d '[:space:]' < "$path"
}

cw_state_tools_mark_installed() {
  local ts path
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cw_state_init
  path="$(cw_state_tools_last_install_path)"
  printf '%s\n' "$ts" > "$path"
  chmod 600 "$path" 2>/dev/null || true
  cw_state_log "bundled tools installed ${ts}"
}

cw_state_tools_age_days() {
  local last now ts age_secs
  last="$(cw_state_tools_last_install_read)" || return 1
  if ! ts="$(date -u -d "$last" +%s 2>/dev/null)"; then
    return 1
  fi
  now="$(date -u +%s)"
  age_secs=$((now - ts))
  if [[ "$age_secs" -lt 0 ]]; then
    return 1
  fi
  printf '%s' "$(( age_secs / 86400 ))"
}

cw_state_backup_file() {
  local target="$1"
  if [[ -f "$target" ]]; then
    local backup="${CW_STATE_DIR}/backups/$(basename "$target").$(date +%s).bak"
    cp -a "$target" "$backup"
    cw_state_record backup "$target" "$backup"
    printf '%s' "$backup"
  fi
}

cw_state_migrate_managed_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if grep -q "$CW_MANAGED_BEGIN_LEGACY" "$file" 2>/dev/null; then
    sed -i "s|${CW_MANAGED_BEGIN_LEGACY}|${CW_MANAGED_BEGIN}|g" "$file"
    sed -i "s|${CW_MANAGED_END_LEGACY}|${CW_MANAGED_END}|g" "$file"
    cw_state_record modify "$file" managed-block-migrated
  fi
}

cw_state_ensure_managed_block() {
  local file="$1" shell_script="$2"
  cw_state_init
  if [[ ! -f "$file" ]]; then
    touch "$file"
    cw_state_record create "$file"
  fi
  if ! grep -q "$CW_MANAGED_BEGIN" "$file" 2>/dev/null && \
     ! grep -q "$CW_MANAGED_BEGIN_LEGACY" "$file" 2>/dev/null; then
    cw_state_backup_file "$file" >/dev/null || true
    {
      echo ""
      echo "$CW_MANAGED_BEGIN"
      echo "[ -f \"$shell_script\" ] && source \"$shell_script\""
      echo "$CW_MANAGED_END"
    } >> "$file"
    cw_state_record modify "$file" managed-block
  fi
}

cw_state_safe_symlink() {
  local src="$1" dest="$2"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
      return 0
    fi
    return 1
  fi
  ln -s "$src" "$dest"
  cw_state_record symlink "$dest" "$src"
}

cw_state_reverse() {
  cw_state_init
  [[ -f "$CW_STATE_FILE" ]] || return 0
  local -a lines=()
  mapfile -t lines < "$CW_STATE_FILE"
  local i
  for (( i=${#lines[@]}-1; i>=0; i-- )); do
    local kind path extra
    IFS=$'\t' read -r kind path extra <<< "${lines[$i]}"
    case "$kind" in
      symlink)
        [[ -L "$path" ]] && rm -f "$path"
        ;;
      create)
        [[ -f "$path" ]] && rm -f "$path"
        ;;
      modify)
        if [[ -n "$extra" && "$extra" == managed-block ]]; then
          if [[ -f "$path" ]]; then
            sed -i '/# >>> cw >>>/,/# <<< cw <<</d' "$path" 2>/dev/null || true
            sed -i '/# >>> cw-doctor >>>/,/# <<< cw-doctor <<</d' "$path" 2>/dev/null || true
          fi
        fi
        ;;
      backup)
        local backup
        backup="$(awk -F'\t' -v p="$path" '$2==p && $1=="backup" {print $3; exit}' "$CW_STATE_FILE")"
        if [[ -n "$backup" && -f "$backup" ]]; then
          cp -a "$backup" "$path"
        fi
        ;;
      local-bin-symlink)
        [[ -L "$path" ]] && rm -f "$path"
        ;;
    esac
  done
}
