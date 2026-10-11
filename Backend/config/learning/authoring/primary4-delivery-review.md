# 小四接入交接：作者逐题审计

2026-10-11。Astra 小四独立作者亲读、亲写，程序只保存文本及检查格式、数量、身份引用。此为未发布交接，不是主代理终审结论。只新增本记录和 `primary4-delivery.astra.json`，未改主稿、未提交、未操作生产。

## 核读与判定范围

本轮实际目视查看14张PNG：PEP印刷17/24/27/48/51/58/61（缓存尾号22/29/32/53/56/63/66）；译林印刷18/24/25/32/33/38/39（尾号21/27/28/35/36/41/42）。已重点重读许可中的I/you、归属中的mine和姓名所有格、try them on及衣物单复数。只依据旧版缓存页，不重验原PDF哈希、不声称读过相邻19页或当前新版。已读原作者稿、原审阅记录及10月7日收尾记录；本轮读过的图像不能算音频或界面验收。

正式比较对象来自catalog的全部9个小四unitId，各6题，共54题：`oliver.primary4.reading-clock`、`oliver.primary4.rainy-reading`、`oliver.primary4.lost-clothes`、`ruby.primary4.cafe-morning`、`ruby.primary4.indoor-volunteers`、`ruby.primary4.clothes-rail`、`marcus.primary4.market-price-tags`、`marcus.primary4.season-photos`、`marcus.primary4.park-sketches`。36道新题逐项对照上述54道旧题的题面、选项/词块、提示和反馈；7道新听力还读脚本。没有猜bank哈希。旧题用unitId/localQuestionId定位，交接JSON保留每一条独立证据。

判断含正反两个方向。前题干扰项也是可见内容；答后反馈保留。相同完整答案、同句空位、同一具体动词/姓名词形或同一词义配对登记；只有can后原形、不同主语的单复数be、不同钟点前at等通用教学迁移，不自动互斥。短语词义与听力要区分方向：看到forty与40的配对不能免听A13；A13答后明确forty=40却会直接完成旧配对，这个方向仍需排斥。共同框架保留，不能把练习当作36次独立掌握诊断。

## 逐题结论

“接受”仅为作者接受保留正文，不意味着无互斥或可发布。表中旧题短名均可在JSON找到完整unitId；未列冲突不等于未读旧题。题目操作语36条均单独亲写，A02/A16/B12保留指定开头，A02保留活动—钟点—时段顺序，A18保留提及而非钟点顺序；A17/B16保留共享词库两空而非变成单选。

