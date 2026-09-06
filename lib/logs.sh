#!/usr/bin/env bash
# Log discovery and fingerprinting

cw_logs_find_access() {
  local logs_dir="$1"
  local f
  for f in nginx-app.status.log nginx-app.access.log; do
    [[ -r "${logs_dir}/${f}" ]] && { echo "${logs_dir}/${f}"; return 0; }
  done
  f="$(find "$logs_dir" -maxdepth 1 -type f -name 'backend_*access.log' -readable 2>/dev/null | head -1)"
  [[ -n "$f" ]] && { echo "$f"; return 0; }
  f="$(find "$logs_dir" -maxdepth 1 -type f -name 'static_*access.log' -readable 2>/dev/null | head -1)"
  [[ -n "$f" ]] && { echo "$f"; return 0; }
  return 1
}

cw_logs_find_php_access() {
  local logs_dir="$1"
  [[ -r "${logs_dir}/php-app.access.log" ]] && echo "${logs_dir}/php-app.access.log"
}

cw_logs_find_slow() {
  local logs_dir="$1"
  [[ -r "${logs_dir}/php-app.slow.log" ]] && echo "${logs_dir}/php-app.slow.log"
}

cw_logs_find_error() {
  local logs_dir="$1"
  local f
  for f in nginx-app.error.log; do
    [[ -r "${logs_dir}/${f}" ]] && { echo "${logs_dir}/${f}"; return 0; }
  done
  f="$(find "$logs_dir" -maxdepth 1 -type f -name 'backend_*error.log' -readable 2>/dev/null | head -1)"
  [[ -n "$f" ]] && echo "$f"
}

cw_logs_find_debug() {
  local pub="$1"
  [[ -r "${pub}/wp-content/debug.log" ]] && echo "${pub}/wp-content/debug.log"
}

cw_logs_fingerprint_combined() {
  local file="$1"
  local line
  line="$(_cw_tail_sample "$file" 1)"
  if echo "$line" | grep -qE '^[^ ]+ [^ ]+ [^ ]+ \[[^]]+\] "[A-Z]+ [^"]+" [0-9]{3} '; then
    echo "combined"
  else
    echo "unknown"
  fi
}

cw_logs_fingerprint_php_access() {
  local file="$1"
  local line
  line="$(_cw_tail_sample "$file" 1)"
  if echo "$line" | grep -qE '[0-9.]+%[[:space:]]+[0-9.]+%[[:space:]]+"[^"]*"$'; then
    echo "php-fpm-cpu"
    return 0
  fi
  echo "unknown"
}

cw_logs_sample_file() {
  local file="$1" limit="$2"
  _cw_tail_sample "$file" "$limit"
}

cw_logs_list_for_app() {
  local app_dir="$1"
  local logs_dir pub
  logs_dir="$(cw_apps_logs_dir "$app_dir")"
  pub="$(cw_apps_public_html "$app_dir")"
  local access php slow error debug
  access="$(cw_logs_find_access "$logs_dir" 2>/dev/null || true)"
  php="$(cw_logs_find_php_access "$logs_dir" 2>/dev/null || true)"
  slow="$(cw_logs_find_slow "$logs_dir" 2>/dev/null || true)"
  error="$(cw_logs_find_error "$logs_dir" 2>/dev/null || true)"
  debug="$(cw_logs_find_debug "$pub" 2>/dev/null || true)"
  _cw_label "access" "${access:-UNAVAILABLE}"
  _cw_label "php-app" "${php:-UNAVAILABLE}"
  _cw_label "slow" "${slow:-UNAVAILABLE}"
  _cw_label "error" "${error:-UNAVAILABLE}"
  _cw_label "debug.log" "${debug:-UNAVAILABLE}"
}

cw_logs_disk_paths() {
  local app_dir="$1"
  local pub logs_dir
  pub="$(cw_apps_public_html "$app_dir")"
  logs_dir="$(cw_apps_logs_dir "$app_dir")"
  echo "$logs_dir"
  [[ -d "${pub}/wp-content" ]] && echo "${pub}/wp-content"
  [[ -d "${pub}/wp-content/uploads" ]] && echo "${pub}/wp-content/uploads"
  [[ -d "${pub}/wp-content/cache" ]] && echo "${pub}/wp-content/cache"
  [[ -d "${pub}/wp-content/upgrade" ]] && echo "${pub}/wp-content/upgrade"
  # Discover plugin/theme cache dirs that exist (no hardcoded vendor list)
  find "${pub}/wp-content/plugins" -maxdepth 2 -type d \( -name cache -o -name caches -o -name backup -o -name backups \) 2>/dev/null
}
