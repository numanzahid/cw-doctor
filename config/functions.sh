# Shell jump helpers for Cloudways app folders (domain or folder id; fzf when APP omitted)

cda() {
  local dest
  if [[ $# -eq 0 ]]; then
    dest="$(cw path --pick)" || return 1
  else
    dest="$(cw path "$1")" || return 1
  fi
  cd "$dest" || return 1
}

cdapp() {
  local dest
  if [[ $# -eq 0 ]]; then
    dest="$(cw path --pick --app)" || return 1
  else
    dest="$(cw path "$1" --app)" || return 1
  fi
  cd "$dest" || return 1
}

cdlogs() {
  local dest
  if [[ $# -eq 0 ]]; then
    dest="$(cw path --pick --logs)" || return 1
  else
    dest="$(cw path "$1" --logs)" || return 1
  fi
  cd "$dest" || return 1
}
