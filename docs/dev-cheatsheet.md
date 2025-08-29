# 开发者速查表（aria2-dev）

本速查表概览事件钩子、核心库函数与关键配置，帮助快速理解与维护。

## 目录结构速览
- handlers/: Aria2 事件回调脚本（on_start/on_complete/on_pause/on_stop）
- lib/: 可复用的库（logger/common/config/path/rpc/file_ops/torrent）
- utils/: 辅助工具（tracker）
- etc/cont-init.d/: 容器初始化脚本（11-banner/20-config/30-aria2-conf/40-tracker/50-darkhttpd/60-permissions）
- etc/services.d/aria2/run: 启动 aria2c

## 事件钩子（Aria2 callbacks）
aria2.conf 中由 30-aria2-conf 写入：
- on-download-start -> `/aria2/scripts/handlers/on_start.sh`
- on-download-complete -> `/aria2/scripts/handlers/on_complete.sh`
- on-download-pause -> `/aria2/scripts/handlers/on_pause.sh`
- on-download-stop -> `/aria2/scripts/handlers/on_stop.sh`

调用约定（aria2 传参）：
- $1=GID  $2=FILE_NUM  $3=FILE_PATH

行为摘要：
- on_start：当 `remove-repeat-task=true` 且目标 completed 目录存在同名任务时，删除当前重复任务与控制文件。
- on_complete：按 `move-task/content-filter/delete-empty-dir` 执行清理与移动；按 `handle-torrent` 处理 .torrent。
- on_pause：当 `move-paused-task=true` 时，强制 `MOVE=true` 执行移动，并处理 .torrent。
- on_stop：依据 `remove-task`（rmaria/recycle/delete）执行对应动作，并处理 .torrent。

## 配置与环境变量
- setting.conf（/config/setting.conf）
  - remove-task: rmaria|recycle|delete（默认 rmaria）
  - move-task: false|true|dmof（默认 false）
  - content-filter: true|false（默认 false）
  - delete-empty-dir: true|false（默认 true）
  - handle-torrent: retain|delete|rename|backup|backup-rename（默认 backup-rename）
  - remove-repeat-task: true|false（默认 true）
  - move-paused-task: true|false（默认 false）
- 文件过滤（/config/文件过滤.conf）
  - min-size/include-file/exclude-file/keyword-file/include-file-regex/exclude-file-regex
- 环境变量（docker-compose.yml / Dockerfile）
  - 端口与运行：PORT/BTPORT/CACHE/QUIET
  - 功能：UT（启动更新 tracker）、RUT（定时 RPC 更新 tracker）、SMD（bt-save-metadata）、FA（file-allocation）、WEBUI/WEBUI_PORT
  - 用户：PUID/PGID（基础镜像内置用户 abc）

## 初始化与服务
- 20-config：创建目录与日志；复制 aria2.conf.default/setting.conf/文件过滤.conf；
  - 调用 `config_apply_setting_defaults`：按模板补齐 setting.conf 缺失项（复制模板→覆盖用户值→补默认→原子替换）。
- 30-aria2-conf：写入回调与端口、SMD、FA 等至 /config/aria2.conf。
- 40-tracker：按 UT 更新 bt-tracker 到配置；按 RUT 写入 crontab，每日 05:00 通过 RPC 更新。
- 50-darkhttpd：若 WEBUI=true，则启动 AriaNg。
- services.d/aria2/run：以 s6-setuidgid abc 启动 aria2c（SECRET/CACHE/QUIET）。

## 核心库函数速查
- logger.sh
  - log_i/log_w/log_e：统一带时间的 INFO/WARN/ERROR 输出
- common.sh
  - panel(title, ...lines)：打印分割面板
  - try_run cmd...：错误不 exit，返回实际码
  - kv_get(file, key)/kv_set(file, key, val)：简单的 key=value 读写
  - check_space_before_move(src, dstDir)：跨盘移动前检查空间，0=可用/1=不足
  - path_join(base, sub)/relative_path(base, full)：路径工具
