# 行为回归测试

测试保护文件和配置的用户可见结果。预期路径与内容写在场景中，不调用生产函数计算正确答案。
aria2c 是上游组件，不是被测对象：场景只用它产生真实的事件、hook 参数和 RPC 状态，
被测的是本项目的封装（环境变量、配置、身份、服务）、hook 文件处理，以及用户经 RPC 操作时的结果。

## 运行

先通过项目构建入口生成包含当前修改的镜像：

```bash
bash build.sh standard
bash tests/lint.sh
bash tests/run.sh superng6/aria2:latest standard

# 列出或只运行一个场景
bash tests/run.sh superng6/aria2:latest standard --list
bash tests/run.sh superng6/aria2:latest standard reserved
bash tests/run.sh superng6/aria2:latest standard lib:paths

bash build.sh a2b
bash tests/run.sh superng6/aria2:a2b-latest a2b
```

宿主需要 Bash、Docker 和 openssl（`rpc-tls` 临时生成自签证书，私钥不进仓库）；静态检查还需要 ShellCheck。
测试使用镜像里的 GNU 工具、aria2 和真实 `/init`。
不挂载用户的下载目录、不使用现有容器、不发布宿主端口。每个场景新建一个容器与匿名卷，退出时删除。
场景之间互不共享状态，默认 4 个并行（`TEST_JOBS` 调整）；含 30 秒暂停等待的慢场景最先启动。
两个变体默认用本机架构；CI 用 `TEST_PLATFORM=linux/amd64` 明确指定。ARM 的 CI smoke-test 保留原编排。

失败时打印场景名、断言、预期/实际值，并保存场景输出、容器日志、文件清单和项目磁盘日志。
通过 `TEST_ARTIFACTS=/tmp/aria2-results` 固定输出目录；默认放在本机临时目录。不要对正常日志逐字快照。
本地没有 Docker 或缺少镜像时直接失败，不降级为模拟测试。

## 分工与行为约定

| 测试 | 触发方式 | 必须成立 |
|---|---|---|
| `identity` | `/init` 正常启动 | abc 身份、配置可写、四种正式 hook 已注册 |
| `http` | 本地 HTTP 完成、热修改配置、再次下载 | 先留后移，内容完整，分类目录兄弟文件不变 |
| `filter-partial` | 真实多文件 BT 完成 | 扩展名与关键词重复命中只删目标文件，剩余内容完整 |
| `filter-all` | 多条规则合计匹配全部文件 | 整次过滤及空目录清理跳过，仍正常移动 |
| `selected` | BT 只选第一个文件 | 正确处理选中内容的任务路径，不重复测试 aria2 原生选择算法 |
| `single-bt` | 自定义目录、尾斜杠、单文件 BT，再从 completed 续种 | 只移动单文件，分类目录其他内容保留；续种完成后不嵌套移动 |
| `cross-device` | completed 挂载为独立 tmpfs | 真实跨文件系统移动后内容完整、所有者正确 |
| `move-failure` | completed 对 abc 不可写 | 原任务完整移动至 move-failed 并记录原因 |
| `repeat` | completed 中已有相同任务目录 | 新任务被取消，旧副本保持完整 |
| `pause-move` | 暂停→恢复→再暂停并保持暂停 | 延迟后只移动一次，内容完整，清理旧控制文件，不记录移动失败 |
| `pause-disable` / `pause-resume` | hook 等待期间关闭功能或恢复任务 | 整个观察窗口内原文件与控制文件保留 |
| `recycle` / `delete` | RPC 删除活动任务 | 按配置回收或删除，记录结果，不触碰无关文件 |
| `recycle-failure` | 回收目标不可写、RPC 删除任务 | 遵守项目已接受的永久删除退路，并记录日志 |
| `reserved` | 下载目录带尾斜杠、BT 根目录叫 completed | 停止时不得整体操作历史共享目录 |
| `config-upgrade` | 精简非默认配置、真实重启同一容器 | 用户值保留、新键补齐、键唯一、仍可写 |
| `http-nested` | HTTP 下载到多级、带特殊字符的分类子目录 | 移动后空子目录逐级清理，仍有内容的分类目录保留 |
| `complex-bt` | 多级目录、中文/方括号/逗号/单引号名称的 BT 完成 | 结构完整移动，过滤与空目录清理正确 |
| `magnet` | 零配置用户添加磁力链接（本地做种端 + 静态 tracker） | 元数据接续为下载任务；默认不移动、种子按任务名备份、无残留控制文件 |
| `stop-inactive` | `remove-task=delete` 下删除活动任务、已暂停任务、已完成记录 | 只有活动任务触发删除；后两种 aria2 不发事件，文件保持原位 |
| `ownership-root` / `ownership-custom` | `PUID/PGID` 为 0 或 1234 | aria2c 身份、配置与移动后文件所有者均为指定值 |
| `hook-registration` | 用户自带 aria2.conf 缺 hook 行、hook 指向别处、末尾无换行，再重启 | 托管键补齐且唯一，用户注释保留，真实完成事件触发 hook |
| `rpc-tls` | 开启 `rpc-secure` 后重启 | 明文 RPC 关闭，hook 经 HTTPS 回退仍完成移动 |
| `a2b-restart`（仅 a2b） | root 执行 crontab 中的 aria2b 定时重启命令 | 间隔符合 `CRA2B`，aria2b 重启而 aria2c 不受影响 |
| `lib:*` | abc 调用正式库函数 | 过滤边界（含 min-size 字节比较与 CRLF 规则）、路径等价、种子模式、tracker JSON、横幅脱敏、a2b 协议 |
| `lib:config-failure` | 仅替换 cp，模拟写失败留下空临时文件 | 正式 SED_CONF 返回失败，旧配置字节不变 |
| `lib:move-fallback` | 目标目录位于不可创建的位置 | 任务移入 move-failed，日志写明无法创建目标目录而非空间不足 |
| `lib:config-crlf` | CRLF 行尾的 setting.conf | 开关与横幅识别用户值，升级合并后不残留 CR |

