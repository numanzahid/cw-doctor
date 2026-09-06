#!/usr/bin/env bash

cw_disk_cmd() {
  local app="${1:-}"
  if [[ -z "$app" ]] && _cw_is_interactive; then
    app="$(cw_apps_pick_with_scope)"
  fi

  _cw_section "Filesystem"
  _cw_label "disk /" "$(cw_platform_disk_root)"
  _cw_label "inodes /" "$(cw_platform_inode_root)"

  if [[ -z "$app" ]]; then
    _cw_possible "Specify an app for log and cache sizes"
    return 0
  fi

  local base
  base="$(cw_apps_resolve "$app")"
  _cw_section "App disk: $app"

  local path
  while IFS= read -r path; do
    [[ -d "$path" ]] || continue
    local du_out
    du_out="$(du -sh "$path" 2>/dev/null | awk '{print $1}')"
    _cw_label "$(echo "$path" | sed "s|^${HOME}/||")" "${du_out:-?}"
  done < <(cw_logs_disk_paths "$base")
}

cw_disk_help() {
  echo "Usage: cw disk [APP]"
  echo "Disk and inode summary with bounded du on logs/cache paths."
}
