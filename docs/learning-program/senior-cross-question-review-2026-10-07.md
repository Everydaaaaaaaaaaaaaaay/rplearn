# 高中正式题库组内及跨单元提示审计

2026-10-07，Astra只读作者审计。亲读正式 `units` 中高一72题、高二90题、高三72题，共27单元234题；其中每档两个companion单元各18题，共108题。核对题面、全部选项或词块、提示、解析、标准答案、听力文字稿；另检查所有instruction。程序仅帮助定位相同词形、核对插槽及计数，以下风险均逐题人工判断。没有生成或修改正式题，没有听取实际音频、访问线上或运行完整测试；报告不等于发布批准。

## 结论与组卷边界

最明确的前题答案提示集中在高二 `checking`、`listening`、`gives`，高三 `collected`、`so that`。高一有跨单元 `the reason why…` 对同结构why填空的提示。高二第二组固定顺序确有 `s2.astra.second.q04 → s2.astra.second.q11`；其余五个companion固定18题序列未发现另一个同等直接的整句或同词形答案复制对，但仍有共同语法及策略的教学支架，不能因此称为18次独立测量。

核对了 `bank-catalog.ts`、`bank-content.ts` 与 `bank.json` 的当前实际实现：

- 每个正式单元形成一个同顺序的goal/type插槽蓝图。抽题先按level、topic、role和学习状态筛选，再按goal/type匹配；使用过的bank ID不可再用。
- 现有去重没有题间答案提示的互斥关系。`bankIdentity`以题型、题面和材料识别内容，不会识别“此题解析就是另题的填空答案”。
- **同年级、同topic只是必要条件。** 必须有一个实际蓝图同时提供双方的goal/type插槽，且需要两个不同题时有足够插槽，才能断言可同卷。
- 三档首组companion（paper-windmill、postcard-bird、folded-page）都在 `daily`；第二组（window-rainbow、shadow-boats、paper-boat）都在 `projects`。不能把两组的任意相似题直接说成当前可同卷。
- 高一旧单元分布为books两组、daily两组、community一组、projects一组；高二旧单元为books两组、projects七组；高三旧六组均projects。所有上述bank条目的roleKeys为空。
- 下述“可共卷”是当前本地题库和插槽允许，并假定双方符合用户seen/mastered等资格；没有声称某位线上用户实际抽到过。

## 已确认需要阻断或改题的有向关系

为避免旧题的 `q1` 等局部ID混淆，表内总写“单元ID / 题ID”。箭头表示前者的可见内容可以支持后者直接抄出答案。这里的“高”指会绕过主要作答步骤，不是内容本身错误。

