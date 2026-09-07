#!/usr/bin/env bash

cw_errors_cmd() {
  local app="$1"
  app="$(cw_apps_require_app "$app")"
  local base logs_dir pub error debug
  base="$(cw_apps_resolve "$app")"
  logs_dir="$(cw_apps_logs_dir "$base")"
  pub="$(cw_apps_public_html "$base")"
  error="$(cw_logs_find_error "$logs_dir" 2>/dev/null || true)"
  debug="$(cw_logs_find_debug "$pub" 2>/dev/null || true)"

  _cw_section "Errors: $app"
  local files=()
  [[ -n "$error" ]] && files+=("$error")
  [[ -n "$debug" ]] && files+=("$debug")

  if [[ ${#files[@]} -eq 0 ]]; then
    _cw_unavailable "no readable error or debug logs"
    return 0
  fi

  local combined sample lines meta_parts=() f
  combined="$(mktemp)"
  for f in "${files[@]}"; do
    cw_logs_sample_file "$f" "$CW_ERROR_SAMPLE_LINES" >> "$combined"
    meta_parts+=("$(basename "$f"): $(cw_logs_sample_meta)")
  done
  lines="$(wc -l < "$combined" | tr -d ' ')"
  _cw_observed "Analyzed $lines lines from ${#files[@]} log(s)"
  for f in "${meta_parts[@]}"; do
    _cw_observed "  $f"
  done

  awk '
  {
    line = $0
    type = "other"
    if (tolower(line) ~ /fatal|parse error/) type = "fatal"
    else if (tolower(line) ~ /deprecated|warning/) type = "warning"
    else if (line ~ / 5[0-9]{2} /) type = "5xx"
    else if (tolower(line) ~ /timeout|timed out/) type = "timeout"
    types[type]++

    sig = line
    gsub(/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+/, "<TS>", sig)
    gsub(/pid [0-9]+/, "pid <PID>", sig)
    gsub(/in \/[^ ]+ on line [0-9]+/, "in <PATH> on line <N>", sig)
    if (length(sig) > 160) sig = substr(sig, 1, 160) "..."
    sig_count[sig]++
  }
  END {
    print ""
    print "== Counts by type =="
    for (t in types) printf "  %s: %d\n", t, types[t]+0
    print ""
    print "== Top signatures (max 15) =="
    n = asorti(sig_count, s, "@val_num_desc")
    for (i = 1; i <= n && i <= 15; i++)
      printf "  %d  %s\n", sig_count[s[i]], s[i]
  }
  ' "$combined" | _cw_redact_line

  rm -f "$combined"
}

cw_errors_help() {
  echo "Usage: cw errors APP"
  echo "Grouped error log summary."
}
