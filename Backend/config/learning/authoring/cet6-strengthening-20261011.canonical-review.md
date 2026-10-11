# 六级强化稿：正式结构待媒体适配复核

对应 `cet6-strengthening-20261011.canonical.json`，来源为同目录已返修的 `cet6-strengthening-20261011.astra.json`、作者 `.review.md` 与 `docs/learning-program/cet-strengthening-review-2026-10-11.md`。`postgraduate` 始终表示大学英语六级，不改成考研。

本次仅将已经逐题亲写并经主代理纸面主审的18题和完整开场故事对照当前 `LearningUnit` 合同搬运；没有重新组合题干、候选、答案、解析或剧情。程序仅保存、字段搬运、逐字比较和校验。18条操作说明及提示逐题人工补写，未使用词槽模板生成。纸面主审不等于媒体核听或正式发布批准。

## 结构处理

- 正式单元外层沿用 `companion` 角色、schemaVersion=1、scoringVersion=1；单元ID为 `companion.postgraduate.pocket-star-strengthening`，未登记到正式清单。
- 现有普通选择/填空题没有独立 `material`：q01–06及q10–12将原材料、两个换行和原prompt完整串接到正式prompt。材料及原题干逐字相等，未截断。所有选择候选、答案、解释、词块和配对项均保留。
- q17/q18继续把完整独立材料放在 `passage`，没有合并丢失或用题面替代。插槽s1/s2、候选展示顺序、全部完整acceptedFills组合原样保留。
- q13/q14的acceptedOrders原样保留，各只有作者明确认可的一条完整顺序。q13仍为a-b-c-d；q14仍为d-c-b-a。逐一阅读完整句块后，没有新增需要接受的合法顺序：q13受宾语与从句结构限制；q14受题面明确的“初始解释→反向观察→替代解释→检验”顺序限制，不能把别的排列笼统称为不合语法。
- q10–12的answer转为acceptedAnswers，作者acceptedVariants均为空，不擅增shortened、qualified等语义变体；只保留大小写、首尾空格和句末标点归一化。q15/q16配对次序不影响判分，三左四右的额外干扰候选保留。
- 故事《旧口袋里的星星》按自然句界拆成三个beat，全部afterQuestion=0。英文以一个空格重新拼接、中文直接拼接后分别与原故事逐字一致。不是故事梗概，也没有让题目依赖故事。
- q07–09保留listeningChoice。audio.text逐字保存脚本，audio.status=pending，并保留scriptVisibility、suggestedWordsPerMinute和delivery制作指示。没有assetId或假声线，也没有将听力降为阅读题。脚本是制作资料，答前必须隐藏；本稿未接入客户端，尚未验证隐藏行为。

## 逐题对照结果