| 编号 | 前题 → 受影响题 | 具体暴露字段与目标答案 | 风险和当前可共卷证据 | 建议 |
| --- | --- | --- | --- | --- |
| H01 | companion.senior2.shadow-boats / s2.astra.second.q04 → 同单元 / s2.astra.second.q11 | q04的prompt指定Checking开头，tokens[c]=Checking，explanation再次给Checking；q11让check在devote time to后变形，答案checking。 | 高；固定18题第4题就展示了第11题的完整单词，忽略大小写后可抄。虽语法位置不同，键盘输出词形相同。 | 人工互斥；若保留q04，可给该completion槽选择不含checking的候选。不要只调顺序或隐藏答后解析，因为prompt与tokens也暴露。 |
| H02 | companion.senior2.shadow-boats / s2.astra.second.q04 → marcus.senior2.interview-worktable / by-checking | 同上Checking；by-checking为by ___ the recording，给check，答案checking。 | 高；shadow-boats的-ing主语arrange槽与-ing角色completion槽可分别抽入两题。 | 和H01同一词形冲突，互斥可解决当前18题蓝图。 |
| H03 | marcus.senior2.interview-worktable / by-checking → companion.senior2.shadow-boats / s2.astra.second.q11 | 前题explanation直接写“填checking”“by checking”；后题同样要求check→checking。 | 高；interview-worktable有两个-ing角色completion槽，可以同时抽两题。shadow-boats自身仅一个此类completion槽，不能在它的单卷内同时抽这两题。 | 两道completion应互斥；见下方蓝图缺口，旧6题蓝图仅加互斥还不够。 |
| H04 | companion.senior2.shadow-boats / s2.astra.second.q11 → marcus.senior2.interview-worktable / by-checking | q11explanation给“to是介词，后接checking”；by-checking答案checking。 | 高；H03反向同样成立，两个completion插槽的选择次序可反转。 | H03/H04按无向不可同卷关系执行，不能只禁止其中一个先后次序。 |
| H05 | marcus.senior2.community-project-brief / listening-value → marcus.senior2.interview-worktable / job-not-action | listening-value的prompt、tokens[t1]及explanation给Listening；job-not-action要求listen的-ing形式，答案listening。 | 高；shadow-boats同时有-ing主语arrange与-ing角色completion槽，可先组Listening句再抄同词形。两题虽分别主语／表语，后题题面已直接要求-ing，剩余主要任务就是拼写。 | 互斥；18题可另选Checking主语句搭配listening填空，或Listening主语句搭配checking填空。仍需同时核对其他冲突。 |
| H06 | marcus.senior2.interview-worktable / ing-functions → 同单元 / job-not-action | matching左列l1完整写My task is listening…，提示也出现listening；后题My main job is ___ carefully，答案listening。 | 高；固定原文件job-not-action在第2题、matching在第4题，原顺序只构成后题复现；但公共蓝图第6题也是相同goal/type的completion，可抽job-not-action，形成matching先给答案的实际可行顺序。 | 互斥或亲写替题；仅把原文件第2题摆在前面不能控制动态抽题。 |
| H07 | marcus.senior2.community-project-brief / activity-focus → 同单元 / single-activity-agreement | matching左列l2：Sharing rough drafts **gives** others a chance…；后题Working with local families ___ us new perspectives，给give，答案gives。 | 中高；固定第4题在第6题前，都是整体-ing活动作单数主语、同一give词形，仅换活动宾语就能抄gives。不是看到任意第三人称动词就报警。 | 需替换其中一道或增加可填满蓝图的真实不同候选，不能只加互斥。 |
| H08 | ruby.senior2.volunteer-handover / reversed-history → companion.senior2.shadow-boats / s2.astra.second.q11 | reversed-history选项b中有while we were **checking** the tank；q11目标checking。 | 中；前题b错误在时间事实而非checking拼写，因此即便该选项未选对仍公开可复制词形。shadow-boats过去完成choice槽在第5题，-ing角色completion在第11题。 | 可作为checking词形的同卷互斥；有其他past-perfect choice可替换，不必改目标。不要把错误选项中的文字排除出泄漏审查。 |
| H09 | ruby.senior2.volunteer-handover / reversed-history → marcus.senior2.interview-worktable / by-checking | 同一选项b的checking；目标by ___的checking。 | 中；shadow-boats同样可抽此对。 | 与H08一致，可用候选替换／互斥解决。 |
| H10 | ruby.senior3.coastal-display-captions / q1 → 同单元 / q2 | q1正确选项a及explanation给the bottles **collected** by volunteers和过去分词collected；q2要求collect过去分词，答案collected。 | 高；固定第1题→第2题，同为被收集物的后置过去分词，仅bottles换shells。目标词形与结构都直接暴露。 | 6题蓝图没有替代choice或completion余量，需作者亲写替题；单加互斥将无法组卷。 |
| H11 | ruby.senior3.project-conditions / q3 → 同单元 / q5 | q3词块及explanation给**so that**，明确引出目的；q5仅从because/so that填入目的连接词，答案so that。 | 中高；固定第3题→第5题，都是行动+so that+everyone+can/could的近似句架，前题给出的不只泛泛“目的关系”。 | 6题蓝图的唯一arrange和两道必选completion之一冲突；需亲写替题或补真实替代内容，不可靠随机重排。 |
| H12 | companion.senior1.paper-windmill / s1.astra.b10 → ruby.senior1.meeting-place-details / q5 | 前题完整解释The reason **why** we cancelled the walk…，词块也有why；后题That is the reason ___ we changed the meeting time要求关系副词，答案why。 | 中高；同为daily，同goal的arrange可进入meeting-place-details第3槽，q5可进第5completion槽；固定the reason why框架几乎原样补空。paper-windmill本身没有这一completion槽，不能反过来声称此对能在它的18题蓝图内相遇。 | 可仅互斥解决：该arrange槽另有ruby原q3地点句，且其他插槽不因此缺候选；后续仍应观察同组关系副词巩固的密度。 |

H01/H02/H05/H08/H09是拼写线索暴露，不意味着两句语义相同或语法角色相同。若产品把后题作为已教后的抄写巩固，可另行保留，但不能把它算作无提示的词形掌握证据。此次按用户要求优先阻断同卷内这种直接复制机会。

## 为什么仅加互斥会让部分蓝图失败

下面按当前level/topic及goal/type实际候选检查，不按目录题数猜余量；`daily`候选不会自动补进`projects`。

