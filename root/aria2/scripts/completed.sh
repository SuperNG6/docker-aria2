#!/usr/bin/env bash
# 下载完成事件脚本
# aria2 在任务完成时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：按配置移动文件到 /downloads/completed，并处理种子文件
#
# 设计选择 — 用 on-download-complete 而非 on-bt-download-complete：
#   on-bt-download-complete 在 BT 下载完毕但做种开始前触发；此时 move 文件会破坏 seeding
#   （aria2 在原路径上做种，文件被搬走后 seeding 失败）。
#   on-download-complete 在做种也结束后触发，文件已完全释放，move 100% 安全。
#   当前默认 seed-time=0，等价于"下完即停"，二者触发时机无差。
#   若用户改大 seed-time / seed-ratio，move 会推迟到做种结束，是有意的取舍。
#
# 设计选择 — MOVE_FILE 后台化：
#   大文件跨盘 cp+rm 可能耗时数十分钟。aria2 同步 fork 钩子，等返回才能调度新任务。
#   把 MOVE_FILE 放后台，hook 立刻退出，aria2 立刻继续接活；MOVE 由 s6/init 接管收尸。
#   CHECK_TORRENT 留在前台：.torrent 单文件操作毫秒级，串行避免与 RRT 路径竞争。

. "$(dirname "${BASH_SOURCE[0]}")/lib/event.sh"

INIT_EVENT completed "$@"  # 初始化路径、RPC 信息（目标目录：completed）
GUARD_EVENT                 # 磁力/无效任务跳过；路径错误退出
MOVE_FILE &                 # 后台化大文件搬运，不阻塞 aria2 主线程
CHECK_TORRENT               # 同步处理种子文件（按 TOR 配置）
