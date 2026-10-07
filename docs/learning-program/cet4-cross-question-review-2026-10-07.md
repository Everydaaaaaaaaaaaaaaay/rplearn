# 四级正式库跨题提示泄漏人工审计（2026-10-07）

结论：亲读当前两个正式单元的全部 36 题、六段开场故事和组卷实现后，发现一组需要处理的**先教答案词、再填同一词**风险：`cet4.astra.a16 → cet4.astra.a10` 的 because。它在现有混卷规则下可实际出现，不能因原文件中 a16 排在 a10 后面而忽略。未发现其他题直接提供完整听写答案句、完整排序答案句，或 postponed、require、usually/normally 等受控输入答案的情况。没有将共用语法关系、普通词汇或一段相同礼貌套语都判作直接泄漏。

本次只写审计文档，没有修改正式库、生成新题、提交或访问线上。结论不表示题库已获得独立测量效度认证。

## 审计范围和依据

实际逐题读取下列 JSON 全字段，包括题面、选项/词块/匹配两侧、提示、解析、答案、同义变体、录音脚本和故事中英文本：

- `Backend/config/learning/units/companion.undergraduate.clear-messages.json`：18 题，故事“被风吹乱的下午”。
- `Backend/config/learning/units/companion.undergraduate.small-mountain.json`：18 题，故事“盘子里的小山”。

同时读取 `Backend/config/learning/bank.json`、`Backend/src/modules/learning/bank-catalog.ts`、`Backend/src/modules/learning/bank-content.ts`，并核对 `content.ts` 的公开题面投影。程序检索只辅助定位，下面的语义判断由作者逐题完成。本轮没有播放音频，音频部分是对已存 `audio.text` 及其可揭示内容的审计，不声称完成真人听感验收。

公开题面投影只提供音频 assetId，并不直接发送 audio.text；本报告仍把前题播放过的声音以及答后可揭示的正确内容作为学习者已经接触的信息，覆盖比“只看题面字符串”更大的范围。没有据 JSON 中存在脚本就断言客户端听前已显示脚本。

## 为什么必须跨单元、跨原顺序检查

两单元在 bank.json 中均为 `level=undergraduate`、`topic=projects`，`roleKeys=[]`。`bank-catalog.ts` 将各单元题目转为共同候选，并将原题的 goalId/type 顺序转为 blueprint slots。`assembleBankQuestions`：

1. 先按 level、topic、可复习/未见状态、角色过滤候选；不按原 unitId 隔离。
2. 每个槽再按 goalId/type 取候选，优先未掌握项，随机选一个。
3. `used` 仅避免同一内容身份重复；没有检查某题的反馈是否给出后题答案。

“同 goal/type”约束是某题进入哪个槽的条件，不是整卷只能有一个 goal/type。同卷不同槽仍会把 cohesion、paraphrase、translation 等目标混在一起，因此也检查了跨目标提示。原题 ID 的 a/b 前缀不表示最终试卷分组。`bankIdentity` 也不会因为两道不同题共享一个正确词或句法结构就自动排斥它们。

以下给出当前蓝图上的可行路径，表示在候选均可用时可能发生，不声称对任何实际用户抽中过，也没有访问线上答题记录。

## 应处理的真实冲突

| 先行题 → 后题 | 精确字段与暴露内容 | 可行混卷路径 | 判定与建议 |
| --- | --- | --- | --- |
| `cet4.astra.a16` → `cet4.astra.a10` | a16 的 `options[b].text` 是 `Because the website was unavailable, several people could not complete their bookings.`；其 `explanation` 明说“b将网站不可用置于because从句，将无法预订作为结果”。a10 的 `acceptedAnswers[0]` 是 `because`，任务是在 because/although/unless 中选词解释改线上讨论的原因。 | clear-messages 蓝图第 3 槽为 `cet4.cohesion/choice`，可抽到 a16；第 9 槽为 `cet4.cohesion/completion`，可抽到 a10。原 a16 位于第 15 题并不能保护这一路径。 | **定向支架泄漏，中等风险。**先题直接给出后题正确词及“because 表原因”的反馈。后题仍需要把公交取消与线上讨论判断为因果，故不是整句抄答；作为巩固合理，作为独立掌握证据不独立。建议为测量型卷建立 a16/a10 双向同卷排斥；如保留学习型连练，明确后题是反馈后的迁移练习，不把两次命中累加为两个独立证据。 |

