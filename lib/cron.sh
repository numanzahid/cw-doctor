#!/usr/bin/env bash

cw_cron_cmd() {
  local app="$1"
  [[ -n "$app" ]] || _cw_die "APP required"
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
    _cw_observed "From last $lines access log lines:"
    _cw_label "wp-cron.php hits" "$cron"
    _cw_label "admin-ajax.php hits" "$ajax"
    if [[ "$lines" -gt 0 ]]; then
      awk -v cron="$cron" -v lines="$lines" 'BEGIN {
        if (lines > 0) printf "  wp-cron rate: ~%.2f per line in sample\n", cron/lines
      }'
    fi
  else
    _cw_unavailable "access log for wp-cron counts"
  fi

  _cw_section "User crontab"
  if crontab -l 2>/dev/null | grep -v '^#' | grep -q .; then
    crontab -l 2>/dev/null | grep -v '^#' | _cw_redact_line
  else
    _cw_observed "no user crontab entries (or crontab empty)"
  fi

  _cw_section "WP-CLI cron (read-only)"
  if command -v wp >/dev/null 2>&1 && cw_apps_is_wordpress "$base"; then
    wp cron event list --path="$pub" 2>/dev/null | head -20 || _cw_unavailable "wp cron event list failed"
  else
    _cw_unavailable "wp-cli not available"
  fi
}

cw_cron_help() {
  echo "Usage: cw cron APP"
  echo "WP cron and admin-ajax activity (report only)."
}
