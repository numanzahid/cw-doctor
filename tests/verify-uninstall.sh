#!/usr/bin/env bash
# Verify uninstall left a clean state
set -uo pipefail

pass=0
fail=0
ok()  { echo "PASS: $*"; pass=$((pass+1)); }
bad() { echo "FAIL: $*"; fail=$((fail+1)); }

echo "=== UNINSTALL VERIFY ==="

if grep -q 'cw-doctor' "${HOME}/.bash_aliases" 2>/dev/null; then
  bad "bash_aliases still has cw-doctor block"
else
  ok "bash_aliases clean"
fi

if [[ -L "${HOME}/.local/bin/cw" ]]; then
  bad "~/.local/bin/cw symlink still exists"
else
  ok "~/.local/bin/cw removed"
fi

for f in .tmux.conf .inputrc; do
  if [[ -L "${HOME}/${f}" ]] && readlink "${HOME}/${f}" | grep -q cw-doctor; then
    bad "${f} still points to cw-doctor"
  else
    ok "${f} not cw-doctor symlink"
  fi
done

if [[ -d "${HOME}/.local/opt/cw-doctor" ]]; then
  bad "install dir still exists"
else
  ok "install dir removed"
fi

if command -v cw >/dev/null 2>&1; then
  bad "cw still on PATH"
else
  ok "cw not on default PATH"
fi

echo "PASS=$pass FAIL=$fail"
exit "$fail"
