#!/usr/bin/env bash

cw_slow_cmd() {
  local app="$1"
  app="$(cw_apps_require_app "$app")"
  local base logs_dir php_log slow_log php_path slow_path
  base="$(cw_apps_resolve "$app")"
  logs_dir="$(cw_apps_logs_dir "$base")"
  php_path="${logs_dir}/php-app.access.log"
  slow_path="${logs_dir}/php-app.slow.log"
  php_log="$(cw_logs_find_php_access "$logs_dir" 2>/dev/null || true)"
  slow_log="$(cw_logs_find_slow "$logs_dir" 2>/dev/null || true)"

  _cw_section "Slow analysis: $app"

  if [[ -n "$php_log" ]] && cw_logs_path_has_content "$php_log"; then
    local fp
    fp="$(cw_logs_fingerprint_php_access "$php_log")"
    _cw_label "php-app.access" "$php_log ($fp)"
    if [[ "$fp" == php-fpm-cpu ]]; then
      _cw_section "Top expensive PHP requests (sample)"
      sample="$(cw_logs_sample_file "$php_log" "$CW_PHP_SAMPLE_LINES")"
      local meta
      meta="$(cw_logs_sample_meta)"
      if [[ -n "$meta" ]]; then
        _cw_observed "$meta"
      fi
      echo "$sample" | awk '
      match($0, /^([^ ]+) - \[[^]]+\] "[A-Z]+ [^"]+" ([0-9]{3}) [^ ]+ [^ ]+ ([0-9]+) ([0-9]+) ([0-9.]+) [0-9]+ ([0-9.]+)%/, parts) {
        uri = $0
        if (match($0, /"([^"]+)"$/, up)) uri = up[1]
        cpu = parts[6]+0; dur = parts[5]+0; pid = parts[3]
        key = pid SUBSEP uri SUBSEP dur SUBSEP cpu
        if (!(key in seen)) { seen[key]=1; print cpu, dur, pid, uri }
      }
      ' | { sort -k1 -nr 2>/dev/null || true; } | head -20 | awk '{ printf "  cpu=%s%% dur=%ss pid=%s %s\n", $1, $2, $3, $4 }' || true
    else
      _cw_not_established "php-app.access field layout unknown; skipping CPU ranking"
      local sample_line
      sample_line="$(cw_logs_sample_line "$php_log" 2>/dev/null || true)"
      if [[ -n "$sample_line" ]]; then
        _cw_observed "sample line: ${sample_line:0:120}"
        [[ "${#sample_line}" -gt 120 ]] && _cw_observed "..."
      fi
    fi
  else
    local php_status php_detail
    IFS='|' read -r php_status php_detail <<< "$(cw_logs_path_status "$php_path")"
    _cw_log_path_issue "$php_status" "$php_path" "php-app.access.log" "$php_detail"
  fi

  if [[ -n "$slow_log" ]] && cw_logs_path_has_content "$slow_log"; then
    _cw_section "Slow log traces (sample)"
    slow_sample="$(cw_logs_sample_file "$slow_log" "$CW_ERROR_SAMPLE_LINES")"
    meta="$(cw_logs_sample_meta)"
    if [[ -n "$meta" ]]; then
      _cw_observed "$meta"
    fi

    echo "$slow_sample" | awk '
    BEGIN { trace=0 }
    /^\[[0-9]{2}-[A-Za-z]{3}-[0-9]{4}/ { pid=""; script=""; delete stack; trace++ }
    /pid ([0-9]+)/ { match($0, /pid ([0-9]+)/, a); pid=a[1] }
    /script_filename = / { sub(/.*script_filename = /, ""); script=$0 }
    /wp-content\/plugins\/[^\/]+/ {
      match($0, /wp-content\/plugins\/([^\/]+)/, p)
      plugins[p[1]]++
      if (pid != "") pid_plugin[pid SUBSEP p[1]] = 1
    }
    /wp-content\/themes\/[^\/]+/ {
      match($0, /wp-content\/themes\/([^\/]+)/, t)
      themes[t[1]]++
    }
    END {
      print ""
      print "== Plugin paths in slow traces =="
      n = asorti(plugins, sp, "@val_num_desc")
      if (n == 0) print "  none in sample"
      for (i = 1; i <= n && i <= 20; i++)
        printf "  appears in %d traces: plugin/%s\n", plugins[sp[i]], sp[i]
      print ""
      print "== Theme paths in slow traces =="
      n = asorti(themes, st, "@val_num_desc")
      if (n == 0) print "  none in sample"
      for (i = 1; i <= n && i <= 10; i++)
        printf "  appears in %d traces: theme/%s\n", themes[st[i]], st[i]
      print ""
      print "NOT ESTABLISHED: trace counts do not prove causation"
    }
    '
  else
    local slow_status slow_detail
    IFS='|' read -r slow_status slow_detail <<< "$(cw_logs_path_status "$slow_path")"
    _cw_log_path_issue "$slow_status" "$slow_path" "php-app.slow.log" "$slow_detail"
  fi
}

cw_slow_help() {
  echo "Usage: cw slow APP"
  echo "PHP slow log and expensive request analysis."
}