| 题号 | 结论 | 本组及跨组具体复核 | 与现有54题比较及处理 |
| --- | --- | --- | --- |
| A01 | 接受 | 四点完整报时；A02五点、A03晚饭六点均不提供该完整句。 | four-thirty是半点，不直接给four o'clock；when-answer为活动时间，属不同任务。 |
| A02 | 接受 | 五点作业的完整事实不在A18（作业六点）；原形与时间框架复现不算整句抄写。 | at-two、breakfast-seven仅给不同活动/钟点的通用at结构；本题不填at词形，未列排斥。 |
| A03 | 接受、媒体待验 | 六点晚饭与八点就寝；A18晚饭七点，无法替代听取本题事实。 | daily-plan教have dinner、break-labels教go to bed，但均不提供六点/八点事实配对；必须听。 |
| A04 | 接受、有互斥 | B02逐字给It's time to go home，登记跨组。 | time-to-read动作不同，只迁移to/for规则；旧库无同一go home的to空。 |
| A05 | 接受、有互斥 | A06三种降水/风类不含cool/cold；B03回答warm而非本题二词。 | weather-cards给cool中文，cold-caption反馈给cool/cold全部映射，分别双成员互斥。 |
| A06 | 接受、有互斥 | 题面逐字给B04排序句；跨组排斥。 | weather-question同问句；weather-cards给rainy词义；rain-report同天气核心句。三对分别登记。 |
| A07 | 接受、依赖A17提案 | 原A17的第一空I可抄Can I；换情境不能解决。A17提案改为两次不同许可结果判断；A07只给许可请求句架，不提供两次老师决定。 | sit-request、go-inside是不同动作的Can I；非完整答案相同，未将整个许可目标排斥。 |
| A08 | 最小替题提案 | 原Yes,I can干扰直接给同组A15完整能力短答；换Yes,he can。原对A17的I/you反馈直给由A17替题解决。与B15仍有Yes,you can整句复现，登记跨组。 | permission-answer同正确句；can-draw-answer干扰及解释也给you句，分别登记。 |
| A09 | 接受、媒体待验 | Mia才是音频主人的事实，A10及B07都未提供Mia；两声部仍必需。 | ben-scarf给主人Ben，不能回答Mia；姓名加's是通用教学，无同名目标词形。 |
| A10 | 接受、有互斥 | B17同帽子、自有视角给It's mine及yours，跨组排斥。 | mine-not-my同帽子mine填空，互斥；these-yours整句排序的构造并非本题答案。 |
| A11 | 接受、有互斥 | 本组无另一鞋子too small完整答案；B16给too small但不是本题完整复数回答，只保留一般意义迁移。 | too-small的___ small可直接抄too；fit-words的just right配对可由本题反馈完成，分别登记。 |
| A12 | 接受 | 三块围巾问价；B18物品代词句不同，未把所有How much都互斥。 | price-hat问帽子、try-shirt的T恤干扰是句架迁移，不是同完整围巾句或同词形空。 |
| A13 | 接受、有互斥、媒体待验 | 40元录音不由A12或B10的30元提供；依然必须听。 | 答后forty=40直接完成price-labels其中一条，登记有方向的风险。 |
| A14 | 接受、有互斥 | B13选项仅中文秋天，未给autumn/fall拼写；不因此自动排斥。 | autumn-word同目标词及变体，直接可抄，互斥。 |
| A15 | 接受、依赖A08提案 | 原A08的Yes,I can直给已建议移除；A16换宾语tree仅共享can see框架。与B15同完整短答、与B01同What can you see意义，各自跨组互斥。 | ask-visible同问句；draw-question同句缺draw；help-signs同绘画问句；can-draw-answer同短答；no-swimming干扰展示同短答，五对独立登记。 |
| A16 | 接受 | A15是flower，未给tree完整句；没有仅因I can see框架判冲突。 | see-two-boats为复数两船，carry-box为另一动作，不直接给完整树句。 |
| A17 | 替题提案、交互待验 | 根据主审退回意见，撤回open/use辨形稿。改为画画获准、带画回家未获准两段自足情景，共享can/can’t两块，分别理解许可结果。A08未给这两个事实，不能套一个同意短答解两空。 | 删除已失效的open词形互斥；新版can’t会提示B14拼写，登记跨组。新版can draw会提示can-draw及draw-question的具体draw词形，分别登记新旧对。 |
| A18 | 接受、媒体待验 | 顺序dinner→home→homework，非钟点先后；A03两个活动无该完整顺序，A02作业时间也不同。 | when-answer有go home at five干扰，但不提供三活动的提及顺序，故不把共同单句片段当完整顺序答案。 |
| B01 | 接受、有互斥 | A15同What can you see及语义，跨组已列；其他题不提供When do you have lunch整句。 | do-you-start只测When ___ you的do，本题完整问句给同助动词形式；ask-visible同干扰问句和语义，各登记。ask-breakfast换宾语属一般When框架。 |
| B02 | 接受、有互斥 | A04同go home句的to空，已列；本组无同午饭for空。 | time-for-lunch同完整午飯句空；time-to-read反馈示例也直接给time for lunch，各登记。 |
| B03 | 接受、有互斥、媒体待验 | 问句cold非事实，必须听No及warm；A05没有warm/No答案组合。 | not-cold的暖和不冷事实与完整否定答句同构同事实，登记。 |
| B04 | 接受、有互斥 | A06题面逐字给整句，已列跨组。 | weather-question整句仅缩写差异，互斥。 |
| B05 | 接受、有互斥 | 原题自然场景区分许可，不用中文直接复述答案；新版A17测许可结果，B05的draw原形不提供老师的两次决定。 | can-draw及draw-question仅要draw形式，本题给can后的draw，分别登记。go-inside是通用功能，不含本题同动作整句。 |
| B06 | 接受 | 原B16 gloves已换shorts；完整同主语词形冲突已去除，仍共享复数be知识。 | these-are不是gloves同主语空，whose-coat也不是同完整问句，只是一般所属/单复数迁移。 |
| B07 | 最小替题提案 | 把mine换Ben's并去掉我的/自己反馈，彻底去掉B17目标代词的直接教学；c仍Leo's。 | 新Ben's会给ben-scarf中同姓名所有格辨形，新增该具体互斥；不与所有人名所有格题一概排斥。 |
| B08 | 接受、有互斥、媒体待验 | 裤子too long不同于B16短裤too big；复数are只是共同规则。 | fit-words的too long/too short中文配对由本题反馈直给，登记。 |
| B09 | 接受、有互斥 | B11用these shoes，而本题测them，不是同完整代词句；A17提案也不再用try it。 | try-them完整Can I try them on直接填空，互斥。 |
| B10 | 接受、有互斥 | B11是60元，A13是40元，都不提供本题30元事实答案。 | price-labels给30元词义；pair-price的单数干扰It is thirty yuan逐字给答案，各登记。 |
| B11 | 接受 | 试穿与报价配对；B09未展示Of course,Here you are，B10也未给60元回应。 | try-shirt/try-hat虽同试穿目的，但没有本题完整许可递物回答；不扩大排斥到购物主题。 |
| B12 | 接受、有互斥 | 冬天滑冰题面已给，不从活动猜季节；B13为夏天划船，没有同活动完整句。 | winter-caption直接复现in winter；season-names的winter映射可由本题反馈完成，分别登记。 |
| B13 | 接受、有互斥、媒体待验 | A14秋天不提供录音summer；B12冬天也不提供录音事实。 | 答后summer中文直给season-names；summer-swim的具体in summer短语复现单独列出，不扩为所有季节题。 |
| B14 | 接受、依赖B15提案 | 原B15 No,I can't可直接抄can't；替换该干扰后本组无同否定词形答案。 | cannot-see同句空；no-swimming、help-signs展示并解释cannot，分别登记。 |
| B15 | 最小替题提案 | 把No,I can't换Yes,they can，去掉B14词形暴露。改成只测人称，须主审接受；仍与A15的Yes,I can及A08的Yes,you can跨组排斥。 | can-draw-answer正确短答、no-swimming干扰短答都给Yes,I can，分别登记。 |
| B16 | 接受、有互斥、交互待验 | shorts修订避免B06同gloves/are直给；B08不同衣物只是一般复数模式。 | dress-is同This dress空；shorts-big整句逐字填第二空；本题too small又直给旧too-small空，三对独立登记。 |
| B17 | 接受、依赖B07提案 | 保留双视角迁移，B07去mine后无需拆题；与A10同帽子视角具体答案，跨组排斥。 | mine-not-my同帽子自述mine，登记。these-yours只有共同物主代词规则，不是同完整句排序。 |
| B18 | 接受 | How much is it不同于A12围巾句、B10衬衫问句和B11外套问句；不把询价框架一概排斥。 | price-hat保留hat名词，未出现相同代词答案；只是询价迁移。 |