建议双向排斥不是说两个方向泄漏程度相同：a10 → a16 也会教 because 的因果关系，但 a16 仍要比较原因和结果的方向，a/b 两个选项都包含 because，单纯记住词不能作答。两方向都应保留评估说明，不能把后者夸大为答案直给。

暂不建议只通过调整这两个 JSON 的题序修复：组卷会重新按槽抽选；也不建议把 because 机械换成另一个连接词冒充解决语义关联。真正处理应由主代理决定目标是教学巩固还是独立测量，再选择互斥或人工重写不同认知任务。

## 有共享信息但不应误报为答案直给的双题关系

| 双 ID 与方向 | 具体字段/共享内容 | 人工判断 |
| --- | --- | --- |
| `cet4.astra.a12` ↔ `cet4.astra.a04` | a12 的 `tokens[a]` 和 `explanation` 给 Although 让步背景及 still；a04 的答案是 Nevertheless，解析讲不合预期的转折。 | 共让步/转折关系，不同连接形式与作答任务；前题没有给 Nevertheless。可形成教学迁移，不是完整答案复现。 |
| `cet4.astra.b04` → `cet4.astra.a16` | b04 的 `prompt/explanation` 给 so that 的目的；a16 的 `options[d]` 用 so that 构成与题意不同的目的句。 | 会帮助排除一个干扰项，但不能在 a/b 两个 because 句中判断正确因果方向；属于规则支架，不等同正确句直给。 |
| `cet4.astra.b07` ↔ `cet4.astra.b13` | b07 的 `left[l2]` 为 `I see your point, but a shorter break may not give everyone enough time.`，解析说明先认可再提不足。b13 四个选项全部以 `I see your point, but` 开头。 | 重复礼貌套语真实存在，但四项都包含它，不能据此定位 c。b13 还必须保留六人、顺序访谈和至少九十分钟，不能据先题照填。 |
| `cet4.astra.a11` → `cet4.astra.b14` | a11 的 `left[l1]/explanation` 解释 few＝很少；b14 的 `audio.text` 有 first few comments、only a small number、hear from the rest。 | 能帮助听懂人数限制，但不能替代对正面反馈和等待决定的整段整合。答案不是 few 的拼写或翻译；这是词义巩固。 |
| `cet4.astra.a14` ↔ `cet4.astra.b17` | a14 的 `audio.text/options[a]/explanation` 同时包含进步与保留；b17 的 `prompt/options[b]/explanation` 也保留改善和局部不足。 | 相同评价逻辑，具体对象与行动结论不同，没有复现目标答案句。不要把“有进步但仍需改善”这一常见关系本身当作抄答证据。 |
| `cet4.astra.b10` ↔ `cet4.astra.b11`、`cet4.astra.b02` | provided that、subject to approval/if approval is granted、If the replacement part arrives 分别表达条件。 | 跨语境条件理解；没有共享安静、批准或零件到货的事实答案。b02 还须区分到货和不到货两分支的承诺。 |
| `cet4.astra.a02` ↔ `cet4.astra.second01` | 两道 `audio.text` 都涉及安排/房间变动；前者是 two/Room Six/Room Nine，后者是 `Only the morning session has been moved to the smaller room.` | 题材接近但时间、房间、限定和完整措辞均不同；前者没有给出后者完整听写句，不能因此禁用所有场地通知。 |
| `cet4.astra.a07` → `cet4.astra.b12` | a07 的词块含 `book a table`，b12 的题干含 `book in advance`。 | b12 的输入目标为 usually/normally，并非 book；共享预订词汇没有给出作答目标。 |
| `cet4.astra.b06` ↔ `cet4.astra.a12` | 两题均有 still；前者还对比增长、下降和常见，后者排序 Although/展览/吸引。 | 仅共有保留限制的常用词及语义要求，没有完整排序句或选择答案复制。 |

## clear-messages：18 题逐题检查

此表按正式文件题序记录；每题也放回另一单元及混卷候选中检查，不能把表的顺序当作允许的唯一执行顺序。

