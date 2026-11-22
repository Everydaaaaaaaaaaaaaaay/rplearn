# 学习功能开发入口

学习、测评和挑战相关的 Debug 预览与实测入口。通用的构建和预览命令见[开发速查](../development.md)。
除 `learning-test` 外，下列入口都只在 Debug 免登录内存账号中生效：不连接后端、不判分、不产生奖励、不写正式题库。
不要传入答案、解析或真实账号数据。Release 不包含这些代码。

## 首次测评与首登流程

设置页的“测试初次水平测评”直接打开正式测评第一题。“测试首次登录完整流程”从登录成功后的学习档案开始，
依次经过测评、开场剧情、选旅伴、上手练习，最后进入主页面。两个入口都使用独立的内存档案和隔离的偏好设置，
不读取登录凭证，也不访问生产服务。右上角“结束测试”返回设置页，再次进入从头开始。
正式首次建档提交后同样直接进入测评，不需要点测评邀请或介绍页按钮。

## 升星与晋升动效

入口：“我的 → 设置 → 学习实测 → 动效预览 → 升星与晋升特效”，正式题库加载期间也可进入。

```bash
Scripts/preview.sh build achievement-preview   # 构建、安装并打开动效控制页
Scripts/preview.sh preview achievement-preview # 复用已构建产物
Scripts/preview.sh preview promotion-preview   # 内存夹具：剧情、取消/确认、成功揭晓
```

- 预览直接使用正式角色学习页，显示当前城市的学习背景、所选旅伴、档位、聊天进度和挑战记录。
- 顶部“播放升星”让星星飞入卡片里的实际星槽；设置菜单可选 0 / 3 / 8 颗起始星，或运行多星边界测试；学士帽按钮播放晋升揭晓。
- 遵循系统明暗外观与减弱动态效果设置。进度服务留在内存，播放走正式回到学习页后的奖励展示路径，不写入账号。
- 实际升星只在本次挑战获得正积分回执、关闭挑战后成功读到同档位星数增长时播放；普通刷新、查看历史和切换档位不触发。
- 正式学习在九星满档时由服务端自动晋升，不需要专门的晋升题或确认。真实学习页先播放原档位第九星，再展示晋升结果；
  关闭结果页只收起展示。`promotion-preview` 只是历史手动课程的兼容预览，不是正式学习的晋升入口。

## 角色学习页与挑战题型

- 方向选择：`SIMCTL_CHILD_UI_TEST_LEARNING_PAGE_STATE=ready SIMCTL_CHILD_UI_TEST_LEARNING_DIRECTION=ielts-academic Scripts/preview.sh preview role-learning`
  检查准备中状态；`active` 检查已有挑战入口。方向切换只保存在 Debug 内存，重启重置。
- 题型：`SIMCTL_CHILD_UI_TEST_LEARNING_QUESTION=<题型> Scripts/preview.sh preview unit-challenge`，题型可选
  `choice`、`arrange`、`matching`、`completion`、`audioArrange`（听后排序）、`listeningCompletion`（听力笔记短答）、`cloze`（共享词库多空题）。
  - `listeningCompletion` 检查两词限制、超限提示，以及音频未听完时的提交门槛，不属于正式教学题。
  - 听力题沿用紧凑播放器，完整播放后才可检查；已选卡片可点回，或用辅助功能动作调整顺序。
  - `cloze` 的选空、替换和撤回可用 `Scripts/test-ui.sh -only-testing:LingoTripUITests/ChallengeLayoutUITests/testClozeSelectReplaceUndoAndLargeText` 检查普通与最大辅助字号。
- 长题面：用 `SIMCTL_CHILD_UI_TEST_LEARNING_UNIT_JSON` 传入服务端 `publicUnit` 导出的公开单元 JSON，再用
  `SIMCTL_CHILD_UI_TEST_LEARNING_QUESTION_ID` 指定题目；不指定 ID 时按 `UI_TEST_LEARNING_QUESTION` 选题型。
  同时设置 `SIMCTL_CHILD_UI_TEST_LEARNING_STORY=1` 可检查该单元的完整封面、开场故事和总题数。
  正式九年级四题型样本及来源哈希在 `Tests/LingoTripUITests/Fixtures/`，
  可用 `Scripts/test-ui.sh -only-testing:LingoTripUITests/JuniorChallengeLayoutUITests` 检查普通字号和辅助字号。
- 这些都是只读工程夹具，不计学习进度，不代表正式听力材料已审核发布；正式内容、听力和联网结算另行验收。

## 图片与真实素材

- 工程图形：`SIMCTL_CHILD_UI_TEST_LEARNING_IMAGES=1 SIMCTL_CHILD_UI_TEST_LEARNING_QUESTION=choice Scripts/preview.sh preview unit-challenge`
  显示两个本地工程图形；`matching` 检查图片配对；`UI_TEST_LEARNING_IMAGE_FAILURE=1` 让每张图首次下载失败以验证重试。
  定向路径为 `Scripts/test-ui.sh -only-testing:LingoTripUITests/LearningImageUITests`。
- 小一真实视听素材（离线）：在公开题面（`UI_TEST_LEARNING_UNIT_JSON` / `UI_TEST_LEARNING_QUESTION_ID`）上设置
  `UI_TEST_LEARNING_LOCAL_MEDIA=1` 和绝对路径 `UI_TEST_LEARNING_MEDIA_DIRECTORY=<工作树>/Backend/config/learning`。
  预览只读取题目实际引用的 `images/image.<sha256>.png` 或 `audio/audio.<sha256>.wav`，限制长度并核对摘要；
  省略目录时读取应用文档目录的 `LearningPreviewMedia/`。不要传入供应商信息。
