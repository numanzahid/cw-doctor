# Shell integration for cw diagnostics
export PATH="${HOME}/.local/opt/cw-doctor/bin:${PATH}"

if [[ -f "${HOME}/.local/opt/cw-doctor/config/aliases.sh" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.local/opt/cw-doctor/config/aliases.sh"
fi

if [[ -f "${HOME}/.local/opt/cw-doctor/config/functions.sh" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.local/opt/cw-doctor/config/functions.sh"
fi

if [[ -f "${HOME}/.local/opt/cw-doctor/completions/cw.bash" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.local/opt/cw-doctor/completions/cw.bash"
fi
