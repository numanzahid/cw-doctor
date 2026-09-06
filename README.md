# cw-doctor

Read-only SSH diagnostic toolkit for Cloudways WordPress servers.

## Quick start

```bash
git clone <repo-url> cw-doctor
cd cw-doctor
./install.sh          # moves repo to ~/.local/opt/cw-doctor (includes .git)
source ~/.bash_aliases
cw apps
cw cpu
cw traffic <APP>
```

Install location: `~/.local/opt/cw-doctor` (clone directory is removed; no leftover in `$HOME`).

Reinstall or repair: `~/.local/opt/cw-doctor/install.sh`

Updates: `cw update` (`git pull --ff-only` + refresh bundled tools).

## App navigation

Cloudways app folders use opaque ids (`~/applications/kuwzfqjbxq`). Jump by **domain** instead:

| Command | Goes to |
|---------|---------|
| `cda` | `public_html` (fzf picker if no APP) |
| `cda example.com` | `public_html` for that app |
| `cdapp example.com` | app root (`~/applications/<id>`) |
| `cdlogs example.com` | `logs/` |

APP can be primary domain, any alias (`www.example.com`), or the folder id. No `https://` prefix.

With multiple apps and no APP argument, **fzf** opens a searchable list labeled by domain.

```bash
cda                      # fzf: pick by domain
cda staging.client.com   # jump directly
cw path example.com      # print path (for scripts)
cd "$(cw path example.com --logs)"
```

Bundled tools (`rg`, `fd`, `fzf`, `bat`, `btop`, `gdu`, `tmux`, `nvim`, `lazygit`) are on PATH after shell integration. Diagnostics use the `cw` command only.

## Commands

| Command | Description |
|---------|-------------|
| `cw apps` | List applications on this server |
| `cw path APP` | Print app path (`--pick` for fzf chooser) |
| `cw doctor [APP]` | Server and app health snapshot |
| `cw cpu [APP]` | CPU, RAM, processes |
| `cw traffic APP` | Access log traffic analysis |
| `cw slow APP` | PHP slow log analysis |
| `cw watch APP [mode]` | Live log tail (access, php, errors, slow) |
| `cw errors APP` | Error log summary |
| `cw cron APP` | WP cron and admin-ajax activity |
| `cw disk [APP]` | Disk and inode usage |
| `cw collect [APP]` | Write sanitized report bundle |
| `cw status` | Install health check |
| `cw update` | Manual update (git pull + refresh tools) |
| `cw uninstall` | Reverse install changes |

## Safety

- Read-only by default. No root, no service restarts, no auto-fixes.
- Does not modify application files or enable `WP_DEBUG`.
- Reports redact secrets; `wp-config.php` and `.env` are never collected.

## Uninstall

```bash
~/.local/opt/cw-doctor/uninstall.sh
```

Reports in `.state/reports/` are preserved unless you use `--purge`.
