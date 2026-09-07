#!/usr/bin/env bash
# Download and install bundled tools (latest releases)

_cw_download() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$dest" "$url"
  else
    wget -q -O "$dest" "$url"
  fi
}

_cw_github_latest_asset() {
  local repo="$1" pattern="$2"
  local api="https://api.github.com/repos/${repo}/releases/latest"
  local json
  json="$(_cw_download "$api" /dev/stdout 2>/dev/null)" || return 1
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r --arg pat "$pattern" '.assets[] | select(.browser_download_url | test($pat)) | .browser_download_url' | grep -E '\.(tar\.gz|tgz|zip)$' | head -1
    return 0
  fi
  echo "$json" | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"/\1/' | grep -E "$pattern" | head -1
}

_cw_extract_archive() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  if tar -xzf "$archive" -C "$dest" 2>/dev/null; then
    return 0
  fi
  if tar -xJf "$archive" -C "$dest" 2>/dev/null; then
    return 0
  fi
  if unzip -qo "$archive" -d "$dest" 2>/dev/null; then
    return 0
  fi
  _cw_toolkit_die "unsupported archive: $archive"
}

_cw_find_binary() {
  local dir="$1" name="$2"
  local found
  found="$(find "$dir" -type f -name "$name" -perm -111 2>/dev/null | head -1)"
  [[ -n "$found" ]] && { printf '%s' "$found"; return 0; }
  found="$(find "$dir" -type f -name "${name}_*" -perm -111 2>/dev/null | head -1)"
  [[ -n "$found" ]] && { printf '%s' "$found"; return 0; }
  found="$(find "$dir" -type f -perm -111 2>/dev/null | head -1)"
  [[ -n "$found" ]] && printf '%s' "$found"
}

cw_tools_install_github() {
  local name="$1" repo="$2" pattern="$3" bin_name="${4:-$1}"
  local tmp="${CW_TOOLS_DIR}/${name}/.installing-$$"
  local ver_dir version url archive binary

  rm -rf "$tmp"
  mkdir -p "$tmp"

  url="$(_cw_github_latest_asset "$repo" "$pattern")"
  [[ -n "$url" ]] || _cw_toolkit_die "no release asset for $name ($repo)"

  version="$(basename "$url" | sed -E 's/[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
  [[ -z "$version" ]] && version="latest"

  archive="${tmp}/download"
  _cw_toolkit_info "Installing $name ($version)..."
  _cw_download "$url" "$archive"
  _cw_extract_archive "$archive" "${tmp}/extract"

  binary="$(_cw_find_binary "${tmp}/extract" "$bin_name")"
  [[ -n "$binary" ]] || binary="$(_cw_find_binary "${tmp}/extract" "${name}")"
  [[ -n "$binary" ]] || _cw_toolkit_die "binary not found for $name"

  ver_dir="${CW_TOOLS_DIR}/${name}/${version}"
  rm -rf "$ver_dir"
  mkdir -p "$ver_dir"
  cp -a "$(dirname "$binary")"/. "$ver_dir/"
  rm -rf "$tmp"

  cw_tools_write_wrapper "$name" "$ver_dir" "$bin_name"
  cw_state_record tool "$name" "$version"
}

cw_tools_install_tmux() {
  local name="tmux"
  local tmp="${CW_TOOLS_DIR}/${name}/.installing-$$"
  local ver_dir deb

  rm -rf "$tmp"
  mkdir -p "$tmp"

  (cd "$tmp" && apt download tmux libevent-core-2.1-7 2>/dev/null) || _cw_toolkit_die "apt download tmux/libevent failed"

  ver_dir="${CW_TOOLS_DIR}/${name}/system"
  rm -rf "$ver_dir"
  mkdir -p "$ver_dir"
  while IFS= read -r deb; do
    dpkg-deb -x "$deb" "$ver_dir"
  done < <(find "$tmp" -maxdepth 1 -name '*.deb' -type f)
  rm -rf "$tmp"

  cw_tools_write_tmux_wrapper "$ver_dir"
  cw_state_record tool "$name" "system-deb"
}

