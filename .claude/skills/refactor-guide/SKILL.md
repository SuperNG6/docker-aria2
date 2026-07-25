---
name: refactor-guide
description: docker-aria2 项目的修改与评审入口。修改 root、Dockerfile、CI、测试或讨论设计时使用；项目事实和约束统一以 CLAUDE.md 为准。
disable-model-invocation: false
---

# docker-aria2 修改入口

本文件只负责让工具发现项目指南，不重复维护架构和规则。

执行任务前必须完整读取仓库根目录的 `../../../CLAUDE.md`，并以它作为唯一权威来源。若本文件、代码注释和 `CLAUDE.md` 不一致，先核对实际代码，再更新 `CLAUDE.md`，不要在本文件复制新规则。

## 工作方式

1. 读取目标文件、直接调用方和对应测试。
2. 遵守用户明确范围，不顺手扩大重构。
3. 只在真实不确定边界增加防护；容器内受控路径保持简单。
4. 修改脚本后运行 `bash -n`、ShellCheck 和相关测试。
5. 评论使用中文，解释原因而非复述代码。

## 评审输出

列改动建议时说明现状、实际问题、最小修改、测试影响和风险；区分真实风险与理论上的完整性。

## 测试

### 语法预检

```bash
bash -n .github/scripts/rpc-integration-test.sh
bash -n .github/scripts/in-container-lib-test.sh
bash -n root/aria2/scripts/lib/*.sh
bash -n root/etc/cont-init.d/*-* root/etc/services.d/*/run
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/Build Image.yml'))"
```

### ShellCheck

```bash
shellcheck --severity=warning -x \
  root/aria2/scripts/lib/*.sh \
  root/aria2/scripts/*.sh \
  root/etc/cont-init.d/*-* \
  root/etc/services.d/*/run \
  .github/scripts/*.sh \
  build.sh
```

### 宿主侧 RPC 集成测试

脚本：`.github/scripts/rpc-integration-test.sh`

```bash
.github/scripts/rpc-integration-test.sh <host> <port> <secret> [container-name] [variant]
```

覆盖重点：

* RPC 服务连通
* aria2.conf 中 `FA` / `SMD` / `BTPORT` 的项目默认值
* `move-task=true` 时下载完成 hook 的 MOVE 端到端行为

aria2 原生 RPC、磁力、torrent、pause/unpause 等能力由上游保证，不在本项目重复测试。

### 容器内 lib 单元测试

脚本：`.github/scripts/in-container-lib-test.sh`

```bash
docker cp .github/scripts/in-container-lib-test.sh aria2-local:/tmp/
docker exec aria2-local bash /tmp/in-container-lib-test.sh
```

覆盖重点：

* filter
  * 是否按任务目录的真实文件数决定多文件过滤，不依赖 aria2 hook 的文件数
  * `keyword-file` 只匹配文件名，不因任务目录名命中而删光任务
  * 正则配置兼容模板历史上使用的可选引号
  * 全部文件被过滤后是否正常结束，不进入移动失败回退
* move
* delete / recycle / `.aria2`
* torrent 处理
* path 计算
  * 项目保留目录不能成为任务根目录
* RRT 重复任务处理
* tracker
* aria2b HTTP / HTTPS RPC URL 选择（仅 a2b 变体）
* config 升级保留
* 启动信息横幅（首次配置、已有配置和 SECRET 防泄漏）
* log demo

## 本地构建与 CI

```bash
./build.sh
./build.sh a2b
./build.sh all
```

触发当前分支 CI：

```bash
gh workflow run "Build Image.yml" --ref "$(git rev-parse --abbrev-ref HEAD)"
```

查看最新运行：

```bash
gh run list --workflow="Build Image.yml" \
  --branch "$(git rev-parse --abbrev-ref HEAD)" \
  --limit 3

gh run view <run-id> --log-failed
```

## 本地 smoke-test：standard

```bash
IMAGE=ghcr.io/supernng6/aria2:dev-latest

docker run -d --name aria2-local \
  -p 16800:6800 \
  -p 18080:8080 \
  -e SECRET=smoketoken \
  -e UT=false \
  -e RUT=false \
  "${IMAGE}"

.github/scripts/rpc-integration-test.sh \
  127.0.0.1 16800 smoketoken aria2-local standard

docker cp .github/scripts/in-container-lib-test.sh aria2-local:/tmp/
docker exec aria2-local bash /tmp/in-container-lib-test.sh

docker rm -f aria2-local
```

## 本地 smoke-test：a2b

```bash
docker run -d --name aria2b-local \
  --cap-add NET_ADMIN \
  -v /lib/modules:/lib/modules:ro \
  -p 16801:6800 \
  -p 18081:8080 \
  -e A2B=true \
  -e SECRET=smoketoken \
  -e UT=false \
  -e RUT=false \
  ghcr.io/supernng6/aria2:a2b-dev-latest
```
