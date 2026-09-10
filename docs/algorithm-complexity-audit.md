# App 算法复杂度盘点

更新时间：2026-08-10

2026-09-11 注：下表保留历史盘点口径；其中 `MascotKit` 与 GLTFKit2 已从当前构建移除，吉祥物改由 2D 图片渲染。

## 范围与口径

本盘点覆盖 `App/` 编排层和 `Packages/LingoKit/Sources/` 下全部 24 个模块的自有算法。
系统框架、FluidAudio、GLTFKit2、SQLite 和 SwiftData 内部实现不展开；涉及它们时，只记录 App
侧的输入规模与调用次数。哈希表、集合和缓存查找按平均 O(1) 计算。

常用符号：

- `b`：文本、网络响应或音频数据长度；
- `n`：当前集合元素数；
- `m`：会话消息数，`a`：其中助手消息数；
- `p`：语法模式数，`s`：模式词位数，`g`：相邻词位候选分支数；
- `c`：语法候选命中数；
- `q`：分级测验候选题数，`G = 121`：IRT 后验网格点数，`r <= 12`：已答题数；
- `v/e`：剧情图的节点数和边数。

表中其余英文名称（如 `friends`、`tokens`、`samples`）直接表示对应集合的元素数。

Big-O 用来判断数据增长后的风险，不代替 Instruments。网络 RTT、模型推理、磁盘和音频设备
通常比这里的本地集合操作更耗时。

## 本轮已优化

| 路径 | 优化前 | 优化后 | 结果 |
| --- | --- | --- | --- |
| `DictKit/GrammarPointStore` | 每次递归转移扫描 token 区间判断句界；重复解析模式表达式和生成词形；候选压制最坏 O(c²) | O(b) 预建句界前缀，转移 O(1)；词形和表达式预计算；压制集合平均 O(c) | 保留固有回溯 O(p·n·g^(s-1))，去掉回溯内额外区间扫描、字符串处理和二次候选扫描 |
| `RealtimeVoiceKit/StreamingSpeechSegmenter` | 每个流式 delta 都从缓冲区起点重新找标点和单词边界，逐字符输入最坏累计 O(b²) | 只扫描新字符，累计摊销 O(b)，空间 O(l)，`l` 为未完成片段长度 | 长回复和细粒度 token 流不再随累计文本变慢；同一 delta 内仍由标点优先形成自然句 |
| `PersistenceKit/ChatStore` + `ChatFeature/ConversationReadState` | 摘要对消息做最大值、过滤、映射等多次遍历；每次 UI 未读统计 O(a) | 摘要一次 O(m) 遍历收集，时间只排序一次；未读统计二分 O(log a) | 列表刷新为 O(Σm + Σa·log a + n·log n)，重复行渲染的未读计算显著收敛 |
| `DomainKit/AdaptivePlacementEngine` | `max` 比较器重复评分同一题，并在每次评分内重新归一化后验、计算能力 | 每次选题只归一化一次后验，每个候选只评分一次；日志后验原地归一化 | 渐进复杂度仍是必要的 O(q·G)，评分次数由最多 `2(q-1)` 降为 `q`，移除大量 `exp` 和临时数组重算 |
| `DomainKit/ProactiveMessageService` | 循环查找并全串替换双空格，连续空白最坏 O(b·log b) | 一次 `split/join` 线性归一化，O(b) | 同时统一空格、换行、制表符等空白，保留引号移除与内容校验语义 |

## 模块清单