cw_tools_shim_path() {
  printf '%s/%s' "$CW_SHIMS_DIR" "$1"
}

cw_tools_resolve_shim() {
  local name="$1" shim
  shim="$(cw_tools_shim_path "$name")"
  [[ -x "$shim" ]] && printf '%s' "$shim"
}

# Remove legacy generated wrappers from bin/ (pre-shims layout).
cw_tools_migrate_legacy_layout() {
  local name list="${CW_ROOT}/manifest/tools.list"
  local legacy_crawlers="${CW_ROOT}/config/crawlers.json"
  mkdir -p "$CW_SHIMS_DIR" "$CW_STATE_DIR"
  [[ -f "$list" ]] || return 0
  while IFS= read -r name; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    if [[ -f "${CW_BIN_DIR}/${name}" ]]; then
      rm -f "${CW_BIN_DIR}/${name}"
    fi
  done < "$list"
  if [[ -f "$legacy_crawlers" && ! -f "$CW_CRAWLERS_FILE" ]]; then
    mv "$legacy_crawlers" "$CW_CRAWLERS_FILE"
  elif [[ -f "$legacy_crawlers" ]]; then
    rm -f "$legacy_crawlers"
  fi
}

cw_tools_write_wrapper() {
  local name="$1" ver_dir="$2" bin_name="$3"
  local wrapper shim binary
  shim="$(cw_tools_shim_path "$name")"
  binary="$(_cw_find_binary "$ver_dir" "$bin_name")"
  [[ -n "$binary" ]] || _cw_toolkit_die "wrapper target missing: $name"

  mkdir -p "$CW_SHIMS_DIR"
  cat > "$shim" <<EOF
#!/usr/bin/env bash
exec "${binary}" "\$@"
EOF
  chmod +x "$shim"
}

cw_tools_write_tmux_wrapper() {
  local ver_dir="$1"
  local tmux_bin shim lib_paths
  tmux_bin="$(find "$ver_dir" -type f -path '*/bin/tmux' 2>/dev/null | head -1)"
  lib_paths="$(find "$ver_dir" -type d -path '*/lib/x86_64-linux-gnu' 2>/dev/null | tr '\n' ':')"
  lib_paths="${lib_paths}$(find "$ver_dir" -type d -name lib 2>/dev/null | tr '\n' ':')"
  shim="$(cw_tools_shim_path tmux)"
  mkdir -p "$CW_SHIMS_DIR"
  cat > "$shim" <<EOF
#!/usr/bin/env bash
export LD_LIBRARY_PATH="${lib_paths}\${LD_LIBRARY_PATH:-}"
exec "${tmux_bin}" "\$@"
EOF
  chmod +x "$shim"
}

cw_tools_write_nvim_wrapper() {
  local ver_dir="$1"
  local nvim_bin shim runtime
  nvim_bin="$(_cw_find_binary "$ver_dir" nvim)"
  runtime="${CW_ROOT}/runtime/nvim"
  shim="$(cw_tools_shim_path nvim)"
  mkdir -p "${runtime}/data" "${runtime}/state" "${runtime}/cache" "$CW_SHIMS_DIR"
  cat > "$shim" <<EOF
#!/usr/bin/env bash
export XDG_DATA_HOME="${runtime}/data"
export XDG_STATE_HOME="${runtime}/state"
export XDG_CACHE_HOME="${runtime}/cache"
exec "${nvim_bin}" "\$@"
EOF
  chmod +x "$shim"
}

