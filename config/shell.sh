# Shell integration for cw diagnostics
_CW_SHELL_ROOT="${HOME}/.local/opt/cw-doctor"
export PATH="${_CW_SHELL_ROOT}/bin:${_CW_SHELL_ROOT}/shims:${PATH}"

if [[ -x "${_CW_SHELL_ROOT}/shims/fzf" ]]; then
  # shellcheck disable=SC2016
  eval "$("${_CW_SHELL_ROOT}/shims/fzf" --bash)"
elif command -v fzf >/dev/null 2>&1; then
  # shellcheck disable=SC2016
  eval "$(fzf --bash)"
fi

if [[ -f "${_CW_SHELL_ROOT}/config/aliases.sh" ]]; then
  # shellcheck source=/dev/null
  source "${_CW_SHELL_ROOT}/config/aliases.sh"
fi

if [[ -f "${_CW_SHELL_ROOT}/config/functions.sh" ]]; then
  # shellcheck source=/dev/null
  source "${_CW_SHELL_ROOT}/config/functions.sh"
fi

if [[ -f "${_CW_SHELL_ROOT}/completions/cw.bash" ]]; then
  # shellcheck source=/dev/null
  source "${_CW_SHELL_ROOT}/completions/cw.bash"
fi
