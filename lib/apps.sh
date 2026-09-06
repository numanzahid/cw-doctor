#!/usr/bin/env bash
# Application discovery on Cloudways

cw_apps_read_server_names() {
  local app_dir="$1"
  local conf nginx apache line
  for conf in "${app_dir}/conf/server.nginx" "${app_dir}/conf/server.apache"; do
    [[ -r "$conf" ]] || continue
    while IFS= read -r line; do
      line="${line%%;*}"
      if [[ "$line" =~ ^[[:space:]]*server_name[[:space:]]+(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*ServerName[[:space:]]+(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*ServerAlias[[:space:]]+(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
      fi
    done < "$conf"
  done | tr ' ' '\n' | sed '/^$/d' | sort -u
}

cw_apps_primary_url() {
  local app_dir="$1"
  local names=() name primary="" fallback=""
  mapfile -t names < <(cw_apps_read_server_names "$app_dir")
  for name in "${names[@]}"; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == *cloudwaysapps.com ]]; then
      [[ -z "$fallback" ]] && fallback="$name"
      continue
    fi
    if [[ "$name" == www.* ]]; then
      [[ -z "$primary" ]] && primary="${name#www.}"
      continue
    fi
    primary="$name"
    break
  done
  if [[ -n "$primary" ]]; then
    printf '%s' "$primary"
  elif [[ -n "$fallback" ]]; then
    printf '%s' "$fallback"
  else
    printf '%s' "unknown"
  fi
}

cw_apps_all_urls() {
  local app_dir="$1"
  cw_apps_read_server_names "$app_dir" | tr '\n' ' ' | sed 's/ $//'
}

cw_apps_stack_type() {
  local app_dir="$1"
  local pub names name
  pub="$(cw_apps_public_html "$app_dir")"
  if cw_apps_is_wordpress "$app_dir"; then
    printf '%s' "WordPress"
    return 0
  fi
  mapfile -t names < <(cw_apps_read_server_names "$app_dir")
  for name in "${names[@]}"; do
    if [[ "$name" == phpstack-* ]]; then
      printf '%s' "PHP"
      return 0
    fi
    if [[ "$name" == wordpress-* ]]; then
      printf '%s' "WordPress"
      return 0
    fi
  done
  if [[ -d "$pub" ]]; then
    printf '%s' "PHP"
  else
    printf '%s' "unknown"
  fi
}

cw_apps_short_path() {
  local path="$1"
  echo "$path" | sed "s|^${HOME}/||"
}

cw_apps_list() {
  local apps_dir
  apps_dir="$(cw_platform_applications_dir)" || return 1
  local d
  for d in "$apps_dir"/*/; do
    [[ -d "$d" ]] || continue
    basename "$d"
  done | sort
}

cw_apps_match_id() {
  local query="$1"
  local apps_dir="$2"
  local app base primary name
  for app in "$apps_dir"/*/; do
    [[ -d "$app" ]] || continue
    base="$(basename "$app")"
    [[ "$base" == "$query" ]] && { printf '%s' "$base"; return 0; }
    primary="$(cw_apps_primary_url "$app")"
    [[ "$primary" == "$query" ]] && { printf '%s' "$base"; return 0; }
    while IFS= read -r name; do
      [[ "$name" == "$query" ]] && { printf '%s' "$base"; return 0; }
    done < <(cw_apps_read_server_names "$app")
  done
  return 1
}

cw_apps_resolve() {
  local query="$1"
  local apps_dir base resolved
  apps_dir="$(cw_platform_applications_dir)" || _cw_die "applications directory not found"
  if [[ -z "$query" ]]; then
    _cw_die "APP required"
  fi
  base="${apps_dir}/${query}"
  if [[ -d "$base" ]]; then
    printf '%s' "$base"
    return 0
  fi
  resolved="$(cw_apps_match_id "$query" "$apps_dir")" || _cw_die "unknown app: $query"
  printf '%s' "${apps_dir}/${resolved}"
}

cw_apps_is_wordpress() {
  local app_dir="$1"
  [[ -f "${app_dir}/public_html/wp-config.php" ]] || \
  [[ -f "${app_dir}/public_html/wp-settings.php" ]] || \
  [[ -d "${app_dir}/public_html/wp-content" ]]
}

cw_apps_public_html() {
  local app_dir="$1"
  printf '%s/public_html' "$app_dir"
}

cw_apps_logs_dir() {
  local app_dir="$1"
  printf '%s/logs' "$app_dir"
}

cw_apps_detect_wp_cli() {
  local pub="$1"
  if [[ -x "${pub}/wp" ]]; then
    echo "wp-cli: present (${pub}/wp)"
  elif command -v wp >/dev/null 2>&1; then
    echo "wp-cli: present (system PATH)"
  else
    echo "wp-cli: not found"
  fi
}

cw_apps_read_disable_wp_cron() {
  local cfg="$1/wp-config.php"
  if [[ ! -r "$cfg" ]]; then
    echo "DISABLE_WP_CRON: UNAVAILABLE (no wp-config.php)"
    return 0
  fi
  if grep -qE "define\s*\(\s*['\"]DISABLE_WP_CRON['\"]\s*,\s*true" "$cfg" 2>/dev/null; then
    echo "DISABLE_WP_CRON: true (OBSERVED in wp-config.php)"
    return 0
  fi
  echo "DISABLE_WP_CRON: not set or false"
  return 0
}

cw_apps_cmd() {
  local apps
  mapfile -t apps < <(cw_apps_list 2>/dev/null || true)
  if [[ ${#apps[@]} -eq 0 ]]; then
    _cw_die "no applications found under ~/applications"
  fi
  _cw_section "Applications (${#apps[@]})"
  printf "%-14s %-10s %-32s %s\n" "ID" "TYPE" "PRIMARY URL" "PATH"
  local app base pub type url path aliases
  for app in "${apps[@]}"; do
    base="$(cw_apps_resolve "$app")"
    pub="$(cw_apps_public_html "$base")"
    type="$(cw_apps_stack_type "$base")"
    url="$(cw_apps_primary_url "$base")"
    path="$(cw_apps_short_path "$pub")"
    printf "%-14s %-10s %-32s %s\n" "$app" "$type" "$url" "$path"
    aliases="$(cw_apps_all_urls "$base")"
    if [[ -n "$aliases" && "$aliases" != "$url" ]]; then
      echo "  aliases: $aliases"
    fi
  done
}

cw_apps_pick_interactive() {
  local apps
  mapfile -t apps < <(cw_apps_list)
  if [[ ${#apps[@]} -eq 1 ]]; then
    echo "${apps[0]}"
    return 0
  fi
  if _cw_is_tty && [[ -x "${CW_BIN_DIR}/fzf" ]]; then
    local apps_dir line id url type
    apps_dir="$(cw_platform_applications_dir)"
    while IFS= read -r id; do
      url="$(cw_apps_primary_url "${apps_dir}/${id}")"
      type="$(cw_apps_stack_type "${apps_dir}/${id}")"
      printf '%s  %s  %s\n' "$id" "$type" "$url"
    done <<< "$(printf '%s\n' "${apps[@]}")" | "${CW_BIN_DIR}/fzf" | awk '{print $1}'
  else
    _cw_die "multiple apps; specify APP explicitly"
  fi
}
