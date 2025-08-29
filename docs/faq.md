# 常见问题（FAQ）

## 1. WebUI 无法访问或空白
- 检查环境变量：`WEBUI=true` 且 `WEBUI_PORT` 未被占用。
- 确认 `50-darkhttpd` 已执行：容器日志应出现 darkhttpd 启动信息。
- 如自定义挂载 `/www`，确保 `index.html` 存在且可读。

## 2. RPC 连接失败（AriaNg 提示连接错误）
- 确认 `PORT` 映射正确，AriaNg 端填写地址为 `ws://<host>:<PORT>/jsonrpc`（或 http 的 JSON-RPC）。
- 若设置了 `SECRET`，AriaNg 需填写同样的令牌。
- 查看容器日志是否有 `Aria2 RPC 接口错误`（来自 `rpc.sh`）。

## 3. 下载完成后未移动到 completed
- `setting.conf` 中 `move-task` 是否为 `true` 或 `dmof`？
- 多文件 BT 任务在子目录内：逻辑会以任务顶层目录为单位移动。
- 跨盘移动失败或空间不足时会回落到 `/downloads/move-failed`，查看 `config/logs/move.log`。

## 4. 暂停后未触发移动
- 需将 `move-paused-task=true` 才会在 on_pause 中执行移动。
- on_pause 中会强制 `MOVE=true`，其余过滤/清理策略仍生效。

## 5. .torrent 文件未按预期处理
- 确认 `handle-torrent` 的值：retain/delete/rename/backup/backup-rename。
- 仅 BT 且 `bt-save-metadata=true` 的情形才会生成 `.torrent`。

## 6. 重复任务未被删除
- 确认 `remove-repeat-task=true`。
- on_start 阶段仅当解析到的 `COMPLETED_DIR` 已存在且任务状态不为 error 才会移除重复任务。

## 7. Tracker 未更新或仍为旧列表
- 启动时更新：`UT=true` 将写入 bt-tracker 到 `aria2.conf`。
- 定时更新：`RUT=true` 会在每日 05:00 通过 RPC 更新（无需重启 aria2）。
- 自定义源：设置 `CTU`（逗号分隔多个 URL），程序会合并去重。

## 8. setting.conf 键被误删导致异常
- `20-config` 会在初始化时调用 `config_apply_setting_defaults`：复制模板→覆盖已设置值→为缺失键填默认值→原子替换。
- 手工恢复：删除 `/config/setting.conf`，重启容器以从模板再生（会丢失手动改动）。

## 9. 权限问题（下载/移动失败）
- 检查 PUID/PGID 是否与宿主用户一致；基础镜像使用用户 `abc`。 
- `60-permissions` 会在启动时尝试 `chown -R abc:abc /config /downloads`。

## 10. 如何快速定位问题
- 查看 `/config/logs/`：`move.log`、`recycle.log`、`delete.log`、`文件过滤日志.log`。
- 关注容器启动面板（11-banner），确认关键 ENV 与版本。
- 开启临时调试：设置环境变量 `DEBUG=1`（`common.sh` 中的 `_dbg` 输出）。
