# 高三强化稿正式结构适配审阅

日期：2026-10-11。对应 `senior3-strengthening-20261011.canonical.json`。仅在隔离作者目录保存，未注册、未提交、未发布。正文依据已主审的 `senior3-strengthening-20261011.astra.json`、作者review及 `docs/learning-program/senior-strengthening-review-2026-10-11.md`，逐题读回后适配；程序仅复制保存与校验，不组合题干、选项或剧情。

## 结构合同与无损边界

按当前 `Backend/src/modules/learning/content.ts` 的 LearningUnit / LearningQuestion 整理。单元暂定 `companion.senior3.umbrella-kindness` v1，参考最近正式 `companion.senior3.paper-boat` 与 `folded-page` 的角色及开场合同。20分钟只是待实测估计，不是真人完成时间证据。

开场英文、中文分别按完整句拆成两个 `afterQuestion: 0` beat；英文以一个空格重新连接、中文直接连接均与原故事逐字相同，全部在题前。没有重写故事或把题目变成故事回忆。01—03的独立material原样置于prompt前，以两个换行与原问题分隔，其余prompt原样复制。所有选项、答案、配对候选、词块、完整可接受组合、解析及review.difficulty逐字段等值验证；q16机器暂不收现金、窗口仍收现金的条件保留。

instruction与hint是本轮逐题亲写的必要界面字段，仍待主代理最后读回；hint不直接复制作者review.shortestPath。作者review和sourceReading不混进客户端问题字段，出处与限制写入references，其余自审保存在原作者稿和本文件。空acceptedVariants不携带额外答案，故不写入正式结构；三道填空和听写按作者合同设大小写及句末标点归一，后端原有处理也归一首尾/连续空格及直弯撇号。

## 逐题结果

| 题 | 结构映射与答案核对 | 目标、媒体与提示核查 |
| --- | --- | --- |
| 01 | 完成choice，108词材料完整，b；四选项不变 | 原argument-evidence-link适配；无听力媒体。例证/评价维度提示没有给出答案。 |
| 02 | 完成choice，117词材料完整，c；保留十二人及两晚资源 | 原argument-evidence-link适配；有限证据支持有限行动，不一律选延迟。 |
| 03 | 完成choice，118词材料完整，a；保留独立描述和外部记录 | 原argument-evidence-link适配；无研究术语要求，提示只区分两项方法。 |
| 04 | 完成choice，c；长句、术语释义、在读条件完整 | 原interview-summary过窄，改为待登记complex-record-scope；无媒体。 |
| 05 | 完成choice，b；四项正式措辞完整 | 原clarification-register适配；提示不把收稿确认等同时间承诺。 |
| 06 | 完成matching，l1-r1/l2-r2/l3-r3；3左4右 | r4原文保留且未用；原argument-evidence-link适配。 |
| 07 | 完成listeningChoice字段映射，b；最终四阶段完整 | 原listen-discourse-position适配；audio.pending，未生成assetId/voice，不降为阅读。 |
| 08 | 完成listeningChoice字段映射，c | 保留主审“不晚于周三”修订；原listen-discourse-position适配；audio.pending。 |
| 09 | 完成completion；In addition / Furthermore均保留 | 原argument-evidence-link的命题关系应用；词库及As a result干扰仍在题面，不能当开放表达能力。 |
| 10 | 完成arrange；a-b-c-d / c-d-a-b两个完整序列 | 原interview-summary适配；两句自身时间关系完整。与旧whether空存在规则支架风险，详见下文。 |
| 11 | 完成completion；denies approving / denies having approved均保留 | 原interview-summary不含deny转述，改为待登记reported-claim-status。 |
| 12 | 完成dictation字段映射；原句与标准归一完整 | 原目标仅限定旧两句，改为待登记listen-scope-record；audio.pending，基础七词听记。 |
| 13 | 完成listeningChoice字段映射，b | 原listen-discourse-position适配；保留草稿—审核—录制次序；audio.pending。 |
| 14 | 完成matching，l1-r1/l2-r2/l3-r3；3左4右 | 保留自然但重复已知时长的r4；原clarification-register适配。 |
| 15 | 完成choice，d；not because、真实原因与段落范围完整 | 原argument-evidence-link适配；与17共用采访题材，不提供17输出短语。 |
| 16 | 完成arrange；a-b-c-d / a-c-b-d两个完整序列 | 原argument-evidence-link适配；题干明确机器暂不收现金、旧窗口能收现金，不能丢掉这一支持前提。 |
| 17 | 完成completion；accompanied by / presented with均保留 | 澄清请求目标不涵盖本题修订建议，改为待登记controlled-information-revision；replaced by干扰仍在词库。 |
| 18 | 完成audioArrange字段映射；c-d-a-b | 改为待登记listen-scope-record；audio.pending，原声还原而非自由组句，保留十词基础支架定位。 |

