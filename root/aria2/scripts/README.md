# Aria2脚本框架 v2.0

## 概述

这是一个完全重构的Aria2脚本框架，采用模块化设计，遵循Unix哲学"做好一件事"的原则。框架提供了统一的日志记录、错误处理、文件操作和RPC通信功能。

## 目录结构

```
scripts/
├── bin/                    # 可执行脚本（Aria2回调接口）
│   ├── start.sh           # 下载开始回调
│   ├── completed.sh       # 下载完成回调
│   ├── stop.sh            # 下载停止回调
│   ├── pause.sh           # 下载暂停回调
│   └── cron-restart-a2b.sh # A2B定时重启管理
├── lib/                   # 核心库模块
│   ├── lib.sh             # 主库文件，框架入口
│   ├── util.sh            # 工具函数
│   ├── log.sh             # 日志系统
│   ├── rpc.sh             # RPC通信
│   ├── paths.sh           # 路径处理
│   ├── fsops.sh           # 文件系统操作
│   └── torrent.sh         # 种子文件处理
├── etc/                   # 配置模板
│   └── setting.conf.default
└── test/                  # 测试文件
    └── fixtures/
```

## 设计特点

### 1. 模块化设计
- 每个模块专注于单一职责
- 松耦合，便于维护和测试
- 统一的接口设计

### 2. 错误处理
- 分级错误码系统
- 详细的错误日志记录
- 优雅的错误恢复机制

### 3. 并发安全
- 使用flock保证日志写入安全
- 文件操作锁机制
- 原子性操作保证

### 4. 配置驱动
- 支持标准KEY=VALUE配置格式
- 环境变量支持
- 默认值后备机制

### 5. 调试支持
- DRY_RUN模式支持
- 分级日志输出
- 详细的操作记录

## 使用方法

### 基本使用

脚本通过Aria2的回调机制自动调用：

```bash
# 下载开始时
bin/start.sh <GID> <FILE_NUM> <FILE_PATH>

# 下载完成时  
bin/completed.sh <GID> <FILE_NUM> <FILE_PATH>

# 下载停止时
bin/stop.sh <GID> <FILE_NUM> <FILE_PATH>

# 下载暂停时
bin/pause.sh <GID> <FILE_NUM> <FILE_PATH>
```

### 配置文件

主配置文件位于 `/config/setting.conf`，支持以下选项：

- `remove-task`: 删除任务策略 (rmaria/delete/recycle)
- `move-task`: 移动任务设置 (true/false/dmof)
- `content-filter`: 内容过滤 (true/false)
- `delete-empty-dir`: 删除空目录 (true/false)
- `handle-torrent`: 种子处理策略 (retain/delete/backup/rename/backup-rename)
- `remove-repeat-task`: 重复任务检测 (true/false)
- `move-paused-task`: 暂停后移动 (true/false)

### 环境变量

框架支持以下环境变量：

- `DEBUG_MODE`: 启用调试模式
- `DRY_RUN`: 启用空运行模式
- `LOG_LEVEL`: 设置日志级别 (debug/info/warn/error)

## 开发指南

### 添加新功能

1. 确定功能属于哪个模块
2. 在相应模块中添加函数
3. 遵循现有的命名约定
4. 添加适当的错误处理和日志记录
5. 更新文档

### 错误处理约定

- 使用预定义的错误码
- 函数返回0表示成功，非0表示失败
- 记录详细的错误信息
- 提供恢复建议

### 日志记录约定

- 使用适当的日志级别
- 包含足够的上下文信息
- 避免敏感信息泄露
- 支持结构化日志格式

## 故障排查

### 常见问题

1. **权限问题**: 确保脚本有执行权限和文件访问权限
2. **RPC连接失败**: 检查Aria2服务状态和端口配置
3. **路径计算错误**: 验证下载目录配置和文件路径
4. **磁盘空间不足**: 检查目标目录的可用空间

### 调试技巧

1. 启用调试模式: `export DEBUG_MODE=true`
2. 使用空运行模式: `export DRY_RUN=true`
3. 查看详细日志: 设置日志级别为debug
4. 手动执行脚本进行测试

## 性能优化

- 使用适当的日志级别减少I/O开销
- 合理设置锁超时时间
- 定期清理旧日志文件
- 优化路径计算算法

## 安全考虑

- 验证所有用户输入
- 限制文件操作范围
- 避免命令注入风险
- 使用安全的临时文件处理

## 维护建议

- 定期运行shellcheck进行静态检查
- 监控日志文件大小
- 备份重要配置文件
- 定期更新依赖工具