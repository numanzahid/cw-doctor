#!/usr/bin/env bash
# Log discovery and fingerprinting

CW_LOGS_LAST_SAMPLE_META=""

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

cw_logs_sample_line() {
  local file="$1"
  local line rot

  [[ -r "$file" ]] || return 1

  line="$(tail -n 5 "$file" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 1)"
  if [[ -n "$line" ]]; then
    printf '%s' "$line"
    return 0
  fi

  while IFS= read -r rot; do
    [[ -n "$rot" && -r "$rot" ]] || continue
    line="$(cw_logs_read_tail "$rot" 5 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 1)"
    if [[ -n "$line" ]]; then
      printf '%s' "$line"
      return 0
    fi
  done < <(cw_logs_list_rotated "$file" | sort -rV)

  return 1
}

cw_logs_path_status() {
  local path="$1"
  local active total rot

  if [[ -z "$path" ]]; then
    printf '%s|%s' "missing" "path not set"
    return 1
  fi
  if [[ ! -e "$path" ]]; then
    printf '%s|%s' "missing" "file not found"
    return 1
  fi
  if [[ ! -r "$path" ]]; then
    printf '%s|%s' "denied" "permission denied"
    return 1
  fi

  active="$(cw_logs_count_lines "$path")"
  total="$(cw_logs_count_lines_total "$path")"
  rot="$(cw_logs_rotated_count "$path")"

  if [[ "$total" -eq 0 ]]; then
    if [[ "$rot" -gt 0 ]]; then
      printf '%s|%s' "empty" "0 lines in active file and ${rot} rotated sibling(s)"
    else
      printf '%s|%s' "empty" "0 lines"
    fi
    return 2
  fi

  if [[ "$active" -eq 0 ]]; then
    printf '%s|%s' "ok" "active empty; ${total} lines in ${rot} rotated file(s)"
  else
    printf '%s|%s' "ok" "${total} lines (active ${active}, ${rot} rotated)"
  fi
  return 0
}

cw_logs_path_has_content() {
  local path="$1" status
  status="$(cw_logs_path_status "$path" | cut -d'|' -f1)"
  [[ "$status" == ok ]]
}

cw_logs_fingerprint_combined() {
  local file="$1"
  local line
  line="$(cw_logs_sample_line "$file" 2>/dev/null || true)"
  if echo "$line" | grep -qE '^[^ ]+ [^ ]+ [^ ]+ \[[^]]+\] "[A-Z]+ [^"]+" [0-9]{3} '; then
    echo "combined"
  else
    echo "unknown"
  fi
}

cw_logs_fingerprint_php_access() {
  local file="$1"
  local line
  line="$(cw_logs_sample_line "$file" 2>/dev/null || true)"
  if echo "$line" | grep -qE '[0-9.]+%[[:space:]]+[0-9.]+%[[:space:]]+"[^"]*"$'; then
    echo "php-fpm-cpu"
    return 0
  fi
  echo "unknown"
}

cw_logs_is_rotated_sibling() {
  local base="$1" candidate="$2"
  local cand_base
  cand_base="$(basename "$candidate")"
  [[ "$cand_base" != "$base" ]] || return 1
  [[ "$cand_base" == "${base}."* || "$cand_base" == "${base}-"* ]]
}

cw_logs_list_rotated() {
  local file="$1"
  local dir base f
  dir="$(dirname "$file")"
  base="$(basename "$file")"
  for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == "$file" ]] && continue
    cw_logs_is_rotated_sibling "$base" "$f" || continue
    basename "$f"
  done | sort -V | while IFS= read -r bn; do
    printf '%s/%s\n' "$dir" "$bn"
  done
}

cw_logs_read_stream() {
  local file="$1"
  if [[ "$file" == *.gz ]]; then
    if command -v zcat >/dev/null 2>&1; then
      zcat -- "$file"
    elif command -v gzip >/dev/null 2>&1; then
      gzip -dc -- "$file"
    else
      return 1
    fi
  else
    cat -- "$file"
  fi
}

cw_logs_count_lines() {
  local file="$1" count
  [[ -r "$file" ]] || { echo 0; return 0; }
  count="$(cw_logs_read_stream "$file" 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s' "${count:-0}"
}

cw_logs_read_tail() {
  local file="$1" limit="$2"
  cw_logs_read_stream "$file" 2>/dev/null | tail -n "$limit"
}

cw_logs_count_lines_total() {
  local file="$1" total=0 rot n
  n="$(cw_logs_count_lines "$file")"
  total=$((total + n))
  while IFS= read -r rot; do
    [[ -n "$rot" ]] || continue
    n="$(cw_logs_count_lines "$rot")"
    total=$((total + n))
  done < <(cw_logs_list_rotated "$file")
  printf '%s' "$total"
}