cw_tools_install_nvim() {
  local tmp="${CW_TOOLS_DIR}/nvim/.installing-$$"
  local url ver_dir version archive binary

  rm -rf "$tmp"
  mkdir -p "$tmp"

  url="$(_cw_github_latest_asset neovim/neovim 'nvim-linux-x86_64\.tar\.gz$')"
  [[ -n "$url" ]] || _cw_toolkit_die "no neovim release asset"

  archive="${tmp}/download"
  _cw_download "$url" "$archive"
  _cw_extract_archive "$archive" "${tmp}/extract"
  binary="$(_cw_find_binary "${tmp}/extract" nvim)"
  [[ -n "$binary" ]] || _cw_toolkit_die "nvim binary not found"

  version="$(basename "$url" | sed -E 's/[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
  ver_dir="${CW_TOOLS_DIR}/nvim/${version:-latest}"
  rm -rf "$ver_dir"
  mkdir -p "$ver_dir"
  cp -a "$(dirname "$binary")"/. "$ver_dir/"
  rm -rf "$tmp"
  cw_tools_write_nvim_wrapper "$ver_dir"
  cw_state_record tool nvim "${version:-latest}"
}

cw_tools_all_present() {
  local name list="${CW_ROOT}/manifest/tools.list"
  [[ -f "$list" ]] || return 1
  while IFS= read -r name; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    [[ -x "$(cw_tools_shim_path "$name")" ]] || return 1
  done < "$list"
  return 0
}

# Return 0 when bundled binaries should be downloaded (missing, stale, or --force).
cw_tools_refresh_needed() {
  local force="${1:-0}"
  [[ "$force" == 1 ]] && return 0
  cw_tools_all_present || return 0
  cw_state_tools_last_install_read >/dev/null || return 0
  local age
  age="$(cw_state_tools_age_days)" || return 0
  [[ "$age" -ge "${CW_TOOLS_REFRESH_DAYS}" ]]
}

cw_tools_install_all() {
  local force="${1:-0}"
  cw_tools_migrate_legacy_layout
  mkdir -p "$CW_TOOLS_DIR" "$CW_SHIMS_DIR" "$CW_BIN_DIR"
  if ! cw_tools_refresh_needed "$force"; then
    local last
    last="$(cw_state_tools_last_install_read)"
    _cw_toolkit_info "bundled tools fresh (last install ${last}); skipping download (use --force to refresh)"
    return 0
  fi
  cw_tools_install_github rg BurntSushi/ripgrep 'x86_64.*linux.*tar\.gz' rg
  cw_tools_install_github fd sharkdp/fd 'x86_64.*linux.*tar\.gz' fd
  cw_tools_install_github fzf junegunn/fzf 'linux_amd64\.tar\.gz' fzf
  cw_tools_install_github bat sharkdp/bat 'x86_64.*linux.*tar\.gz' bat
  cw_tools_install_github btop aristocratos/btop 'x86_64.*linux.*\.tar\.gz' btop
  cw_tools_install_github gdu dundee/gdu 'gdu_linux_amd64.*\.tgz' gdu
  cw_tools_install_github lazygit jesseduffield/lazygit 'linux_x86_64\.tar\.gz' lazygit
  cw_tools_install_tmux
  cw_tools_install_nvim
  cw_state_tools_mark_installed
}

cw_tools_check_one() {
  local name="$1"
  local wrapper
  wrapper="$(cw_tools_resolve_shim "$name")"
  if [[ -z "$wrapper" ]]; then
    echo "$name: MISSING"
    return 1
  fi
  local ver
  ver="$("$wrapper" --version 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
  if [[ -z "$ver" && "$name" == tmux ]]; then
    ver="$("$wrapper" -V 2>/dev/null || echo unknown)"
  fi
  [[ -z "$ver" ]] && ver=unknown
  echo "$name: OK ($ver)"
}

cw_tools_status() {
  local name
  while IFS= read -r name; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    cw_tools_check_one "$name" || true
  done < "${CW_ROOT}/manifest/tools.list"
}

cw_tools_fetch_crawlers() {
  local dest="$CW_CRAWLERS_FILE"
  local url="https://raw.githubusercontent.com/monperrus/crawler-user-agents/master/crawler-user-agents.json"
  cw_state_init
  if _cw_download "$url" "${dest}.tmp" 2>/dev/null; then
    mv "${dest}.tmp" "$dest"
    cw_state_log "crawler list refreshed"
  else
    _cw_toolkit_warn "could not refresh crawler list; using existing copy if present"
  fi
}
