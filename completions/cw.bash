# bash completion for cw
_cw_app_tokens() {
  cw apps --completion 2>/dev/null
}

_cw_complete() {
  local cur prev words cword
  _init_completion || return
  local commands="menu apps path doctor cpu traffic slow watch logs errors cron disk collect reports go wp status update uninstall help"
  local watch_modes="access php errors slow all"
  case "$cword" in
    1)
      COMPREPLY=($(compgen -W "$commands" -- "$cur"))
      ;;
    2)
      case "$prev" in
        traffic|slow|watch|errors|cron|logs|go|wp)
          mapfile -t COMPREPLY < <(compgen -W "$(_cw_app_tokens)" -- "$cur")
          ;;
        doctor|cpu|disk|collect)
          mapfile -t COMPREPLY < <(compgen -W "$(_cw_app_tokens)" -- "$cur")
          compopt -o default
          ;;
        reports)
          COMPREPLY=($(compgen -W "--open" -- "$cur"))
          ;;
      esac
      ;;
    3)
      if [[ "$prev" == "watch" || "${words[1]}" == "watch" ]]; then
        COMPREPLY=($(compgen -W "$watch_modes" -- "$cur"))
      fi
      if [[ "${words[1]}" == "logs" && "$prev" != "logs" ]]; then
        COMPREPLY=($(compgen -W "--list --tail" -- "$cur"))
      fi
      ;;
  esac
}
complete -F _cw_complete cw
