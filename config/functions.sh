# Shell jump helpers for Cloudways app folders (domain or folder id; fzf when APP omitted)

_cda_go() {
  local dest
  dest="$(cw path "$@")" || return 1
  if [[ -z "$dest" || ! -d "$dest" ]]; then
    echo "error: no app path resolved" >&2
    return 1
  fi
  cd "$dest" || return 1
}

cda() {
  if [[ $# -eq 0 ]]; then
    _cda_go --pick
  else
    _cda_go "$1"
  fi
}

cdapp() {
  if [[ $# -eq 0 ]]; then
    _cda_go --pick --app
  else
    _cda_go "$1" --app
  fi
}

cdlogs() {
  if [[ $# -eq 0 ]]; then
    _cda_go --pick --logs
  else
    _cda_go "$1" --logs
  fi
}
