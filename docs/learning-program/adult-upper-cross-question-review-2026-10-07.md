# 六级与高级正式题库：跨题提示审读

2026-10-07，只读审阅当前本地正式稿。范围为四单元各18题，共72题；亲自逐题读取题干、选项／词块／配对项、答案、hint、explanation、全部音频脚本及12段双语开场故事。程序只展开原文、列出ID／目标／题型和核对计数；以下语义分级不是字符串命中自动判定。本轮未改正式内容、未提交、未访问线上、未播放实物音频，不是声学或发布验收。

结论：高级`adv.astra.a04 → adv.astra.a14`存在较强的答案词与语义对照预教；六级`cet6.a03 → cet6.a08`确实先暴露`suggests`，但来源是错误选项，不宜称为“已明确教授正确答案”。另有可混抽的`suggest(s)`提示和听写搭配预教。没有在这72题中找到前题逐字给出后题整句听写答案的情况；同目标的普通方法迁移大量存在，不能统一算成答案泄漏，也不能据此声称后题成绩完全独立。

## 实际共现与揭示机制

源码依据：[bank-catalog.ts](../../Backend/src/modules/learning/bank-catalog.ts)、[bank-content.ts](../../Backend/src/modules/learning/bank-content.ts)、[bank-repository.ts](../../Backend/src/modules/learning/bank-repository.ts)。

1. `loadBankCatalog`把每道正式题转换为全局候选；蓝图只保留原单元的顺序化`goalId/type`插槽，不将原单元ID写成候选约束。完整故事随蓝图保留。
2. `assembleBankQuestions`先限制同`level/topic`、角色许可与可用状态，再按每个插槽的`goalId/type`匹配。`used`在本轮初读版本只防同一bank ID再次入卷，没有有向提示边、共享答案族或来源单元排斥。收尾复核发现主代理同期已在共享工作区加入可选exclusionGroupIds及回溯；本报告不把该在途修改说成旧逻辑。当前本次读取的正式四单元／bank分类没有这些提示边的实际互斥登记，所以不能由字段存在宣布E1–E6已排除。
3. 四单元在`bank.json`均为`projects`、`roleKeys=[]`。当前清单同level/projects的候选恰为该级这两单元各18题；六级与高级之间不能混抽。不能仅见同topic就声称跨级同卷。
4. 新题条件为未seen且未mastered，另可纳入mastered且reviewDue的到期复习；先挑未掌握题。实际用户候选还受数据库published、接触和掌握记录影响。本报告证明存在合法本地蓝图位置，不声称某线上用户已抽中，也不声称所有题对每次都会共现。
5. 本文“固定顺序”指正式JSON中的题数组顺序；“蓝图槽位”也以该数组从1开始编号。局部题号a14不等于第14题。
6. [LearningChallengeView.swift](../../Packages/LingoKit/Sources/LearningFeature/LearningChallengeView.swift)在提交前可展开hint；收到feedback后显示解析，答错或跳过另显示solution，之后才点“继续”。故前题选项无须答错就能曝光，前题解析可在后题前读到。
7. [content.ts](../../Backend/src/modules/learning/content.ts)的`publicQuestion`不返回audio.text、解析或答案；音频题只返回assetId。当前iOS听力控件未发现整段脚本文本面板，不能把作者库的`audio.text`误报为作答前文字泄漏；学习者仍可听到音频，答错听写会看到完整solution。以下分别注明文本选项、音频内容或反馈，不混同这几条途径。

蓝图简称：R=`bank.companion.postgraduate.rainy-screening`；M=`bank.companion.postgraduate.missing-piece`；W=`bank.companion.advanced.waiting-room`；P=`bank.companion.advanced.paper-moon`。下表槽位均给一个或多个确实匹配的方向；只需某合法选择会出现问题，不要求随机抽样命中后才承认风险。

## 真实提示边及建议