| 蓝图 | 当前冲突与候选约束 | 能否只加互斥 |
| --- | --- | --- |
| bank.companion.senior2.shadow-boats | -ing主语arrange可用q04 Checking或listening-value；-ing角色completion可用q11 checking、by-checking、job-not-action listening。过去完成choice另有不同内容可替代reversed-history。 | 可以。可用Checking主语句+listening表语填空，或Listening主语句+checking介词填空；不是只把相同题排序改一下。此处仅说明冲突图有内容层面的余量，不是完成运行时回溯验证。 |
| bank.marcus.senior2.interview-worktable | 两个completion槽，在projects池只有job-not-action、by-checking、q11三题；by-checking与q11不能同选。唯一matching是ing-functions，它又会提示job-not-action。 | 不可以。禁止上述所有直接冲突后无法凑齐两个completion+matching。需亲写不同目标词形的新completion，或替换matching的listening材料；不能从daily借入sitting，也不能少出题。 |
| bank.marcus.senior2.community-project-brief | 两个-ing主语completion只有comparing-viewpoints与single-activity-agreement；唯一matching为activity-focus。后者与gives题冲突。 | 不可以。至少亲写／替换一个相关候选；只调arrange候选无助于必选的matching与gives填空。 |
| bank.ruby.senior3.coastal-display-captions | 此goal在projects中只有原6题；两个choice槽正好q1/q4、两个completion正好q2/q5。必须同时选collected来源与填空。 | 不可以。需要实质替题；不是把q1与q2排远一点。 |
| bank.ruby.senior3.project-conditions | 此goal在projects中只有原6题；唯一arrange为q3，两个completion为q2/q5。目的连接词来源与目标都是必选。 | 不可以。需要实质替题或新增独立内容。 |
| bank.ruby.senior1.meeting-place-details | arrange在daily池有原q3与s1.astra.b10；completion有原q2/q5。 | H12可以只互斥，选原q3即可。projects中的s1.second.c15不能跨topic替补。 |

因此至少四个旧6题蓝图需要作者内容工作。组卷器宜回溯找可行组合，而不是随机贪心选到死路后把缺题解释成全池无解；但回溯不能创造缺失的候选。本报告没有实现组卷代码，也没有作在线可用性声明。

## 共同规则学习：保留普通巩固，不自动判直接泄漏

以下仍应在独立诊断中控制密度，但没有把任意相同的had、it、who或whether都列成硬冲突。这里也给双ID，方便主审检查取舍。

| 题对 | 已读字段与目标 | 人工判断 |
| --- | --- | --- |
| oliver.senior1.book-donation-labels / q1 → 同单元 / q5 | q1的whose covers及解析教授所属；q5要求人的bag所属，答案whose。 | 是同规则教学支架；先行词由物变人、所属名词不同，没有给出whose bag原短语。可保留教学巩固，但不计两次独立掌握。若要求整卷无规则教学，需更宽的课程分组，不能称只是修复答案泄漏。 |
| oliver.senior1.book-donation-labels / q2 → 同单元 / q4 | q2解析“主语关系词不能省略”；q4选择books that are…。 | 后题还要核对复数谓语与完整结构，没有直接提供完整正确项；正常迁移。 |
| companion.senior1.paper-windmill / s1.astra.a06 → 同单元 / s1.astra.a18 | 海报完成／仍在印刷的matching在前；后题把已完成海报与仍核名单结合。 | 共同完成与进行规则、有海报场景复现；a06未提供a18的两项状态答案句。不是高质量新能力扩充，但不直接抄答案。 |
| companion.senior1.window-rainbow / s1.second.c03 → 同单元 / s1.second.c13 | 前题删除重复宾语it；后题比较主语／宾语关系词能否省略。 | 两题都要检查从句成分，但删除it与删除第二句that是不同输出和不同错误机制，可留作迁移。 |
| ruby.senior2.coast-survey-log / counting-since-dawn → 同单元 / since-or-for | 前题since dawn与起点解释；后题last Monday用since。 | 固定起点规则巩固，不是同一个空位或同动词变形；可以保留教学用途，不能作为互不影响的诊断。 |
| ruby.senior2.visitor-board-debate / acknowledge-concern → 同单元 / contrast-marker | 前题成本顾虑+however试用建议；后题更新快+供电限制，选however。 | 让步转折词复现，但前后事实关系仍要判断，且后题本已给however/therefore候选。可保留普通功能词巩固，非必须硬互斥。 |
| companion.senior2.shadow-boats / s2.astra.second.q04 → 同单元 / s2.astra.second.q06 | q04含checking whether every window is closed；q06 The question is ___…or not，答案whether。 | 都是未决问题，但whether已在后题候选内；需要识别主句与信息关系，不将单次出现whether自动等同泄漏。不同于q04→q11完整checking词形被展示。 |
| companion.senior2.shadow-boats / s2.astra.second.q06 → 同单元 / s2.astra.second.q08 | q06讲whether与that；q08配why/how/whether与具体桌子信息。 | 后题的三组对应还要阅读原因、方式、是否，不是抄whether一个词即可解全题；保留。 |
| ruby.senior2.volunteer-handover / boxes-before-arrival → 同单元 / question-before-shift | 前题had checked；后题过去完成疑问句填had。 | 指定时态的助动词共享属于规则复现，不因had字面相同自动标高危；仍可作为入门巩固。 |
| companion.senior3.folded-page / s3.astra.r06 → 同单元 / s3.astra.b06 | 前题区分版本已批准／未批准；后题needs to be approved问待满足要求。 | 同批准话题但被测结构及未知信息不同，没直接给后题完整正确释义；保留，控制题材重复即可。 |
| companion.senior3.paper-boat / s3.second.q02 → 同单元 / s3.second.q17 | 前题限制30位回复者样本，后题已确认8名／其他未查，填at least。 | 共同证据范围训练，不出现at least或后题人数；是把原则应用到新数量边界，而非复制答案。 |
| companion.senior3.paper-boat / s3.second.q05 → 同单元 / s3.second.q12 | 前题配短路线的距离证据，后题听写This route is shorter than the other two routes we tried。 | 前题未提供后题完整听写句，也未提供two或we tried比较范围；不能因同谈路线就判听写泄漏。 |

