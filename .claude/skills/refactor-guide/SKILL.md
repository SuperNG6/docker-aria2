---
name: refactor-guide
description: Analyze docker-aria2 shell scripts and suggest refactoring while preserving all existing functionality. Use when asked to refactor, clean up, or consolidate scripts in /root/aria2/script/.
disable-model-invocation: false
---

# Refactor Guide for docker-aria2

When the user asks for refactoring suggestions, follow this process:

## 1. Scope the analysis

Read all scripts in `/root/aria2/script/`:
- `setting` — config loader + SED_CONF/LOAD_CONF
- `core` — main logic (path calc, file ops, filtering, logging)
- `rpc_info` — RPC interface
- `start.sh`, `completed.sh`, `stop.sh`, `pause.sh` — event hooks
- `tracker.sh`, `rpc_tracker.sh` — tracker update utilities

## 2. Identify refactoring opportunities in priority order

### A. Code duplication
- Tracker URL lists appear in both `tracker.sh` and `rpc_tracker.sh` — candidate for shared variable or shared library
- Token auth pattern repeated across rpc_info functions — candidate for a single auth-helper function
- `source "$(dirname "$0")/X"` sourcing pattern repeated in every event script

### B. Variable quoting safety
- Flag any `${var}` that should be `"${var}"` (paths with spaces)
- This is especially critical in `core` where paths are passed to `mv`, `cp`, `find`

### C. Error handling consistency
- Some functions use `[ $? -eq 0 ]`, others use `if cmd; then`
- Normalize to `if cmd; then` pattern (POSIX, more readable)

### D. Chinese filename handling
- `文件过滤.conf` and `文件过滤日志.log` — note these are intentional for Chinese-locale users; preserve them but flag if any script hardcodes paths without quoting

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
- Do not suggest adding new features or changing default values

## 5. After listing suggestions

Ask: "Which of these would you like me to implement?" before making any changes.
