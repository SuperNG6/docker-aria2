# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

docker-aria2 is an Alpine Linux Docker image running aria2 + AriaNg WebUI. It ships in two variants:
- **standard** — aria2c only
- **a2b** — aria2c + aria2b (BT traffic optimization proxy)

The variant is selected at build time via `ARG VARIANT=standard` in the Dockerfile. The GitHub Actions workflow builds both variants in a single `variant × platform` matrix.

## Runtime Stack

- Base image: `superng6/alpine:3.22` — Alpine + **s6-overlay v2.2.0.3** (last v2 release, not v3)
- Init system entrypoint: `/init` → runs `cont-init.d/` scripts then supervises `services.d/` services
- WebUI: `darkhttpd` serving AriaNg static files from `/www`
- Download user: `abc` (UID 911, GID 1000 / group `users`); all aria2c processes run via `s6-setuidgid abc`

### What the base image provides

The base image (`superng6/alpine`) is a fork of linuxserver's alpine base, rebuilt with the latest Alpine and s6-overlay v2.2.0.3. It already includes:

- **Pre-installed packages**: `bash`, `curl`, `wget`, `ca-certificates`, `coreutils`, `procps`, `shadow`, `tzdata` — no need to install these in the Dockerfile
- **Pre-created directories**: `/app`, `/config`, `/defaults`
- **`abc` user**: UID 911, home `/config`, shell `/bin/false`, member of group `users` (GID 1000)
- **`with-contenv`**: wrapper script that reads env vars from `/var/run/s6/container_environment/` and applies UMASK before exec; all `cont-init.d` and `services.d` scripts use `#!/usr/bin/with-contenv bash` as shebang to inherit container environment variables
- **Patched `init-stage2`**: custom patch applied to `/etc/s6/init/init-stage2` for linuxserver compatibility

### s6-overlay v2 vs v3

This project uses **v2** (not v3). Key differences to remember:
- Service scripts live in `/etc/services.d/<name>/run` (v3 uses `/etc/s6-overlay/s6-rc.d/`)
- Init scripts live in `/etc/cont-init.d/` (v3 uses `/etc/s6-overlay/init.d/`)
- To disable a service from restarting: `exec s6-svc -d .` (v3 uses `s6-rc` and type `oneshot`)

## Directory Structure

```
root/
├── aria2/
│   ├── conf/                   # Default config templates (copied to /config on first start)
│   │   ├── aria2.conf.default
│   │   ├── setting.conf        # Script behavior config (move/delete/filter/torrent)
│   │   ├── 文件过滤.conf        # File content filter rules
│   │   ├── rpc-tracker0        # Crontab for RUT=false (system maintenance only)
│   │   └── rpc-tracker1        # Crontab for RUT=true (+ daily tracker update via RPC)
│   └── script/
│       ├── lib/                # Shared function libraries
│       │   ├── event.sh        # Event hook entry: sources event libs; path calculation; INIT_EVENT/GUARD_EVENT
│       │   ├── log.sh          # Color constants, DATE_TIME(), TASK_INFO() (pass `no-target` to omit move-target line)
│       │   ├── config.sh       # Reads/writes setting.conf; auto-runs LOAD_CONF on source
│       │   ├── files.sh        # MOVE_FILE, DELETE_FILE, MOVE_RECYCLE, RM_ARIA2
│       │   ├── filter.sh       # Content filter (delete by extension/keyword/regex)
│       │   ├── torrent.sh      # .torrent file handling (backup/rename/delete)
│       │   ├── rpc.sh          # Aria2 JSON-RPC query functions
│       │   └── tracker.sh      # Dual-mode tracker update: `file` writes config, `rpc` pushes via JSON-RPC
│       ├── completed.sh        # aria2 on-download-complete hook
│       ├── start.sh            # aria2 on-download-start hook (duplicate task detection)
│       ├── stop.sh             # aria2 on-download-stop hook
│       └── pause.sh            # aria2 on-download-pause hook
└── etc/
    ├── cont-init.d/            # s6 init scripts, run in numeric order at container start
    │   ├── 11-version          # Print version banner
    │   ├── 20-config           # Init config files and directories
    │   ├── 30-config           # Apply env vars to aria2.conf, start crond
    │   ├── 40-config           # Set permissions, chmod scripts, register aria2b restart cron (a2b only, inlined)
    │   ├── 50-config           # Start darkhttpd WebUI
    │   ├── 90-custom-folders   # User customization hook (intentionally empty)
    │   └── 99-custom-scripts   # User customization hook (intentionally empty)
    └── services.d/
        ├── aria2/run           # aria2c service (s6-supervised)
        └── aria2b/run          # aria2b service (s6-supervised, a2b variant only)
```

