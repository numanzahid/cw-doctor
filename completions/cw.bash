# bash completion for cw
_cw_complete() {
  local cur prev words cword
  _init_completion || return
  local commands="apps doctor cpu traffic slow watch errors cron disk collect status update uninstall help"
  local watch_modes="access php errors slow all"
  case "$cword" in
    1)
      COMPREPLY=($(compgen -W "$commands" -- "$cur"))
      ;;
    2)
      case "$prev" in
        traffic|slow|watch|errors|cron)
          mapfile -t COMPREPLY < <(compgen -W "$(cw apps 2>/dev/null | awk 'NR>1 && $1 !~ /^==/ {print $1}')" -- "$cur")
          ;;
        doctor|cpu|disk|collect)
          mapfile -t COMPREPLY < <(compgen -W "$(cw apps 2>/dev/null | awk 'NR>1 && $1 !~ /^==/ {print $1}')" -- "$cur")
          compopt -o default
          ;;
      esac
      ;;
    3)
      if [[ "$prev" == "watch" || "${words[1]}" == "watch" ]]; then
        COMPREPLY=($(compgen -W "$watch_modes" -- "$cur"))
      fi
      ;;
  esac
}
complete -F _cw_complete cw
