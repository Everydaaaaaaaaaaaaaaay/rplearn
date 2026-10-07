# 后端部署

当前开发服务运行在 `rplearn.haruyuki.cn`，采用 Ubuntu 原生 systemd，不使用 Docker。
Caddy 是唯一公网入口；`PUBLIC_HOST` 提供 App API，`ADMIN_HOST` 仅提供受管理员鉴权保护的
AI 控制台。API、Worker、PostgreSQL 17、Redis、MinIO 和 Mailpit 均只在本机监听。

## 2026-10-07 恢复后重新上线

当前线上版本为`2677fe38`，维护资源保护与每分钟资源留档已上线；正式内容保持738道公共题、
99个模板、140段音频。保留`4e5da102`、`6093d4ce`、`0429e210`及发布前数据库备份。
恢复经过见[恢复发布记录](recovery-release-2026-10-07.md)，本次保护与验收见
[服务端预防记录](server-prevention-2026-10-07.md)。

## 2026-10-01 旧端普通聊天同步临时兼容

北京时间 07:47:40 已激活 `762d7114859e`，上一版本 `5af370ab04fd` 保留用于回滚。
旧会话下载补齐关闭的小测字段，旧端上传的已知废弃字段在入库前剥离；增量同步、幂等重放和
冲突回执同步兼容。没有新增迁移。公网隔离账号和旧版 Swift 解码验证通过，详见[验证记录](../verification/legacy-content-sync-compatibility-20261001.md)。

## 2026-10-01 Apple 登录后旅程加载兼容修复

已发布 `5af370ab04fd`，上一版本 `b87cda3da1cb` 保留用于回滚。用户资料响应补回固定为
`false` 的 `quizGloballyEnabled`，满足旧版 iOS 的必选字段解码约束。公网状态接口和旧版
Swift 解码器验证通过，未新增迁移或恢复旧小测业务。详见[验证记录](../verification/apple-login-snapshot-compatibility-20261001.md)。

## 2026-09-26 学习基础接口发布

当前后端为 `ff75b75`，上一版本 `643bc4e`。新学习事务引擎与鉴权接口已上线，迁移 0031/0032 新建学习表并按业主授权删除六张旧学习专属表；不删除聊天、档案、角色关系、收藏或剧情记录。API/Worker active，公网 readiness 正常，9 项线上 HTTP 检查通过。定向回滚备份位于服务器受限目录 `/opt/lingotrip/backups/learning-ff75b75/`。这只是新学习系统的后端基础阶段，题库、聊天计数和客户端尚待实现。完整范围、校验和及回滚边界见[验证记录](../learning-program/unit-learning-verification-2026-09-26.md)。

## 首次初始化

首次初始化时，可将后端源码放到 `/opt/lingotrip/backend`，再运行：

```bash
cd /opt/lingotrip/backend
./ops/native-server/generate-production-env.sh
./ops/native-server/bootstrap-ubuntu.sh
./ops/native-server/install-services.sh
```

`.env.production` 是不受版本控制的唯一源配置。初始化脚本把它拆分成
`/etc/lingotrip/` 下各服务可读的最小环境文件，并创建独立的数据库迁移和运行时账号。
已有配置不会自动覆盖。

## 发布

发布包在开发机编译，只包含 `dist`、当前迁移基线和生产依赖清单：

```bash
cd Backend
./ops/native-server/package-release.sh <commit>
scp build/lingotrip-backend-<commit>.tar.gz root@<server>:/tmp/
ssh root@<server> \
  "/opt/lingotrip/ops/native-server/maintenance.sh deploy /tmp/lingotrip-backend-<commit>.tar.gz <commit>"
```

线上运维脚本安装在 `/opt/lingotrip/ops/native-server`，与发布目录分开；旧 `/opt/lingotrip/backend` 链接可能指向已清理的历史目录，不能作为发布入口。发布包在独立临时目录编译，不携带已删除源码的旧编译产物或 macOS 资源分叉文件。

部署脚本会安装内容寻址的生产依赖、执行数据库迁移、收紧运行时权限、原子切换
`/opt/lingotrip/current`，然后重启 API 和 Worker 并检查 readiness。应用启动失败会切回
上一个发布目录；数据库结构不自动回滚。

默认保留已有发布目录，不在切换后集中清理旧文件。只有另行确认回滚保留范围后，才可设置
`DEPLOY_PRUNE_RELEASES=1` 恢复旧的保留最近五个目录行为。故障恢复发布使用
`DEPLOY_REQUIRE_CACHED_DEPENDENCIES=1`：缓存缺失时停止，不临时在线安装依赖。
生产更新统一经过`maintenance.sh`，直接调用`deploy.sh`也会转入该入口。生产题库CLI检测实际
cgroup与内存限制，普通SSH直接运行会拒绝。入口使用跨发布/导入的统一锁和固定systemd单元名，
即使终端断开也不会解除资源边界。已有健康版本是更新前提；没有可验证回滚版本时拒绝切换，
首次建站需先单独完成底版初始化。