## 四个最小修改与固定组处理

原稿中确认的五对固定组风险：A07/A17、A08/A17、A08/A15、B07/B17、B14/B15。不用重排、不关闭反馈、不加内部互斥造成18题缺口。提出四份完整newQuestion：A08替一个干扰；A17改同目标同cloze的两空测量内容；B07替一个干扰；B15替一个干扰。前两对由A17一起修复。主审不接受初版open/use动词辨形提案，本次已撤回。新版A17亲写两个许可结果相反的情景：纸上画画获准、带画回家未获准；每段自足，题干不预给英文肯否答案。A08的can/can’t是共同许可意义支架，学生仍须分别依据本题两件事作选择，不能直接照搬一个完整回答。两词两空存在排除法，诚实承认测量强度有限。B15保留“我能”的能力回答子目标，只移除直接展示否定词的干扰，不声称消除了共同人称教学。

JSON共52个独立双成员互斥建议：7个跨组新新对、45个新旧对；不合并连通分量。这个数不包含上述五对已用提案处理的原稿组内风险，也不统计既有54题之间的旧旧关系。互斥列表假定四项替题全部采纳；如被否决，应继续亲写替题，而非给固定组加内部排斥。仅元数据不能证明混合组卷仍完整，主代理须用真实银行身份映射后验证。

## 故事与操作语

A保留雨来、接住画册、入室、换出第一本书的小事件，英文77词；B保留风吹散照片、意外入镜的手、选为相册封面的小事件，英文75词。各三段，均旁白、afterQuestion=0、skippable=true。两人只是同行者，不限定姓名或职业。采用现在时短句，必要保留cover、slips、gust、camera等事件用语并有自然中文译文；没有把所有词宣称为所读教材词表。没有题目所需的钟点、价格、主人姓名、排序事实或完整许可/归属/问价答案句。A中fall是雨落动词，不解释成秋天或暗示A14拼写；若儿童试读认为负担大，可改为drops of rain，需主审决定。

36条instruction对应原ID；单空仍保留候选范围，未伪称已有点选控件；多空明确共享词库而非每空各造一套词。新版A17只有can/can’t两块配两空，操作语已去掉“有多余词块”；只有提案审定后才能定稿接入，不能把这条新指令套在未变更的旧三块题上。

## 验证与边界

已用程序检查JSON可解析、36条指令ID与原稿逐一对应、两故事各三段且词数60–85、每对恰好两个成员、旧题定位真实存在、互斥ID唯一、四份提案ID及关键答案引用有效。检查只验证结构，不冒充教学审阅。未制作/审听七段音频，未实现或验证多空界面，未进行儿童试做、生产导入、媒体/UI验收。新稿还需主代理亲自审定后才可进入正式目录。