- config.sh
  - config_load_setting()：加载 setting.conf 键到当前环境
  - config_apply_setting_defaults()：模板回填缺失键（由 20-config 调用）
- path.sh
  - get_base_paths()：初始化下载根、日志路径等
  - completed_path()/recycle_path()：目标根目录指向 completed/recycle
  - print_task_info()/print_delete_info()：统一任务信息输出
  - get_final_path()：根据 FILE_NUM/FILE_PATH 等解析 SOURCE_PATH、TARGET_PATH、COMPLETED_DIR
- rpc.sh
  - rpc_get_status(gid)/rpc_remove_task(gid)/rpc_change_global_option(key, val)
  - rpc_get_parsed_fields(gid)：解析并导出 TASK_STATUS/DOWNLOAD_DIR/INFO_HASH/TORRENT_* 等
  - rpc_remove_repeat_task(gid)：延时移除（用于重复任务场景）
- file_ops.sh
  - rm_aria2()/delete_empty_dir()：清理控制文件/空目录
  - clean_up()：按过滤规则清理并记录日志
  - move_file()：移动文件（含跨盘空间预检与失败回落）
  - delete_file()/move_recycle()：删除或移入回收站
- torrent.sh
  - handle_torrent()/check_torrent()：保留/删除/重命名/备份（含重命名）.torrent 文件
- utils/tracker.sh
  - get_trackers()/show_trackers()：抓取与展示
  - add_trackers_conf()/add_trackers_rpc()：写入配置或通过 RPC 动态更新

## 事件输入与常见字段说明
- 来自 rpc_get_parsed_fields(gid)：
  - TASK_STATUS：任务状态（完整/活动/暂停/错误 等）
  - DOWNLOAD_DIR：任务下载所在目录
  - INFO_HASH：BT 任务的 infoHash
  - TORRENT_PATH/TORRENT_FILE：infoHash 派生路径
- 来自路径解析：
  - SOURCE_PATH：任务源（单文件=文件路径，多文件=任务顶层目录）
  - TARGET_DIR：completed 或 recycle 根
  - TARGET_PATH：保持相对层级后的目标目录
  - COMPLETED_DIR：目标目录下的任务最终位置（多文件）

## 开发建议
- 新增功能尽量放入 lib/，handlers 仅做编排。
- 变更回调路径请同步更新 `30-aria2-conf`。
- 修改 setting.conf 格式需同步更新 `config_load_setting` 与模板。
- 需网络的操作（如 tracker 获取）注意降级与错误提示，不要影响下载主流程。


## 调用链示意图（handlers → lib）

```mermaid
flowchart TD
  A[aria2c 事件回调] --> S[on_start.sh]
  A --> C[on_complete.sh]
  A --> P[on_pause.sh]
  A --> T[on_stop.sh]

  subgraph LIBS[复用库]
    L1[logger.sh]
    L2[common.sh\n(panel/kv/check_space/...)]
    L3[config.sh\n(config_load_setting/\nconfig_apply_setting_defaults)]
    L4[path.sh\n(get_base_paths/\nget_final_path/...)]
    L5[rpc.sh\n(tellStatus/remove/\nchangeGlobalOption)]
    L6[file_ops.sh\n(clean_up/move_file/\nrm_aria2/...)]
    L7[torrent.sh\n(handle_torrent)]
  end

  S --> L1 & L2 & L3 & L4 & L5
  C --> L1 & L2 & L3 & L4 & L5 & L6 & L7
  P --> L1 & L2 & L3 & L4 & L5 & L6 & L7
  T --> L1 & L2 & L3 & L4 & L5 & L6 & L7

  subgraph INIT[初始化/定时]
    I20[20-config\n(复制模板/回填缺失键)]
    I30[30-aria2-conf\n(写回调/端口等)]
    I40[40-tracker\n(UT 更新配置/\nRUT cron RPC)]
    U1[utils/tracker.sh]
  end

  I40 --> U1
```


## 相关文档

- 常见问题（FAQ）：./faq.md