|编号与有向双ID|来源字段 → 目标字段／答词|固定顺序及蓝图共现|判定与建议|
|---|---|---|---|
|E1 `adv.astra.a04 → adv.astra.a14`|前题`options[a]`给出`verified the cost estimate`，`prompt`有`did not endorse`，`explanation`以“未必核实费用／不等于支持延后”解释边界；后题`prompt`让人在`verified / endorsed / proposed`中选，`acceptedAnswers=[verified]`。|W固定第3→8；W语义choice槽3或6都可抽到a04，completion槽8可抽到a14。P没有semantic-register completion槽，不能在P声称此对共现。|**较强答案词／对照预教，建议优先修复。**虽前题a整项错误，其中verified对应核实的局部语义已曝光，后题再次考核实vs支持。不是后题整句逐字给出。建议独立改写其中一道的目标词辨析情境，或按冲突边禁止同卷；单把前题正确答案字母换位无效。|
|E2 `cet6.a03 → cet6.a08`|前题`options[c]`为`failure to complain suggests that they are dissatisfied`；后题`prompt`给`suggests/proves/guarantees`，`acceptedAnswers=[suggests]`。前题解析不把suggests定义为“正确推断”，反而否定从无投诉推不满意。|R固定第2→8；R faithful-choice槽2/5→precise-completion槽8/10。M也可在faithful-choice槽6→precise-completion槽11形成该方向；不是M槽4的目标一定被槽6提前提示。|**真实词形曝光，风险中等，不能夸大为正确答案直教。**错误项也会让后题唯一目标词熟悉，但该错误项本身不能证明选suggests。建议对低题量单词填空做答案词族互斥；若保留，计为重复词汇练习而非独立掌握证明。|
|E3 `cet6.second.03 → cet6.a08`|前题`options[c]`有`The brief observation suggests a benefit...`，与后题`This observation ____ that...`同为observation＋suggests；音频和解析明确“尚未确立好处”，所以c整体错误。|原稿跨单元；M listening-choice槽1/2/3可抽second.03，precise-completion槽4或11可抽a08。R没有listening-choice槽，不能容纳此来源。|**结构接近的词形预热，比E2更像答句框架，仍非正确项证实。**建议与a08列同卷冲突候选，避免仅删R前题而混抽仍复现。|
|E4 `cet6.second.06 → cet6.a08`|前题正确`options[b]`有`The authors suggest that ... could ...`，错误c也有suggest；解析强调保留作者可能性判断。后题答词suggests；第三人称词形有差异，但“suggest＋可能性”的选词依据已经讲解。|跨单元；R faithful-choice槽2/5→precise-completion槽8/10；M faithful-choice槽6→precise-completion槽11。|**较强词义／词族支架，非相同词形逐字答案。**比E2更明确教授审慎措辞。建议将该边纳入a08冲突组或更换后题词汇动作，不仅处理精确字符串suggests。反向a08→second.06只教一般限定，无法区分second.06中方向正确的b与同样含suggest的c。|
|E5 `cet6.second.05 → cet6.second.08`|前题`left[l3]`为`The estimate takes account of maintenance costs`，`explanation`释为“纳入考虑”；后题音频／听写solution为`These figures do not take seasonal changes into account.`|M固定第5→8；matching槽5与dictation槽8/10能如此共现。R没有precise-wording matching和听写槽。|**部分搭配预教，非整句听写泄漏。**takes account of与take ... into account是相关但不同排列；前题未给seasonal changes、否定或全句。若目标为无提示听辨，应换其中一题的核心搭配或拆开；若是已学搭配精确听写，保留但不要把成绩当全新搭配掌握。|
|E6 `adv.astra.b09 → adv.astra.a14`|前题正确`options[c]`说`once the figures have been checked`，题干与解析对应核对后可发送；目标题为`The reviewers ___ the figures`，答案verified。|跨单元；W semantic-choice槽3/6可抽b09，completion槽8可抽a14。P没有目标completion槽。|**同对象核查语境的语义支架，低于E1。**未出现verified本词，不能独自确定它的词义；但先处理figures/check再作verified/endorsed辨析更容易。若对a14做严格独立测量，将该边一并复核；普通迁移练习可保留。|

E1–E6均未修改正式内容。建议先由主代理按产品目标决定：严格独立的挑战使用冲突约束；即时讲解练习则承认支架与复习，不把所有同目标题硬删。只隐藏解析无法处理来源选项和可听音频中的提示；仅调整原单元顺序也无法保证跨单元随机组卷。

## 可迁移但不是完整答案的关系

