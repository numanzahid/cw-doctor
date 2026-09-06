#!/usr/bin/env bash

cw_doctor_cmd() {
  local app="${1:-}"
  if [[ -z "$app" ]] && _cw_is_interactive; then
    app="$(cw_apps_pick_with_scope)"
  fi
  _cw_section "Server"
  _cw_label "hostname" "$(cw_platform_hostname)"
  _cw_label "os" "$(cw_platform_os)"
  _cw_label "arch" "$(cw_platform_arch)"
  _cw_label "uptime" "$(cw_platform_uptime)"
  _cw_label "load" "$(cw_platform_load)"
  echo ""
  cw_platform_mem
  echo ""
  _cw_label "disk /" "$(cw_platform_disk_root)"
  _cw_label "inodes /" "$(cw_platform_inode_root)"

  _cw_section "Top CPU processes"
  cw_platform_top_cpu

  _cw_section "Top memory processes"
  cw_platform_top_mem

  _cw_section "Listeners (sample)"
  cw_platform_listeners

  if [[ -n "$app" ]]; then
    local base pub logs_dir
    base="$(cw_apps_resolve "$app")"
    pub="$(cw_apps_public_html "$base")"
    logs_dir="$(cw_apps_logs_dir "$base")"

    _cw_section "App: $app"
    _cw_label "path" "$pub"
    if cw_apps_is_wordpress "$base"; then
      _cw_observed "WordPress installation detected"
      cw_apps_detect_wp_cli "$pub"
      cw_apps_read_disable_wp_cron "$pub"
    else
      _cw_not_established "WordPress not detected"
    fi

    _cw_section "Logs"
    cw_logs_list_for_app "$base"

    local debug
    debug="$(cw_logs_find_debug "$pub" 2>/dev/null || true)"
    if [[ -n "$debug" ]]; then
      local sz
      sz="$(stat -c%s "$debug" 2>/dev/null || echo 0)"
      _cw_label "debug.log size" "$(_cw_human_bytes "$sz")"
    fi

    local access error
    access="$(cw_logs_find_access "$logs_dir" 2>/dev/null || true)"
    error="$(cw_logs_find_error "$logs_dir" 2>/dev/null || true)"
    if [[ -n "$access" ]]; then
      local fp lines
      fp="$(cw_logs_fingerprint_combined "$access")"
      lines="$(wc -l < "$access" 2>/dev/null || echo 0)"
      _cw_label "access format" "$fp"
      _cw_label "access lines" "$lines (current file)"
      if [[ "$fp" == combined ]]; then
        local fivexx
        fivexx="$(_cw_tail_sample "$access" 5000 | awk '{
          if (match($0, /" ([0-9]{3}) /, a) && a[1] >= 500) c++
        } END { print c+0 }')"
        _cw_label "recent 5xx (sample)" "$fivexx in last 5000 lines"
      fi
    fi
    if [[ -n "$error" ]]; then
      local elines
      elines="$(wc -l < "$error" 2>/dev/null || echo 0)"
      _cw_label "error log lines" "$elines (current file)"
    fi
  else
    _cw_possible "Specify an app name for per-app details"
  fi

  _cw_section "Boundaries"
  _cw_unavailable "PHP-FPM pool config, host quotas, WAF state, MySQL tuning"
}

cw_doctor_help() {
  echo "Usage: cw doctor [APP]"
  echo "Server and application health snapshot (read-only)."
}