## 相似但当前没有“前题→后题”同卷证据的关系

| 题对 | 相似点 | 当前边界 |
| --- | --- | --- |
| marcus.senior3.exhibition-purpose / q3 → oliver.senior3.repair-report-focus / q5 | q3词块to be invited恰好是q5一个完整可接受答案。 | 两者同projects，但当前没有同时含这两个goal/type的蓝图。folded-page虽覆盖两个目标，却是daily；paper-boat是projects，却不含这两个旧目标。属于新增混合蓝图前应登记的潜在冲突，不冒称当前已能同卷。 |
| companion.senior2.postcard-bird / s2.astra.b17 → marcus.senior2.portrait-feedback / confused-visitor | I'm confused by this part…可直接给后题confused。 | daily与projects不同池，当前不共卷；跨课学习可能复现，不在本次已确认同卷硬冲突中。 |
| companion.senior1.paper-windmill / s1.astra.a04 → companion.senior1.window-rainbow / s1.astra.b04 | 两题共享the day we arrived的时间缺口。 | daily与projects不同池，不能据此声称两个18题蓝图会混成一卷。 |
| ruby.senior3.coastal-display-captions / q6 → 同单元 / q5 | q6左列The door is closed展示q5答案closed；q5的gate状态与之相近。 | 原6题与当前此goal蓝图的matching固定末槽，completion都在其前；没有当前前题先显示、后题再填closed的排列。属于反向复现风险，若产品允许回看修改前题或未来更改插槽顺序，应升级互斥；本次未确认这些运行时行为。 |
| marcus.senior3.exhibition-purpose / q6 → 同单元 / q5 | 三个to help片段包含q5全部答案。 | 同样matching末槽、completion在前，当前未证实向后泄漏。若能回改或将matching前移，需要再处理，不能只看到字符串就报告已发生。 |
| oliver.senior1.book-donation-labels / q6 → 同单元 / q5 | whose book直接显示所属词whose，目标whose bag。 | matching末槽，completion在前；原固定次序并非前题给后题。共享规则已在上一节列出，不重复夸大。 |

## 覆盖与后续边界

27个单元全部读完，包括六个companion的108题，不是只审程序命中的片段。程序辅助检索进一步核对了完整acceptedAnswers在其他题字段中的出现，并用当前插槽核对可能共卷；短功能词命中、错误选项中的偶然同词和无法共卷的关系都经人工分类。没有发现高中companion之间完整听写原句被另一题原样提前给出的新增硬冲突；这是对当前文字材料的审阅结论，不替代实际播放及界面隐藏状态验收。

建议主代理先保留上述12条有向硬关系的人工来源证据，再实施互斥及可行组合搜索；其中四个旧6题蓝图必须配合作者亲写替题。不要把系统返回空卷当作完成，也不要为了通过互斥验证撤掉必要插槽、降题型或少出题。对“普通规则巩固”应在产品测量解释上区分学后练习和独立诊断，不能把共同规则的每次正确都当作彼此独立的新证据。