cw_logs_rotated_count() {
  local file="$1" n=0 rot
  while IFS= read -r rot; do
    [[ -n "$rot" ]] && n=$((n + 1))
  done < <(cw_logs_list_rotated "$file")
  printf '%s' "$n"
}

cw_logs_sample_file() {
  local file="$1" limit="$2"
  local tmp older combined remaining line_count part_lines total=0 rot
  local -a sources=()

  CW_LOGS_LAST_SAMPLE_META=""
  [[ -r "$file" ]] || return 1
  [[ "$limit" =~ ^[0-9]+$ ]] && [[ "$limit" -gt 0 ]] || return 1

  tmp="$(mktemp)"
  remaining="$limit"

  line_count="$(cw_logs_count_lines "$file")"
  if [[ "$line_count" -gt "$remaining" ]]; then
    cw_logs_read_tail "$file" "$remaining" > "$tmp"
    total="$remaining"
    sources+=("$(basename "$file"):${total}")
    remaining=0
  elif [[ "$line_count" -gt 0 ]]; then
    cw_logs_read_tail "$file" "$line_count" > "$tmp"
    total="$line_count"
    sources+=("$(basename "$file"):${line_count}")
    remaining=$((limit - line_count))
  fi

  if [[ "$remaining" -gt 0 ]]; then
    while IFS= read -r rot; do
      [[ -n "$rot" && -r "$rot" ]] || continue
      line_count="$(cw_logs_count_lines "$rot")"
      [[ "$line_count" -gt 0 ]] || continue
      if [[ "$line_count" -gt "$remaining" ]]; then
        part_lines="$remaining"
      else
        part_lines="$line_count"
      fi
      older="$(mktemp)"
      cw_logs_read_tail "$rot" "$part_lines" > "$older"
      combined="$(mktemp)"
      cat "$older" "$tmp" > "$combined"
      mv "$combined" "$tmp"
      rm -f "$older"
      total=$((total + part_lines))
      sources+=("$(basename "$rot"):${part_lines}")
      remaining=$((remaining - part_lines))
      [[ "$remaining" -le 0 ]] && break
    done < <(cw_logs_list_rotated "$file")
  fi

  cat "$tmp"
  rm -f "$tmp"

  if [[ ${#sources[@]} -eq 0 ]]; then
    CW_LOGS_LAST_SAMPLE_META="last 0 lines ($(basename "$file"))"
  elif [[ ${#sources[@]} -eq 1 ]]; then
    CW_LOGS_LAST_SAMPLE_META="last ${total} lines from ${sources[0]%%:*}"
  else
    local joined=""
    local s
    for s in "${sources[@]}"; do
      joined="${joined:+$joined + }${s%%:*}:${s##*:}"
    done
    CW_LOGS_LAST_SAMPLE_META="last ${total} lines (${joined})"
  fi
}

cw_logs_sample_meta() {
  printf '%s' "${CW_LOGS_LAST_SAMPLE_META}"
}

cw_logs_list_label_path() {
  local label="$1" path="$2" default_path="$3"
  local check="${path:-$default_path}"
  local status detail

  if [[ -z "$check" || ! -e "$check" ]]; then
    _cw_label "$label" "not found"
    return 1
  fi

  IFS='|' read -r status detail <<< "$(cw_logs_path_status "$check")"
  case "$status" in
    ok)
      _cw_label "$label" "${path:-$check} ($detail)"
      if [[ "$label" == "access" ]]; then
        local active_lines rot_n total_lines
        active_lines="$(wc -l < "$check" 2>/dev/null | tr -d ' ')"
        rot_n="$(cw_logs_rotated_count "$check")"
        total_lines="$(cw_logs_count_lines_total "$check")"
        _cw_label "access lines" "${active_lines:-0} active, ${total_lines:-0} incl. rotations (${rot_n} rotated file(s))"
      fi
      ;;
    empty)
      _cw_label "$label" "${path:-$check} (empty: $detail)"
      ;;
    denied)
      _cw_label "$label" "${path:-$check} (not readable)"
      ;;
    *)
      _cw_label "$label" "${path:-UNAVAILABLE}"
      ;;
  esac
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
  cw_logs_list_label_path "access" "$access" "${logs_dir}/nginx-app.status.log"
  cw_logs_list_label_path "php-app" "$php" "${logs_dir}/php-app.access.log"
  cw_logs_list_label_path "slow" "$slow" "${logs_dir}/php-app.slow.log"
  cw_logs_list_label_path "error" "$error" "${logs_dir}/nginx-app.error.log"
  cw_logs_list_label_path "debug.log" "$debug" "${pub}/wp-content/debug.log"
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