|题号|结构映射与答案|当前缺口|
|---|---|---|
|01|choice；材料与问题完整合入prompt；b；四项及解析不变。|结构通过；原stance-intent不足精确覆盖机制推断，目标待处理。|
|02|choice；完整专栏材料；c；承认潜在收益与质疑宣传的区别保留。|结构通过；argument-links已登记。|
|03|choice；两份报告完整保留；a；时间、单位、目的地干扰均保留。|结构通过；cross-source-reconciliation待登记。|
|04|choice；完整长句与四项；d；三方归属未改。|结构通过；faithful-rephrasing已登记。|
|05|choice；完整评论与末句；b；反讽不变为quiet字面词义题。|结构通过；stance-intent已登记。|
|06|choice；邮件条款与团队处境完整；c。|结构通过；discussion-clarification已登记，工作协作行动的目标覆盖须一并确认。|
|07|listeningChoice；完整四话轮脚本；a。|待双声线制作及核听；由文字专用stance-intent显式改挂已登记listening-scope-stance。|
|08|listeningChoice；完整工作发言；d；仍是本周立即采购。|待制作及核听；cross-source-reconciliation待登记并需含听辨边界。|
|09|listeningChoice；完整四话轮脚本；b。|待双声线制作及核听；由文字专用stance-intent显式改挂listening-scope-stance。|
|10|completion；材料与封闭词库完整；acceptedAnswers=[condensed]。|结构通过；现precise-wording偏证据强度，编辑语义目标待处理。|
|11|completion；完整研究纠错链；acceptedAnswers=[retracted]。|结构通过；原faithful-rephrasing可保留撤回强度，但需确认精确动作词汇目标。|
|12|completion；已完成调拨及7000/5000金额完整；acceptedAnswers=[reallocated]。|结构通过；资金分配动作词汇目标待处理。|
|13|arrange；四块原序展示；仅a-b-c-d；until不扩大为已获发表许可。|结构通过；faithful-rephrasing已登记。|
|14|arrange；四个完整句块；仅d-c-b-a；回指与指定任务阶段保留。|结构通过；argument-links已登记。|
|15|matching；三左四右；l1-r1、l2-r2、l3-r3，r4未用。|结构通过；cross-source-reconciliation待登记。|
|16|matching；三左四右及额外比较试验干扰保留；l1-r1、l2-r2、l3-r3。|结构通过；stance-intent对应作者评价，事实/解释/价值三分仍属巩固。|
|17|cloze；完整新版双方案passage；s1=c第一方案、s2=a第二方案。|结构通过；faithful-rephrasing已登记；没有回退到连接词初稿。|
|18|cloze；完整独立多语言资料passage；s1=a translated、s2=c omitted。|结构通过；资料处理动作词汇目标待处理，不声称独立隐私决策测量。|

## 目标缺口与精确定义

当前JSON对q03/08/15用作者proposal ID作为待登记引用，未伪称已存在。对q07/09完成了上述明确的同模态目标纠偏。其他作者goalId暂保留用于追溯，**不代表语义匹配已验收**；特别是q01、q10/12/18不能因字符串在catalog存在就判定目标就绪。

以下为需要主代理登记或采用等价明确扩定义的完整候选；本次不修改catalog：

```json
[
  {
    "id": "cet6.cross-source-reconciliation",
    "level": "postgraduate",
    "canDo": "能对齐两份来源的时间、对象及指标，辨别可并存结果与实质冲突，并选择与具体对象相符的资料支持行动。",
    "boundaries": "用于q03、q08、q15的阅读与短录音教学切片；录音实际语速与可听辨性须另行验收。不把所有差异解释为口径问题，不默认任一方造假；这是综合分析与篇章关系的产品细化，不是大纲逐字目标，也不将三题当完全独立观测。",
    "sourceIds": ["cet.official.2016"]
  },
  {
    "id": "cet6.mechanism-inference",
    "level": "postgraduate",
    "canDo": "能整合前后措施、观察结果及当事人说明，选出有材料支持的作用机制解释。",
    "boundaries": "用于q01的短篇阅读教学；不把前后对照当随机或反事实试验，不将支持某一机制等同排除其他原因，不考专业统计。",
    "sourceIds": ["cet.official.2016"]
  },
  {
    "id": "cet6.action-wording",
    "level": "postgraduate",
    "canDo": "能依据上下文准确区分编辑删节、撤回主张、资金重新分配及资料翻译与公开省略等正式语域动作。",
    "boundaries": "用于q10、q11、q12、q18的封闭词库或固定词块巩固；保留动作对象、时态、强度及公开范围，不等同自由翻译、写作或独立隐私决策评分，不靠生僻词或专业知识提高难度。",
    "sourceIds": ["cet.official.2016"]
  }
]
```

q06的现有discussion-clarification canDo仅写询问异议、总结事项。若不扩大该定义，可另登记 `cet6.agreement-action`，level=`postgraduate`，canDo=`能按工作邮件中的已明确条款提出具体协作安排，保留承诺的轮次、费用和请求范围。`，boundaries=`用于q06等受控回复选择；只判断题内约定，不提供法律解释，不以礼貌或语法正确代替实际任务适切性，不等同自由工作沟通表现。`，sourceIds=`["cet.official.2016"]`。此候选在正式接入时应与前三项一并作有记录的目标决策。

## 跨题提示再核查

人工再读故事、18题材料/脚本、题面、全部候选与解析，并检查新增instruction/hint：