- `Scripts/test-ui.sh -only-testing:LingoTripUITests/PrimaryChallengeMediaUITests` 读取工作树中三个小一正式单元及素材，
  验证音频实际播放结束、三张图可选、听完并选图后检查按钮解锁，以及最大辅助字号深色布局。
  它不评定人耳音质，也不验证服务器计分；不用于连接真机的测试运行。

## 任务式练习

- `Scripts/preview.sh build practice-preview` 打开离线设计夹具（不是真实测试入口），包含两篇阅读、完整完形、
  七选五和语法填空的原创样例。题型分篇作答，整篇提交后回顾；答案、标记和阅读位置保存在本机独立的
  `practice.preview.v1` 命名空间，不调用正式判分或奖励接口。答案夹具只编译进 Debug。
  七选五选项移到另一空时清除原空；离线语法未收录的表达显示待核对。
- 真实入口 `learning-test` 和正式角色练习共用 `LearningChallengeView`。完整阅读、完形、选句填空、语法填空由共享的
  `LearningPracticeScreen` 呈现，其余题型沿用同一入口内的正式控件。七选五同时呈现完整文章、全部空号和一套共用候选，
  填满本篇后统一提交，再显示服务端解析。
- 正式模式从公开题面构建页面，不含客户端答案；保留原 questionId/optionId、revision 和幂等请求。草稿与待确认命令按
  角色、attemptId、roundId 隔离保存，断网或补答只提交当前轮尚未确认的题。完成本轮仍调用正式 finish 接口和原有周期刷新回调。
  这部分改动需要构建并重启最新 App，只更新后端不会改变原生界面。
- 练习面板只有展开和收起两种状态：居中的上下楔形箭头点击切换，不响应拖动。常规展开高度固定 320pt，收起 44pt；
  键盘或小窗口下保留正文空间。作答按钮居中，略窄于选项。`LearningPracticePanelUITests` 用正式高二公开题面检查深色布局、
  B1 编号去重、点击切换，以及拖动不改变状态。
- 题面清洁规则作用于共用组件：文章编号和重复标题只在呈现层处理；听力、配对、词块和短填空也复用精确文本去重，
  只合并完全相同的说明、设问和材料，不省略不同的题意、作答限制、媒体或评分信息。

## 真实学习实测（learning-test）

Debug App 的“我的 → 设置”里有“学习实测 · 切换档位做题”，也可以直接启动：

```bash
Scripts/preview.sh build learning-test   # 源码改动后构建、安装并进入真实登录流程
Scripts/preview.sh preview learning-test # 已构建后复用产物
```

- 与免登录工程预览走不同的启动分支：强制真实鉴权，默认连接正式后端，不调用 `activateUITestWorkspace` 或
  `DebugLearningPreviewService`。已有登录态时保留账号；否则在模拟器里自行登录，不把密码传给脚本或聊天。
  只在对接隔离的真实后端时设置 `LINGOTRIP_TRIAL_BACKEND_URL`，这个变量不用于注入题目或判分。
- 可选小学一年级至高三、大学英语四级、六级、高级英语共十五档，以及账号内的真实旅伴。数量来自服务端 `learningJourney`，
  开始时再核对权威状态。切换档位和通用英语方向会真实同步到账号，只通过现有 Debug fill 接口略过聊天字数等待；
  之后复用 `LearningChallengeView` 和正式 `LearningServing` 的媒体、答题、奖励、结束和补答流程。
- 已有挑战保持原档位，跨档位时明确提示续做，不改旧快照。无题或供题耗尽时显示真实的不可用状态，不生成本地替代题。
  测试会写入真实学习记录和奖励。
- 入口流程的定向验证是 `Scripts/test.sh -only-testing:LingoTripTests/LearningTrialTests`。原判分和组卷的隔离验证可按需运行
  `Scripts/verify-backend-workflows.py --phase integration`，选择 `learning-bank.test.ts` 和 `learning-api.test.ts`。
  隔离测试与原生实测分开记录。

### 题库与验收记录

研究已按用户要求停止。既有 772 组研究作者稿中，当前主范围 634 个完整原创组（15 档、141 个档位/题型格，每格至少 3 个
完整组、5,090 个作答点）接入正式供题目录，138 组参考稿排除。真题只用于提取结构、输入和判分规则，正式填库使用独立原创稿。
入口支持选择题型和具体原创组，点“刷新题库”读取已发布目录；可抽取数量以服务器和账号已有记录为准。
完整组保留全部材料与子题，不进入固定 6/18 题抽取器；已核对的填空变体同等接受，未确认的表达不直接判错。
发布与验收边界见[原创接入记录](../verification/learning-originals-integration-20261019.json)和
[接入说明](original-groups-integration-2026-10-19.md)。

2026-10-19 已通过真实登录后的 15 档供题数量读取，以及高三 18 题挑战的听力播放门槛、两题服务器判分、各 +1 点反馈、
保存续做和跨档保护。这次人工抽查没有逐档做完整套题，也没有覆盖结束与补答的全部流程，证据和限制见
[实测验收记录](../verification/learning-trial-entry-20261019.json)。这份旧题库验收不替代本轮原创完整组验收；
本轮另外实测了小学图片/听力、填空变体、高三十空保存续做和高级四篇跨文本匹配，记录见上方原创接入记录。
