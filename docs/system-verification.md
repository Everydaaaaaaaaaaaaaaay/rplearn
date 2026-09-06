# 功能与系统验证

验证对象是用户最终得到的结果：界面、数据库、同步副本、账本和外部副作用之间是否一致。
接口返回成功、测试数量或代码覆盖率均不能单独说明功能可靠。新增功能必须能落到下表的一条
用户路径；没有实现的入口不能由底层能力测试冒充已验收。

本表是按风险选择检查的索引，不是每次提交都要全部运行的门禁。模型、支付、邮件、对象存储、
麦克风等外部边界可以在普通测试中替换，但报告必须注明替换了什么。真实学习效果仍要通过测试版
收集真实用户数据，不能用工程测试代替。

## 验证矩阵

| 功能 / 系统 | 要证明的结果与故障边界 | 当前自动验证入口 | 还需真实环境验证的边界 |
| --- | --- | --- | --- |
| 游客、邮箱注册、登录、刷新、注销 | 游客可登记；升级不重发已消费额度；刷新/撤销、错误凭据、账号隔离 | 后端 `auth`、`guest-journey`、`access`、`apple-auth` 集成；`backend-process` E2E；`BackendClientTests` | 邮件投递、Apple 登录授权界面、多账号真机切换 |
| 首启、用户资料、分级测评 | 自评/测评结果落库；路线和等级一致；重复操作幂等 | `AdaptivePlacementEngineTests`、`SelfAssessedEnglishLevelTests`、`BackendUserStateCoordinatorTests`；后端 `domain` | 新用户从安装到完成首启的 UI 路径及可理解性 |
| 文本聊天 | 输入保存后才视为发送；模型全文→气泡→本地保存→重新进入一致；空结果报错 | `ChatWorkflowTests`、`RoleplayReplyFormatterTests`、`ChatStoreTests`；后端 `ai`/`credits` | 模型答非所问、真实延迟、学习收益用独立 live/cost 工作流 |
| 聊天异常恢复 | 断网保留已收到的片段；重试失败保留旧内容；普通消息不能被重试入口删除 | `ChatWorkflowTests` 故障注入；`LLMRouterTests`、`SSEParserTests` | 系统强杀进程与真实网络切换、生成中连续发送/离开页面 |
| 语音、实时对话 | 终稿进入聊天；打断停止生成与 TTS；保存实际已听片段；录音权限/路由状态可恢复 | `RealtimeVoiceCoreTests`、`VoiceRecorderTests`、`SpeechServiceTests`、`ChatWorkflowTests` | 真机麦克风、蓝牙/扬声器回声、后台打断、模型音频质量；文字输入不算语音 E2E |
| 翻译、语法、纠错、词典 | 结果保留并缓存；失败可回退；结构化输出和词义定位正确 | `TranslationServiceTests`、`GrammarAnalysisServiceTests`、`CoachServiceTests`、`Dict*Tests`；后端 `dictionary-translation` | 语言教学准确率需人工/真实样本审阅；系统翻译资源下载 |
| 记忆、关系、成长 | 重复处理不叠加；阈值、衰减和历史引用正确；用户之间关系隔离 | `MemoryServiceTests`、`MemorySourceTests`、`Relationship*Tests`、`CharacterGrowthEngineTests` | 长期自然对话的记忆准确性和人物一致性，不能用数值断言替代 |
| NPC、头像、好友 | 公共身份稳定；头像绑定不随重试改变；缺图可恢复；剧情旅伴不占普通好友位 | `PublicNPCAvatarCoordinatorTests`、`AvatarBadgeTests`、`RosterStoreTests`；后端 `npc`、`npc-encounters`、`access` | 头像素材真实可达性、匹配审美；重做中的活动生成入口另验收 |
| 金币、机票、旅行、剧情奖励 | 服务器为准；重复请求不重复扣款/领奖；游客不能跨城；失败不吞资产 | `Economy*Tests`、`TravelServiceTests`、`LocalUserStateCoordinatorTests`；后端 `domain`、`guest-journey`、`sync` | 真机游客→登录后界面权益刷新 |
| 积分、路由、订阅权益 | 普通输入/缓存/输出分开结算；并发预留不超额；未知成本保留待核对；升级不清历史支出 | 后端 `credit-pricing`、`credits`、`billing`、`ai-config`；`BillingControllerTests` | StoreKit Sandbox 购买、续期、退款、跨设备恢复；供应商账单对账 |
| 剧情阅读、选择、断点 | 分支结果/奖励与选择一致；退出再进恢复；重播不误领奖 | `StoryEpisodeTests`、`StoryPlayerTests`、`StoryProgressStoreTests`；`LondonEpisodeTests` UI | 全部新章节各自内容验收；旁白音频和字幕一致性 |
| 活动与场景 | 活动→结果→日志完整；冷却在暂停和重进后保留；返回层级正确 | `ActivityJourneyTests`、`ActivitySceneGeometryTests`、`ActivitySceneTests` UI | 正在重做的联网偶遇路径不算已验证的当前功能 |
| 收藏、已读、置顶、设置导航 | 数据保留；已读游标不回退；往返后不丢状态；关键按钮可达 | `FavoritesStoreTests`、`ConversationReadStateTests`、`ChatStoreTests`；`MyPagePerformanceTests`、`HomeNavigationTests` UI | 全部辅助功能设置、不同屏幕尺寸与动态字体 |
| 同步、离线、冲突、墓碑 | 重试幂等；失败不丢 Outbox；回执身份匹配；坏回执恢复待发送；墓碑阻止旧数据复活 | `ContentSyncStoreTests`、`BackendContentSyncCoordinatorTests`；后端 `content`、`sync`；进程 E2E | 两台真实设备同时编辑、登出/强杀时仍在飞行的请求 |
| 本地持久化与迁移 | 旧角色/消息/记忆迁移后内容和 ID 不变；失败保留原库 | `SchemaMigrationTests`、各 Store 测试 | 真实历史库版本、磁盘满、系统强杀；内存 Store 重开 ViewModel 不等于进程重启 |
| 语音媒体 | 上传校验、授权下载、消息墓碑确认后删除、重试队列和账号隔离 | `VoiceMediaCoordinatorTests`、`VoiceMediaQueueStoreTests`、`object-store`；可选后端 `media` 集成 | 本轮缺少隔离 S3 服务；端到端对象上传/下载不计作通过 |
| 导出、删除账号、后台任务、运维 | 导出包含本人内容；删除撤销凭据并清关联；任务租约/重试可恢复；日志不泄露隐私 | 后端 `account`、`jobs`、`audit`、`infrastructure` 集成；`backend-process` E2E；迁移/日志单测 | 真实邮件、对象删除、Apple 撤销；线上备份恢复与告警演练 |

