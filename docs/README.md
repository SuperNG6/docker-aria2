# aria2-dev 重构说明

> 环境变量参考：请见 docs/env-vars.md（列出了全部可配置项、默认值与示例）

本目录为重构后的脚本实现，可直接 docker build 构建测试，不影响原项目文件。结构如下：

/aria2/scripts/
- lib/: 共享库（common/config/rpc/file_ops/path/torrent）
- handlers/: 事件处理器（on_start/on_complete/on_stop/on_pause）
- utils/: 工具（tracker）

同时重写了 /etc/cont-init.d 与 /etc/services.d/aria2，以适配新库。

保留行为与兼容性：
- 不修改 /config/setting.conf、/config/文件过滤.conf、/config/aria2.conf.default 格式
- 事件钩子改为新 handlers，但功能一致
- tracker 支持本地写入与 RPC 更新
- 保持磁力保存种子、重复任务检测、暂停移动、回收站、内容过滤、空目录清理、跨盘空间检查

构建：在 aria2-dev 目录内执行 docker build 即可。

## 快速启动

已提供示例 docker-compose.yml：
- 首次运行将自动在本地创建 ./config、./downloads、./www 目录
- WebUI 默认 http://localhost:8080，RPC 地址 ws://localhost:6800/jsonrpc，需要在 AriaNg 中填写 SECRET
- 启动时会打印带版本与配置的面板信息

常见环境变量：
- SECRET：Aria2 RPC 密钥
- PORT：RPC 端口（默认 6800）
- WEBUI_PORT：AriaNg 端口（默认 8080）
- BTPORT：BT 监听端口
- UT/RUT：tracker 容器启动更新 / 定时 RPC 更新
- SMD/FA：aria2 存种/文件预分配策略

### Aria2B（可选）

已内置可选的 Aria2B 进程（用于增强任务巡检/修复等）。通过以下环境变量控制：

- A2B：是否启用 Aria2B（true/false，默认 true 在 DockerfileA2B 中）。
- A2B_DISABLE_LOG：是否屏蔽 aria2b 输出日志（true 时静默运行）。
- CRA2B：定时重启 aria2b 的周期，支持 false 或形如 `2h/12h/24h`（1-24 小时）。无效输入将回退为 2h。

行为说明：
- 当 A2B=true 时，服务脚本会在 aria2c 启动后等待 10 秒再拉起 aria2b，并将其连接到 `http://127.0.0.1:${PORT}/jsonrpc`，携带 `SECRET`。
- 当 CRA2B=false 时，移除定时重启任务；否则按指定小时数在整点执行 `pkill -9 aria2b` 以触发重启。

docker-compose 示例：

services:
	aria2:
		image: your/image:tag
		environment:
			- A2B=true
			- A2B_DISABLE_LOG=false
			- CRA2B=6h    # 每 6 小时重启 aria2b，一般用于长时运行的稳定性
			- SECRET=yourtoken
			- PORT=6800
		# 其余挂载与端口映射略

## 兼容性与迁移

- 旧的 /aria2/script/*.sh 已移除；所有 on-download-* 回调统一指向 /aria2/scripts/handlers/*，容器启动时也会由 30-aria2-conf 强制写入到 /config/aria2.conf
- 不会在运行时改写 setting.conf 与 文件过滤.conf；若缺失则从默认模板复制
- cont-init.d 仅执行一次性初始化；aria2 的 on-download-* 回调由 /aria2/scripts/handlers 处理