维护门槛：可用内存至少384MiB、空闲磁盘至少512MiB、readiness正常，且没有持续内存/I/O阻塞。
维护任务上限256MiB、Node堆128MiB、swap为0、CPU50%、磁盘读写各2MB/s（2,000,000字节/秒）、总时限10分钟。
任务结束允许限速带来的短暂I/O压力消退，三分钟内必须获得连续一分钟稳定；健康检查连续三次失败立即结束观察。观察期间保留锁；发布在这段观察通过前仍保留回滚事务。
超时或OOM通过`ExecStopPost`恢复先前程序版本，不回退用户数据库。恢复后还须检查公网健康。
正常更新不改变内核参数，不为通过门槛临时扩大配额或关闭业务。

```bash
sudo /opt/lingotrip/ops/native-server/maintenance.sh catalog-validate
sudo /opt/lingotrip/ops/native-server/maintenance.sh bank-validate
sudo /opt/lingotrip/ops/native-server/maintenance.sh catalog-publish <完整目录哈希>
sudo /opt/lingotrip/ops/native-server/maintenance.sh bank-publish <完整题库哈希>
```

正式目录仍逐个校验所有媒体字节和审核记录，但不在返回对象中保留所有媒体Buffer；上传前再次
读取和验证，防止校验后替换。目录哈希和原子事务保持不变。CLI把阶段、耗时、RSS写入stderr，
stdout仍为原JSON结果；发布事务有5秒锁等待、30秒单语句及事务空闲超时。

`lingotrip-resource-sampler.timer`每分钟采集`/proc`资源信息与主要进程的RSS、CPU和磁盘增量，
不采集参数、环境变量或业务内容。文件位于`/var/log/lingotrip/resources.jsonl`，每份4MiB、
最多6份轮转备份，另有一份有界当前进程状态文件；原始数据留存时长取决于每条记录大小。
采样服务本身限制48MiB内存、10%CPU、10秒时限，不自动重启业务服务。

## 最近发布验证

2026-09-17（当晚）：发布 `ab144cc7`，上一版本 `output-budget-20260917-01` 保留用于回滚。
发布包 SHA-256：`41d1cb8c0c763dda08bad507369a302cc74357b88f045ad4bf38d0e174b5f6bc`。
这次把此前只推送到仓库、尚未上线的一批提交正式部署（管理后台报错统计与服务日志分区、诊断接口
对齐管理域名、辅助任务预算倍率、迁移 `0023` 把 `translation` 输出上限提到 2400 等）。
诊断读 journal 需要 systemd 组权限，因此同时把 `Backend/ops/native-server/systemd/lingotrip-api.service`
（与线上既有单元逐行一致，仅多 `SupplementaryGroups=systemd-journal`）覆盖到
`/etc/systemd/system/lingotrip-api.service` 并 `daemon-reload` + 重启 api。
API / Worker / Caddy 均 active，公网 `/health/ready` 返回 ready；`GET /internal/admin/ai/diagnostics?hours=6`
返回 200（scanned 835、summary/errors/records 均有数据），确认 journal 读取生效。

2026-09-17（当晚，模型名回退）：按业主决定，两条翻译路由从 `deepseek-flash` 改回
`deepseek-v4-flash`（`translation` v6→v7、`dictionary_example_translation` v6→v7，其余参数不变，
输出上限保持迁移 0023 后的 2400）。`AI_DEEPSEEK_ALLOWED_MODELS` 设为
`deepseek-v4-flash,deepseek-flash`：实际使用旧名，同时保留标准名可选，避免控制台选择时报 409。
直连实测旧名仍可用：HTTP 200、`model` 返回 `deepseek-flash`（由 V4.1-Flash 承载）、0.36s，
与官方定价页“旧名仍被接受、按 Flash 价计费”一致。备份：
`/etc/lingotrip/backend.env.bak-deepseek-20260917`（含第一次白名单改动前的内容）。

