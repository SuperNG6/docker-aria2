# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

docker-aria2 is an Alpine Linux Docker image running aria2 + AriaNg WebUI. It ships in two variants:
- **standard** — aria2c only
- **a2b** — aria2c + aria2b (BT traffic optimization proxy)

The variant is selected at build time via `ARG VARIANT=standard` in the Dockerfile. The GitHub Actions workflow builds both variants in a single `variant × platform` matrix.

The active development branch is **`dev-refactor-20260521`**. It refactored the original `aria2b` branch from a monolithic-script layout into a modular `lib/` layout. The `aria2b` branch is preserved for reference — see [Refactor history](#refactor-history-pre-refactor-aria2b-branch--current-dev-refactor) for the diff.

## External dependencies (read these to understand the runtime)

This image composes three upstream projects. Don't assume legacy behavior — check the actual upstream when in doubt:

### Base image: [SuperNG6/docker-baseimage-alpine](https://github.com/SuperNG6/docker-baseimage-alpine)

Fork of linuxserver/docker-baseimage-alpine, rebuilt with the latest Alpine point release and **s6-overlay v2.2.0.3** (last v2 release; the fork intentionally does not upgrade to v3).

What the base image provides (do NOT re-add these in this Dockerfile):
- **Packages**: `bash`, `curl`, `wget`, `ca-certificates`, `coreutils`, `procps`, `shadow`, `tzdata`. `coreutils` matters — it provides GNU `du -b`, GNU `df --output=avail -B1`, GNU `stat -c %d` that `lib/files.sh#_CHECK_SPACE` relies on
- **`abc` user**: UID 911 / primary group `abc` (UID-paired, via `useradd -U`) / supplementary group `users` (GID 1000). Home `/config`, shell `/bin/false`. `chown abc:abc` works because UID 911 has its own group named `abc`
- **Directories**: `/app`, `/config`, `/defaults`
- **`with-contenv` wrapper**: `/usr/bin/with-contenv` reads env from `/var/run/s6/container_environment/` and applies `UMASK` before exec. Note the base image **renames the original to `/usr/bin/with-contenvb`** and replaces `/usr/bin/with-contenv` with a custom one — this is intentional, do not touch it
- **`init-stage2` patch**: `patch/etc/s6/init/init-stage2.patch` is applied to make linuxserver-style init scripts work. Don't try to undo or re-patch
- **s6-overlay tarball arch mapping** (`install.sh`):  amd64→amd64, arm64→aarch64, arm→arm, 386→x86, ppc64le→ppc64le

Provided cont-init scripts you can rely on (from `root/etc/cont-init.d/`):
- `01-envfile` — base image's env-file loader (runs before our `11-version`)
- `10-adduser` — creates the `abc` user with the requested `PUID`/`PGID`, then prints the GID/UID banner

### aria2b: [SuperNG6/aria2b](https://github.com/SuperNG6/aria2b)

Node.js script that watches aria2's RPC and bans leeching BT clients (迅雷 / 影音先锋 / QQ 旋风 / 百度网盘) via `iptables` + `ipset`. **Linux-only**, requires Node 22+. Only used in the **a2b variant**.

Current pinned version: **v2.1.0** (May 2026). Dockerfile pulls the **latest tag** at build time from GitHub Releases — keep build cache off (see `Build and CI` below) so version bumps are picked up automatically.

What it reads from aria2.conf (parasitic config — keys prefixed with `ab-`):
- `rpc-secret` — auto-shared
- `ab-bt-ban-client-keywords`, `ab-bt-noprogress-keywords`, `ab-bt-noprogress-piece`, `ab-bt-noprogress-wait`, `ab-bt-scan-interval`, `ab-bt-ban-timeout`, `ab-rpc-no-verify`, `ab-rpc-ca`, `ab-rpc-cert`, `ab-rpc-key`

CLI flags `services.d/aria2b/run` passes:
- `-c /config/aria2.conf` — config file (so users can configure aria2b via aria2.conf)
- `-u http://127.0.0.1:${PORT}/jsonrpc` — RPC URL
- `-s "${SECRET}"` — RPC secret

Default block keywords (`-b` flag): `XL,SD,XF,QD,BN` (Xunlei, Xfplay, QQ Xuanfeng, Baidu Netdisk). Default scan interval: 5000ms. IPv6 supported when `/proc/net/if_inet6` exists (uses `bt_blacklist6` + `ip6tables`).

a2b variant requires runtime privileges: `--cap-add NET_ADMIN` and optionally `-v /lib/modules:/lib/modules:ro` (for kernel modules on hosts where they need to be loaded).

**v2.0.0 had a critical bug**: `scanTimer.unref()` caused Node to exit silently after each scan, which under s6 supervision turned into a ~10s restart loop. **v2.1.0 fixes this** (release 2026-05-22) plus 7 other bugs including:
- "Unknown" keyword not actually blocking unknown clients (B2)
- `startsWith('127.')` host check bypassable by `127.0.0.1.evil.com` (B3)
- All-numeric secret losing leading zeros (B4)
- Bare `--noprogress-wait` parsed as `1` (B5)
- RPC timeout not covering connect phase (C1)
- HTTP 3xx treated as success (C2)
- SIGTERM not destroying rpcClient → 30s shutdown delay (C3)

Always pin **>= v2.1.0** in this image.

## Runtime Stack

- Base image: `superng6/alpine:3.23` — Alpine + **s6-overlay v2.2.0.3** (last v2 release, not v3)
- Init system entrypoint: `/init` → runs `cont-init.d/` scripts then supervises `services.d/` services
- WebUI: `darkhttpd` serving AriaNg static files from `/www`
- Download user: `abc` (UID 911 / group `users` GID 1000); all aria2c processes run via `s6-setuidgid abc`

### What this Dockerfile adds on top of the base image

- **Packages**: `darkhttpd`, `curl`, `jq`, `findutils` (a2b additionally: `iptables`, `ip6tables`, `ipset`, `nodejs`)
- **Binaries**: `aria2c` (downloaded from [SuperNG6/Aria2-Pro-Core](https://github.com/SuperNG6/Aria2-Pro-Core) releases — static build, latest CI tag), `aria2b` (a2b only, pinned to latest GH release from `SuperNG6/aria2b`)
- **AriaNg AllInOne**: static HTML/JS, served by darkhttpd from `/www`
- **`root/` overlay**: aria2 default conf, scripts, cont-init.d, services.d

Arch detection in the builder stage uses `uname -m` (buildx + QEMU runs the builder *as* the target arch, so `uname` is reliable without needing `ARG TARGETARCH`). Mapping:

| `uname -m` | Aria2-Pro-Core asset |
|------------|----------------------|
| `x86_64` | `aria2-static-linux-x86_64.tar.gz` |
| `aarch64` | `aria2-static-linux-arm64.tar.gz` |
| `armv7l` / `armv6l` | `aria2-static-linux-armhf.tar.gz` |
| `i386` / `i686` | `aria2-static-linux-i386.tar.gz` |

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

When adding a new shared global, give it a name that is unique across all of `lib/` — `grep -r <NAME> root/aria2/scripts/lib/` before introducing it.

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

### 2. setting.conf 控制的附加功能开关（**不接受 env var**）

| setting.conf key | Default | Reader |
|------------------|---------|--------|
| `move-task` | `false` | `lib/files.sh#MOVE_FILE` (via `MOVE` global) |
| `remove-task` | `rmaria` | `lib/files.sh` (via `RMTASK` global) |
| `content-filter` | `false` | `lib/filter.sh` (via `CF` global) |
| `delete-empty-dir` | `true` | `lib/filter.sh#DELETE_EMPTY_DIR` (via `DET` global) |
| `handle-torrent` | `backup-rename` | `lib/torrent.sh` (via `TOR` global) |
| `remove-repeat-task` | `true` | `start.sh` (via `RRT` global) |
| `move-paused-task` | `false` | `pause.sh` (via `MPT` global) |

**Design contract — single source of truth**: these keys are read **only** from `/config/setting.conf` (via `lib/config.sh#LOAD_CONF`). They are intentionally **not** controlled by env vars. To change behavior, edit `/config/setting.conf` directly or via WebUI — `LOAD_CONF` runs at every event-hook invocation, so changes take effect immediately, no container restart needed.

Why no env-var seeding: master always treated setting.conf as the sole interface. An earlier refactor attempted to add `SEED_ENV_TO_SETTING_CONF` (first-run seed only) under the name "F1 fix", but the half-effective semantics ("env var works only on first container creation") proved a footgun — users would `docker run -e MOVE=true` on the second restart, see no change, and conclude the container was broken. The seed mechanism was reverted on 2026-05-23 to restore master's single-interface design.

## aria2.conf rewrite policy

`cont-init.d/30-config` rewrites these aria2.conf keys on **every** startup using env vars. **Do not hand-edit these lines** — they are overwritten:

| aria2.conf key | Source env var |
|----------------|----------------|
| `on-download-stop` | hardcoded path `/aria2/scripts/stop.sh` |
| `on-download-complete` | hardcoded path `/aria2/scripts/completed.sh` |
| `on-download-pause` | hardcoded path `/aria2/scripts/pause.sh` |
| `on-download-start` | hardcoded path `/aria2/scripts/start.sh` |
| `rpc-listen-port` | `PORT` |
| `dht-listen-port` | `BTPORT` |
| `listen-port` | `BTPORT` (same port, different protocol) |
| `bt-save-metadata` | `SMD` |
| `file-allocation` | `FA` (unset → `falloc`) |
| `bt-tracker` | `UT=true` triggers `tracker.sh file` to rewrite |

These 9 keys are assumed present in `/config/aria2.conf` (the bundled `aria2.conf.default` template has them). `30-config` runs anchored `sed` substitutions and does NOT append missing keys — if a user hand-strips one of them, the sed becomes a no-op and the env-var override silently does nothing. That's an accepted "user folded their own paper" case; do not re-add an ensure-key prepass (previously introduced and reverted — see SKILL.md §3). All other aria2.conf content is preserved across upgrades.

## setting.conf upgrade policy

`cont-init.d/20-config` handles setting.conf with two paths:

- **First start** (`/config/setting.conf` doesn't exist): `cp /aria2/conf/setting.conf /config/setting.conf`. The template ships with sensible defaults; users tune values via WebUI or hand-edit.
- **Subsequent start** (`/config/setting.conf` exists): `LOAD_CONF` reads existing values into globals, then `SED_CONF` copies the latest template to `setting.conf.new`, sed-replaces each known key with the existing-value, and atomically swaps. This preserves the user's settings while picking up any newly added template keys.

User's manual edits to setting.conf are preserved across image upgrades. Env vars never participate — see [setting.conf 控制的附加功能开关](#2-settingconf-控制的附加功能开关不接受-env-var) above for the design rationale.

## Build and CI

Build is triggered manually via `workflow_dispatch`. The GitHub Actions matrix:
- **Variants**: `standard`, `a2b`
- **Platforms**: `linux/amd64`, `linux/arm/v7`, `linux/arm64`
- Dev branch `standard` images are pushed as `:dev-latest` and `:dev-<yy-mm-dd>`
- Dev branch `a2b` images are pushed as `:a2b-dev-latest` and `:a2b-dev-<yy-mm-dd>`
- Workflow order: `build` (push by digest, no user-visible tag) → `smoke-test` (pulls by sha256 digest on amd64 only, since GH runners are amd64; arm variants are validated by build success alone) → `merge` (variant matrix: standard / a2b; only runs if smoke-test passed, then promotes the digests to `:dev-latest` / `:dev-<date>` for standard and `:a2b-dev-latest` / `:a2b-dev-<date>` for a2b). Failed tests never publish a user-visible tag.
- The a2b smoke test runs with `A2B=true`, `--cap-add NET_ADMIN`, and `-v /lib/modules:/lib/modules:ro` when available.
- `buildx` cache is intentionally disabled — the Dockerfile pulls AriaNg / aria2c / aria2b via `curl + grep latest tag`, and GHA cache would freeze versions on stale layers.

## Tests

Two test scripts live under `.github/scripts/`. Both run automatically as part of the smoke-test job; they can also be invoked locally against a running container.

### `rpc-integration-test.sh` (host-side, 16 cases)
Talks to aria2's JSON-RPC over the mapped port. Covers: getVersion, getGlobalStat, changeGlobalOption / getGlobalOption, HTTP single-source / multi-source / with options, pause-unpause-remove, tellActive/Waiting/Stopped, magnet (Big Buck Bunny — well-seeded test torrent, verifies entering `active` only — no full download), .torrent submission (latest Ubuntu 24.04 LTS live-server torrent, base64 encoded → `addTorrent`), purgeDownloadResult, **aria2.conf assertions**: `file-allocation` default = `falloc` (B1 regression), `bt-save-metadata=true` (SMD default), `listen-port=dht-listen-port=32516` (BTPORT default), **tracker RPC end-to-end** (changeGlobalOption pushes a tracker list, then getGlobalOption verifies it landed), **MOVE end-to-end** (`docker exec` to flip move-task=true → submit download → verify file lands in `/downloads/completed/`).

The `rpc()` helper pipes params to `jq` via stdin to bypass Linux `MAX_ARG_STRLEN` (128KB per-arg) — base64 of a .torrent can exceed this. Don't refactor it back to `--argjson`.

Usage: `rpc-integration-test.sh <host> <port> <secret> [container-name] [variant]`. Container name is optional but required for MOVE E2E and aria2.conf assertions.

### `in-container-lib-test.sh` (in-container, 50 cases)
`docker cp` into the running container, then `docker exec bash /tmp/in-container-lib-test.sh`. Sources `lib/{log,files,filter,torrent,event,tracker}.sh` directly and invokes the functions with hand-crafted globals.

Test groups:
- **filter** (8): exclude-file / include-file / keyword / min-size / regex / single-file skip / root-dir skip / DET empty-dir cleanup
- **move** (6): MOVE=false / true single-file / true multi-dir / dmof root-single / dmof subdir-single / unknown-value safe-no-op
- **delete/recycle/.aria2/rmaria** (4): DELETE_FILE / MOVE_RECYCLE / RM_ARIA2 / RMTASK=rmaria 默认行为
- **torrent** (6): retain / delete / rename / backup / backup-rename / unknown safe-keep
- **path** (7): HTTP single root/subdir, BT single root/subdir, BT multi, out-of-bounds error, magnet empty FILE_PATH
- **RRT** (3): completed 同名 → 删本地；TASK_STATUS=error 时跳过；RRT=false 时不动
- **tracker** (8): file write / sed escape / missing-line append / RPC success-response parse / RPC fake-OK in error response (B2 regression) / `main file` E2E / `main rpc` E2E / CTU custom-URL dedup
- **config** (1): SED_CONF upgrade preserve
- **11-version** (2): default SECRET warning / custom SECRET no warning (F2 regression)
- **log demo** (2): 大批量过滤删除（CF=true，~26 文件）/ 整任务删除（DELETE_FILE，25 文件目录）—— 不抑制 stdout，CI artifact 中可肉眼检查 docker logs 输出格式（颜色、TASK_INFO 横幅、log 文件无 ANSI 码）

Move/delete/recycle tests set `FILE_PATH` alongside `SOURCE_PATH` so the `TASK_INFO` banner ("首个文件位置") prints non-empty — mirrors aria2's hook contract where `$3` is the first-file path. New move-mode tests should follow the same pattern.

`in-container-lib-test.sh` deliberately runs **without `set -u`** — `log.sh#TASK_INFO` references implicit-contract variables (FILE_PATH, TASK_TYPE) that individual unit tests can't always pre-set. Use `pipefail` + explicit assertions instead.

## Common commands

```bash
# Local syntax preflight (run before push)
bash -n .github/scripts/rpc-integration-test.sh
bash -n .github/scripts/in-container-lib-test.sh
bash -n root/aria2/scripts/lib/*.sh
bash -n root/etc/cont-init.d/*-* root/etc/services.d/*/run
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/Build Image.yml'))"

# Trigger a CI build of the current branch
gh workflow run "Build Image.yml" --ref "$(git rev-parse --abbrev-ref HEAD)"

# Watch the latest run
gh run list --workflow="Build Image.yml" --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 3
gh run view <run-id> --log-failed   # pulls only failed steps' logs

# Local smoke-test a built image (replace IMAGE)
IMAGE=ghcr.io/superng6/aria2:dev-latest
docker run -d --name aria2-local -p 16800:6800 -p 18080:8080 \
    -e SECRET=smoketoken -e UT=false -e RUT=false "${IMAGE}"
.github/scripts/rpc-integration-test.sh 127.0.0.1 16800 smoketoken aria2-local standard
docker cp .github/scripts/in-container-lib-test.sh aria2-local:/tmp/
docker exec aria2-local bash /tmp/in-container-lib-test.sh
docker rm -f aria2-local

# a2b variant locally (needs NET_ADMIN + modules)
docker run -d --name aria2b-local --cap-add NET_ADMIN \
    -v /lib/modules:/lib/modules:ro \
    -p 16801:6800 -p 18081:8080 \
    -e A2B=true -e SECRET=smoketoken -e UT=false -e RUT=false \
    ghcr.io/superng6/aria2:a2b-dev-latest

# Compare current vs pre-refactor aria2b branch (for any single file)
git show aria2b:root/aria2/scripts/<file>
```

## Development Branch

Active refactoring work happens on `dev-refactor-20260521`. Do not modify cont-init.d filenames — the numeric prefix order is an s6-overlay convention. The files `90-custom-folders` and `99-custom-scripts` are intentionally empty customization hooks.

## Refactor history (pre-refactor `aria2b` branch → current `dev-refactor`)

The original `aria2b` branch had monolithic scripts. The refactor (`dev-refactor-20260521`) split the script layer into `lib/`, fixed several real bugs, and added the `VARIANT` mechanism (standard vs a2b). Knowing what changed helps when reading old issues or PRs.

### Structural changes
| Before (`aria2b` branch) | After (`dev-refactor-20260521`) |
|--------------------------|---------------------------------|
| `script/core` — log/path/file/move all in one file | `lib/{log,event,files,filter,torrent}.sh` |
| `script/setting` — LOAD_CONF + SED_CONF | `lib/config.sh` (LOAD_CONF + SED_CONF; CONFIG_ITEMS array drives both) |
| `script/rpc_info` — RPC payload via string interp | `lib/rpc.sh` — payload via `jq -nc` (safe against JSON injection) |
| `script/tracker.sh` (file mode) + `script/rpc_tracker.sh` (rpc mode) | `lib/tracker.sh` (both modes; `main "$@"` dispatch + source guard) |
| `script/cron-restart-a2b.sh` standalone | Inlined into `cont-init.d/40-config` `_register_a2b_restart` |
| Single image, A2B baked in | `ARG VARIANT={standard,a2b}` × `linux/{amd64,arm/v7,arm64}` matrix |

### Bugs fixed by refactor (silently existed in the old `aria2b` branch)
- `core#HANDLE_TORRENT rename` did `mv ... "${TASK_NAME}.torrent"` with no target dir — landed in aria2c cwd. Refactor adds `${DOWNLOAD_DIR}/` prefix
- `core#HANDLE_TORRENT rename` echoed "已删除种子文件" but actually does a rename — misleading log. Refactor echoes "重命名种子文件"
- `setting#SED_CONF` used an `elif` chain for empty-value defaults — only the first empty key got its default applied. Refactor uses a per-key loop
- `services.d/aria2b/run` when `A2B!=true` just `echo`'d and exited — s6 saw the service exit and restarted it forever (10s loop). Refactor uses `exec s6-svc -d .` to properly disable the service
- `services.d/aria2/run` interpolated `$SECRET_TOKEN` without quotes — `SECRET` containing whitespace word-split. Refactor uses bash array
- `rpc_info#RPC_PAYLOAD` built JSON via string concatenation — SECRET containing `"` `\` newline broke the payload (effectively a JSON-injection vector). Refactor uses `jq -nc --arg`
- `cron-restart-a2b.sh` killed via `ps -ef | grep aria2b | xargs kill -9` — would also kill any process named `aria2b*` (e.g. helpers). Refactor uses `pkill -x aria2b` for exact match
- `30-config` used pattern `.*on-download-pause.*` and `.*on-download-start.*` that also matched commented lines — could overwrite `#on-download-pause=` comments with the hook path. Refactor anchors with `^\(key=\).*`
- `30-config` started `crond` only when `RUT=true` — meant `RUT=false` users had no cron at all, so aria2b restart cron (registered in 40-config) and Alpine periodic (hourly/daily/weekly/monthly) silently did nothing. Refactor always starts crond
- `tracker.sh#ADD_TRACKERS` checked `[ -z $(grep "bt-tracker=" $ARIA2_CONF) ]` — no quotes, no anchor; matched commented `#bt-tracker=` lines, so when the live `bt-tracker=` line was missing nothing got appended and the subsequent `sed` `^\(bt-tracker=\)` matched nothing, leaving trackers empty. Refactor uses `grep -q "^bt-tracker=" || echo "bt-tracker=" >> "${conf}"`
- `start.sh` did `rm -rf SOURCE_PATH` for repeat-task removal but never ran `CHECK_TORRENT` first — magnet-saved `.torrent` files (in `/downloads/<infoHash>.torrent`) survived and could re-trigger downloads. Refactor inserts `CHECK_TORRENT` before the delete so the torrent is handled per `TOR` config
- `start.sh` invoked `REMOVE_REPEAT_TASK` without checking return — silent failure meant the local files were deleted but aria2c could keep downloading into a new copy. Refactor warns on failure (still `exit 0` since local cleanup happened)
- Typo `WARRING` → `WARNING`

### Bugs that survived the refactor (caught later in deep review)
Documented here so future deep dives don't miss them:
- B1 (May 2026): `30-config` `FA` unset case fell to `*) FA_VAL=none` — overrode aria2.conf default `falloc`. Fixed
- B2 (May 2026): `tracker.sh#_update_rpc` used `grep -q OK` — error responses containing "OK" string falsely identified as success. Fixed (uses `jq -e '.result == "OK"'`)
- B3 (May 2026): `tracker.sh#_update_rpc` curl had no timeout — cron tasks could pile up indefinitely. Fixed
- F1 (May 2026, **REVERTED 2026-05-23**): a refactor briefly added `SEED_ENV_TO_SETTING_CONF` to make `MOVE/RMTASK/CF/DET/TOR/RRT/MPT` env vars take effect on first container start (claiming the original README "documented them as env vars but the code never read them"). The fix was reverted after re-reading the original README — those 7 vars were **never** in master's env table; setting.conf has always been the sole interface. The half-effective semantics ("env works only the first time") was a footgun. The 3 SEED unit tests were also removed.
- F2 (May 2026): default `SECRET=yourtoken` was a public exposure risk. Added red-banner warning in `11-version` when default is in use
- F6 (May 2026): `50-config` darkhttpd failure was silent. Fixed (now echoes success/failure)

### Subsystem-by-subsystem comparison (deep dive)

For future reviews — this is what survived intact, what got cleaned up structurally, and what was a genuine bug. Run this same checklist when comparing future refactors.

**File move (`MOVE_FILE`)** — *functionally identical*. Refactor pulled `_IS_CROSS_DEVICE`, `_CHECK_SPACE`, `_MOVE_TO_FAILED` into helpers but cross-disk space check, mv-failed fallback, and the `MOVE=false/true/dmof` branching all match the old `core` script exactly. No regression.

**File filter (`DELETE_EXCLUDE_FILE`)** — *functionally identical*. Refactor pulled the 6 find pipes into a `_filter_rule` helper. Same FILE_NUM>1 guard, same anti-root-delete guard, same `min-size/include-file/exclude-file/keyword-file/include-file-regex/exclude-file-regex` rules. No regression.

**Download event hooks** — refactor improvements, no regressions:
- `completed.sh`: backgrounded `MOVE_FILE &` (was sync — large cross-disk moves blocked aria2c's hook fork)
- `stop.sh`: case/case dispatch instead of elif chain; semantics identical
- `start.sh`: added `CHECK_TORRENT` before `rm -rf SOURCE_PATH` (RRT path) so magnet `.torrent` is properly handled by TOR config; added warning when `REMOVE_REPEAT_TASK` RPC call fails
- `pause.sh`: identical (MPT=true → MOVE=true → MOVE_FILE)
- Refactor's `INIT_EVENT` exits 1 when RPC fails. Old `rpc_info#GET_RPC_RESULT` had `exit 1` inside `GET_DOWNLOAD_DIR` but at slightly different points; net behavior similar

**Startup pipeline (cont-init.d)** — many fixes:
- `11-version`: added SECRET=yourtoken warning (F2)
- `20-config`: first-run copies template, subsequent runs `SED_CONF` merges. setting.conf is the **sole** interface for behavior vars (see F1 reversal note above)
- `30-config`: anchored sed patterns, FA default fixed to falloc (B1), crond always starts
- `40-config`: cron-restart-a2b.sh inlined; `pkill -x` for exact-match process kill
- `50-config`: success/failure echo for darkhttpd (F6)

**Services** — `services.d/aria2/run` switched to bash array (`SECRET` with spaces now safe); `services.d/aria2b/run` uses `exec s6-svc -d .` to disable cleanly, polls aria2c RPC instead of `sleep 10`.

### Things to NOT change (intentional design from refactor)
- `lib/event.sh` uses `BASH_SOURCE[0]` (not `$0`) to resolve `_LIB` — required because event hooks `source` it
- `completed.sh` runs `MOVE_FILE &` in background, `CHECK_TORRENT` in foreground — large cross-disk moves block aria2c's hook fork; backgrounding releases aria2c quickly while s6/PID-1 reaps the move's orphan
- `lib/tracker.sh` source guard `[ "${BASH_SOURCE[0]}" = "${0}" ] && main "$@"` allows tests to source-and-call-functions without triggering `main`
- aria2b/run uses `for i in $(seq 1 30)` to poll RPC at 1s intervals — fixed `sleep 10` was racy on slow systems

## Persistent Config (mounted at /config)

User-facing config lives in the `/config` volume (persisted across container restarts):
- `aria2.conf` — main aria2 config (env vars written in by 30-config on each start)
- `setting.conf` — script behavior settings (see `lib/config.sh` for all options)
- `文件过滤.conf` — file content filter rules
- `logs/` — move/delete/recycle/filter logs
- `backup-torrent/` — torrent file backups
