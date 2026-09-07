#!/usr/bin/env bash
# fzf pickers and cw command menu

cw_pick_fzf_binary() {
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

cw_pick_require_interactive() {
  if ! _cw_is_interactive; then
    _cw_die "interactive terminal required (try: cw menu)"
  fi
}

cw_pick_run_fzf() {
  local header="$1" prompt="$2"
  shift 2
  local fzf_bin
  fzf_bin="$(cw_pick_fzf_binary)" || return 1
  if [[ -t 1 ]]; then
    FZF_DEFAULT_COMMAND= FZF_CTRL_T_COMMAND= "$fzf_bin" \
      --height="${CW_PICK_HEIGHT:-40%}" --reverse \
      --header="$header" --prompt="$prompt" --no-multi "$@"
  else
    FZF_DEFAULT_COMMAND= FZF_CTRL_T_COMMAND= "$fzf_bin" \
      --height="${CW_PICK_HEIGHT:-40%}" --reverse \
      --header="$header" --prompt="$prompt" --no-multi 2>/dev/tty "$@"
  fi
}

cw_pick_field() {
  local mode="$1"
  case "$mode" in
    first) awk '{print $1}' ;;
    last) awk '{print $NF}' ;;
    tab1) awk -F '\t' '{print $1}' ;;
    tab2) awk -F '\t' '{print $2}' ;;
    *) awk '{print $NF}' ;;
  esac
}

cw_pick_lines() {
  local header="$1" prompt="$2" field_mode="${3:-last}"
  local fzf_bin picked
  fzf_bin="$(cw_pick_fzf_binary)" || return 1
  picked="$(cw_pick_run_fzf "$header" "$prompt" | cw_pick_field "$field_mode")"
  [[ -n "$picked" ]] || return 1
  printf '%s' "$picked"
}

cw_pick_fallback_read() {
  local prompt="$1"
  local choice
  printf '%s' "$prompt" >&2
  if [[ -r /dev/tty ]]; then
    read -r choice </dev/tty
  else
    read -r choice
  fi
  [[ -n "$choice" ]] || return 1
  printf '%s' "$choice"
}

