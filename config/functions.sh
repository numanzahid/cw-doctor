# Shell helpers (cw app jump, fzf file/dir tools)

_CW_SHELL_ROOT="${HOME}/.local/opt/cw-doctor"

_cw_shell_bin() {
  local name="$1"
  if [[ -x "${_CW_SHELL_ROOT}/shims/${name}" ]]; then
    printf '%s' "${_CW_SHELL_ROOT}/shims/${name}"
    return 0
  fi
  if [[ -x "${_CW_SHELL_ROOT}/bin/${name}" ]]; then
    printf '%s' "${_CW_SHELL_ROOT}/bin/${name}"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  echo "error: required command not found: $name" >&2
  return 1
}

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

cgo() {
  local dest
  dest="$(cw go "$@")" || return 1
  if [[ -z "$dest" || ! -e "$dest" ]]; then
    echo "error: no path resolved" >&2
    return 1
  fi
  cd "$dest" || return 1
}

# Find a subdirectory under the current folder (or PATH) and cd into it.
fcd() {
  local root="${1:-.}" fzf_bin fd_bin dir abs
  fzf_bin="$(_cw_shell_bin fzf)" || return 1
  fd_bin="$(_cw_shell_bin fd)" || return 1
  root="$(cd "$root" && pwd)" || { echo "error: not a directory: ${1:-.}" >&2; return 1; }
  dir="$(cd "$root" && "$fd_bin" --type d --hidden --exclude .git \
    --max-depth "${FCD_MAX_DEPTH:-20}" 2>/dev/null | "$fzf_bin" --prompt='fcd> ')" || return 1
  [[ -n "$dir" ]] || return 1
  abs="$(cd "$root" && cd "$dir" && pwd)" || { echo "error: not a directory: $dir" >&2; return 1; }
  cd "$abs" || return 1
}

# Find a file under the current folder (or PATH) and open it in nvim.
fnvim() {
  local root="${1:-.}" fzf_bin fd_bin nvim_bin file target
  fzf_bin="$(_cw_shell_bin fzf)" || return 1
  fd_bin="$(_cw_shell_bin fd)" || return 1
  nvim_bin="$(_cw_shell_bin nvim)" || return 1
  root="$(cd "$root" && pwd)" || { echo "error: not a directory: ${1:-.}" >&2; return 1; }
  file="$(cd "$root" && "$fd_bin" --type f --hidden --exclude .git \
    --max-depth "${FNVIM_MAX_DEPTH:-20}" 2>/dev/null | "$fzf_bin" --prompt='fnvim> ')" || return 1
  [[ -n "$file" ]] || return 1
  if [[ "$file" == /* ]]; then
    target="$file"
  else
    target="${root}/${file#./}"
  fi
  [[ -f "$target" ]] || { echo "error: not a file: $target" >&2; return 1; }
  "$nvim_bin" "$target"
}

# Find a file under the current folder (or PATH), preview with bat in fzf, then view.
fbat() {
  local root="${1:-.}" fzf_bin fd_bin bat_bin file target preview_lines
  preview_lines="${FBAT_PREVIEW_LINES:-120}"
  fzf_bin="$(_cw_shell_bin fzf)" || return 1
  fd_bin="$(_cw_shell_bin fd)" || return 1
  bat_bin="$(_cw_shell_bin bat)" || return 1
  root="$(cd "$root" && pwd)" || { echo "error: not a directory: ${1:-.}" >&2; return 1; }
  file="$(cd "$root" && "$fd_bin" --type f --hidden \
    --exclude .git --exclude node_modules --exclude vendor \
    --max-depth "${FBAT_MAX_DEPTH:-20}" 2>/dev/null | \
    "$fzf_bin" --prompt='fbat> ' \
      --bind 'ctrl-/:toggle-preview' \
      --preview "${bat_bin} --color=always --style=numbers --line-range :${preview_lines} -- {}" \
      --preview-window 'right:55%:wrap:border')" || return 1
  [[ -n "$file" ]] || return 1
  if [[ "$file" == /* ]]; then
    target="$file"
  else
    target="${root}/${file#./}"
  fi
  [[ -f "$target" ]] || { echo "error: not a file: $target" >&2; return 1; }
  if [[ -x "${_CW_SHELL_ROOT}/bin/cw-view" ]]; then
    "${_CW_SHELL_ROOT}/bin/cw-view" "$target"
  elif [[ -f "${_CW_SHELL_ROOT}/lib/common.sh" ]]; then
    CW_ROOT="${_CW_SHELL_ROOT}"
    CW_BIN_DIR="${_CW_SHELL_ROOT}/bin"
    # shellcheck source=/dev/null
    source "${_CW_SHELL_ROOT}/lib/common.sh"
    _cw_view_file "$target"
  else
    LESS=FRX BAT_PAGER=cat PAGER=cat "$bat_bin" \
      --no-config --color=always --style=numbers --paging=never --pager=cat "$target" | cat
  fi
}