- `cet6.b06 → cet6.b08`：R第6→11，前题“免旅行不免可靠连接”与后题纸质选择的理由接近；后题全词块本就给出，仍需组织because关系。属于内容与论证支架，不是漏出的唯一缺词。R的argument-choice槽6与arrange槽7/11可共现。
- `cet6.b01 → cet6.second.10`：若只看“正面评价＋保留”很像，但M没有stance-intent choice槽，R没有dictation槽，当前两蓝图不能让该对同卷；只能是跨次学习迁移。
- `adv.astra.a01 → adv.astra.b17`：关联不等于因果是共同目标语义，前题associated与后题association词族有关；但W没有dictation，P没有evidence-causality choice槽，当前蓝图不能让这两题同卷。不能因同advanced/projects就报为真实同卷泄漏。
- `cet6.a14 → cet6.second.15`：前题要求解释证据如何支持结论，后题听力批评例子与主张的联系，语义很接近；M没有precise-wording choice槽，R没有listening-choice槽，当前不可同卷。
- `adv.astra.a03 → adv.astra.a12`、`adv.astra.b03 → adv.astra.second.c01`、`adv.astra.b07 → adv.astra.b12`：P中可先后出现，分别迁移“认可与质疑对象分开”“开放态度／预测不等于授权”“可能性不等于确定结果”。具体说话人、条件、行动和时间不同，没有前题给出后题完整答案事实；归为正常同目标巩固。
- `cet6.a16 → cet6.second.03`、`adv.astra.b15 → adv.astra.second.c03`：否定范围、澄清而非反对在概念上相关，但对应matching槽不在含后题听力的另一蓝图中，不能据此报同卷冲突。
- 两级隔离示例：`cet6.b07`的associated与`adv.astra.b17`的association、`adv.astra.second.a08`的on grounds of与`cet6.second.11`的grounds，不能跨级进入同一卷。

## 72题逐题审读账

“无直接边”仅表示在本轮这72题及当前蓝图内未发现完整答案／强答案词直给，不等于语言测量效度或全年去重验收。E编号对应上表，不把一般规则重复重复计数。

### R：雨声里的放映

|实际位置／ID|逐题核对结论|
|---|---|
|1 cet6.a01|高信心不等于信心增长，提示与解释是比较资料检查；无直接答词边。|
|2 cet6.a03|否定“无投诉足够证明满意”不推出不满意；c里的suggests构成E2，错误项性质已保留。|
|3 cet6.a06|access费用／时间／其他含义，正确项保持开放；向其他澄清题迁移规则，不提供它们的具体答案。|
|4 cet6.b01|promising与长期未知→cautiously positive；与听写评价主题相似，但当前槽位阻止相关跨单元同卷。|
|5 cet6.b04|no less与例外双边界，提示不提供其他题所需整句；与second.17同goal/type可交换，是不同判断轴。|
|6 cet6.b06|连接需求仍在，不取消免旅行收益；对b08有共同理由支架，非完整答案直给。|
|7 cet6.a07|Although让步词块全部在本题提供；与其他让步题同规则，不把本题自带词块误记为跨题泄漏。|
|8 cet6.a08|单一答案suggests的受控填词，接收E2/E3/E4；仍需区分来源前置是否真实可发生。|
|9 cet6.a05|Granted／For instance／Taken together各自功能；后续Consequently不是这些词的同答案复现。|
|10 cet6.b07|associated with与因果限制，三候选搭配不同；本级前题未直接提供associated答案词。|
|11 cet6.b08|纸质选择＋网络理由组句，与b06主题接近；目标是组织原因关系，非重复缺词。|
|12 cet6.a15|Consequently解释场地不足导致延期；故事实际另找场地放映，没有把本题延期结论预告。|
|13 cet6.a13|每千人投诉的共同分母；a01也检查比较基础，但未给本题per thousand users答案。|
|14 cet6.a14|请求支持依据，而非可读性／实施方式；与second.15相似却当前不可同卷。|
|15 cet6.a16|claim否定范围三种不同归属；无同卷后题直接照抄这些配对。|
|16 cet6.b13|百分比只覆盖实际自选回应者；与a01同证据目标，非同一材料／答案。|
|17 cet6.b15|人群、环境、时间限制；限定方法可迁移，未给其他题具体限制组合。|
|18 cet6.b18|同意试行但未定成功标准；对second.16公开标准题只共享criteria主题，事实不同。|

### M：少了一块的拼图

