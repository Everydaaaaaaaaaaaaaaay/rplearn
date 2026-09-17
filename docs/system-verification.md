# 功能与系统验证

验证对象是用户最终得到的结果：界面、数据库、同步副本、账本和外部副作用之间是否一致。
接口返回成功、测试数量或代码覆盖率均不能单独说明功能可靠。按受影响的用户路径选择下表中的验证；
没有实现的入口不能由底层能力测试冒充已验收。

本表是按风险选择检查的索引，不是每次提交都要全部运行的门禁。模型、支付、邮件、对象存储、
麦克风等外部边界可以在普通测试中替换，但报告必须注明替换了什么。真实学习效果仍要通过测试版
收集真实用户数据，不能用工程测试代替。

## 验证矩阵

| 功能 / 系统 | 要证明的结果与故障边界 | 当前自动验证入口 | 还需真实环境验证的边界 |
| --- | --- | --- | --- |
| 登录入口、邮箱注册、刷新、注销、旧游客兼容 | 生产必须登录；账号工作区隔离；旧游客认领不重发额度；刷新/撤销、错误凭据 | 后端 `auth`、`guest-journey`、`access`、`apple-auth` 集成；`backend-process` E2E；`BackendClientTests` | 邮件投递、Apple 登录授权界面、多账号真机切换 |
| 首启、用户资料、分级测评 | 自评/测评结果落库；路线和等级一致；重复操作幂等 | `AdaptivePlacementEngineTests`、`SelfAssessedEnglishLevelTests`、`BackendUserStateCoordinatorTests`；后端 `domain` | 新用户从安装到完成首启的 UI 路径及可理解性 |
| 文本聊天 | 输入保存后才视为发送；模型全文→气泡→本地保存→重新进入一致；空结果报错 | `ChatWorkflowTests`、`RoleplayReplyFormatterTests`、`ChatStoreTests`；后端 `ai`/`credits` | 模型答非所问、真实延迟、学习收益用独立 live/cost 工作流 |
| 聊天异常恢复 | 断网保留已收到的片段；重试失败保留旧内容；普通消息不能被重试入口删除 | `ChatWorkflowTests` 故障注入；`LLMRouterTests`、`SSEParserTests` | 系统强杀进程与真实网络切换、生成中连续发送/离开页面 |
| 语音、实时对话 | 终稿进入聊天；打断停止生成与 TTS；保存实际已听片段；录音权限/路由状态可恢复 | `RealtimeVoiceCoreTests`、`VoiceRecorderTests`、`SpeechServiceTests`、`ChatWorkflowTests` | 真机麦克风、蓝牙/扬声器回声、后台打断、模型音频质量；文字输入不算语音 E2E |
| 聊天整句翻译 | 优先云端 LLM 并持久缓存；重复点击与重新进入复用译文；云端失败回退 Apple 端上翻译，两者都失败才报错；回退队列取消可恢复 | `ChatWorkflowTests`、`TranslationServiceTests`、`AppleTranslatorQueueTests`；后端 `ai`/`credits` | 译文质量需真实样本人工审阅；真机系统语言包下载/取消、离线回退与逐句延迟；模拟器不运行翻译模型 |
| 语法、纠错、词典 | 结果保留并缓存；结构化输出和词义定位正确 | `GrammarAnalysisServiceTests`、`CoachServiceTests`、`Dict*Tests`；后端 `dictionary-translation` | 语言教学准确率需人工/真实样本审阅；词典系统翻译回退 |
| 记忆、关系、成长 | 重复处理不叠加；阈值、衰减和历史引用正确；用户之间关系隔离 | `MemoryServiceTests`、`MemorySourceTests`、`Relationship*Tests`、`CharacterGrowthEngineTests` | 长期自然对话的记忆准确性和人物一致性，不能用数值断言替代 |
| NPC、头像、好友 | 公共身份稳定；头像绑定不随重试改变；缺图可恢复；剧情旅伴不占普通好友位 | `PublicNPCAvatarCoordinatorTests`、`AvatarBadgeTests`、`RosterStoreTests`；后端 `npc`、`npc-encounters`、`access` | 头像素材真实可达性、匹配审美；活动生成与真实模型质量另验收 |
| 金币、机票、旅行、剧情奖励 | 服务器为准；重复请求不重复扣款/领奖；保留旧游客跨城限制的兼容测试；失败不吞资产 | `Economy*Tests`、`TravelServiceTests`、`LocalUserStateCoordinatorTests`；后端 `domain`、`guest-journey`、`sync` | 真机登录/切号后界面权益刷新；旧游客迁移兼容 |
| 积分、路由、订阅权益 | 普通输入/缓存/输出分开结算；并发预留不超额；未知成本保留待核对；升级不清历史支出 | 后端 `credit-pricing`、`credits`、`billing`、`ai-config`；`BillingControllerTests` | StoreKit Sandbox 购买、续期、退款、跨设备恢复；供应商账单对账 |
| 剧情阅读、选择、断点 | 分支结果/奖励与选择一致；退出再进恢复；重播不误领奖 | `StoryEpisodeTests`、`StoryPlayerTests`、`StoryProgressStoreTests`；`LondonEpisodeTests` UI | 全部新章节各自内容验收；旁白音频和字幕一致性 |
| 活动与场景 | 活动→结果→日志完整；冷却在暂停和重进后保留；返回层级正确 | `ActivityJourneyTests`、`ActivitySceneGeometryTests`、`ActivitySceneTests` UI | 联网偶遇已接入 SocialEncounterModel，真实生成与过渡影像分别验收；影像候选仍未放行 |
| 收藏、已读、置顶、设置导航 | 数据保留；已读游标不回退；往返后不丢状态；关键按钮可达 | `FavoritesStoreTests`、`ConversationReadStateTests`、`ChatStoreTests`；`MyPagePerformanceTests`、`HomeNavigationTests` UI | 全部辅助功能设置、不同屏幕尺寸与动态字体 |
| 同步、离线、冲突、墓碑 | 重试幂等；失败不丢 Outbox；回执身份匹配；坏回执恢复待发送；墓碑阻止旧数据复活 | `ContentSyncStoreTests`、`BackendContentSyncCoordinatorTests`；后端 `content`、`sync`；进程 E2E | 两台真实设备同时编辑、登出/强杀时仍在飞行的请求 |
| 本地持久化与迁移 | 旧角色/消息/记忆迁移后内容和 ID 不变；失败保留原库 | `SchemaMigrationTests`、各 Store 测试 | 真实历史库版本、磁盘满、系统强杀；内存 Store 重开 ViewModel 不等于进程重启 |
| 语音媒体 | 上传校验、授权下载、消息墓碑确认后删除、重试队列和账号隔离 | `VoiceMediaCoordinatorTests`、`VoiceMediaQueueStoreTests`、`object-store`；可选后端 `media` 集成 | 需要隔离 S3 服务验证端到端上传/下载；缺少服务时注明未测 |
| 导出、删除账号、后台任务、运维 | 导出包含本人内容；删除撤销凭据并清关联；任务租约/重试可恢复；日志不泄露隐私 | 后端 `account`、`jobs`、`audit`、`infrastructure` 集成；`backend-process` E2E；迁移/日志单测 | 真实邮件、对象删除、Apple 撤销；线上备份恢复与告警演练 |

