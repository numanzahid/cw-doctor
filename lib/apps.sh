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

cw_apps_completion_tokens() {
  local apps_dir app base
  apps_dir="$(cw_platform_applications_dir)" || return 1
  for app in "$apps_dir"/*/; do
    [[ -d "$app" ]] || continue
    base="$(basename "$app")"
    printf '%s\n' "$base"
    cw_apps_read_server_names "$app"
  done | sort -u
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
  query="${query#"${query%%[![:space:]]*}"}"
  query="${query%"${query##*[![:space:]]}"}"
  apps_dir="$(cw_platform_applications_dir)" || _cw_die "applications directory not found"
  if [[ -z "$query" ]]; then
    _cw_die "APP required"
  fi
  base="${apps_dir}/${query}"
  if [[ -d "$base" ]]; then
    if [[ "${base%/}" == "${apps_dir%/}" ]]; then
      _cw_die "unknown app: $query"
    fi
    printf '%s' "${base%/}"
    return 0
  fi
  resolved="$(cw_apps_match_id "$query" "$apps_dir")" || _cw_die "unknown app: $query"
  printf '%s' "${apps_dir}/${resolved}"
}

cw_apps_fzf_binary() {
  if [[ -x "${CW_BIN_DIR}/fzf" ]]; then
    printf '%s' "${CW_BIN_DIR}/fzf"
    return 0
  fi
  if command -v fzf >/dev/null 2>&1; then
    command -v fzf
    return 0
  fi
  return 1
}

cw_apps_pick_lines() {
  local apps_dir="$1"
  shift
  local apps=("$@") id url type
  for id in "${apps[@]}"; do
    url="$(cw_apps_primary_url "${apps_dir}/${id}")"
    type="$(cw_apps_stack_type "${apps_dir}/${id}")"
    printf '%-36s %-10s %s\n' "$url" "$type" "$id"
  done
}

cw_apps_run_fzf() {
  local fzf_bin="$1"
  # Keep app lines on stdin (pipe). UI goes to /dev/tty when stdout is captured.
  # Do NOT use 0</dev/tty; that drops the piped list and fzf walks the cwd.
  if [[ -t 1 ]]; then
    FZF_DEFAULT_COMMAND= FZF_CTRL_T_COMMAND= "$fzf_bin" \
      --height=40% --reverse --prompt='cw app> ' --header='Select application' --no-multi
  else
    FZF_DEFAULT_COMMAND= FZF_CTRL_T_COMMAND= "$fzf_bin" \
      --height=40% --reverse --prompt='cw app> ' --header='Select application' --no-multi 2>/dev/tty
  fi
}

cw_apps_validate_picked_id() {
  local picked="$1"
  shift
  local apps=("$@") id
  for id in "${apps[@]}"; do
    [[ "$id" == "$picked" ]] && return 0
  done
  return 1
}

cw_apps_pick_select() {
  local apps_dir="$1"
  shift
  local apps=("$@")
  local i=1 choice id url n
  for id in "${apps[@]}"; do
    url="$(cw_apps_primary_url "${apps_dir}/${id}")"
    printf '  %2d) %-36s %s\n' "$i" "$url" "$id" >&2
    i=$((i + 1))
  done
  printf 'Number, domain, or folder id: ' >&2
  if [[ -r /dev/tty ]]; then
    read -r choice </dev/tty
  else
    read -r choice
  fi
  [[ -n "$choice" ]] || _cw_die "no app selected"
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    n=$((choice))
    if [[ "$n" -ge 1 && "$n" -le ${#apps[@]} ]]; then
      printf '%s' "${apps[$((n - 1))]}"
      return 0
    fi
    _cw_die "invalid selection: $choice"
  fi
  local matched
  matched="$(cw_apps_match_id "$choice" "$apps_dir")" || _cw_die "unknown app: $choice"
  printf '%s' "$matched"
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
  if [[ "${1:-}" == "--completion" ]]; then
    cw_apps_completion_tokens
    return 0
  fi

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
  if [[ ${#apps[@]} -eq 0 ]]; then
    _cw_die "no applications found under ~/applications"
  fi
  if [[ ${#apps[@]} -eq 1 ]]; then
    echo "${apps[0]}"
    return 0
  fi
  if ! _cw_is_interactive; then
    _cw_die "multiple apps; specify APP (domain or folder id)"
  fi

  local apps_dir picked fzf_bin
  apps_dir="$(cw_platform_applications_dir)"
  if fzf_bin="$(cw_apps_fzf_binary)"; then
    picked="$(cw_apps_pick_lines "$apps_dir" "${apps[@]}" | cw_apps_run_fzf "$fzf_bin" | awk '{print $NF}')"
  else
    picked="$(cw_apps_pick_select "$apps_dir" "${apps[@]}")"
  fi

  [[ -n "$picked" ]] || _cw_die "no app selected"
  cw_apps_validate_picked_id "$picked" "${apps[@]}" || _cw_die "invalid app selection: $picked"
  printf '%s' "$picked"
}

cw_path_cmd() {
  local pick=0 target="web" query=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pick) pick=1; shift ;;
      --app|--root) target="app"; shift ;;
      --web|--public) target="web"; shift ;;
      --logs) target="logs"; shift ;;
      -h|--help) cw_path_help; return 0 ;;
      --) shift; break ;;
      -*)
        _cw_die "unknown option: $1"
        ;;
      *)
        if [[ -n "$query" ]]; then
          _cw_die "unexpected argument: $1"
        fi
        query="$1"
        shift
        ;;
    esac
  done

  if [[ $pick -eq 1 ]]; then
    query="$(cw_apps_pick_interactive)" || _cw_die "app selection failed"
    [[ -n "$query" ]] || _cw_die "no app selected"
  elif [[ -z "$query" ]]; then
    _cw_die "APP required (domain, folder id, or --pick)"
  fi

  local app_dir out apps_dir
  apps_dir="$(cw_platform_applications_dir)" || _cw_die "applications directory not found"
  app_dir="$(cw_apps_resolve "$query")" || _cw_die "unknown app: $query"
  case "$target" in
    app) out="$app_dir" ;;
    web) out="$(cw_apps_public_html "$app_dir")" ;;
    logs) out="$(cw_apps_logs_dir "$app_dir")" ;;
  esac
  [[ -d "$out" ]] || _cw_die "path not found: $out"
  printf '%s\n' "$out"
}

cw_path_help() {
  cat <<'EOF'
Usage: cw path APP [--app|--web|--logs]
       cw path --pick [--app|--web|--logs]

Print an application directory path. APP is a folder id or domain (same as cw traffic).

  --web     public_html (default)
  --app     application root (~/applications/<id>)
  --logs    logs directory
  --pick    interactive chooser (fzf when multiple apps)

Shell helpers (after install): cda, cdapp, cdlogs
EOF
}
