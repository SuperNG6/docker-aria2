---
name: refactor-guide
description: Analyze docker-aria2 shell scripts and suggest refactoring while preserving all existing functionality. Use when asked to refactor, clean up, or consolidate scripts in root/aria2/script/.
disable-model-invocation: false
---

# Refactor Guide for docker-aria2

When the user asks for refactoring suggestions, follow this process:

## 1. Scope the analysis

Read the current script layout under `root/aria2/script/`:
- `lib/event.sh` — event hook entrypoint; sources event libs, calculates paths, defines `INIT_EVENT` and `GUARD_EVENT`
- `lib/config.sh` — `setting.conf` loader and `SED_CONF` upgrade merge
- `lib/files.sh` — `.aria2` cleanup, move, delete, recycle, move-failed fallback
- `lib/filter.sh` — content filtering from `文件过滤.conf`
- `lib/log.sh` — color constants, `DATE_TIME`, `TASK_INFO`
- `lib/rpc.sh` — aria2 JSON-RPC query and task removal helpers
- `lib/torrent.sh` — `.torrent` backup, rename, delete, retain handling
- `lib/tracker.sh` — dual-mode tracker update (`file` for startup config, `rpc` for cron)
- `start.sh`, `completed.sh`, `stop.sh`, `pause.sh` — event hooks
- `root/etc/cont-init.d/` and `root/etc/services.d/` — s6-overlay v2 startup and services

## 2. Identify refactoring opportunities in priority order

### A. Code duplication
- Repeated JSON-RPC request patterns in `lib/rpc.sh` and `lib/tracker.sh` may be candidates for a small helper if another RPC call is added.
- Repeated filesystem fallback logging in `lib/files.sh` may be consolidated only if it improves clarity.
- Keep `lib/event.sh` as the single source entrypoint for event hooks unless there is a concrete need to narrow dependencies.

### B. Variable quoting safety
- Flag any `${var}` that should be `"${var}"` (paths with spaces)
- This is especially critical in `lib/event.sh`, `lib/files.sh`, `lib/filter.sh`, and `lib/tracker.sh`.

### C. Error handling consistency
- Some functions use `[ $? -eq 0 ]`, others use `if cmd; then`
- Prefer `if cmd; then` and explicit return codes for library functions.
- Library functions should return non-zero and write diagnostics to stderr; event scripts decide whether to exit.

### D. Chinese filename handling
- `文件过滤.conf` and `文件过滤日志.log` — note these are intentional for Chinese-locale users; preserve them but flag if any script hardcodes paths without quoting

### E. Event hook contracts
- Preserve `INIT_EVENT` order: `GET_BASE_PATH` → `COMPLETED_PATH`/`RECYCLE_PATH` → `GET_RPC_INFO` → `GET_FINAL_PATH`.
- Preserve aria2's three hook arguments: GID, file count, first selected file path.
- Be careful changing `completed.sh`: `MOVE_FILE` intentionally runs in the background, while `.torrent` handling stays synchronous.

## 3. Presentation format

For each suggestion:
```
**[CATEGORY]** Short title
- What: what the duplication/issue is
- Where: file:line_number references
- Safe change: the minimal refactor that preserves behavior
- Risk: none | low | medium (if medium, explain why)
```

## 4. Constraints — always respect these

- **Preserve all functionality** — no behavior changes, only structural improvements
- **s6-overlay v2** — do not use s6-overlay v3 patterns
- **Alpine Linux** — no bash-isms that require bash 5+; scripts use `#!/bin/bash` but keep portability in mind
- **abc user context** — scripts run via `s6-setuidgid abc`; do not change permission model
- **Config file compatibility** — `setting.conf` and `文件过滤.conf` key names are user-facing; do not rename keys
- **Variant compatibility** — keep both `standard` and `a2b` Dockerfile variants working
- Do not suggest adding new features or changing default values

## 5. After listing suggestions

Ask: "Which of these would you like me to implement?" before making any changes.
