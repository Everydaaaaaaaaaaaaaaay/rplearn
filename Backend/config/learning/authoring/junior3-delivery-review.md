# 初三正式接入准备人工审阅

2026-10-11。交付仅新增本报告与 `junior3-delivery.astra.json`，不修改源题面、正式单元或运行时代码，不提交、不调用生产、不制作音频。本人逐项阅读36候选题与9个正式初三单元54题，包含题面、候选/词块/配对、答案、提示和解析。不是程序相似度扫描后自动定互斥；程序只检查计数、英文词数、引用和实际ID。

## 双语故事

亲自写成英文及逐段中文，保留原事件。每篇130英文词（空白分词），各三个`opening.1`至`opening.3`，全部`afterQuestion: 0`、`speaker: 旁白`。字段参照正式 `companion.senior1.window-rainbow.json`，未借用其高中难度。

“卷起来的角”保留湿长椅、屋檐窄窗台、地图卷角、钥匙压纸、风翻出旧笑脸、折纸时把笑脸留在外面。“最后一格光”保留陌生小路、小窗光斑、光移向台阶、一起换角度、照片里两双鞋、取消裁剪、回程窗格已暗。没有结尾口号，没有职业设定，也没有候选或旧库听写完整答案。钥匙、地图、窗户与题中同类名词出现不构成作答条件；两故事可跳过，所有题仍独立。

## 逐题操作合同与近邻判断

交付`questions`仅含`id`和`instruction`，没有复制或改写题面。A11/B08明确“有一块多余”，不能用“全部词块”；其余排序明确使用全部词块。短指令不提前揭示选项或所填英文。

| 题 | 人工核对与旧库边界 |
| --- | --- |
| A01 | 许可问询不是地点；旧ask-room主要查从句语序，本题还需辨意图。通用if词不触发全目标互斥。 |
| A02 | 伙伴变化、安静偏好保留；旧former-shelf完全停止，任务不同。 |
| A03 | 三块最低门槛排序；与labels-written同类脚手架，登记择一。 |
| A04 | 三项完整语法，靠邀请方向；旧two-photos主要查复数be，保留。 |
| A05 | 指定be原形；旧there-used填used，不能把相同结构中出现be当独立答案泄漏。 |
| A06 | 许可强度到中文对应；与rule-strength核心操作重复，登记择一。 |
| A07 | 相同ticket下匹配实际回应；旧enquiry-intentions按不同信息类型配目的，保留。 |
| A08 | 完整are collected；旧sent-form只产出sent，词形及操作不同。 |
| A09 | 听是否运行；旧问询材料不含电梯运行事实，保留。 |
| A10 | Did you use to完整句架排序；与did-you-work实质同任务，登记择一。 |
| A11 | found/left均合语法，必须听；旧过去被动题不提供录音事实。 |
| A12 | 食物禁令与水许可范围；旧no-running产出ing，操作不同。 |
| A13 | 否定从句仍用does；旧start-form省疑问does再产出starts，不能同类化。 |
| A14 | 相同人名、反向帮助、否定帮助；已不再是旧record-time的时态配对。 |
| A15 | 听习惯变化且拒绝“每节课一定”；旧then-now-labels不提供该完整事实。 |
| A16 | 必须存放的情态被动构造；与bags-rule实质同任务，登记择一。 |
| A17 | 六词听写含broken；旧was-repaired不是完整听写答案，保留。 |
| A18 | 已知地点、缺路线；旧booking-order是单一报名句架语序辨析，保留。 |
| B01 | 每日变周末，没有完全停止；区别旧former-shelf的现在不卖。 |
| B02 | 未经许可的禁令范围；旧allowed-entry填be，操作不同。解析语义边界见下。 |
| B03 | bags/tickets绑定两个地点；旧daily-check相同are checked未提供地点答案。 |
| B04 | 拼写目的与礼貌方式双判断；旧ask-room主要语法判断，保留。 |
| B05 | 关机≠禁用；相同phones避免名词捷径。相较旧rule-strength增加动作边界，保留。 |
| B06 | if there is…left与旧whether-seat相同存在句是否空，登记具体答案互供。 |
| B07 | 完整were taken与旧two-photos完全相同；photo-taken和caption-meanings也供应指定take的分词taken，共三条具体题对。 |
| B08 | should/could听辨后排序；旧ask-room不提供应选情态，保留。 |
| B09 | 未知执行者不可臆加brother；旧daily-check没有该语用决策，保留。 |
| B10 | 填过去简答did；旧did-you-work选择完整问句，未提供Yes,I did简答答案。 |
| B11 | by短语两位置均收；旧wall-painted没有作者位置选择，保留。 |
| B12 | 姓名必填、照片可选的听取绑定；旧rule-strength只提供通用情态意义，保留。 |
| B13 | 同动作的过去习惯/昨天事件/当前习惯；旧then-now-labels含过去否定而无单次事件格，保留为迁移。 |
| B14 | 不确定时适当回应；旧问询题不供应回应，保留。 |
| B15 | 将will we need改为we will need；与旧polite-arrival相同将来间接问句词序任务，登记择一；if-two-jobs是不同功能辨认。 |
| B16 | 六词完整听写；旧former-evening只给通用used to，不给share a room原句。 |
| B17 | only紧邻时间，不能前置限定Maps；旧labels-written无范围决策，保留。 |
| B18 | 制作者/接收者/过去时间三关系；旧covers-last-week没有双动作双角色互换，保留。 |

