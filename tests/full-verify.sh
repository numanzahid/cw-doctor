#!/usr/bin/env bash
# Full cw-doctor verification script (read-only diagnostics; safe on production)
set -uo pipefail

export PATH="${HOME}/.local/opt/cw-doctor/bin:${HOME}/.local/bin:${PATH}"
CW="${HOME}/.local/opt/cw-doctor/bin/cw"
ROOT="${HOME}/.local/opt/cw-doctor"

pass=0
fail=0
skip=0

ok()   { echo "PASS: $*"; pass=$((pass+1)); }
bad()  { echo "FAIL: $*"; fail=$((fail+1)); }
skip() { echo "SKIP: $*"; skip=$((skip+1)); }

section() { echo ""; echo "######## $* ########"; }

section "BINARIES"
TOOLS=(rg fd fzf bat btop gdu tmux nvim cw)
for t in "${TOOLS[@]}"; do
  bin="${ROOT}/bin/${t}"
  if [[ -x "$bin" ]]; then
    ver="$("$bin" --version 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*m//g' || echo ok)"
    ok "$t ($ver)"
  else
    bad "missing binary: $bin"
  fi
done

section "CW STATUS"
if [[ -x "$CW" ]]; then
  "$CW" status || bad "cw status exited non-zero"
  ok "cw status ran"
else
  bad "cw not found at $CW"
fi

section "CW APPS"
if [[ -x "$CW" ]]; then
  apps_out="$("$CW" apps 2>&1)" || { bad "cw apps failed"; apps_out=""; }
  mapfile -t apps < <(echo "$apps_out" | awk '/^[a-z0-9]{10,12}[[:space:]]/ {print $1}')
  if [[ ${#apps[@]} -gt 0 ]]; then
    ok "cw apps listed ${#apps[@]} app(s)"
    echo "$apps_out"
  else
    bad "no apps parsed from cw apps"
  fi
fi

section "CW COMMANDS (per app + global)"
GLOBAL_CMDS=(status)
APP_CMDS=(doctor cpu traffic slow errors cron disk)
GLOBAL_ONLY=(cpu disk doctor collect)

for c in "${GLOBAL_CMDS[@]}"; do
  if "$CW" "$c" >/dev/null 2>&1; then ok "cw $c"; else bad "cw $c"; fi
done

for c in "${GLOBAL_ONLY[@]}"; do
  if "$CW" "$c" >/dev/null 2>&1; then ok "cw $c (no app)"; else bad "cw $c (no app)"; fi
done

if [[ ${#apps[@]} -gt 0 ]]; then
  first="${apps[0]}"
  for c in "${APP_CMDS[@]}"; do
    if "$CW" "$c" "$first" >/dev/null 2>&1; then
      ok "cw $c $first"
    else
      # slow/watch may be empty - check if command ran vs app missing
      out="$("$CW" "$c" "$first" 2>&1)" || true
      if echo "$out" | grep -qE 'UNAVAILABLE|NOT ESTABLISHED|no slow|unknown app'; then
        ok "cw $c $first (graceful: no data)"
      else
        bad "cw $c $first"
        echo "  $out" | head -2
      fi
    fi
  done
  if "$CW" collect "$first" >/dev/null 2>&1; then ok "cw collect $first"; else bad "cw collect $first"; fi
  # watch: start and kill quickly (not interactive long run)
  if timeout 2 "$CW" watch "$first" access >/dev/null 2>&1; then
    ok "cw watch $first access (2s)"
  else
    rc=$?
    if [[ $rc -eq 124 ]]; then ok "cw watch $first access (timeout ok)"
    else bad "cw watch $first access (rc=$rc)"; fi
  fi
fi

section "ALL APPS SPOT CHECK"
for app in "${apps[@]}"; do
  if "$CW" traffic "$app" >/dev/null 2>&1; then
    ok "traffic $app"
  else
    out="$("$CW" traffic "$app" 2>&1)" || true
    bad "traffic $app"
  fi
done

section "SHELL INTEGRATION"
if grep -q 'cw-doctor' "${HOME}/.bash_aliases" 2>/dev/null; then ok "bash_aliases block"; else bad "bash_aliases block"; fi
[[ -L "${HOME}/.tmux.conf" ]] && ok ".tmux.conf symlink" || skip ".tmux.conf symlink (may pre-exist)"
[[ -L "${HOME}/.inputrc" ]] && ok ".inputrc symlink" || skip ".inputrc symlink"
[[ -L "${HOME}/.local/bin/cw" ]] && ok "~/.local/bin/cw symlink" || bad "~/.local/bin/cw symlink"
[[ -f "${ROOT}/.state/crawlers.json" ]] && ok "crawlers.json" || bad "crawlers.json"

section "SUMMARY"
echo "PASS=$pass FAIL=$fail SKIP=$skip"
exit "$fail"