| 模块 | 主要算法与复杂度 | 结论 |
| --- | --- | --- |
| `App` | 主动消息调度排序 O(n log n)，但待发送上限固定为 2；根视图聚合多为 O(n) | 有界，无需堆或优先队列 |
| `AuthFeature` | 表单校验和状态映射 O(b)；认证本身是外部 I/O | 合理 |
| `BackendKit` | JSON 编解码、请求体和 SSE 行处理 O(b)；重试次数有上限 | 合理，网络主导 |
| `BillingKit` | 商品排序 O(n log n)，权益过期时间排序 O(n log n)，StoreKit 交易扫描 O(n) | 商品和权益集合很小，保留可读性 |
| `ChatFeature` | 会话投影使用字典/集合 O(f+s)；未读 O(log a)；消息展示与 prompt 窗口 O(m) | 已优化关键重绘路径 |
| `CoreKit` | `WordTokenizer` O(b+t)，`TokenEstimator` O(b)，`TokenCache` 命中平均 O(1) | 合理 |
| `DesignSystem` | 流式布局 O(n)；可点文本选择生成并排序少量候选，O(t log t) | token 与候选窗口小，暂不增加索引结构 |
| `DictKit` | SQLite 精确/lemma/前缀查询取决于数据库索引，返回处理 O(k)；词形回退候选有小上限；语法匹配见上表 | 语法热点已优化；数据库需用查询计划而非仅凭源码判断 |
| `DomainKit` | IRT 选题 O(q·G)，答题更新 O(G)，一致性倒置 O(r²)；关键词 O(n)+O(k log k)；记忆分层排序 O(n log n)；prompt 拼装 O(b) | 选题与清洗已优化；`r <= 12`，倒置计数不值得复杂化 |
| `FavoritesFeature` | 收藏加载、筛选和渲染 O(n) | 合理 |
| `HomeFeature` | 好友、会话、主线状态投影 O(n)，主要数据源并发加载 | 合理 |
| `LLMKit` | SSE/流式文本处理 O(b)，路由重试 O(retry·b)，重试集合固定 | 合理，模型与网络主导 |
| `MapFeature` | 地区筛选、解锁映射和标记生成 O(n) | 地区目录为小型静态集合 |
| `MascotKit` | glTF 场景加载 O(nodes+animations)，语义动画查找 O(animations) | 当前动画目录仅少量条目，无需额外索引 |
| `MediaKit` | 音频上传/下载和校验 O(b)，失败重试固定为 2，待上传队列线性处理 | 合理，I/O 主导 |
| `OnboardingFeature` | 固定步骤状态机和少量角色投影 O(n) | 有界 |
| `PersistenceKit` | ID 谓词查询由 SwiftData/SQLite 计划决定；内容变更批次上限 100；会话摘要见上表；本地同步合并通常 O(remote+local) | 已优化会话热点；大表继续依赖索引和分页 |
| `PlacementFeature` | 题目选项展示 O(options)，主要计算委托 `AdaptivePlacementEngine` | 合理 |
| `RealtimeVoiceKit` | 增量切句摊销 O(b)；识别恢复次数固定；会话文本拼接 O(b) | 切句热点已优化 |
| `RosterFeature` | 角色列表加载、分组和展示 O(n) | 合理 |
| `SettingsFeature` | 记忆调试列表 O(n)，商品/语音选项 O(n) | 用户可见集合小 |
| `SpeechKit` | 音频电平和 PCM 处理 O(samples)，系统声音选择 O(voices)，文件清理 O(files) | 必须线性读取实际数据，合理 |
| `StoryEngine` | 脚本引用校验与可达性搜索 O(v+e)，节点查找平均 O(1)，播放 O(实际路径长度) | 图算法已是最优阶 |
| `StoryFeature` | 当前节点、选项和文本 token 渲染 O(n)，语法标注委托 `DictKit` | 合理 |
| `SyncKit` | push O(commands)，pull O(changes+pages)，合并用集合去重平均 O(n)；循环由服务端游标推进终止 | 合理，分页与网络主导 |

## 明确保留的实现

- `AdaptivePlacementEngine.inversionCount` 是 O(r²)，但 `r` 被产品规则硬限制为 12，最坏只有
  66 对比较。改成 Fenwick Tree 或排序扫描会增加正确性风险，几乎没有可见收益。
- Billing、地区、吉祥物动画和主动消息队列虽然有排序或线性查找，但集合是个位数或有严格
  上限。此处保持直观实现。
- 记忆注入和 prompt 历史窗口已有 quota / suffix 限制。若未来取消上限，再考虑小顶堆或
  数据库侧 Top-K；当前不提前引入复杂结构。
- SQLite/SwiftData 查询不能仅凭调用处宣称 O(log n)。词典查询使用有序范围与精确谓词，
  但发布前若数据规模改变，仍应以 `EXPLAIN QUERY PLAN` 和 Instruments 验证索引命中。

## 后续性能门槛

出现下列任一变化时重新审计，而不是按固定周期机械重写：

- 单会话消息达到 5,000 条，或会话列表达到 500 条；
- 语法模式从约百条增长到 500 条以上，或允许的 `maximumGaps` 明显扩大；
- 分级题库超过 500 题，或 IRT 网格从 121 点提高一个数量级；
- 记忆、收藏、角色或地区列表取消当前配额；
- Instruments 显示主线程 CPU 热点超过一帧预算，或流式语音首句延迟出现随文本长度增长。