`record-corner`全部6题、`reusable-cafe`全部6题，以及其他单元的条件、定语从句题均亲读；没有找到与本批候选的具体答案或局部任务重合，不为覆盖率虚设互斥。

## 真实bank身份与互斥范围

仓库中不存在 `Backend/config/learning/bank/` 逐题目录。本轮实际读取 `bank.json`、`bank-catalog.ts`、`bank-content.ts`，并执行项目的`loadBankCatalog("Backend/config/learning")`取得54条初三正式记录的公共ID。公共ID是`question.`加`bankIdentity`的材料哈希，不是`unitId/localQuestionId`。JSON九条互斥均保存完整64位哈希ID，并保留来源单元和局部ID。只确认当前本地已审核catalog身份；未声称检查了生产数据库。

互斥组采用具体题对：5组是实质同类任务择一（A03、A06、A10、A16、B15），4组是直接答案互供（B06一组、B07三组），共9条。每组只有一个候选及一个旧题。候选B07加入三个不同组，不把三个旧题彼此自动互斥；不把整个被动/问询目标互斥。

通用语法词if/whether/be/use/used在其他题出现属于可迁移知识；除同一具体词形产出（take→taken）或相同句架缺口（if there is…left）外，未仅凭共词设互斥。含if的所有题不是彼此独立盲测，但无须将整个间接问句池清空。交付数组是接入提案，不代表运行时已登记或任意抽卷已验收。

## 教材阅读与发现

本轮实际目视读取缓存`build/learning-research-20260926/pep-junior3-archive-p34.png`整页，印刷20/PDF34：Grammar Focus礼貌问询、4a改写、4b场景信息需求（含if there is）、4c游客问询。确实是正文而非目录。已读源稿sourceReading与前次审阅记录，但没有将它们列出的其余页冒充本轮重新目视核读；未读全册，未声称当前新版。

B02的英文正确项只表达“未经许可不得开窗”，许可是必要条件；“获得许可后可以开”来自题面额外规则，不能单由该英文句推出。已把精确语义问题报告主代理。主代理告知已在源稿explanation澄清这一区别，本交付未擅改题面或选项。该局部解释修订不意味着媒体、UI或生产已完成。

## 核验与剩余门槛

完成JSON解析、36个指令ID与源稿一一对应、每条映射仅两字段、两故事各3个前置beat、词数、9个旧库ID与单元局部ID实际对应及diff空白检查。未运行App构建、原生操作、真人听感或生产检查。主代理可据此继续音频、字段转换、互斥写入与组卷验证；本文件没有将其记为完成。