## Critical Patterns

### Event script call order (must not be changed)
All event scripts source `lib/event.sh` and call `INIT_EVENT <type> "$@"`. The `type` argument (`completed` or `recycle`) determines `TARGET_DIR` before `GET_FINAL_PATH` runs. Breaking this order causes incorrect path calculation.

```bash
# Correct order inside INIT_EVENT:
GET_BASE_PATH → COMPLETED_PATH or RECYCLE_PATH → GET_RPC_INFO → GET_FINAL_PATH
```

### Disabling a s6-overlay v2 service
To prevent s6 from infinitely restarting a service when it should not run, use:
```bash
exec s6-svc -d .
```
This is used in `services.d/aria2b/run` when `A2B != true`.

### lib/event.sh uses BASH_SOURCE[0]
The lib directory is resolved with `dirname "${BASH_SOURCE[0]}"`, not `$0`. This ensures the correct path when the file is sourced (not executed directly).

### Library global variable naming convention
Globals shared across libs should be named after their purpose, not their owning script. Two pre-existing conf paths follow this rule (renamed in the refactor — the older `SCRIPT_CONF` name is intentionally retired to avoid namespace collision between libs):
- `SETTING_CONF` — `/config/setting.conf`, defined in `lib/config.sh`, consumed by `LOAD_CONF` / `SED_CONF`
- `FILTER_CONF` — `/config/文件过滤.conf`, defined in `lib/event.sh#GET_BASE_PATH`, consumed by `lib/filter.sh#LOAD_FILTER_CONF`

When adding a new shared global, give it a name that is unique across all of `lib/` — `grep -r <NAME> root/aria2/script/lib/` before introducing it.

### Event helper libs don't `exit`
Event helper libs (`lib/rpc.sh`, `lib/config.sh`, ...) return non-zero and write errors to `stderr` instead of calling `exit`. Decisions to abort belong in the caller (`INIT_EVENT` does `GET_RPC_INFO || exit 1`). Standalone operational scripts such as `lib/tracker.sh` may exit directly for CLI-style failures.

### Event scripts inherit env from aria2c, not via with-contenv
Hooks (`completed.sh` / `start.sh` / `stop.sh` / `pause.sh`) use `#!/usr/bin/env bash`, not `with-contenv`. They are fork-execed by aria2c, so they inherit aria2c's environment — which was set up by `services.d/aria2/run` (which DOES use `with-contenv`). This means container env vars (PORT/SECRET/CTU/etc) are visible to hooks transitively.

`lib/config.sh#LOAD_CONF` is called every time `lib/event.sh` is sourced, so setting.conf edits are picked up immediately by the next hook invocation — no aria2c restart needed.

### cron path
`cont-init.d/30-config` writes `rpc-tracker0`/`rpc-tracker1` to `/etc/crontabs/root`. This works on this Alpine base image (whether by alpine-baselayout symlink or busybox crond `-c` override is configured in the base image). Do not "fix" this to `/var/spool/cron/crontabs/` — the existing path is intentional. `40-config` uses `crontab -l` / `crontab -` for aria2b restart cron, which writes to `/var/spool/cron/crontabs/` — both paths coexist in this image without conflict.