- q17已经是first/second方案回指。q14的however和q02/q08等处的therefore/However不能直接填入q17，也没有旧连接词候选残留。方案事实为本题独立提供；四种主语都可接would，答案依赖时点和归属。
- q03→q08→q15共享来源适用性方法；联合方法支架已承认，不当作三份独立能力证据。q15的同名单计数冲突仍须根据该题独立记录判断。
- q04与q16共享主体归属方法；q01与q14共享解释思路。没有从前题复制后题完整排序块或三组配对答案。新增提示只指向本题查证步骤，不加入后题答案词块。
- q09匿名信息与q10删例子可共同提示公开文本删减这一一般动作，q18仍不是独立隐私测量；它要求区分语言转换与公开范围。前题没有translated/omitted完整答案组合。
- q10–12的condensed/retracted/reallocated未由本组前题材料、解析或新增提示直接给出；旧稿withdraw与retracted的近义关系仍按原审阅视为迁移，不能宣称概念从未教授。
- 故事的quiet notes只表示音乐安静，不能替代q05的预设结论与参与形式落差。故事全篇不提供填空答案组合或排序句块。

本次只复核当前18题及已记录的跨题风险；没有重新穷举正式全池随机共现，也没有宣称混卷独立性已验收。

## 实际校验与未通过项

使用当前 `content.ts` 的questionSchema：15道文字题全部通过。另在内存中抽取15道文字题并同步收窄goalIds，仅此文字单元投影通过unitSchema（含单元级细化）；保存文件仍为原18题，没有删去听力或改写为阅读。使用当前 `grading.ts` 的gradeAnswer对完整待媒体题对象直接调用：23个正确案例和82个错误案例通过，包含九道选择题所有候选、三道填空原答案及大小写/空白/句末标点变体、两道排序各24种排列、配对逆序提交与错误配对、两道cloze正确/反向/不完整组合。这是判题函数证据，不是听力对象通过schema或完整前后端旅程。

另逐字核对所有原material+prompt、解释、候选、词块、配对、acceptedOrders、passage、acceptedFills及audioScript；故事拼接完全一致。作者没有提供额外语义答案变体，因此不存在丢弃其他合法变体的情况。

完整unitSchema确实失败，当前实测仅返回三道音频各三类问题，共9条：缺少audio.assetId、缺少audio.voice、严格对象不接受status/scriptVisibility/suggestedWordsPerMinute/delivery待制作字段。这是刻意保留的发布阻断，不以占位素材绕过。unitSchema只校验goal ID结构和单元内引用，不检查目标在catalog是否登记，更不检查目标语义覆盖；登记检查另发现cross-source-reconciliation不存在。音频结构失败还会阻止依赖完整对象的单元级细化校验，因此不声称18题完整单元通过。

媒体剩余：q07两声线约150词/分、q08单人约150词/分、q09两声线约145词/分；按各题delivery自然表达，不读A/B、不用答案提示性重音。需制作实际音频、注册真实资源与voice、核听发音/话轮/清晰度/实际语速及答前隐藏，再清除待制作字段并复验完整单元。20分钟只为正式合同内的初始估计，18题实际耗时仍需原生连续作答确认。

本次没有修改正式题库、catalog、源码或部署文件，没有提交或发布。作者稿及现有主审记录保持不动。

## 展示文案复核

依主代理要求，仅将summary改为“穿上旧外套出门，口袋里的一颗纸星星唤起了多年前的回忆。”，贴合开场故事。未改其他单元字段或题目内容；工程状态和能力边界继续留在authorship及本复核记录。

## 主代理目标决策

主代理读回本记录、新增操作说明和提示后，采用明确新目标，不扩大既有定义：q01改挂mechanism-inference，q06改挂agreement-action，q10/11/12/18改挂action-wording。以上目标及cross-source-reconciliation都仍待catalog登记，canonical的goalIds同步反映实际题目引用。前文逐题表记录的是转换提交时的旧映射，本段是最终决定；没有改动材料、题干、候选或答案，也不把新目标当成已经注册或获得独立测量效度。
