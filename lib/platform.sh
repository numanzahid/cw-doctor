#!/usr/bin/env bash
# Platform detection and server facts

cw_platform_home() {
  printf '%s' "${HOME}"
}

cw_platform_applications_dir() {
  local apps="${HOME}/applications"
  if [[ -d "$apps" ]]; then
    printf '%s' "$apps"
    return 0
  fi
  return 1
}

cw_platform_arch() {
  uname -m
}

cw_platform_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    printf '%s %s' "${NAME:-Linux}" "${VERSION_ID:-unknown}"
  else
    uname -s
  fi
}

cw_platform_hostname() {
  hostname -f 2>/dev/null || hostname
}

cw_platform_uptime() {
  uptime -p 2>/dev/null || uptime
}

cw_platform_load() {
  awk '{print $1" "$2" "$3}' /proc/loadavg
}

cw_platform_mem() {
  free -h 2>/dev/null || free
}

cw_platform_disk_root() {
  df -h / 2>/dev/null | tail -1
}

cw_platform_inode_root() {
  df -hi / 2>/dev/null | tail -1
}

cw_platform_listeners() {
  ss -tln 2>/dev/null | head -30 || netstat -tln 2>/dev/null | head -30 || _cw_unavailable "cannot list listeners"
}

cw_platform_top_cpu() {
  ps aux --sort=-%cpu 2>/dev/null | head -12
}

cw_platform_top_mem() {
  ps aux --sort=-%mem 2>/dev/null | head -12
}

cw_platform_php_mysql_procs() {
  ps aux 2>/dev/null | awk '/php-fpm|mysqld|mysql|maria/ && !/awk/ {print}' | head -20
}

cw_platform_scanner_note() {
  local hits
  hits="$(ps aux 2>/dev/null | awk '/imunify|malware|scanner|lfd/ && !/awk/ {print}' | head -5)"
  if [[ -n "$hits" ]]; then
    _cw_section "Security scanner processes (OBSERVED)"
    echo "$hits"
  fi
}

cw_platform_preflight() {
  local arch
  arch="$(cw_platform_arch)"
  [[ "$arch" == "x86_64" || "$arch" == "amd64" ]] || _cw_toolkit_die "unsupported architecture: $arch (x86_64 only)"
  [[ -w "$HOME" && -x "$HOME" ]] || _cw_toolkit_die "home directory must be writable and executable: $HOME"
  command -v bash >/dev/null || _cw_toolkit_die "bash required"
  command -v tar >/dev/null || _cw_toolkit_die "tar required"
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || _cw_toolkit_die "curl or wget required"
  mkdir -p "${HOME}/.local" || _cw_toolkit_die "cannot create ~/.local"
}

# Cloudways app roots live under ~/applications/<id>. Refuse install elsewhere unless overridden.
cw_platform_require_cloudways() {
  if cw_platform_applications_dir >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${CW_DOCTOR_ALLOW_INSTALL:-}" == 1 ]]; then
    _cw_toolkit_warn "non-Cloudways host (dev/test install only)"
    return 0
  fi
  _cw_toolkit_die "Cloudways applications directory not found (~/applications). cw-doctor is for Cloudways SSH only. To install on another host for development, set CW_DOCTOR_ALLOW_INSTALL=1"
}