|实际位置／ID|逐题核对结论|
|---|---|
|1 cet6.second.01|加入白天而不取消晚间；支持条件由音频给定，未在其他题整句重现。|
|2 cet6.second.02|线上调查遗漏少上网者，不否定反馈本身；样本人群规则迁移，具体结论独立。|
|3 cet6.second.03|无证据不等于无效；c的observation suggests为E3，音频和解析不支持c。|
|4 cet6.second.04|raise questions而非解决／忽略疑问；本级其余题未给该缺词的直接搭配。|
|5 cet6.second.05|三种讨论动作；takes account of进入E5，另外draw distinction/address concern未形成目标答词直给。|
|6 cet6.second.06|作者归属＋可能性＋方向，正确b的suggest/could进入E4；b/c仍需辨关系方向。|
|7 cet6.second.07|真实节时、漏算维护、暂不信总优势；与second.14共享维护成本主题但判断目的不同。|
|8 cet6.second.08|否定季节变化未纳入的整句听写，接收E5的部分搭配预教，未见整句前置。|
|9 cet6.second.09|调查期间保留规则，确认跨场所问题再考虑修改；consider不等于必改，具体时序独立。|
|10 cet6.second.10|encouraging但far from conclusive；本级同卷来源未给完整句或far from conclusive搭配。|
|11 cet6.second.11|on the grounds that理由；高级里grounds不能跨级混抽，不误报。|
|12 cet6.second.12|unless保必要条件，不保证同意就延长；一般条件规则不等于其他题直接提供unless。|
|13 cet6.second.13|先在大中心测试再考虑全国扩展；受second.03慎推论方法支架，地点与行动仍须听。|
|14 cet6.second.14|两报价维护覆盖不一，应统一口径；second.07也谈维护遗漏但未给两报价答案事实。|
|15 cet6.second.15|例子与主张的支持联系未讲清；近义cet6.a14受蓝图隔离，不报同卷边。|
|16 cet6.second.16|公开标准且在开始前，不是无限延后；与b18同标准主题但已决未决不同。|
|17 cet6.second.17|更省时与两者不简单分别保留；与b04同goal/type可替换，但不共享答案事实。|
|18 cet6.second.18|无无偿加班是支持前提，预算问题准确接住；同条件目标而非既有整句复用。|

### W：候船亭里的八音盒

|实际位置／ID|逐题核对结论|
|---|---|
|1 adv.astra.a01|自选工具与逾期关联，无基线不能因果；与b17相关但当前蓝图不能共现。|
|2 adv.astra.a02|只读Park综述须透明归属；后续归属配对为规则迁移，无同一报告答案。|
|3 adv.astra.a04|acknowledge／verify／endorse边界；E1来源，前题a错误不抹去其中可学习的局部词义。|
|4 adv.astra.a06|尚不足排除记录错误，不等于最可能；与a07缺证目标相近，事实和模态不同。|
|5 adv.astra.a09|澄清样本代表谁，不是批准现有样本；向其他澄清题迁移方法，无直接答案。|
|6 adv.astra.b04|only/as many as添预期，中性数量无需评价；P可抽此题但其他目标无对应唯一答词。|
|7 adv.astra.a13|Although稳健估计／未计维护组句；高级P无cohesion arrange槽，不能拿其故事抽题混淆。|
|8 adv.astra.a14|verified缺词受到E1和较弱E6支架；目标单词与明确词义对照优先处理。|
|9 adv.astra.a15|supplier claims／本方测试／未来估计；可在P归属matching槽2出现，仍无前述三责任整组复用。|
|10 adv.astra.b13|作者suggest、may可能归因；六级suggests不同level，不能报跨级同卷。|
|11 adv.astra.b14|alternatively竞争解释，非推论或相似；当前高级其他题未提供该唯一答案词。|
|12 adv.astra.b15|关键词澄清／有理由质疑／暂缓表态；与c03澄清主题相关，但P无其matching槽。|
|13 adv.astra.a07|未确立差异不等于等效；a06提供方法支架，未给本题具体比较事实。|
|14 adv.astra.b06|主观清楚度与未测表现分开；a01也区分证据类型，无完整答案复现。|
|15 adv.astra.b02|清楚但导航慢的忠实转述，不能创造引语；其他题无该双重评价原文。|
|16 adv.astra.b05|学习快与学后少错分阶段；跨题可迁移多维度摘要，非已有排名答案。|
|17 adv.astra.b08|白天证据不支持全天，应补夜间；条件和采样方法迁移，未给另一题整句。|
|18 adv.astra.b10|去掉不完整表单→分析数下降，非回应人数或动机；其他题无该事件链。|

### P：橱窗后面的纸月亮