客户端测试位于 `Packages/LingoKit/Tests`，UI 测试位于 `Tests/LingoTripUITests`。
后端默认单测位于 `Backend/test`，数据库和进程测试分别位于 `integration`、`e2e`。

## 按需执行

1. **日常改动**：按矩阵选受到影响的测试。纯格式化/算法用单测；涉及落库与失败恢复时选流程测试。
   示例：`Scripts/test.sh -only-testing:LingoTripTests/ChatWorkflowTests`。
2. **后端跨模块流程**：`python3 Scripts/verify-backend-workflows.py`。自动创建独立本地 PostgreSQL
   集群、随机端口 Redis 和 `lingotrip_test_*` 数据库，执行 18 组集成测试及编译后的 HTTP 进程流程，
   最后停掉自建服务。失败时保留数据库和日志，不接触开发/生产数据库。
   `--phase integration` / `--phase e2e` 可单独选择；`--test test/integration/credits.test.ts`
   可只重跑失败领域。常规执行不包括真实供应商、S3 媒体及 NPC 素材库基准。
3. **客户端全量基线**：`Scripts/test.sh -only-testing:LingoTripTests`。显式 live 套件跳过要单列，
   不计作通过。测试宿主默认连接本地不可用端口，防止后台任务使用线上网关。
4. **UI 路径**：通过 `LingoTripPerformanceTests` scheme 运行指定 `LingoTripUITests/<Suite>/<test>`。
   使用 `Scripts/test-ui.sh` 复用构建锁与专用模拟器选择。普通 UI 测试固定本地网关，验证离线流程，
   不能由此宣称实际登录、购买或模型能力通过。
5. **发布/大检查**：根据本次版本涉及的领域组合上述路径；真实邮件、StoreKit、语音、S3、跨设备
   单独出具记录。只阻止受影响且尚未验证的功能发布，不把所有历史测试变成每次提交的门禁。

iOS 执行前指定测试用 `LINGOTRIP_SIMULATOR_UDID`，不要借用用户正在使用的模拟器。
测试通过后只因代码又变更或出现新问题才重跑。四个 live Swift 套件不属于默认测试。

## 结果与追踪约定

- 一次运行记录源码提交、工作区差异、环境、选择的测试、替换的外部服务、通过/失败/跳过、耗时。
  后端入口在 `build/verification/<run>/report.json` 持续记录阶段状态，另存 Vitest JSON 和日志；
  iOS 使用 `.xcresult` 保留断言、截图及运行设备。目录必须为本次新建，避免把旧结果算作新结果。
- iOS 入口读取结果包核对实际执行数量；筛选没有匹配到测试，或只执行了被跳过的 live 套件，
  即使 Xcode 返回 0 也判为验证失败。新结果位于 `build/DerivedData/VerificationResults/`；
  用户显式传入 `-resultBundlePath` 时保留其路径。
- 运行中断或超时记录为中断/失败；部分通过、跳过、没接上真实外部服务均不写成全量通过。
- 每个确认缺陷先留下可复现输入和失败断言，再修复并做针对性复测。测试不照搬现有实现的数值或
  分支作为正确答案，要检查内容守恒、ID/所有权、资产守恒、幂等、恢复后状态等不变量。
- 模型质量测试同时保存原始输出和最终显示/保存文本；排版不能删语义。需注意安全拒绝、纠错、
  质量重生成等有意替换不能被简单等值比较误报。
- 测试失败的日志可能含合成凭据或用户内容。原始资料保持本地私有；提交只包含脱敏摘要与必要夹具。
- 真实使用成本、学习收益、转化和续费沿用独立实验，参考 [成本工作流](user-cost-evaluation.md)。