### `services.d` runtime env
`services.d/aria2/run` and `services.d/aria2b/run` both use `#!/usr/bin/with-contenv bash`, so they see the full container env. `aria2c` is launched with `s6-setuidgid abc` (UID 911 / group users). `aria2b` (a2b variant only) polls aria2c's RPC up to 30s before launching itself.

### `QUIET=true` silences stderr too
The default `QUIET=true` passes `--quiet=true` to aria2c, which silences both stdout and stderr. If aria2c fails to start (port conflict, bad config), the failure is invisible in `docker logs`. Set `-e QUIET=false` to debug startup problems.

## Key Environment Variables

Three categories by how they reach the runtime:

### 1. Directly read by `services.d` / `cont-init.d` (active env vars)

| Variable | Default | Where consumed | Description |
|----------|---------|----------------|-------------|
| `VARIANT` | `standard` | Dockerfile ARG | Build-time: `standard` or `a2b` |
| `A2B` | `false` (a2b: `true` via `A2B_DEFAULT`) | `services.d/aria2b/run`, `cont-init.d/40-config` | Enable aria2b service + cron restart |
| `A2B_DISABLE_LOG` | `false` | `services.d/aria2b/run` | Pipe aria2b output to /dev/null |
| `SECRET` | `yourtoken` | `services.d/aria2/run`, `lib/rpc.sh`, tracker cron | RPC token (⚠ default is public — banner warns on `yourtoken`) |
| `PORT` | `6800` | `30-config` → aria2.conf, `lib/rpc.sh` | RPC listen port |
| `BTPORT` | `32516` | `30-config` → aria2.conf (listen-port + dht-listen-port) | BT/DHT port |
| `WEBUI` | `true` | `50-config` | Enable darkhttpd serving /www |
| `WEBUI_PORT` | `8080` | `50-config` | WebUI listen port |
| `UT` | `true` | `30-config` | Update trackers on startup (writes aria2.conf) |
| `RUT` | `true` | `30-config` | Daily cron tracker update via RPC (5am) |
| `SMD` | `true` | `30-config` → aria2.conf `bt-save-metadata` | Save magnet metadata to .torrent |
| `FA` | `falloc` | `30-config` → aria2.conf `file-allocation` | Disk pre-alloc: `falloc`/`trunc`/`prealloc`/`none` (unset → `falloc`) |
| `CACHE` | `128M` | `services.d/aria2/run` | aria2c `--disk-cache` |
| `QUIET` | `true` | `services.d/aria2/run` | aria2c `--quiet` (true also silences stderr; set `false` to debug) |
| `CRA2B` | `2h` | `40-config` | aria2b restart cron interval hours (a2b variant) |
| `CTU` | _(empty)_ | `lib/tracker.sh#GET_TRACKERS` | Custom tracker URLs (comma-separated) |
| `TZ` | `Asia/Shanghai` | base image | Timezone (also affects `date` in scripts) |
| `PUID` / `PGID` | `1026` / `100` | base image (10-adduser) | abc user id mapping for /downloads ownership |

### 2. setting.conf seed env vars (only effective on first run)

| Variable | Default | Maps to setting.conf key | Effective when |
|----------|---------|--------------------------|----------------|
| `MOVE` | `false` | `move-task` | `/config/setting.conf` does not yet exist |
| `RMTASK` | `rmaria` | `remove-task` | (same) |
| `CF` | `false` | `content-filter` | (same) |
| `DET` | `true` | `delete-empty-dir` | (same) |
| `TOR` | `backup-rename` | `handle-torrent` | (same) |
| `RRT` | `true` | `remove-repeat-task` | (same) |
| `MPT` | `false` | `move-paused-task` | (same) |