2026-09-17：DeepSeek 模型名对齐官方标准（无需发布新包，只改运行环境与路由）。**（当晚已按业主决定回退为 `deepseek-v4-flash`，见下方最新一条。）**
官方定价页（`https://api-docs.deepseek.com/quick_start/pricing`）现在只列 `deepseek-flash`
（DeepSeek-V4.1-Flash）与 `deepseek-v4-pro`；`deepseek-v4-flash`、`deepseek-v4-flash-vision-exp`
仍是旧名，请求会被 V4.1-Flash 承接并按 Flash 价计费，但官方要求用标准名。
操作顺序避免断档：先把 `/etc/lingotrip/backend.env` 与 `/opt/lingotrip/shared/.env.production` 的
`AI_DEEPSEEK_ALLOWED_MODELS` 设为 `deepseek-flash,deepseek-v4-flash` 并重启，再用管理 API 把两条
DeepSeek 路由改名（`translation` v4→v5、`dictionary_example_translation` v5→v6，其余参数不变），
最后把白名单收窄为 `deepseek-flash` 再重启。API / Worker active，公网 `/health/ready` 返回 ready，
重启后日志无异常；用标准名直连实测一次翻译返回 `model=deepseek-flash`、`finish_reason=stop`、0.56s。
仓库侧：迁移 `0024_deepseek_flash_model_name` 统一旧名、`AI_DEEPSEEK_ALLOWED_MODELS` 默认值改为
`deepseek-flash`、价格手册版本刷到 2026-09-17（价格行不变，旧名条目保留用于历史对账）。
备份：`/etc/lingotrip/backend.env.bak-deepseek-20260917`。

2026-09-17：发布 `output-budget-20260917-01`，上一版本 `translation-route-20260917-01` 保留用于回滚。
发布包 SHA-256：`f58c61cba86d6b3d36b490102e9b4d721f2593bb16aa16b6888fc6a6a41543a8`。
同样是基于线上 `dist` 的热修（诊断模块仍只在生产存在）：只补 `dist/modules/ai/output-budget.js`
的 GLM 输出预算下限。用户反馈词典里没有的词做 AI 解释时报「解释失败，请稍后再试」：客户端只请求
200 tokens，而 OpenRouter 上 GLM 的推理无法关闭（`Reasoning is mandatory for this endpoint`），
实测一次「kilda」解释消耗 295 completion tokens、其中 241 是推理，正文因此被截断为空，
后端记为 `AI_OUTPUT_LIMIT`。现在 `dictionary_explain` 与 `grammar_explain` 与 coach_review /
memory_summary 一样至少给 1536（仍受路由上限约束），DeepSeek 之类可关闭推理的 provider 不受影响。
该修复由 `Backend/src/modules/ai/output-budget.ts` 与其单测承载，仓库改动在提交
`Fix AI explanations truncated by GLM reasoning budget`。
API / Worker / Caddy 均 active，公网 `/health/ready` 返回 ready，重启后日志无异常。

2026-09-17：发布 `translation-route-20260917-01`，上一版本 `auxiliary-rate-20260916-01` 保留用于回滚。
发布包 SHA-256：`fceb265b3218b071f662556f997102d4846c3754aa6222c37732503c924405fa`。
本次是线上热修：本地仓库 `87939db` 的 `dist` 缺少生产 `auxiliary-rate-20260916-01` 里的
管理诊断模块（`app/request-diagnostics`、`modules/ai/diagnostics-console`、
`modules/observability/diagnostics-routes|service`、`infrastructure/journal-reader`，本地仓库没有对应
源码），直接用仓库构建包发布会丢掉该功能，因此以当前线上 `dist` 为基础，只把
`modules/ai/config-repository.js` 的任务过滤改回 `where task <> 'speech_feedback'`，再按标准
`deploy.sh` 切换发布。无新增迁移，依赖键未变（复用既有 `node_modules`）。API / Worker / Caddy
均 active，公网 `/health/ready` 返回 ready；管理员 API `/internal/admin/ai/routes` 返回 10 条路由，
含 `translation`（openrouter / z-ai/glm-5.3-flash，v2）与 `dictionary_example_translation`
（同模型，v3），两者可分别编辑并参与一键切换。
该待办已在 2026-09-17 解决：生产独有的诊断模块源码（`app/request-diagnostics`、`modules/ai/diagnostics-console`、`modules/observability/diagnostics-routes|service`、`infrastructure/journal-reader`）此前只存在于生产 `dist`，合并本地 `main`（`e1a3819`）后已回到仓库，用仓库构建的发布包不再因此丢功能。

2026-09-11：发布 `f4977bb`，上一版本 `8b2ef54` 保留。发布包 SHA-256：
`aa63029d61fe3de2bdfbc68feb5dcd3393d9e982a8478c0cd7ab511c1d2f478e`。
GLM 聊天改为 minimal 思考、总输出预算下限 512（受路由上限约束）；空正文记为失败并由服务承担。
API / Worker active，公网 readiness 正常。使用当前发布的真实 OpenRouter 流式适配器验证，
收到非空正文及 done，实际输出 30 tokens。无新增数据库迁移。
详见[空回复修复记录](../chat-empty-reply-fix-2026-09-11.md)。新版 iPhone 13 开发包已覆盖安装成功。

