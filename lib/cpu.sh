#!/usr/bin/env bash

cw_cpu_cmd() {
  local app="${1:-}"
  if [[ -z "$app" ]] && _cw_is_interactive; then
    app="$(cw_apps_pick_with_scope)"
  fi

  _cw_section "Load and memory"
  _cw_label "load" "$(cw_platform_load)"
  cw_platform_mem
  echo ""
  _cw_label "swap" "$(free -h 2>/dev/null | awk '/Swap/ {print $2" used "$3}')"

  _cw_section "Top CPU"
  cw_platform_top_cpu

  _cw_section "Top memory"
  cw_platform_top_mem

  _cw_section "PHP / MySQL activity"
  cw_platform_php_mysql_procs || _cw_not_established "no matching processes in sample"

  cw_platform_scanner_note

  if [[ -n "$app" ]]; then
    local base logs_dir php_log
    base="$(cw_apps_resolve "$app")"
    logs_dir="$(cw_apps_logs_dir "$base")"
    php_log="$(cw_logs_find_php_access "$logs_dir" 2>/dev/null || true)"
    _cw_section "App: $app"
    if [[ -n "$php_log" ]]; then
      local fp
      fp="$(cw_logs_fingerprint_php_access "$php_log")"
      _cw_label "php-app.access" "$php_log ($fp)"
      if [[ "$fp" == php-fpm-cpu ]]; then
        _cw_likely "High PHP CPU may show in php-app.access.log"
        _cw_possible "Review slow-request and access-log analysis for this app"
      else
        _cw_possible "Review access-log traffic for this app"
      fi
    else
      _cw_not_established "php-app.access.log not available"
      _cw_possible "Review access-log traffic for this app"
    fi
  else
    _cw_possible "High load with many apps: review access-log traffic per app"
    _cw_possible "PHP slowness suspicion: review slow-request logs per app"
  fi
}

cw_cpu_help() {
  echo "Usage: cw cpu [APP]"
  echo "CPU, RAM, swap, and process snapshot."
}
