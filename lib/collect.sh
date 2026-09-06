#!/usr/bin/env bash

cw_collect_cmd() {
  local app="${1:-}"
  local ts report_id out
  ts="$(_cw_now_ts)"
  report_id="$ts"
  out="${CW_STATE_DIR}/reports/${ts}"
  mkdir -p "$out"

  _cw_toolkit_section "collect"
  _cw_toolkit_label "install" "$CW_ROOT"
  _cw_toolkit_label "report" "${out}/summary.txt"
  _cw_toolkit_label "scope" "${app:-server-wide}"

  {
    echo "Server diagnostic report"
    echo "timestamp: ${ts}"
    echo "hostname: $(cw_platform_hostname)"
    echo ""
    cw_doctor_cmd "$app" || true
    echo ""
    cw_cpu_cmd "$app" || true
    echo ""
    if [[ -n "$app" ]]; then
      cw_traffic_cmd "$app" || true
      echo ""
      cw_slow_cmd "$app" || true
      echo ""
      cw_errors_cmd "$app" || true
      echo ""
      cw_cron_cmd "$app" || true
    fi
    echo ""
    cw_disk_cmd "$app" || true
  } 2>&1 | _cw_redact_line | _cw_sanitize_report | sed -E \
    -e '/wp-config\.php/d' \
    -e '/\.env/d' \
    > "${out}/summary.txt"

  cw_state_log "collect report ${report_id}"
  _cw_toolkit_info "shareable summary written (toolkit references stripped from summary.txt)"
}

cw_collect_help() {
  echo "Usage: cw collect [APP]"
  echo "cw-doctor: write a sanitized diagnostic report (summary.txt is shareable)."
}