|实际位置／ID|逐题核对结论|
|---|---|
|1 adv.astra.a03|认可速度但质疑检查充分性；向a12迁移认可／质疑分离方法。|
|2 adv.astra.second.a08|记录主张、接受依据、决定行动分别配对；不能把grounds词与六级缺词跨级连接。|
|3 adv.astra.second.a10|笔误／改期／已确认白跑责任不同，完整责任才合要求；无其他题同事件答句。|
|4 adv.astra.a11|晚间出勤同时宣传更广，不能单归时段；支持一般因果边界，不提供b17整句听写。|
|5 adv.astra.a12|认可方案但支持日期取决检查排期；a03方法相关，后题条件须重新听。|
|6 adv.astra.a16|周三中午条件交付，未满足须另议；与a17同有条件，但不同日期／承诺事实。|
|7 adv.astra.a17|测试前提下的周四预测未确认；与c01预测非授权共规则，不是其实际要求答案。|
|8 adv.astra.b01|This指沉默被解释满意的推断；六级a03虽近义但level阻隔，不能同卷。|
|9 adv.astra.b03|允许探索非采购承诺；可为c01提供授权边界方法，不给其预测事实。|
|10 adv.astra.b07|潜在后续好处对照即时成本，could保可能；向b12迁移模态规则，不提供其呼叫预测。|
|11 adv.astra.b09|核对数字后才发送，不是个人不愿；E6来源，在W可能前置到a14。|
|12 adv.astra.b11|更正后归属为组发现缺记录、本人建议延期；c03亦更正标签，但主体事实不同。|
|13 adv.astra.b12|可能初期增呼叫，长期未知；没有其他题提供这句长期结论全句。|
|14 adv.astra.b17|association/not proven cause整句听写；W的a01不可同卷，P音频有因果概念但无整句前置。|
|15 adv.astra.second.c01|预测不要求新试验，不授权忽略真实请求；b03方法支架非答句复现。|
|16 adv.astra.second.c02|区间更窄是精度而非必然更近真值；本题音频内解释术语属可理解性支持，无前题答案。|
|17 adv.astra.second.c03|发言者撤回“反对”标签，Dana只问temporary；b11更正方法相同，未共享被更正事实。|
|18 adv.astra.second.c04|草稿反馈可引但需标版本，不能变终稿评价；归属和许可方法可迁移，具体许可独立。|

## 故事与音频揭示的边界

四故事全部三段在题前：R因线路进水临时楼上放映；M共同找回拼图；W取出旧票使八音盒复响、感应灯重亮；P折纸月亮意外像微笑并留下画。英文与中文逐段已读；没有故事逐字给出verified、suggests、raise、grounds、unless、alternatively、Consequently或三道听写整句。R“另有房间所以继续放映”与a15“无其他场地所以延期”条件相反，不能拿故事结果作答。

M的10段、P的8段音频脚本均纳入本次文字审阅，共18段；其中听写为M两题、P一题。本轮未验证音频文件是否与脚本声学一致，未以脚本文本可读取推定界面会显示脚本。音频里的普通词语和主题重合不一律登记为泄漏；E5明确只有搭配教学，缺词、否定、时态和整句接收仍须完成。

## 下一步与验收约束

- 优先处理E1；同一轮中用verified核实/endorsed支持的前题再测试后题，独立判断强度明显降低。
- 若修a08，须同时覆盖E2、E3、E4，不能只修改rainy-screening固定顺序而遗漏missing-piece或可混入的faithful-choice槽。
- 采用冲突约束时，应按真实全局bank ID落地，并保存来源字段、目标答案与方向；局部ID适合本记录定位，不足以成为运行时唯一键。
- 组卷验证应证明每条禁止边在所有合法目标蓝图中被排除，同时确保18槽仍能填满；不能通过静默少题或题型降级绕过问题。
- 内容改写必须重新逐题审阅、更新内容审阅哈希并检查媒体变化。当前报告不授权或宣布这些动作已完成。

本轮已完成72题、12段故事和18段音频脚本的只读文本审读；未作学习者试验、音频实听、运行时抽样或生产状态核实。

收尾覆盖复核：逐题表恰有72个不同ID，逐一对应四正式单元所有题目；12段故事、18段audio脚本计数相符，相对文件链接均存在。没有未读题。共享工作区bank-content.ts与测试的同期实现改动归主代理，本报告没有修改或覆盖它们；以上蓝图风险需在其最终约束登记后重新判定是否仍可共现。