| 顺位 / ID | 必须判断或产生的答案 | 全字段与跨题判断 |
| --- | --- | --- |
| 1 `cet4.astra.a01` | 请求是否可延迟一天，而不是预设对方同意 | 没有别题给出 `Would it be possible to submit our report a day later?`。a07/b01 同为合作安排，内容与决策边界不同。提示是请求与决定先后，不复述正确英语。 |
| 2 `cet4.astra.a03` | covers＝包含材料费用 | 另一题 a13 的选项含 figures cover 哪个期间，不解释费用 covers；虽同词根，不可据覆盖期间直接确定费用义。无其他题直接教授本题完整语境义。 |
| 3 `cet4.astra.a04` | Nevertheless | 其他题含 Although、but/still 等对照，未给 Nevertheless 答词；属于关系迁移。槽位可被 a16/b04/b16 替代，是实质冲突路径的起点之一。 |
| 4 `cet4.astra.a05` | 周五之后收到的不予考虑 | 其余截止/条件题没有复制 applications received by Friday 或审核不等于录取的正确句；同为范围保留不能视为泄漏。 |
| 5 `cet4.astra.a06` | 暂时且仅本地居民可用 | 同卷 b06 也有居民，但考骑行趋势和汽车状态；没有 For now/only to local residents 的完整答案复用。 |
| 6 `cet4.astra.b15` | conservative＝谨慎偏低 | 冒号后是本题必要语境，非别题泄漏；其他题未展示该词及释义。 |
| 7 `cet4.astra.a07` | 请求确认人数、再订桌子的词块顺序 | 三块及标点本来是排序材料，不能把本题词块算作跨题泄漏；没有另一题完整复制请求句。 |
| 8 `cet4.astra.a09` | keep track of / take account of / make use of 的三种意义 | 三短语及解释没有在另一题要求原样输入；与旅行故事只共享 trip，不含词义答案。 |
| 9 `cet4.astra.a10` | because | **需处理**：a16 的先行正确反馈可直接教授该目标词与关系；详见冲突路径。 |
| 10 `cet4.astra.a11` | few、not all、most 的范围配对 | b14 的少量反馈听力形成词义巩固；没有后题照填 few/not all/most。not all 的“至少一些没完成”没有被别题直接复制。 |
| 11 `cet4.astra.a12` | Although 引导让步的完整词块排列 | 其他转折题教关系但未展示这个展览句的完整顺序。让步规则共用不直接给答案词块位置的全部判断。 |
| 12 `cet4.astra.b12` | usually 或 normally，允许同义变体 | 36 题其余字段及两故事没有提供该空位完整答案；与预约题材重复无关。题内词库是受控输入支架，不属于跨题泄漏。 |
| 13 `cet4.astra.a13` | 澄清 soon 的明确截止时间 | 所有选项均合作，需识别缺少的信息。b03 的 figures/support 与此处 figures cover 只是对象词汇重复。没有别题提供正确回复句。 |
| 14 `cet4.astra.a15` | settled on＝最终选定 | 其他题未出现这一目标短语；故事的 choose/planning 不是该短语答案的直接释义材料。 |
| 15 `cet4.astra.a16` | 正确因果方向的 because 句 | **可成为泄漏先题**：混卷可前移至第 3 槽。反向 a10 只教 because，不足以区分含 because 的 a/b 两项。 |
| 16 `cet4.astra.a17` | 尝试联系、目前尚无回复 | b02 的电话承诺、b14 的少量回复均不是 supplier 的状态，不能照搬。尚未回复不等于拒绝的区别仍需本题判断。 |
| 17 `cet4.astra.a18` | postponed | 另一单元有改房间、维修另约日期等语义邻近内容，但没有 postponed 词形或完整被动答案句；不是“同题材即漏答”。 |
| 18 `cet4.astra.b07` | 确认所指、认可后保留、道歉补救三功能 | b13 共用礼貌开头，但四选项全有；没有照抄后可定位正确项的结果。 |

## small-mountain：18 题逐题检查