# Labeled fzf list: key + description columns (avoids tab-delimiter bugs).
cw_pick_labeled() {
  local header="$1" prompt="$2" width="$3"
  shift 3
  local key desc picked
  [[ $# -ge 2 ]] || return 1
  picked="$(
    while [[ $# -ge 2 ]]; do
      key="$1"
      desc="$2"
      shift 2
      printf '%-'"${width}"'s %s\n' "$key" "$desc"
    done | cw_pick_run_fzf "$header" "$prompt" | awk '{print $1}'
  )"
  [[ -n "$picked" ]] || return 1
  printf '%s' "$picked"
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
  choice="$(cw_pick_fallback_read 'Number, domain, or folder id: ')" || _cw_die "no app selected"
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

cw_apps_pick_interactive() {
  local apps
  mapfile -t apps < <(cw_apps_list)
  if [[ ${#apps[@]} -eq 0 ]]; then
    _cw_die "no applications found under ~/applications"
  fi
  if [[ ${#apps[@]} -eq 1 ]]; then
    printf '%s' "${apps[0]}"
    return 0
  fi
  cw_pick_require_interactive

  local apps_dir picked
  apps_dir="$(cw_platform_applications_dir)"
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(cw_apps_pick_lines "$apps_dir" "${apps[@]}" | cw_pick_run_fzf "Select application" "cw app> " | awk '{print $NF}')"
  else
    picked="$(cw_apps_pick_select "$apps_dir" "${apps[@]}")"
  fi

  [[ -n "$picked" ]] || _cw_die "no app selected"
  cw_apps_validate_picked_id "$picked" "${apps[@]}" || _cw_die "invalid app selection: $picked"
  printf '%s' "$picked"
}

cw_apps_require_app() {
  local app="${1:-}"
  if [[ -n "$app" ]]; then
    printf '%s' "$app"
    return 0
  fi
  cw_apps_pick_interactive
}

cw_apps_pick_with_scope() {
  local app="${1:-}"
  if [[ -n "$app" ]]; then
    printf '%s' "$app"
    return 0
  fi
  if ! _cw_is_interactive; then
    printf '%s' ""
    return 0
  fi

  local apps apps_dir picked lines
  mapfile -t apps < <(cw_apps_list)
  apps_dir="$(cw_platform_applications_dir)"
  if [[ ${#apps[@]} -eq 0 ]]; then
    printf '%s' ""
    return 0
  fi
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(cw_apps_pick_lines "$apps_dir" "${apps[@]}" | awk '{printf "%s\t%s (%s)\n", $NF, $1, $2}')"
    lines="$(printf 'server-wide\tServer-wide (all apps on server)\n%s' "$picked")"
    picked="$(printf '%s' "$lines" | cw_pick_run_fzf "Select scope" "cw scope> " --delimiter=$'\t' --with-nth=2.. | awk -F '\t' '{print $1}')"
    [[ -z "$picked" ]] && _cw_die "no scope selected"
    [[ "$picked" == "server-wide" ]] && printf '%s' "" && return 0
    cw_apps_validate_picked_id "$picked" "${apps[@]}" || _cw_die "invalid app selection: $picked"
    printf '%s' "$picked"
    return 0
  fi

  printf '  0) Server-wide (all apps on server)\n' >&2
  picked="$(cw_apps_pick_select "$apps_dir" "${apps[@]}")"
  printf '%s' "$picked"
}

cw_pick_command() {
  cw_pick_require_interactive
  local picked
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(cw_pick_labeled "cw-doctor commands" "cw> " 16 \
      apps "List applications on this server" \
      path "Print app directory path" \
      doctor "Server and app health snapshot" \
      cpu "CPU, RAM, and processes" \
      traffic "Access log traffic analysis" \
      slow "PHP slow log analysis" \
      watch "Live log tail" \
      logs "Browse and view log files" \
      errors "Error log summary" \
      cron "WP cron and admin-ajax activity" \
      disk "Disk and inode usage" \
      collect "Write sanitized report bundle" \
      reports "Browse past collect reports" \
      go "Jump path within an app" \
      wp "List WordPress plugins or themes" \
      status "Install health check" \
      update "Manual update (git pull + tools)" \
      help "Show command help")" || _cw_die "no command selected"
  else
    cat >&2 <<'EOF'
  apps       List applications on this server
  watch      Live log tail
  traffic    Access log traffic analysis
  logs       Browse and view log files
  reports    Browse past collect reports
  help       Show command help
EOF
    picked="$(cw_pick_fallback_read 'Command name: ')" || _cw_die "no command selected"
  fi
  printf '%s' "$picked"
}

cw_pick_watch_mode() {
  local mode="${1:-}"
  [[ -n "$mode" ]] && { printf '%s' "$mode"; return 0; }
  cw_pick_require_interactive
  local picked
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(cw_pick_labeled "Watch mode" "cw watch> " 10 \
      all "All log streams" \
      access "Access log" \
      php "PHP app log" \
      errors "Error and debug logs" \
      slow "PHP slow log")" || _cw_die "no watch mode selected"
  else
    picked="$(cw_pick_fallback_read 'Watch mode (all|access|php|errors|slow): ')" || _cw_die "no watch mode selected"
  fi
  printf '%s' "$picked"
}

cw_pick_path_target() {
  local target="${1:-}"
  [[ -n "$target" ]] && { printf '%s' "$target"; return 0; }
  cw_pick_require_interactive
  local picked
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(cw_pick_labeled "Path target" "cw path> " 8 \
      web "public_html" \
      app "Application root" \
      logs "Logs directory")" || _cw_die "no path target selected"
  else
    picked="$(cw_pick_fallback_read 'Target (web|app|logs): ')" || _cw_die "no path target selected"
  fi
  printf '%s' "$picked"
}

cw_pick_log_file() {
  local logs_dir="$1"
  local files=() f
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(find "$logs_dir" -maxdepth 1 -type f -readable 2>/dev/null | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    _cw_die "no readable log files in $logs_dir"
  fi
  if [[ ${#files[@]} -eq 1 ]]; then
    printf '%s' "${files[0]}"
    return 0
  fi
  cw_pick_require_interactive
  local picked
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(for f in "${files[@]}"; do
      printf '%s\t%s\n' "$f" "$(basename "$f")"
    done | cw_pick_run_fzf "Select log file" "cw logs> " --delimiter=$'\t' --with-nth=2.. | awk -F '\t' '{print $1}')"
  else
    local i=1 base
    for f in "${files[@]}"; do
      base="$(basename "$f")"
      printf '  %2d) %s\n' "$i" "$base" >&2
      i=$((i + 1))
    done
    picked="$(cw_pick_fallback_read 'Log file number: ')"
    [[ "$picked" =~ ^[0-9]+$ ]] || _cw_die "invalid selection: $picked"
    [[ "$picked" -ge 1 && "$picked" -le ${#files[@]} ]] || _cw_die "invalid selection: $picked"
    picked="${files[$((picked - 1))]}"
  fi
  [[ -n "$picked" && -f "$picked" ]] || _cw_die "no log file selected"
  printf '%s' "$picked"
}

cw_pick_report_dir() {
  local dirs=() d base picked
  if [[ ! -d "${CW_STATE_DIR}/reports" ]]; then
    _cw_die "no reports directory (${CW_STATE_DIR}/reports)"
  fi
  while IFS= read -r d; do
    [[ -n "$d" ]] && dirs+=("$d")
  done < <(find "${CW_STATE_DIR}/reports" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
  if [[ ${#dirs[@]} -eq 0 ]]; then
    _cw_die "no reports found (run: cw collect)"
  fi
  if [[ ${#dirs[@]} -eq 1 ]]; then
    printf '%s' "${dirs[0]}"
    return 0
  fi
  cw_pick_require_interactive
  local picked
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(for d in "${dirs[@]}"; do
      base="$(basename "$d")"
      if [[ -f "${d}/summary.txt" ]]; then
        printf '%s\t%s (summary.txt)\n' "$d" "$base"
      else
        printf '%s\t%s\n' "$d" "$base"
      fi
    done | cw_pick_run_fzf "Select report" "cw reports> " --delimiter=$'\t' --with-nth=2.. | awk -F '\t' '{print $1}')"
  else
    local i=1
    for d in "${dirs[@]}"; do
      printf '  %2d) %s\n' "$i" "$(basename "$d")" >&2
      i=$((i + 1))
    done
    picked="$(cw_pick_fallback_read 'Report number: ')"
    [[ "$picked" =~ ^[0-9]+$ ]] && picked="${dirs[$((picked - 1))]}"
  fi
  [[ -n "$picked" && -d "$picked" ]] || _cw_die "no report selected"
  printf '%s' "$picked"
}

cw_pick_app_target() {
  local app_dir="$1"
  local pub logs_dir
  pub="$(cw_apps_public_html "$app_dir")"
  logs_dir="$(cw_apps_logs_dir "$app_dir")"
  cw_pick_require_interactive
  local lines picked
  lines="$(printf '%s\n' \
    "${pub}\tpublic_html" \
    "${app_dir}\tapplication root" \
    "${logs_dir}\tlogs" \
    "${pub}/wp-content\twp-content")"
  [[ -d "${pub}/wp-content/plugins" ]] && lines+="$(printf '\n%s\tplugins' "${pub}/wp-content/plugins")"
  [[ -d "${pub}/wp-content/themes" ]] && lines+="$(printf '\n%s\tthemes' "${pub}/wp-content/themes")"
  [[ -d "${app_dir}/conf" ]] && lines+="$(printf '\n%s\tconf' "${app_dir}/conf")"
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(printf '%s' "$lines" | cw_pick_run_fzf "Go to path" "cw go> " --delimiter=$'\t' --with-nth=2.. | awk -F '\t' '{print $1}')"
  else
    printf '%s\n' "$lines" | awk -F '\t' '{printf "  %s\n", $0}' >&2
    picked="$(cw_pick_fallback_read 'Path (full path from list): ')"
  fi
  [[ -n "$picked" && -e "$picked" ]] || _cw_die "no path selected"
  printf '%s' "$picked"
}

cw_pick_wp_kind() {
  local kind="${1:-}"
  [[ -n "$kind" ]] && { printf '%s' "$kind"; return 0; }
  cw_pick_require_interactive
  local picked
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(cw_pick_labeled "WordPress path" "cw wp> " 10 \
      plugins "Plugin directories" \
      themes "Theme directories")" || _cw_die "no kind selected"
  else
    picked="$(cw_pick_fallback_read 'Kind (plugins|themes): ')" || _cw_die "no kind selected"
  fi
  printf '%s' "$picked"
}

cw_pick_wp_item() {
  local dir="$1"
  local items=() d name
  [[ -d "$dir" ]] || _cw_die "directory not found: $dir"
  while IFS= read -r d; do
    [[ -n "$d" ]] && items+=("$d")
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [[ ${#items[@]} -eq 0 ]]; then
    _cw_die "no directories in $dir"
  fi
  if [[ ${#items[@]} -eq 1 ]]; then
    printf '%s' "${items[0]}"
    return 0
  fi
  cw_pick_require_interactive
  local picked
  if cw_pick_fzf_binary >/dev/null; then
    picked="$(for d in "${items[@]}"; do
      name="$(basename "$d")"
      printf '%s\t%s\n' "$d" "$name"
    done | cw_pick_run_fzf "Select item" "cw wp> " --delimiter=$'\t' --with-nth=2.. | awk -F '\t' '{print $1}')"
  else
    local i=1
    for d in "${items[@]}"; do
      printf '  %2d) %s\n' "$i" "$(basename "$d")" >&2
      i=$((i + 1))
    done
    picked="$(cw_pick_fallback_read 'Number: ')"
    [[ "$picked" =~ ^[0-9]+$ ]] && picked="${items[$((picked - 1))]}"
  fi
  [[ -n "$picked" && -d "$picked" ]] || _cw_die "no item selected"
  printf '%s' "$picked"
}

cw_menu_cmd() {
  cw_pick_require_interactive
  local cmd app mode target file report base pub kind

  cmd="$(cw_pick_command)" || return 1

  case "$cmd" in
    apps) cw_apps_cmd ;;
    path)
      app="$(cw_apps_pick_interactive)"
      target="$(cw_pick_path_target)"
      cw_path_cmd "$app" "--${target}"
      ;;
    doctor) cw_doctor_cmd "$(cw_apps_pick_with_scope)" ;;
    cpu) cw_cpu_cmd "$(cw_apps_pick_with_scope)" ;;
    traffic) cw_traffic_cmd "$(cw_apps_require_app "")" ;;
    slow) cw_slow_cmd "$(cw_apps_require_app "")" ;;
    watch)
      app="$(cw_apps_require_app "")"
      mode="$(cw_pick_watch_mode)"
      cw_watch_cmd "$app" "$mode"
      ;;
    logs) cw_logs_cmd ;;
    errors) cw_errors_cmd "$(cw_apps_require_app "")" ;;
    cron) cw_cron_cmd "$(cw_apps_require_app "")" ;;
    disk) cw_disk_cmd "$(cw_apps_pick_with_scope)" ;;
    collect) cw_collect_cmd "$(cw_apps_pick_with_scope)" ;;
    reports) cw_reports_cmd --open ;;
    go) cw_go_cmd ;;
    wp) cw_wp_cmd ;;
    status) cw_status_cmd ;;
    update) cw_update_cmd ;;
    help) _cw_help_global ;;
    *)
      _cw_die "unknown menu command: $cmd"
      ;;
  esac
}

cw_menu_help() {
  echo "Usage: cw menu"
  echo "cw-doctor: interactive fzf command launcher (same as bare 'cw')."
}

cw_logs_view_file() {
  local file="$1"
  if [[ -x "${CW_BIN_DIR}/bat" ]]; then
    "${CW_BIN_DIR}/bat" --paging=always "$file"
  elif command -v bat >/dev/null 2>&1; then
    bat --paging=always "$file"
  else
    tail -n 100 "$file"
  fi
}

cw_logs_cmd() {
  local app="" action=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list|-l) action="list"; shift ;;
      --tail) action="tail"; shift ;;
      -h|--help) cw_logs_help; return 0 ;;
      -*)
        _cw_die "unknown option: $1"
        ;;
      *)
        [[ -z "$app" ]] && app="$1" || _cw_die "unexpected argument: $1"
        shift
        ;;
    esac
  done

  app="$(cw_apps_require_app "$app")"
  local base logs_dir file pub
  base="$(cw_apps_resolve "$app")"
  logs_dir="$(cw_apps_logs_dir "$base")"
  pub="$(cw_apps_public_html "$base")"

  if [[ "$action" == "list" ]]; then
    _cw_section "Logs: $app"
    cw_logs_list_for_app "$base"
    local extra
    extra="$(cw_logs_find_debug "$pub" 2>/dev/null || true)"
    [[ -n "$extra" ]] && _cw_label "debug.log" "$extra"
    return 0
  fi

  file="$(cw_pick_log_file "$logs_dir")"
  if [[ "$action" == "tail" ]]; then
    _cw_section "Tail: $(basename "$file")"
    tail -F -n 0 "$file"
    return 0
  fi

  cw_logs_view_file "$file"
}

cw_logs_help() {
  echo "Usage: cw logs [APP] [--list|--tail]"
  echo "Browse log files (fzf picker when APP omitted). Default: view with bat or tail."
}

cw_reports_cmd() {
  local open=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --open) open=1; shift ;;
      -h|--help) cw_reports_help; return 0 ;;
      *) _cw_die "unknown option: $1" ;;
    esac
  done
  local dir summary
  dir="$(cw_pick_report_dir)"
  summary="${dir}/summary.txt"
  if [[ $open -eq 1 && -f "$summary" ]]; then
    cw_logs_view_file "$summary"
    return 0
  fi
  _cw_toolkit_section "report"
  _cw_toolkit_label "directory" "$dir"
  [[ -f "$summary" ]] && _cw_toolkit_label "summary" "$summary"
}

cw_reports_help() {
  echo "Usage: cw reports [--open]"
  echo "cw-doctor: browse past collect reports (fzf picker)."
}

cw_go_cmd() {
  local app="${1:-}"
  app="$(cw_apps_require_app "$app")"
  local base
  base="$(cw_apps_resolve "$app")"
  local target
  target="$(cw_pick_app_target "$base")"
  printf '%s\n' "$target"
}

cw_go_help() {
  echo "Usage: cw go [APP]"
  echo "Print a path inside an app (fzf picker for public_html, logs, wp-content, ...)."
}

cw_wp_cmd() {
  local app="${1:-}" kind="${2:-}"
  app="$(cw_apps_require_app "$app")"
  local base pub dir item
  base="$(cw_apps_resolve "$app")"
  pub="$(cw_apps_public_html "$base")"
  cw_apps_is_wordpress "$base" || _cw_die "not a WordPress app: $app"
  kind="$(cw_pick_wp_kind "$kind")"
  dir="${pub}/wp-content/${kind}"
  [[ -d "$dir" ]] || _cw_die "directory not found: $dir"
  item="$(cw_pick_wp_item "$dir")"
  printf '%s\n' "$item"
}

cw_wp_help() {
  echo "Usage: cw wp [APP] [plugins|themes]"
  echo "Pick a plugin or theme directory (fzf)."
}