客户端测试位于 `Packages/LingoKit/Tests`，UI 测试位于 `Tests/LingoTripUITests`。
后端默认单测位于 `Backend/test`，数据库和进程测试分别位于 `integration`、`e2e`。

## 按需执行

1. **日常改动**：按矩阵选受到影响的测试。纯格式化/算法用单测；涉及落库与失败恢复时选流程测试。
   示例：`Scripts/test.sh -only-testing:LingoTripTests/ChatWorkflowTests`。
2. **后端跨模块流程**：`python3 Scripts/verify-backend-workflows.py`。自动创建独立本地 PostgreSQL
   集群、随机端口 Redis 和 `lingotrip_test_*` 数据库，执行当前集成测试（排除媒体套件）及编译后的 HTTP 进程流程，
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
测试通过后只因代码又变更或出现新问题才重跑。live Swift 套件不属于普通验证范围。

## 结果记录

- 报告本次检查范围、通过/失败/跳过和未测边界，注明替换的外部服务。中断、零匹配或
  只有跳过不能算通过；iOS 脚本会核对 `.xcresult` 的实际执行结果。
- 保留本次日志/结果包即可，不另写重复报告。后端脚本输出到 `build/verification/<run>/`，
  iOS 默认输出到 `build/DerivedData/VerificationResults/`；自定义结果路径以参数为准。
- 缺陷用可复现输入验证修复；需要回归测试时检查所有权、幂等、资产守恒及恢复后的状态，
  避免照搬实现。模型质量评估保留原始输出与最终展示内容，区分有意纠错和意外丢失。
- 原始日志可能包含凭据和用户内容，保留在本地；仅提交脱敏摘要或必要夹具。
- 成本与学习效果使用独立的[成本工作流](user-cost-evaluation.md)。