2026-09-11：发布 `8b2ef54`，上一版本 `c36296c` 保留用于回滚。发布包 SHA-256：
`e978bc6c87150e63861328c96f96fc61e235f3e2873e904a808c5e8ad7b45709`。
此次只改 OpenRouter 会话粘性路由，无新增迁移或生产依赖；API / Worker 均 active，
公网 `/health/ready` 返回 ready。对当前发布的客户端模块注入模拟 fetch，验证跨轮 session_id
一致及缓存 token 解析正常，未追加真实供应商调用。此前 8 次 GLM 缓存对照见
[费用优化与缓存实测](../ai-cost-optimization-2026-09-11.md)。
小测合并、记忆策略及提示词重排仍需安装新版 iOS App。

2026-09-11：发布 `c36296c`，上一版本为 `credit-fix-30fa8b4`。发布包 SHA-256：
`66fd7928d253ee3a74685d053b94368d28adf9f4d79a0305adb3da8b87468cf4`。
此次无迁移文件变更，沿用现有生产依赖。API / Worker 均为 active，readiness 返回 ready。
在已登录的 Chrome 页面 `https://coovingo.com/internal/admin/ai` 刷新数据后，
确认任务路由只剩 9 项，不再显示整句翻译和语音反馈；其他任务仍使用 GLM 5.3 Flash。
语音反馈的旧客户端请求会在模型调用与额度操作前被拒绝，历史账单和配置记录保留。
这次上线的是后端；Apple 本地整句翻译和客户端点评卡移除需安装新版 iOS App。

## 数据保护

保留现有账号、媒体和迁移历史；服务端迁移只追加，SwiftData 使用版本化迁移。
迁移失败停止发布并保留原库，不能以清库恢复。破坏性操作需单独明确授权和可恢复备份。
隔离测试环境可使用一次性数据库，不能连接开发或生产数据。

备份、恢复与线上开关的实际状态需在部署任务中核实；历史“尚无真实用户”的假设不再作为
重置数据或跳过兼容的依据。

## 日常检查

```bash
systemctl status lingotrip-api lingotrip-worker lingotrip-caddy \
  lingotrip-minio lingotrip-redis postgresql
journalctl -u lingotrip-api -u lingotrip-worker --since -1h
curl --fail https://rplearn.haruyuki.cn/health/ready
```

Mailpit 用于捕获开发邮件。Apple 登录和计费是否启用以部署环境为准；启用前核实外部凭据。密钥、完整
环境文件和用户内容不得进入 Git、命令参数、聊天记录或日志。

启用原生 Apple 登录前，在 Apple Developer 中为 App ID 打开 Sign in with Apple，并创建对应
私钥。服务器环境至少填写 `APPLE_CLIENT_IDS`、`APPLE_TEAM_ID`、`APPLE_KEY_ID`、
`APPLE_PRIVATE_KEY_BASE64`、`APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64` 和
`APPLE_CREDENTIAL_KEY_VERSION`，再将 `APPLE_AUTH_ENABLED` 设为 `true`；纯原生 iOS 登录不填
`APPLE_REDIRECT_URI`。加密密钥和版本需要随备份保留，轮换前必须保证旧版本仍可解密。
发布后分别用新 Apple 账号、隐藏邮箱账号、已有邮箱账号的显式绑定、另一设备会话撤销、
解除 Apple 登录和 App 内删除账号做真机验收；不得把模拟器或替身测试当作 Apple 线上验收。

## NPC 图库与后台补齐

已验收头像以内容哈希命名存放在 `/srv/lingotrip/npc-avatars`，由 Caddy 的 `/npc-avatars/*` 路由提供公开 HTTPS 图片与长期 immutable 缓存。该目录只放公开 PNG；清单、来源记录和测试状态保存在非公开目录。图片上传后逐张校验 SHA，先确认公开 URL 可用，再导入清单；已有同名文件哈希不符时应拒绝覆盖。

```bash
# 在服务器上运行，环境值只由 Node 读取，不展开到命令参数。
/opt/lingotrip/runtime/bin/node \
  --env-file=/etc/lingotrip/backend.env \
  --env-file=/etc/lingotrip/release.env \
  /opt/lingotrip/current/dist/cli/import-npc-avatars.js /absolute/manifest.json
```

导入在同一数据库事务中唤醒待匹配请求。新版 `lingotrip-worker` 每分钟处理到期队列；App 登录进入前台后自动领取绑定结果。服务器发布不会替用户安装新版 iOS 客户端。

2026-09-06 的 0006/0007 迁移只新增图库画像、匹配记录、待匹配表及调整头像共享索引；既有 29 个账号未重置。该次临时数据库快照与旧 Caddy 配置保留在 `/opt/lingotrip/migration-backups/npc-6f307a4-20260906`。旧程序启动要求迁移数量完全一致，因此另备了 `/opt/lingotrip/releases/npc-6f307a4-fallback`（原程序配合当前迁移文件）的回退包；普通旧发布目录不能在新迁移后直接重启。该回退包仅适用于本次兼容的迁移，后续发布不能机械复用。
