#!/usr/bin/env bash

cw_cron_cmd() {
  local app="$1"
  app="$(cw_apps_require_app "$app")"
  local base logs_dir access pub
  base="$(cw_apps_resolve "$app")"
  logs_dir="$(cw_apps_logs_dir "$base")"
  pub="$(cw_apps_public_html "$base")"
  access="$(cw_logs_find_access "$logs_dir" 2>/dev/null || true)"

  _cw_section "Cron / scheduled traffic: $app"

  cw_apps_read_disable_wp_cron "$pub"

  if [[ -n "$access" ]]; then
    local sample
    sample="$(cw_logs_sample_file "$access" "$CW_TRAFFIC_SAMPLE_LINES")"
    local lines cron ajax
    lines="$(echo "$sample" | wc -l)"
    cron="$(echo "$sample" | grep -c 'wp-cron\.php' || true)"
    ajax="$(echo "$sample" | grep -c 'admin-ajax\.php' || true)"
    local meta
    meta="$(cw_logs_sample_meta)"
    if [[ -n "$meta" ]]; then
      _cw_observed "From $meta:"
    else
      _cw_observed "From last $lines access log lines:"
    fi
    _cw_label "wp-cron.php hits" "$cron"
    _cw_label "admin-ajax.php hits" "$ajax"
    if [[ "$lines" -gt 0 ]]; then
      awk -v cron="$cron" -v lines="$lines" 'BEGIN {
        if (lines > 0) printf "  wp-cron rate: ~%.2f per line in sample\n", cron/lines
      }'
    fi
  else
    _cw_observed "access log: not found or not readable under $logs_dir"
  fi

  _cw_section "User crontab"
  if crontab -l 2>/dev/null | grep -v '^#' | grep -q .; then
    crontab -l 2>/dev/null | grep -v '^#' | _cw_redact_line
  else
    _cw_observed "no user crontab entries (or crontab empty)"
  fi

  _cw_section "WP-CLI cron (read-only)"
  if command -v wp >/dev/null 2>&1 && cw_apps_is_wordpress "$base"; then
    local wp_out wp_err
    wp_out="$(wp cron event list --path="$pub" 2>&1)"
    if [[ $? -eq 0 ]] && [[ -n "$wp_out" ]]; then
      echo "$wp_out" | head -20
    else
      wp_err="$(cw_apps_wp_cli_error_summary "$wp_out")"
      if [[ -n "$wp_err" ]]; then
        _cw_observed "wp-cli: $(printf '%s' "$wp_err" | _cw_redact_line)"
      fi
      _cw_observed "wp cron event list skipped (WordPress bootstrap failed; site/plugin config, not SSH access)"
      _cw_possible "Fix object-cache drop-in, wp-salt.php, or Redis/object-cache plugin before wp-cli cron works"
    fi
  else
    _cw_unavailable "wp-cli not available"
  fi
}

cw_cron_help() {
  echo "Usage: cw cron APP"
  echo "WP cron and admin-ajax activity (report only)."
}
