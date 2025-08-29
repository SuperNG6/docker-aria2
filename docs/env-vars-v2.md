# 环境变量参考 (v2)

本文档详细说明了 `docker-aria2` 容器支持的所有环境变量，旨在帮助用户进行深度自定义。

## 目录
1.  [核心运行与权限](#核心运行与权限)
2.  [Aria2 核心参数](#aria2-核心参数)
3.  [功能开关](#功能开关)
4.  [路径自定义](#路径自定义)
5.  [Aria2B 增强功能 (可选)](#aria2b-增强功能-可选)
6.  [Docker Compose 示例](#docker-compose-示例)

---

### 核心运行与权限

这类变量控制容器的基础运行环境。

| 变量 | 描述 | 默认值 |
| :--- | :--- | :--- |
| `TZ` | 设置容器的系统时区。 | `Asia/Shanghai` |
| `PUID` | 用户 ID。用于将容器内 `abc` 用户的 UID 映射到宿主机用户，解决文件权限问题。 | `1026` |
| `PGID` | 用户组 ID。用于将容器内 `abc` 用户的 GID 映射到宿主机用户组。 | `100` |
| `DEBUG`| 启用详细的调试日志输出。 | `0` (关闭) |

---

### Aria2 核心参数

这些变量直接影响 `aria2c` 进程的启动参数或核心配置。

| 变量 | 描述 | 默认值 |
| :--- | :--- | :--- |
| `SECRET` | Aria2 的 RPC 密钥（token）。 | (未设置) |
| `PORT` | RPC 服务监听端口。 | `6800` |
| `BTPORT` | BT 监听端口 (TCP/UDP)。 | `32516` |
| `CACHE` | 磁盘缓存大小。 | `128M` |
| `QUIET` | 是否启用静默模式，减少 aria2c 的控制台输出。 | `true` |
| `SMD` | 是否在下载磁力链接时保存 `.torrent` 种子文件 (`bt-save-metadata`)。 | `true` |
| `FA` | 文件预分配策略 (`file-allocation`)。可选值: `none`, `falloc`, `trunc`, `prealloc`。 | `falloc` |

---

### 功能开关

这些变量用于启用或禁用容器内置的自动化功能。

| 变量 | 描述 | 默认值 |
| :--- | :--- | :--- |
| `WEBUI` | 是否启动内置的 AriaNg Web UI。 | `true` |
| `WEBUI_PORT` | Web UI 的访问端口。 | `8080` |
| `UT` | **U**pdate on s**T**artup。是否在容器启动时更新 BT-Tracker 列表到配置文件。 | `true` |
| `RUT` | **R**egular **U**pdate for **T**racker。是否启用每日定时 (05:00) 通过 RPC 更新 BT-Tracker。 | `true` |
| `CTU` | **C**ustom **T**racker **U**RLs。自定义 Tracker 源地址，多个 URL 用逗号 `,` 分隔。 | (未设置) |
| `TRACKER_SHOW` | 控制启动时 Tracker 列表的输出模式。`count`: 只显示数量；`list`: 显示完整列表。 | `count` |

---

### 路径自定义

所有核心路径都支持通过环境变量覆盖，方便用户将数据存储在任何位置。

**注意**: 修改这些路径时，请确保 Docker 的卷挂载 (`volumes`) 与之对应。

| 变量 | 描述 | 默认值 |
| :--- | :--- | :--- |
| `DOWNLOAD_PATH` | 下载文件的根目录。 | `/downloads` |
| `CONFIG_DIR` | 所有配置文件的根目录。 | `/config` |
| `LOG_DIR` | 所有日志文件的存储目录。 | `${CONFIG_DIR}/logs` |
| `SETTING_FILE` | 功能脚本的配置文件路径。 | `${CONFIG_DIR}/setting.conf` |
| `ARIA2_CONF` | Aria2 的主配置文件路径。 | `${CONFIG_DIR}/aria2.conf` |
| `FILTER_FILE` | 内容过滤规则文件路径。 | `${CONFIG_DIR}/文件过滤.conf` |
| `SESSION_FILE` | Aria2 会话文件路径。 | `${CONFIG_DIR}/aria2.session` |
| `DHT_FILE` | DHT 数据文件路径。 | `${CONFIG_DIR}/dht.dat` |
| `BAK_TORRENT_DIR` | 种子文件备份目录。 | `${CONFIG_DIR}/backup-torrent` |
| `MOVE_LOG` | 文件移动日志路径。 | `${LOG_DIR}/move.log` |
| `RECYCLE_LOG` | 文件回收站日志路径。 | `${LOG_DIR}/recycle.log` |
| `DELETE_LOG` | 文件删除日志路径。 | `${LOG_DIR}/delete.log` |
| `CF_LOG` | 内容过滤日志路径。 | `${LOG_DIR}/文件过滤日志.log` |

---

### Aria2B 增强功能 (可选)

Aria2B 是一个辅助进程，用于屏蔽吸血客户端等。

| 变量 | 描述 | 默认值 |
| :--- | :--- | :--- |
| `A2B` | 是否启用 Aria2B 进程。 | `false` |
| `A2B_DISABLE_LOG` | 是否静默运行 Aria2B (不输出日志)。 | `false` |
| `CRA2B` | **C**ron **R**estart **A**ria**2B**。定时重启 Aria2B 的周期。`false` 可禁用，或设为 `Nh` (N=1-24)。 | `2h` |

---

### Docker Compose 示例

一个包含了常用配置的 `docker-compose.yml` 示例片段：

```yaml
services:
  aria2:
    image: superng6/aria2:a2b-latest
    container_name: aria2
    network_mode: host
    environment:
      # 核心运行与权限
      - TZ=Asia/Shanghai
      - PUID=1000
      - PGID=1000
      # Aria2 核心参数
      - SECRET=your_strong_secret
      - PORT=6800
      - BTPORT=32516
      - CACHE=512M
      # 功能开关
      - WEBUI=true
      - WEBUI_PORT=8080
      - UT=true
      - RUT=true
      - TRACKER_SHOW=count
      # Aria2B (如果需要)
      - A2B=true
      - CRA2B=6h
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    restart: unless-stopped
```