**Critical semantics**: these 7 env vars are absorbed by `cont-init.d/20-config` → `SEED_ENV_TO_SETTING_CONF` **only on the first container start** (when `/config/setting.conf` doesn't exist). On subsequent starts the persistent setting.conf wins — env var changes have no effect. To change at runtime, edit `/config/setting.conf` directly or via WebUI (changes take effect immediately, no restart).

This is intentional. Letting env vars override at every start would silently shadow user edits to setting.conf and break the "edit setting.conf, it takes effect now" contract that event hooks rely on (`lib/config.sh#LOAD_CONF` always reads from file).

## aria2.conf rewrite policy

`cont-init.d/30-config` rewrites these aria2.conf keys on **every** startup using env vars. **Do not hand-edit these lines** — they are overwritten:

| aria2.conf key | Source env var |
|----------------|----------------|
| `on-download-stop` | hardcoded path `/aria2/script/stop.sh` |
| `on-download-complete` | hardcoded path `/aria2/script/completed.sh` |
| `on-download-pause` | hardcoded path `/aria2/script/pause.sh` |
| `on-download-start` | hardcoded path `/aria2/script/start.sh` |
| `rpc-listen-port` | `PORT` |
| `dht-listen-port` | `BTPORT` |
| `listen-port` | `BTPORT` (same port, different protocol) |
| `bt-save-metadata` | `SMD` |
| `file-allocation` | `FA` (unset → `falloc`) |
| `bt-tracker` | `UT=true` triggers `tracker.sh file` to rewrite |

If any of these keys are missing from a user's old aria2.conf, `30-config` appends them as empty lines first so the subsequent `sed` replacement always lands (added 2026-05 to recover from silent failures on legacy configs). All other aria2.conf content is preserved across upgrades.

## setting.conf upgrade policy

`cont-init.d/20-config` handles setting.conf with two paths:

- **First start** (`/config/setting.conf` doesn't exist): `cp /aria2/conf/setting.conf /config/setting.conf` then `SEED_ENV_TO_SETTING_CONF` writes env vars in as seed values.
- **Subsequent start** (`/config/setting.conf` exists): `LOAD_CONF` reads existing values into globals, then `SED_CONF` copies the latest template to `setting.conf.new`, sed-replaces each known key with the existing-value, and atomically swaps. This preserves the user's settings while picking up any newly added template keys.

User's manual edits to setting.conf are preserved across image upgrades; env var changes are NOT propagated after first run.

## Build and CI

Build is triggered manually via `workflow_dispatch`. The GitHub Actions matrix:
- **Variants**: `standard`, `a2b`
- **Platforms**: `linux/amd64`, `linux/arm/v7`, `linux/arm64`
- Dev branch `standard` images are pushed as `:dev-latest` and `:dev-<yy-mm-dd>`
- Dev branch `a2b` images are pushed as `:a2b-dev-latest` and `:a2b-dev-<yy-mm-dd>`
- After manifests are pushed, CI inspects Docker Hub and GHCR manifests, then pulls GHCR dev tags to smoke-test container startup, aria2 RPC, WebUI access, and the aria2b process on amd64. The a2b smoke test runs with `A2B=true`, `NET_ADMIN`, and `/lib/modules` mounted when available.

## Development Branch

Active refactoring work happens on `dev-refactor-20260521`. Do not modify cont-init.d filenames — the numeric prefix order is an s6-overlay convention. The files `90-custom-folders` and `99-custom-scripts` are intentionally empty customization hooks.

## Persistent Config (mounted at /config)

User-facing config lives in the `/config` volume (persisted across container restarts):
- `aria2.conf` — main aria2 config (env vars written in by 30-config on each start)
- `setting.conf` — script behavior settings (see `lib/config.sh` for all options)
- `文件过滤.conf` — file content filter rules
- `logs/` — move/delete/recycle/filter logs
- `backup-torrent/` — torrent file backups