“完成映射”不等于可发布：五道音频题目前故意不符合正式audio合同；四项新增目标仅提出，未改catalog。

## 必须登记的精确定义

本轮实际检查catalog，五个作者原goalId均存在，但“存在”不等于语义适配。以下四个新ID当前未登记；canonical已明确使用这些候选ID。没有扩大已有目标来掩盖缺口，也没有让相近旧目标冒充目标覆盖。

```json
[
  {
    "id": "senior3.complex-record-scope",
    "level": "senior3",
    "canDo": "能从包含多层修饰与条件的长句中恢复主干，记录适用对象、事件先后和实施条件。",
    "boundaries": "限题内明确的信息与给定摘要选项；q04涉及获推荐续发的奖学金、九月支付及保持在读条件。不由此推断全部申请均获批准，不等同自由长句翻译或全年语法覆盖。现有教材核读只支持综合信息理解任务，不宣称直接核读了本句全部句法形式。",
    "sourceIds": ["fltrp.senior3.archive20260929"]
  },
  {
    "id": "senior3.reported-claim-status",
    "level": "senior3",
    "canDo": "能按给定动词和形式要求转述说话者的否认，保留说法归属及事实尚未核查的状态。",
    "boundaries": "限受控句框与题面指定形式；q11接受denies approving和denies having approved，不把说话者否认写成叙述者确认。教材页支持记录解释与未确认信息，不被宣称为deny接动名词的直接形式出处；不等同开放转述或法律事实判断。",
    "sourceIds": ["fltrp.senior3.archive20260929"]
  },
  {
    "id": "senior3.listen-scope-record",
    "level": "senior3",
    "canDo": "能通过整句听写或词块还原，保留简短录音中包含与排除、承认与接受之间影响含义的区别。",
    "boundaries": "限q12七词听写与q18十词四块原声排序，允许重播；仅基础听记支架，不计作高阶长篇听力或自由协商。原创录音待制作及独立核听；教材听记任务是能力依据，不是这些原句的来源。",
    "sourceIds": ["fltrp.senior3.archive20260929"]
  },
  {
    "id": "senior3.controlled-information-revision",
    "level": "senior3",
    "canDo": "能在受控修订建议中选择表示附加信息的短语，保持原内容并避免读者形成错误时间印象。",
    "boundaries": "限q17明确词库与保留访谈、附上录制日期的任务；接受accompanied by和presented with，replaced by与保留要求冲突。不把词库选择当自由写作，不把教材任务目标虚构为两个短语的直接语法出处。",
    "sourceIds": ["pep.senior3.archive20260929", "fltrp.senior3.archive20260929"]
  }
]
```

q04由interview-summary改映complex-record-scope；q11由interview-summary改映reported-claim-status；q12、18由listen-precise-record改映listen-scope-record；q17由clarification-register改映controlled-information-revision。其余原目标保留。listen-discourse-position现有boundaries写“5道听选”，是旧单元数量描述；新增三题仍在其canDo与语境边界内，但登记新组时应将该历史题数说明与实际范围分开，不能继续当整个目标永久只有5题。

