# cw-doctor

Read-only SSH diagnostic toolkit for Cloudways WordPress servers.

## Quick start

```bash
git clone <repo-url> cw-doctor
cd cw-doctor
./install.sh          # moves repo to ~/.local/opt/cw-doctor (includes .git)
source ~/.bash_aliases   # loads cw, cda, tab completion
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

## Interactive menu (fzf)

Type `cw` with no arguments to open the command launcher:

```bash
cw          # pick command -> pick app/options -> run
cw menu     # same
cw traffic  # pick app if omitted, then run
cw watch    # pick app, pick mode, then tail
cw logs     # pick app, pick log file, print with bat (no pager)
cw reports --open   # pick past report, view summary
```

Omit APP on most commands to get an fzf picker (domain-labeled). For `doctor`, `cpu`, `disk`, and `collect`, you can also choose **Server-wide**.

| Shell helper | Action |
|--------------|--------|
| `cda` | cd to public_html |
| `cdapp` | cd to app root |
| `cdlogs` | cd to logs |
| `cgo` | cd to path from `cw go` |
| `fcd [DIR]` | fzf pick a subfolder under DIR (default `.`) and cd |
| `fnvim [DIR]` | fzf pick a file under DIR (default `.`) and open in nvim |
| `fbat [DIR]` | fzf pick a file (bat preview in picker), then print with bat (no pager) |

**Ctrl+R** uses fzf fuzzy history search (via `fzf --bash` in shell integration).

## Commands

| Command | Description |
|---------|-------------|
| `cw` / `cw menu` | Interactive fzf command launcher |
| `cw apps [-i]` | List apps (`-i` pick one for detail) |
| `cw path [APP]` | Print app path (pick if omitted) |
| `cw doctor [APP]` | Server and app health snapshot |
| `cw cpu [APP]` | CPU, RAM, processes |
| `cw traffic [APP]` | Access log traffic analysis |
| `cw slow [APP]` | PHP slow log analysis |
| `cw watch [APP] [mode]` | Live log tail |
| `cw logs [APP]` | Browse/view log files (stdout, no pager) |
| `cw errors [APP]` | Error log summary |
| `cw cron [APP]` | WP cron and admin-ajax activity |
| `cw disk [APP]` | Disk and inode usage |
| `cw collect [APP]` | Write sanitized report bundle |
| `cw reports [--open]` | Browse past collect reports |
| `cw go [APP]` | Pick path within an app |
| `cw wp [APP]` | Pick plugin or theme directory |
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