所有生命周期文件场景额外检查两个无关哨兵文件，防止“目标正确、旁边全删了”。
库层允许构造生产全局变量、替换外部故障边界；生命周期层只使用 RPC、配置编辑和容器重启。
每个规则组单独启动 Bash，避免跨组全局变量污染。汇总数字是独立场景/规则组，不是断言数量。

## 验证测试确实有用

```bash
bash tests/mutate.sh superng6/aria2:latest standard
```

宿主额外需要 Python 3。待测镜像必须由当前工作区构建。
脚本依次取消共享路径保护、将升级改为默认覆盖、取消全文件过滤保护、忽略暂停开关、
把 HTTP 文件移动改成移动父目录、不追加缺失的 hook 行、不清理空父目录、种子备份不按任务名重命名。每项先验证正常镜像通过，再向专用容器复制有错误的文件。
对应场景必须输出明确失败断言；Docker 启动失败或脚本语法错误不算捕获成功。
工作区不会被修改。此项用于修改测试后的人工验收，常规 CI 不重复运行慢场景。

新增场景先写“用户操作、应该改变什么、绝不能改变什么”，再准备最小夹具。
不要为了增加 PASS 数量拆分字段断言，也不要给每个生产函数机械配一个同构测试。

## 夹具

`fixtures/multi.torrent` 包含 `fixture-task/keep.mp4`（`KEEP\n`）和
`fixture-task/remove.txt`（`REMOVE\n`）；`reserved.torrent` 仅将根目录改为 `completed`；
`single.torrent` 包含 `single.iso`（`SINGLE\n`）；`complex.torrent` 的根目录为 `[字幕组] 名字 Vol.1, 测试's`，
包含 `Season 1/第01集 [1080p].mkv`（`EPISODE1\n`）、`Season 1/Extras/说明.txt`（`README\n`）和
`Season 2/第01集.mkv`（`EPISODE2\n`），内容由场景写入。所有 piece length 为 16384，
piece hash 为顺序拼接内容的 SHA-1，announce 指向本地不可用端口。
完成场景预置正确内容，让真实 aria2 校验后触发 hook；活动场景由 aria2 自己创建文件。
HTTP 场景通过本容器 AriaNg 获取固定页面，不访问公网。
磁力场景在容器内另起一个不读配置的 aria2c 做种（端口 51413），并把 compact peer 列表写成
WebUI 下的静态 `announce` 文件充当 tracker，全程离线。