## 媒体与unitSchema的实际结果

07、08、12、13、18使用 `audio: { text: 原脚本, status: "pending" }`。没有assetId、voice、URL或文件，也未把脚本放进prompt/hint。status仅供隔离待制作稿标识，不是正式audio字段。媒体制作、声音安排、发音/语速/时长实听、答前脚本隐藏及5道原生听力交互均未完成。

实际调用当前unitSchema：失败15项，全部定位在上述5题audio中：各缺assetId、缺voice、status为未识别键。没有伪造字段使校验变绿。4个拟新增goalId是否已登记不由unitSchema检查，因此即使媒体补齐，仍须catalog目标注册与目录级验证。

13道非音频题逐题通过questionSchema。另将五道音频题从内存副本移除并同步过滤无题目标，剩余单元结构通过unitSchema，用来确认非媒体字段与前置故事结构；该副本未写盘，不代表18题单元通过。

对18题直接调用真实gradeAnswer：23个完整正确答案/排列全部判对，18个合法错误提交全部判错。含09/11/17各两个文本答案、10/16各两个完整排列；06/14分别用r4替换一个正确关系作合法错例。五道音频题的这些检查仅证明既定答案数据可判，不经过questionSchema，不证明媒体、客户端听力或线上闭环可用。

## 跨题提示再审

逐题核读18题完整输入、选项、词块、音频脚本和解释，以及本次新增hint；没有把作者的最短解答路径直接暴露为提示。故事只包含善意传递的叙事，不提供18题所需缺失事实。01—03分别是信息可获取性、有限证据的行动范围、一致性与独立核查，不能靠另题事实直接作答；共享证据判断策略属学习迁移。06、09、15、16也训练论证关系，不据此声称独立测量六次能力。05、14均训练信息缺口与不虚构承诺，原有澄清策略可能帮助下一题。

07、08、13虽都需追踪澄清/最终要求，安排、借书类别及审批条件各自只由本题录音给出；新hint不泄漏对应答案序列。12费用方向与18承认/接受区别没有在其他可见输入中给出原声句。09的两项补充表达、11的两项否认表达、17的两项附加信息表达，均未在其他题可见正文或新hint中提前出现完整短语。15与17虽共用interview，删段依据不提供附日期短语；10与04均有资助背景，但未决是否提供与已获推荐续发不是同一事实，不能借一题决定另一题答案。16两条理由自足，不能仅靠“现金”常识猜出窗口能力。

程序辅助比较7个完整acceptedAnswers（09两项、11两项、12一项、17两项）与其余17题以及当前units目录八个高三v1单元，均未命中；扫描bank-revisions未发现顶层LearningUnit结构，故不把该次辅助扫描声称为正式线上修订内容穷尽。没有重审八个旧单元的每一道题或动态抽题蓝图，不能以字面无命中证明全池独立。

已人工核实旧 `marcus.senior3.interview-summary` q2是whether/if宾语从句填空、q5是句首whether填空。新q10直接显示“Whether financial support will be offered”主语从句，与旧q5尤其形成明显规则支架；新q10解释及排序反馈也可能提示旧q2的是否表达。正式混编时至少应审查并隔离这两组配对：新单元s3.strength.10与旧单元q5、新单元s3.strength.10与旧单元q2。单元内完整开场训练不等于跨挑战无学习影响；最终互斥规则须按实际版本和抽题插槽验证，本稿不写bank。

## 交接范围

仅新增canonical.json与本文件。未改作者稿、catalog、bank、正式units、音频、代码或线上数据；未提交。下一步需主代理审核4项目标定义和新增hint，完成5段媒体及核听、登记目标、真实混编检查和18题连续原生作答后，才可判断是否正式接入。

## 沉浸文案补记

按主代理转达的用户要求，仅将summary由教学能力说明改为“一把陌生人的伞，让米娜把善意带上了火车。”，贴合开场剧情。已用解析后的字段比较确认18题及其他JSON字段完全不变；本次不新增教学或媒体验收结论。
