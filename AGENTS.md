# 仓库贡献指南

## 从哪里开始

按任务阅读相关文件，无需每次通读仓库。用户可见行为查 [PRD](docs/PRD.md)，启动、配置及事件契约查 [开发 Spec](docs/DEVELOPMENT_SPEC.md)，测试场景查 [tests/README.md](tests/README.md)。修改时先看目标文件、直接调用方和对应测试；文档与代码不一致时，以当前代码和测试核实后同步文档。

## 目录与实现边界

`Dockerfile` 和 `build.sh` 构建 `standard`、`a2b` 两种镜像。`root/` 是容器 overlay：`root/etc/cont-init.d/` 依序初始化，`root/etc/services.d/` 定义 s6 服务，`root/aria2/conf/` 存模板，`root/aria2/scripts/` 存事件入口与 `lib/`。`tests/cases/`、`tests/lib/`、`tests/fixtures/` 分别放场景、辅助函数和本地夹具。

项目使用 s6-overlay v2；保持初始化数字顺序和 `services.d` 布局。文件处理开关以 `/config/setting.conf` 为准，后续 hook 重新读取；`aria2.conf` 的部分 key 会在启动时被环境变量覆盖。事件路径先确定 completed/recycle 目标，再查询 RPC 和计算任务源路径。保留 `/downloads` 根目录及 `completed`、`recycle`、`move-failed` 共享目录保护。

## 开发与验证

```bash
bash tests/lint.sh
./build.sh standard
bash tests/run.sh superng6/aria2:latest standard
./build.sh a2b
bash tests/run.sh superng6/aria2:a2b-latest a2b
```

`build.sh all` 可构建两种变体；`tests/run.sh <镜像> <变体> --list` 列出场景，末尾改为 `lib:paths` 等名称可只运行一个。容器测试前先构建当前工作区镜像。脚本改动至少运行 `tests/lint.sh`（Bash 语法、ShellCheck、自检和 diff 检查）；用户可见行为还需运行相关容器场景。宿主需 Bash、Docker，静态检查需 ShellCheck。

## 代码与测试约定

沿用周围 Bash 代码的缩进和命名；变量展开加引号，公共函数及跨库变量使用大写名称，局部变量使用小写。被 `source` 的库用 `${BASH_SOURCE[0]}` 定位自身。编写或修改代码时，注释统一使用中文；为函数、复杂分支和易误解的边界说明目的与原因，命令、配置键及专有名词保留原文。避免逐行复述显而易见的操作，也不要顺手格式化或重构无关文件。

确定性规则放 `tests/cases/library.sh` 或 `boundaries.sh`；下载、暂停、删除、配置升级等用户流程放 `lifecycle.sh` 或 `configuration.sh`。真实场景通过 aria2 RPC、正式 hook 或容器重启触发，以 `abc` 身份运行，使用本地夹具和有上限的条件轮询；不要直接 source 生产库或手写生产全局变量来代替用户流程。

## 提交与安全

近期提交标题使用 `fix:`、`test:`、`refactor:`、`docs:`、`ci:` 等前缀。拉取请求说明行为变化、受影响变体及验证命令；相关 issue 存在时附链接。不要提交 token、用户配置或下载数据；对外开放 RPC 前替换公开默认值 `SECRET=yourtoken`。