| 顺位 / ID | 必须判断或产生的答案 | 全字段与跨题判断 |
| --- | --- | --- |
| 1 `cet4.astra.a02` | 两点去九号室 | 另一听写 second01 的 smaller room 没给本题数字；自己的选项列四组组合是正常选择材料。故事没有房号/钟点答案。 |
| 2 `cet4.astra.b01` | 今晚不能、明早能检查 | a01 请求延期与本题替代安排不是同一正确句；必须区分今晚检查、明早反馈、之后再确认。 |
| 3 `cet4.astra.b03` | support＝为主张提供证据 | 没有别题展示 support 的同一语境义；a13 只共享 figures 这一名词。 |
| 4 `cet4.astra.b04` | 加标签是目的而非已验证效果 | a16 的 so that 干扰句及 a/b 因果关系会形成规则支架，未提供 boxes/labels 的正确事实；不判整句泄漏。 |
| 5 `cet4.astra.b05` | 以前仓库、现在社区活动场所 | 两故事及其他题没有 former warehouse/used to 的同句或目标翻译，过去与现在仍须对照。 |
| 6 `cet4.astra.b06` | 骑车者增加，汽车仍常见 | a06 同讲居民但不同限定；a12 的 still 教保留关系，不给本题增长方向及汽车状态。 |
| 7 `cet4.astra.b08` | `Please save a copy, not just a link.` | 全句没有在其他题题面、选项、反馈或故事出现。a13 有 receive a copy，仅公共词 copy，不给 not just a link 的听写关键。 |
| 8 `cet4.astra.b09` | require | 其他题没有把该答词直接给出；compulsory/must 在本题中是理解语义的必要证据。其提示很强但属本题支架，不是跨题冲突。 |
| 9 `cet4.astra.b10` | provided that 条件词块句 | b11/b02 练条件但没有该许可句完整顺序；quiet 与 a09 的 quiet room 共享普通形容词，不给 provided that。 |
| 10 `cet4.astra.b11` | 计划来春开店且须获批 | b10/b02 提供条件概念巩固，未提供本题时间、批准状态或完整改写句。 |
| 11 `cet4.astra.second01` | `Only the morning session has been moved to the smaller room.` | 完整听写句未见于其余题。a02 教场地更改，但其数字和 repairs 信息不能写出本句。故事和 b18 含 smaller，不提供限定/时态/地点整句。 |
| 12 `cet4.astra.b13` | 六次至少十五分钟顺序访谈，至少九十分钟且不改人数/方式 | b07 礼貌开头不是定位答案的线索，四项同有。仍需核对至少/至多与并行条件，不把礼貌复现虚报为直给。 |
| 13 `cet4.astra.b02` | 零件未到则五点前来电商量其他日期 | b11/其他条件题只教关系，未提供此处到货分支和承诺内容；前题只有“房间/安排变化”不等于本题维修承诺。 |
| 14 `cet4.astra.a14` | 认可搜索，但改善分享前保留旧分享工具 | b17 共用“改进但有保留”逻辑；本题仍需实听 search/share 和保留动作，未给跨题完整答案。 |
| 15 `cet4.astra.b14` | 当前好评但回复少，收齐意见后再决定 | a11 可预教 few 的语义，不能替代正/负反馈、已决定/待决定的综合辨认。 |
| 16 `cet4.astra.b16` | This 回指缩短表格与删重的整项改动 | 其他题没有事件回指的完整同句。a11 的 shorter version 与此 shorter form 只是对象相近，不能给代词指代答案。 |
| 17 `cet4.astra.b17` | 新版更清晰但部分仍需改 | a14/让步题的评价结构可迁移，不能照抄出该句或排除 only layout、方向倒置、无提升等选项。 |
| 18 `cet4.astra.b18` | To reduce waste / canteen / began / smaller portions | 故事面包“gets smaller”和 second01 smaller room 只重现比较级；均不给 reduce waste 或本句词块的完整顺序。目的关系与 b04 共用，属于规则巩固。 |

## 故事检查

“被风吹乱的下午”的六项主要事件是带旧书、落雨、车票入水、回忆初次旅行、交换书、计划再出发。没有 Friday 截止、居民资格、费用 covers、because 答词、usually/normally、postponed 或任一听写完整句。出现 trip/book/choose/planning 这样的共同词不构成后题答案泄漏，故事也不被题干用作事实来源。

“盘子里的小山”讲揉面失败、面包外形、试吃、变小、收拾厨房及下次再试。`gets smaller` 可使学习者接触 smaller 这一普通比较级，但不是 second01 的 `smaller room` 完整听写，也不是 b18 的 `serving smaller portions` 排序句；没有独立给出场地时间、维修条件、搜索/分享态度或 require 答词。不能因食物故事与食堂题题材相近就认定泄漏。

两故事目前不会回答任何题目。此判断覆盖所读两单元；没有宣称整个四级池、其他项目故事或未来新题也已检查。

## 后续处理边界

- 主代理应决定 a16/a10 在正式学习型挑战中的容许方式；若按独立掌握来计证据，需实现或登记同卷排斥，而不是仅调原文件顺序。
- 若新增排斥，验证应至少覆盖“a16 被抽进 clear-messages 第 3 槽、a10 为第 9 槽”的具体路径，并保留题量不足时不重复/降级凑题的现有规则。本报告没有实施或测试该功能。
- 当前“未发现完整句直给”的范围仅为这 36 题及六段故事。新增题、扩大候选池、变更答案反馈展示或随机规则后需重审，不能把一次报告当作永久证书。
