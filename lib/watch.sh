#!/usr/bin/env bash

CW_WATCH_PIDS=()

_cw_watch_cleanup() {
  local pid
  for pid in "${CW_WATCH_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}

_cw_watch_tail() {
  local file="$1" prefix="$2"
  [[ -r "$file" ]] || return 0
  tail -F -n 0 "$file" 2>/dev/null | while IFS= read -r line; do
    echo "${prefix} $line"
  done &
  CW_WATCH_PIDS+=($!)
}

cw_watch_cmd() {
  local app="$1" mode="${2:-all}"
  [[ -n "$app" ]] || _cw_die "APP required"
  local base logs_dir pub
  base="$(cw_apps_resolve "$app")"
  logs_dir="$(cw_apps_logs_dir "$base")"
  pub="$(cw_apps_public_html "$base")"

  trap _cw_watch_cleanup EXIT INT TERM

  _cw_section "Watching $app (mode=$mode, new lines only)"
  _cw_observed "Press Ctrl+C to stop"

  case "$mode" in
    access)
      _cw_watch_tail "$(cw_logs_find_access "$logs_dir")" "[ACCESS]" || _cw_die "no access log"
      ;;
    php)
      _cw_watch_tail "$(cw_logs_find_php_access "$logs_dir")" "[PHP]" || _cw_die "no php-app log"
      ;;
    errors)
      local error debug
      error="$(cw_logs_find_error "$logs_dir" 2>/dev/null || true)"
      debug="$(cw_logs_find_debug "$pub" 2>/dev/null || true)"
      [[ -n "$error" ]] && _cw_watch_tail "$error" "[ERROR]"
      [[ -n "$debug" ]] && _cw_watch_tail "$debug" "[DEBUG]"
      [[ ${#CW_WATCH_PIDS[@]} -eq 0 ]] && _cw_die "no error logs"
      ;;
    slow)
      _cw_watch_tail "$(cw_logs_find_slow "$logs_dir")" "[SLOW]" || _cw_die "no slow log"
      ;;
    all)
      _cw_watch_tail "$(cw_logs_find_access "$logs_dir" 2>/dev/null || true)" "[ACCESS]"
      _cw_watch_tail "$(cw_logs_find_php_access "$logs_dir" 2>/dev/null || true)" "[PHP]"
      local error debug
      error="$(cw_logs_find_error "$logs_dir" 2>/dev/null || true)"
      debug="$(cw_logs_find_debug "$pub" 2>/dev/null || true)"
      [[ -n "$error" ]] && _cw_watch_tail "$error" "[ERROR]"
      [[ -n "$debug" ]] && _cw_watch_tail "$debug" "[DEBUG]"
      _cw_watch_tail "$(cw_logs_find_slow "$logs_dir" 2>/dev/null || true)" "[SLOW]"
      [[ ${#CW_WATCH_PIDS[@]} -eq 0 ]] && _cw_die "no logs available to watch"
      ;;
    *)
      _cw_die "unknown mode: $mode"
      ;;
  esac

  wait
}

cw_watch_help() {
  echo "Usage: cw watch APP [errors|php|access|slow|all]"
  echo "Live log tail (tail -F -n 0). Cleans up child processes on exit."
}
