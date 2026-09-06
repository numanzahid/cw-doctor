#!/usr/bin/env bash

cw_slow_cmd() {
  local app="$1"
  [[ -n "$app" ]] || _cw_die "APP required"
  local base logs_dir php_log slow_log
  base="$(cw_apps_resolve "$app")"
  logs_dir="$(cw_apps_logs_dir "$base")"
  php_log="$(cw_logs_find_php_access "$logs_dir" 2>/dev/null || true)"
  slow_log="$(cw_logs_find_slow "$logs_dir" 2>/dev/null || true)"

  _cw_section "Slow analysis: $app"

  if [[ -n "$php_log" ]]; then
    local fp
    fp="$(cw_logs_fingerprint_php_access "$php_log")"
    _cw_label "php-app.access" "$php_log ($fp)"
    if [[ "$fp" == php-fpm-cpu ]]; then
      _cw_section "Top expensive PHP requests (sample)"
      cw_logs_sample_file "$php_log" "$CW_PHP_SAMPLE_LINES" | awk '
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
    fi
  else
    _cw_unavailable "php-app.access.log"
  fi

  if [[ -n "$slow_log" ]] && [[ -s "$slow_log" ]]; then
    _cw_section "Slow log traces (recent)"
    local traces
    traces="$(wc -l < "$slow_log" 2>/dev/null || echo 0)"
    _cw_observed "$traces lines in current slow log"

    awk '
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
    ' "$slow_log"
  else
    _cw_unavailable "php-app.slow.log"
  fi
}

cw_slow_help() {
  echo "Usage: cw slow APP"
  echo "PHP slow log and expensive request analysis."
}
