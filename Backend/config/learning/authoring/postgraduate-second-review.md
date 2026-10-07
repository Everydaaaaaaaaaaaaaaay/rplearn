# 六级第二组作者审阅记录

日期：2026-10-07。对象：`postgraduate-second-unit.astra.json`。这里的 postgraduate 明确指大学英语六级，不是考研。作者亲自逐题审读和修订，主代理终审未完成，不能据此进入正式内容包。

## 选题与来源

对照 `postgraduate.astra.json`、`docs/learning-program/astra-adult-review-2026-10-07.md` 六级部分、正式 `units/companion.postgraduate.rainy-screening.json` 及对应 review 后，手选恰好18道未发布原题。没有复用正式单元的18题；概念可形成巩固，但题干、材料和作答证据来自未发布稿或本次重写。不是用脚本组合教学文本：三篇故事、每道修订、每项理由均逐项人工编写；程序仅按明确选择清单搬运、序列化及机械检查。

亲读缓存 CET2016 的正文印刷1—4、8—9／PDF6—9、13—14。核查 SHA-256 为 `9166d3c03b7bc43abd9d9df91bd2ef8085b4419286f1e5ca100dea68f3cfd1f1`，与 catalog 已登记来源一致。[教育部教育考试院官方PDF](https://cet.neea.edu.cn/res/Home/1704/55b02330ac17274664f06d9d3db8249d.pdf) 是能力依据，不是本稿题文来源；本稿均为原创教学材料，不复制真题。没有新增声称通读整本、目视所有页或这是最新政策。

印刷1—2明确六级中速熟悉题材听力、主旨细节、隐含信息、交际功能、观点态度及句间关系；印刷8明确约140—160词/分及真正考试材料的长度。本稿短录音不冒充280—320词长对话或完整篇章测量。印刷3—4对应贴切措辞、衔接、保义及讨论澄清；短题不证明完整写作或自由讨论能力。

只读 catalog 发现 `cet6.stance-intent` 的现有边界限定“本组只含文字态度判断”。本稿保留原目标归属作追溯，另给出完整 `cet6.listening-scope-stance` 待登记对象和每道音频的 `audioGoalProposalId`。主代理应在正式导入前决定采用新目标或修订旧目标边界，不能直接宣称原文字范围已经覆盖音频。

扩展用法核查：

- [Cambridge ground 的理由义](https://dictionary.cambridge.org/dictionary/english/ground?topic=topics-and-areas-of-interest)：核读搜索返回的词典正文，确认 `on the grounds that` 引出理由。第11题改为独立安全检查语境，避免与词典示例的隐私语境过近。
- [Cambridge unless](https://dictionary.cambridge.org/us/dictionary/english/unless)：核读搜索返回的词典正文，确认条件义；第12题不把必要条件擅自升级为充分条件。
- [Cambridge Learner’s Dictionary 出版社样页](https://drupal-s3fs-prod.s3.eu-west-1.amazonaws.com/files/9113/8071/5737/cambridge-learners-dictionary4-intermediate-paperback-with-cd-rom-sample-pages.pdf)：搜索正文确认 `take ... into account` 表示考虑。原a11的 `account for` 存在“解释原因”等多义，故本稿第08题改为明确短语，不沿用无语境时唯一义项的讲解。

部分词典直达页返回403；以上核查范围是搜索返回的明确词典/出版社正文，未声称成功打开这些直达页。

## 逐题判断

每题JSON中包含完整题面、答案、提示、解析、逐项 `review.optionNotes`、歧义范围及显式变体；音频另有隐藏脚本、pending资产和建议语速。下表记录本次作者判断，不能代替主代理亲自终审。

| 本组题号 | 未发布原稿 | 作者处理与可接受边界 |
| --- | --- | --- |
| 01 | a02 | 重写三个选项为同类条件性支持；录音明确保留晚间并新增白天，避免正确项仅靠最长最温和获选。a排除部分人，b完全替换时段，c符合并行安排。题面不出现白天答案。 |
| 02 | a12 | 保留纠正误解的原音，将明显无关的禁网干扰改为主题与回应时间，三项都是可能的调查异议。只有录音的rarely use与online poll决定覆盖问题。质疑覆盖不等于证实完全未覆盖。 |
| 03 | b02 | 保留经首批主审修订的三个自然判断。a将缺证当暂定无效的支持，b保留缺证与观察范围，c添加初步效果。提示移除直接解释正确概念的旧表述。 |
| 04 | a04 | 手改词库为raise/resolve/dismiss，三者均可及物，不靠rise语法排除。按引出、解决、不予考虑区分。承认是跨档搭配巩固，不靠它独立认证六级难度。 |
| 05 | b03 | 保留搭配配对，逐项说明动作不等于结果：回应不保证解决，获取不等于使用，考虑不等于忽略。明确跨档巩固。 |
| 06 | a10 | 三个选项都保留作者归属；分别改变证据强度或因果方向，不能只看According to猜答案。b保留提出观点与可能性。 |
| 07 | a09 | 原排序能看词块语法直接解出，弃用该交互。重写短发言和三个立场概括：确认局部省时、未确信整体收益，不等于已证明整体劣势。录音是认可范围和保留范围的唯一来源。 |
| 08 | a11 | 听写改为明确take ... into account；保留do not/don't两种形式。单数改写即使语法成立也不是本次原音。题面与提示不透露具体内容或否定方向。属于听写巩固，不包装为独立高阶推断。 |
| 09 | b09 | 原排序容易凭标点解出，改为完整行动建议听力选择。听取rather than/during/if区分现状、调查、后续条件；确认后仅考虑修订，非必然修订。三个方案均可理解，不能凭常识判唯一。 |
| 10 | b10 | 保留听写与四种完整标点/缩写组合。far from漏掉会反转克制评价，results/they不能擅改单数。提示不泄露具体态度。听写巩固。 |
| 11 | b12 | 词库改为grounds/terms/extent，删除地板等明显弱干扰。改写独立语境。选词靠理由结构；“委员会以此为由”不表示第三方已证明理由真实。跨档搭配巩固。 |
| 12 | b17 | 保留必要条件的受控转写；because改变因果方向，although改成让步。不能反推一旦同意必然延长。 |
| 13 | a17 | 保留强干扰：地点错误或验证/推广顺序颠倒。those settings指大中心；不同压力是可能性而非已证失败。提示不直接点名大中心。 |
| 14 | b11 | 保留两个报价明确包含/排除维护的原音。a对齐口径，b添加未来变价，c添加维护期限；两项干扰同时有局部自然性与材料错误。不能推最终谁更便宜。 |
| 15 | b16 | 保留好例子/重要主题与论据连接不清的分层评价。a新增数量不足，b倒置已认可部分，c准确。与首组反馈技能相关但不是同一题或材料；本次作答必须听评价。 |
| 16 | b05 | 公开范围、开始前时序、拒绝无限拖延三层均保留。a改公开范围，b改时间，c不增承诺。独立对话不靠故事设定。 |
| 17 | b14 | 保留两个维度：相对省时与两者均不简单。错误项增加复杂程度排序或完全相等，不能从neither推出两者同样复杂。 |
| 18 | a18 | 删除旧末句“希望核对额外工时报酬”的直接提示。从英语provided和unpaid overtime识别条件；a检查支付，b明确要求现有员工额外工作而不加报酬，c转访客偏好。主代理指出旧b的自愿捐献时间可能符合原条件，已修正；不把自愿贡献普遍判为禁止。 |

选择题均按ID；配对按完整对应；听写和填空显式变体在JSON中。输入归一化是作者需求，尚未验证正式判题映射，特别不声称内部逗号会自动忽略。

## 音频交付边界

最终8道听力选择、2道听写，共10道。所有 `audio.status=pending`、`assetId=null`。建议标准英语自然语速150词/分；对话用可辨的两位说话人，不朗读A/B标签。自然停顿，不用额外重音标出正确答案，不读题目、选项或解析。答前不展示脚本或译文。

| 题号 | 词数（简单空格计数，对话含标签） | 150词/分纯读估算 |
| --- | --- | --- |
| 01 | 42 | 16.8秒 |
| 02 | 28 | 11.2秒 |
| 03 | 28 | 11.2秒 |
| 07 | 37 | 14.8秒 |
| 08 | 9 | 3.6秒 |
| 09 | 37 | 14.8秒 |
| 10 | 10 | 4.0秒 |
| 13 | 31 | 12.4秒 |
| 14 | 33 | 13.2秒 |
| 15 | 31 | 12.4秒 |

以上只是文本时长估计，不是成品媒体测量。每段均小于1200字符；制作后仍须查实际时长、听清否定/比较/条件、说话人交替、自然停顿、音量、发音与真实播放。当前没有生成音频，没有请求供应商，没有试听，因此不能标ready。

## 故事及机械检查

新写三个完整中英双语备选开场：《露台上的风铃》《末班船之前》《少了一块的拼图》。均 `afterQuestion=0`，每次只选一篇；你和普通同行者不被强设职业。每篇有事件、行动及收束，英中信息对应。题目独立于故事，不需记住任何角色或前文事实。

已机械核查：JSON可解析；恰好18题且ID唯一；18个原稿来源ID与正式题ID交集为空；10道音频均pending且无虚构assetId；每道均有题面、提示、解析、逐项说明和变体字段；三篇开场双语非空且位置为0；源PDF哈希一致。未跑服务测试或App构建，因为此次仅写作者稿，不修改正式units/catalog/bank。不提交、不部署，等待主代理终审及音频制作链路。

## 主代理终审修订与制作冻结

主代理已读完10段脚本及8道文字题。第07题正确项由“整体优势尚未被证明”收紧为“说话者尚未确信整体优势”；解析和逐项理由同步收紧，不改录音稿，避免把个人unconvinced直接升级成客观证据结论。

第18题旧b询问自愿捐献时间，确有可能满足“不要求无偿加班”的条件。按主代理意见改为明确要求现有员工额外工作却不增加报酬，解析只指出该要求冲突，不泛称自愿服务违规。

第02、14题已加 `production.speakerSegments`，A候选F1、B候选M1；明确A/B标签不朗读。逐字验证按一个空格连接片段文本，严格等于删除A/B标签后的原稿。候选声音尚未试听，所有资产仍pending。10段原音稿冻结，不启动producer或ASR；等待主代理调度，避免与四级制作争用设备。

主代理选择故事第3篇《少了一块的拼图》作为正式完整开场，拆为3个自然连续beats且全部afterQuestion=0。前两篇仍保留为作者备选稿，不强塞入正式单元，也不假设客户端有随机开场选择能力。

## 正式导入字段映射建议（只读核对，不修改正式文件）

已查看 `Backend/src/modules/learning/catalog.ts`、`content.ts`、`audio.ts` 及当前正式六级单元。以下是实测代码形状对应关系；作者稿不能原样复制，因为正式schema使用strictObject。

| 作者稿 | 正式目标及处理 |
| --- | --- |
| unitId | 单元id；建议固定为companion.postgraduate.second或主代理审定的故事化ID，随后catalog.unitIds、文件名、review.unitId三处一致。 |
| level/title | 直接映射；补version=1、schemaVersion=1、scoringVersion=1、roleKey=companion、roleVersion=1；summary/scene应使用拼图故事，estimatedMinutes为2—20整数。 |
| sources与各题pages | 来源已登记，复用cet.official.2016；单元references需sourceId、unit、pages、alignment，页码覆盖印刷1—4、8—9／PDF6—9、13—14。词典核查继续保留作者审阅，不必把教学方法依据伪成额外官方目标。 |
| questions[].id、goalId | 保留新的second题ID；音频按下文建议重映射目标。正式goalIds只列确有题目使用的目标，总数至多9。 |
| prompt、hint、explanation | 原样映射审定正文；新增instruction，difficulty映射difficultyReason。删除taskIntent、originQuestionId、authoringStatus、review、pages、sourceId等作者字段。 |
| choice/listeningChoice | 保留options和answer；删除acceptedVariants。正式选择项文字至多240字符。 |
| completion/dictation | answer与acceptedVariants去重后合成acceptedAnswers，删除原两个字段；normalization仅允许ignoreCase和ignoreTerminalPunctuation两个布尔值。内部逗号变体继续显式保留。 |
| matching | left/right直接映射，answerPairs从[l,r]转成{left:l,right:r}；删除acceptedVariants。 |
| audioScript/audio | 成品通过后写audio={assetId,text,voice}，不能把pending/status/null/建议语速带进正式题。对话text采用去标签的实际朗读稿；必须与catalog音频transcript严格相等。 |
| production | 仅用于制作审计，不进正式题。每个speakerSegments可转生产计划clip的segments；补rate/breath等实际制作参数后才运行。 |
| stories | 仅选第3篇，按自然段切为3个连续beats，speaker=旁白、英文进text、中文进translation，全部afterQuestion=0。正式每段英文/中文最多500字符，不能整篇塞进一个beat。 |
| author | 转成authorship的kind/author/reviewedBy/reviewedAt/reviewNotes，reviewedBy和reviewedAt与正式review严格一致；不带制作尚未完成的approved声明。 |

音频资源schema要求：ID是实际WAV SHA256对应的audio.<64位哈希>；byteSize、durationMs取成品，不能用文字估算。24kHz单声道16位PCM、300—60000ms，实际字节和峰值须通过verifyLearningAudio。资产登记transcript最长1200字符，voice仅接受M1—M5或F1—F5。**当前单个voice字段无法完整表达F1/M1双人制作归属**：正式导入前需要主代理明确现有项目的多声音登记约定，或做有依据的小范围schema处理；不能写“F1+M1”绕过校验，也不能无说明地把双人录音说成全为一种声音。候选两人声信息保留production及reviewNotes供审核。

建议新增两项局部目标（完整可登记对象如下；pages/status等作者元信息不可混入strict goal对象）：

```json
[
  {
    "id": "cet6.listening-scope-stance",
    "level": "postgraduate",
    "canDo": "能从熟悉话题的短发言与交流中辨认信息范围、条件性态度、纠正误读、比较口径与行动时序。",
    "boundaries": "对应六级听力的局部理解技能；短录音选择不等于完整六级听力测量，不以个人未信服断言客观反证。",
    "sourceIds": ["cet.official.2016"]
  },
  {
    "id": "cet6.listening-detail-encoding",
    "level": "postgraduate",
    "canDo": "能听辨并准确记录短句中的否定、复数与表达保留态度的完整短语。",
    "boundaries": "句子听写属于跨档教学巩固；不等同六级考试题型，不据短句拼写正确宣称已具备篇章听力能力。",
    "sourceIds": ["cet.official.2016"]
  }
]
```

映射建议：01/02/03/07/09/13/14/15→listening-scope-stance；08/10→listening-detail-encoding；04/05/11继续precise-wording；06/12/17继续faithful-rephrasing；16/18继续discussion-clarification。共5个目标，每个均有题目。不要为沿用首组结构而在goalIds里保留无题覆盖的evidence-scope、stance-intent或argument-links。

正式review需每题standaloneContext、ambiguityReview、optionNotes及至少一正一误的probes。**只有choice/listeningChoice的optionNotes可非空**；本作者稿给填空、配对、听写写的逐项理由应并入ambiguityReview并继续保留在作者稿，正式optionNotes必须是{}，否则loadCuratedCatalog拒绝。各probe必须经gradeAnswer验证，且不能拿skip当错误反例；题面文字型重复会跨单元被拒绝。最终单元确定后由contentHash(unit)生成review.contentHash，后续任何题面改动都必须重审并更新哈希。
