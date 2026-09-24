export type UnitQuestion = Readonly<{
  id: string;
  kind: "choice" | "order" | "write";
  prompt: string;
  options: readonly string[];
  answer: string;
  explanation: string;
}>;

export type UnitTemplate = Readonly<{
  id: string;
  roleKey: string;
  grade: number;
  title: string;
  objective: string;
  scene: readonly Readonly<{ speaker: "narrator" | "character"; english: string; chinese: string }>[];
  questions: readonly UnitQuestion[];
}>;

type Lesson = Readonly<{
  title: string;
  objective: string;
  line: string;
  translation: string;
  questions: readonly UnitQuestion[];
}>;

const choice = (id: string, prompt: string, options: string[], answer: string, explanation: string): UnitQuestion =>
  ({ id, kind: "choice", prompt, options, answer, explanation });
const order = (id: string, prompt: string, words: string[], answer: string, explanation: string): UnitQuestion =>
  ({ id, kind: "order", prompt, options: words, answer, explanation });
const write = (id: string, prompt: string, answer: string, explanation: string): UnitQuestion =>
  ({ id, kind: "write", prompt, options: [], answer, explanation });

// 原创短情境。目标按小学一年级起点、初中、高中递进；不复制教材课文或题目。
const lessons: readonly Lesson[] = [
  { title: "第一次见面", objective: "问候、姓名与回应", line: "Hello! I'm {name}. What's your name?", translation: "你好！我是{name}。你叫什么名字？", questions: [
    choice("q1", "对方先做了什么？", ["介绍自己", "问天气", "告别"], "介绍自己", "I'm ... 是自我介绍。"),
    order("q2", "排成询问姓名的句子", ["your", "name", "What's", "?"], "What's your name?", "What's your name? 用来询问对方姓名。"),
    write("q3", "用英语回答：我叫 Alex。", "I'm Alex.", "I'm 后接自己的姓名。"),
  ] },
  { title: "寻找蓝色物品", objective: "颜色与 this is", line: "This is my blue bag. The red bag is yours.", translation: "这是我的蓝色包。红色包是你的。", questions: [
    choice("q1", "谁的包是蓝色的？", ["说话的人", "听话的人", "没有说明"], "说话的人", "my blue bag 指说话者的蓝色包。"),
    order("q2", "排成“这是我的包”", ["my", "This", "bag", "is", "."], "This is my bag.", "This is ... 用来指近处的东西。"),
    write("q3", "写出英语单词：红色", "red", "red 表示红色。"),
  ] },
  { title: "谁在这里", objective: "人物与 he/she", line: "This is my friend. She likes cats.", translation: "这是我的朋友。她喜欢猫。", questions: [
    choice("q1", "She 指谁？", ["朋友", "猫", "说话者"], "朋友", "She 回指前一句的 friend。"),
    order("q2", "排成“她喜欢猫”", ["cats", "She", "likes", "."], "She likes cats.", "第三人称单数后用 likes。"),
    write("q3", "写出英语单词：朋友", "friend", "friend 指朋友。"),
  ] },
  { title: "教室里的约定", objective: "地点、物品与简单请求", line: "My pencil is on the desk. Please pass it to me.", translation: "我的铅笔在桌上。请把它递给我。", questions: [
    choice("q1", "铅笔在哪里？", ["桌上", "桌下", "书包里"], "桌上", "on the desk 表示在桌面上。"),
    order("q2", "排成礼貌请求", ["it", "Please", "pass", "to", "me", "."], "Please pass it to me.", "Please 放在请求前更礼貌。"),
    write("q3", "写出表示“在……上面”的词", "on", "on 表示物体接触表面。"),
  ] },
  { title: "今天的时间表", objective: "星期、时间与先后", line: "We have art on Tuesday. Music is on Thursday.", translation: "我们星期二有美术课，星期四有音乐课。", questions: [
    choice("q1", "音乐课是哪天？", ["Tuesday", "Thursday", "Friday"], "Thursday", "Music is on Thursday。"),
    order("q2", "排成“我们星期二有美术课”", ["art", "We", "on", "Tuesday", "have", "."], "We have art on Tuesday.", "星期前通常用 on。"),
    write("q3", "填出英语：星期四", "Thursday", "Thursday 是星期四。"),
  ] },
  { title: "先去哪里", objective: "方位与路线", line: "Go straight, then turn left at the library. The park is next to it.", translation: "直走，在图书馆左转。公园就在它旁边。", questions: [
    choice("q1", "在图书馆该做什么？", ["左转", "右转", "停在原地"], "左转", "turn left at the library。"),
    order("q2", "排成“公园在它旁边”", ["park", "next", "The", "to", "it", "is", "."], "The park is next to it.", "next to 表示紧挨着。"),
    write("q3", "写出英语：向左", "left", "left 表示左边。"),
  ] },
  { title: "咖啡馆的价格牌", objective: "数量、价格与可数名词", line: "Two small drinks cost six dollars. One large drink costs four.", translation: "两杯小饮料共六美元，一杯大饮料四美元。", questions: [
    choice("q1", "买两杯小饮料需多少美元？", ["4", "6", "8"], "6", "第一句直接给出总价 six dollars。"),
    order("q2", "排成“一个大杯四美元”", ["costs", "large", "drink", "four", "One", "dollars", "."], "One large drink costs four dollars.", "单数主语 One large drink 搭配 costs。"),
    write("q3", "写出英语：六", "six", "six 是六。"),
  ] },
  { title: "比较两条路", objective: "比较级与理由", line: "The river path is shorter, but the hill path is safer after rain.", translation: "河边路更短，但雨后山路更安全。", questions: [
    choice("q1", "雨后更安全的是哪条路？", ["河边路", "山路", "一样安全"], "山路", "but 后指出 hill path is safer。"),
    order("q2", "排成“河边路更短”", ["path", "shorter", "The", "river", "is", "."], "The river path is shorter.", "shorter 用于比较长度。"),
    write("q3", "写出 safe 的比较级", "safer", "以 e 结尾的形容词直接加 r。"),
  ] },
  { title: "昨天发生了什么", objective: "一般过去时与事件顺序", line: "I missed the bus, so I walked to the shop. I arrived before nine.", translation: "我错过公交车，所以步行去店里。我九点前到了。", questions: [
    choice("q1", "为什么步行？", ["错过公交车", "想锻炼", "学校太近"], "错过公交车", "so 前给出原因 missed the bus。"),
    order("q2", "排成“我步行去店里”", ["shop", "the", "walked", "I", "to", "."], "I walked to the shop.", "walked 表示过去发生的动作。"),
    write("q3", "写出 arrive 的过去式", "arrived", "规则动词 arrive 的过去式是 arrived。"),
  ] },
  { title: "下周的打算", objective: "计划、条件与调整", line: "If it rains on Saturday, we'll visit the museum instead of the beach.", translation: "如果星期六下雨，我们就去博物馆，而不去海滩。", questions: [
    choice("q1", "下雨时的替代计划是什么？", ["去博物馆", "去海滩", "待在家里"], "去博物馆", "visit the museum instead of the beach。"),
    order("q2", "排成条件从句", ["rains", "If", "it", ",", "we'll", "stay", "inside", "."], "If it rains, we'll stay inside.", "if 从句用现在时表示将来条件。"),
    write("q3", "写出表示“代替”的短语", "instead of", "instead of 后接被替代的事物。"),
  ] },
  { title: "找出真正的信息", objective: "转折、来源与推断", line: "The notice says the gallery closes at five, but today's ticket says six. Let's ask the desk before we make plans.", translation: "公告说画廊五点关门，但今天的票写着六点。安排之前先问服务台。", questions: [
    choice("q1", "为什么要问服务台？", ["两个来源时间冲突", "票价太贵", "找不到出口"], "两个来源时间冲突", "notice 和 ticket 给出不同的闭馆时间。"),
    order("q2", "排成“票上写着六点”", ["ticket", "says", "The", "six", "."], "The ticket says six.", "says 可表示文字信息写着什么。"),
    write("q3", "写出表示“在……之前”的词", "before", "before 表示先后顺序。"),
  ] },
  { title: "修正误会", objective: "澄清、引用与礼貌回应", line: "I said the meeting starts at ten, not that it ends at ten. Could you update the message?", translation: "我说的是会议十点开始，不是十点结束。你能更新消息吗？", questions: [
    choice("q1", "正确的时间信息是什么？", ["十点开始", "十点结束", "十一点开始"], "十点开始", "starts at ten 是说话者要澄清的事实。"),
    order("q2", "排成礼貌请求", ["update", "Could", "message", "the", "you", "?"], "Could you update the message?", "Could you ...? 是礼貌请求。"),
    write("q3", "写出 end 的反义词", "start", "start 表示开始。"),
  ] },
  { title: "平日与周末", objective: "习惯、频率与一般现在时", line: "I usually work on weekdays, but I visit the park on Sundays.", translation: "我通常在工作日工作，星期天会去公园。", questions: [
    choice("q1", "说话者何时去公园？", ["星期天", "每个工作日", "星期六"], "星期天", "on Sundays 表示习惯性的星期天活动。"),
    order("q2", "排成“我通常在工作日工作”", ["weekdays", "work", "usually", "I", "on", "."], "I usually work on weekdays.", "usually 放在实义动词 work 前。"),
    write("q3", "用英语写出“通常”", "usually", "usually 是常见的频率副词。"),
  ] },
  { title: "此刻正在发生", objective: "现在进行时与当下动作", line: "The team is preparing the room now. We are waiting outside.", translation: "团队现在正在布置房间。我们正在外面等候。", questions: [
    choice("q1", "团队现在在做什么？", ["布置房间", "关门离开", "出售门票"], "布置房间", "is preparing the room now。"),
    order("q2", "排成“我们正在外面等候”", ["outside", "waiting", "are", "We", "."], "We are waiting outside.", "be + 动词 ing 表示正在进行。"),
    write("q3", "写出 wait 的现在分词", "waiting", "wait 加 ing 构成 waiting。"),
  ] },
  { title: "同时发生的事", objective: "过去进行时与打断", line: "While I was checking the map, the lights went out. We waited by the door.", translation: "我在查看地图时灯灭了。我们在门边等待。", questions: [
    choice("q1", "灯灭时说话者正在做什么？", ["查看地图", "开门", "打电话"], "查看地图", "was checking 表示当时持续进行的动作。"),
    order("q2", "排成“灯灭了”", ["out", "The", "went", "lights", "."], "The lights went out.", "went out 是灯熄灭的常见表达。"),
    write("q3", "写出 wait 的过去式", "waited", "waited 表示过去等待。"),
  ] },
  { title: "改变计划的条件", objective: "条件句与可行建议", line: "If the bus is late, we can take the train. It leaves every twenty minutes.", translation: "如果公交车晚点，我们可以坐火车。火车每二十分钟一班。", questions: [
    choice("q1", "公交车晚点时有什么替代办法？", ["坐火车", "步行", "取消出行"], "坐火车", "if 从句后给出 take the train。"),
    order("q2", "排成“如果车晚点，我们可以等”", ["late", "If", "is", "bus", "the", ",", "we", "can", "wait", "."], "If the bus is late, we can wait.", "if 从句用现在时说明可能的条件。"),
    write("q3", "用英语写出“每二十分钟”", "every twenty minutes", "every twenty minutes 表示发车间隔。"),
  ] },
  { title: "被谁改变的计划", objective: "被动语态与信息重点", line: "The event was moved to Friday because the hall is being repaired.", translation: "因为大厅正在维修，活动被移到了星期五。", questions: [
    choice("q1", "活动改到哪天？", ["星期三", "星期五", "星期日"], "星期五", "was moved to Friday。"),
    order("q2", "排成“活动被改期了”", ["moved", "was", "event", "The", "."], "The event was moved.", "was moved 强调活动受到的改变。"),
    write("q3", "用英语写出“因为”", "because", "because 引出原因。"),
  ] },
  { title: "哪一张照片", objective: "定语从句与限定信息", line: "The photo that shows the empty street belongs to the local archive, not to us.", translation: "那张拍到空街道的照片属于本地档案馆，不属于我们。", questions: [
    choice("q1", "照片属于谁？", ["本地档案馆", "说话者", "街道商店"], "本地档案馆", "belongs to the local archive。"),
    order("q2", "排成“那张展示街道的照片”", ["street", "the", "shows", "that", "photo", "The"], "The photo that shows the street", "that 从句限定具体是哪张照片。"),
    write("q3", "写出 belong 的第三人称单数", "belongs", "单数主语 The photo 搭配 belongs。"),
  ] },
  { title: "图表背后的原因", objective: "趋势描述与谨慎推断", line: "Attendance rose after the opening hours changed. However, the survey does not show whether the new hours caused the rise.", translation: "开放时间调整后到访人数上升，但调查不能证明调整导致了上升。", questions: [
    choice("q1", "哪项结论最谨慎？", ["人数上升但原因未证实", "调整必然有效", "调查证明无影响"], "人数上升但原因未证实", "先后发生不等于因果已证实。"),
    order("q2", "排成“到访人数上升”", ["rose", "Attendance", "."], "Attendance rose.", "rose 是 rise 的过去式。"),
    write("q3", "用英语写出“然而”", "however", "however 引出对前一句的限制。"),
  ] },
  { title: "读者的不同观点", objective: "比较观点并辨析依据", line: "Some readers value short opening hours because they reduce costs. Others say longer hours make the service more accessible.", translation: "有人认为缩短开放时间可降低成本，另有人认为延长时间更方便使用。", questions: [
    choice("q1", "支持更长开放时间的理由是什么？", ["更方便使用", "降低成本", "减少员工"], "更方便使用", "make the service more accessible。"),
    order("q2", "排成“其他人支持更长时间”", ["hours", "prefer", "Others", "longer", "."], "Others prefer longer hours.", "Others 指另一组人。"),
    write("q3", "写出“可获得的、方便使用的”对应词", "accessible", "accessible 在此指服务更容易被使用。"),
  ] },
  { title: "方案中的隐含代价", objective: "权衡、反驳与折中", line: "A cheaper exhibition would reach more visitors, yet removing captions would exclude some of them. We can reduce printing costs instead.", translation: "低价展览能接触更多人，但取消字幕会排除部分观众；可以改为削减印刷费。", questions: [
    choice("q1", "更合理的折中是什么？", ["削减印刷费", "取消字幕", "提高票价"], "削减印刷费", "最后一句给出替代做法。"),
    order("q2", "排成“字幕帮助部分观众”", ["some", "Captions", "visitors", "help", "."], "Captions help some visitors.", "保留字幕与可及性有关。"),
    write("q3", "写出表示“然而、却”的词", "yet", "yet 在这里引出相反的考虑。"),
  ] },
  { title: "核对来源", objective: "来源可靠性与限定措辞", line: "The headline calls the project a success, whereas the report records only its first month. We need later data before judging its long-term effect.", translation: "标题称项目成功，但报告仅记录首月；判断长期效果仍需后续数据。", questions: [
    choice("q1", "目前缺少什么？", ["后续数据", "项目名称", "首月报告"], "后续数据", "need later data。"),
    order("q2", "排成“报告仅记录首月”", ["first", "report", "only", "month", "The", "records", "its", "."], "The report records only its first month.", "only 限定证据覆盖的时间范围。"),
    write("q3", "写出表示“长期的”词组", "long-term", "long-term 表示长期的。"),
  ] },
  { title: "写一段平衡的结论", objective: "综合证据、承认限制", line: "The pilot improved access for some visitors. Since the sample was small, the result is promising rather than conclusive.", translation: "试点改善了部分访客的使用体验；样本较小，所以结果有希望，但并非定论。", questions: [
    choice("q1", "作者对结果的态度是什么？", ["有希望但未成定论", "完全失败", "已经证实对所有人有效"], "有希望但未成定论", "promising rather than conclusive 明确限定结论。"),
    order("q2", "排成“样本较小”", ["small", "sample", "The", "was", "."], "The sample was small.", "先说明证据限制，再下结论。"),
    write("q3", "用英语写出“决定性的”", "conclusive", "conclusive 指足以支持确定结论。"),
  ] },
  { title: "向不同读者解释", objective: "根据受众调整表达", line: "For specialists, the report includes detailed methods. For visitors, a short summary explains what changed and what remains uncertain.", translation: "报告为专业人员提供详细方法，为访客提供简要摘要说明变化和不确定之处。", questions: [
    choice("q1", "访客版摘要应包含什么？", ["变化和仍不确定之处", "全部原始数据", "只写结论不写限制"], "变化和仍不确定之处", "末句明确列出摘要的两个内容。"),
    order("q2", "排成“摘要解释了变化”", ["explains", "changed", "summary", "what", "The", "."], "The summary explains what changed.", "what changed 作 explains 的内容。"),
    write("q3", "写出英语：不确定的", "uncertain", "uncertain 表示尚无把握。"),
  ] },
];

const roleSettings: Record<string, { name: string; places: string[]; placesZh: string[] }> = {
  oliver: { name: "Oliver", places: ["his second-hand bookshop", "a reading table"], placesZh: ["二手书店", "阅读桌旁"] },
  ruby: { name: "Ruby", places: ["her Melbourne café", "a beach rescue desk"], placesZh: ["墨尔本咖啡馆", "海滩救助站"] },
  marcus: { name: "Marcus", places: ["his Brooklyn photo stall", "a community gallery"], placesZh: ["布鲁克林摄影摊", "社区画廊"] },
};

// 每一幕的开场与该单元的线索相连；占位符仅替换成角色及其所在地。
const sceneOpenings: readonly { english: string; chinese: string }[] = [
  { english: "This is {name}. Say hello!", chinese: "这是 {name}。和对方打个招呼吧！" },
  { english: "{name} has two bags. Look at the colors.", chinese: "{name} 有两个包。看看它们的颜色。" },
  { english: "{name} shows you a friend.", chinese: "{name} 向你介绍一位朋友。" },
  { english: "A pencil is on the desk near {name}.", chinese: "{name} 旁边的桌上有一支铅笔。" },
  { english: "At {place}, {name} reads a class timetable with you.", chinese: "在{placeZh}，{name} 和你一起看课程表。" },
  { english: "You and {name} check a map before visiting the park.", chinese: "你和 {name} 去公园前查看地图。" },
  { english: "At {place}, {name} checks the price of two drinks.", chinese: "在{placeZh}，{name} 查看两杯饮料的价格。" },
  { english: "After rain, {name} compares two paths on a map.", chinese: "雨后，{name} 比较地图上的两条路。" },
  { english: "You ask {name} why the trip to the shop took longer yesterday.", chinese: "你问 {name} 昨天去商店为什么花了更久。" },
  { english: "{name} is making a Saturday plan with you.", chinese: "{name} 正和你商量周六的安排。" },
  { english: "At {place}, you and {name} find two different closing times.", chinese: "在{placeZh}，你和 {name} 发现两种不同的闭馆时间。" },
  { english: "A meeting message contains a mistake. {name} wants to correct it.", chinese: "会议通知写错了，{name} 想澄清。" },
  { english: "{name} tells you about a usual week and a Sunday routine.", chinese: "{name} 告诉你平日和星期天通常做什么。" },
  { english: "A room is busy today. {name} describes what is happening now.", chinese: "今天房间里很忙，{name} 描述此刻正在发生的事。" },
  { english: "You hear about a sudden power cut while {name} studies a map.", chinese: "{name} 查看地图时突然停电了。" },
  { english: "A bus may be late. {name} checks another way to travel.", chinese: "公交车可能晚点，{name} 查看其他出行方式。" },
  { english: "At {place}, {name} reads an event update.", chinese: "在{placeZh}，{name} 读到一条活动变更通知。" },
  { english: "{name} helps identify the owner of a photograph in an archive.", chinese: "{name} 帮忙确认档案馆里一张照片的归属。" },
  { english: "At {place}, {name} studies a survey about visitor numbers.", chinese: "在{placeZh}，{name} 阅读一份访客人数调查。" },
  { english: "{name} compares two readers' views about opening hours.", chinese: "{name} 比较两位读者对开放时间的不同观点。" },
  { english: "{name} considers how to keep an exhibition affordable and accessible.", chinese: "{name} 思考怎样让展览既负担得起，又方便更多人参与。" },
  { english: "At {place}, {name} checks whether a headline matches its report.", chinese: "在{placeZh}，{name} 核对标题和报告是否一致。" },
  { english: "{name} reviews evidence from a small pilot project.", chinese: "{name} 审阅一个小型试点项目的证据。" },
  { english: "{name} prepares two versions of a report for different readers.", chinese: "{name} 为不同读者准备两个版本的报告。" },
];

export const authoredUnitSeeds: readonly UnitTemplate[] = Object.entries(roleSettings).flatMap(([roleKey, role]) =>
  lessons.map((lesson, index) => {
    const grade = Math.floor(index / 2) + 1;
    const place = role.places[index % 2] ?? "the meeting place";
    const placeZh = role.placesZh[index % 2] ?? "约定地点";
    const opening = sceneOpenings[index];
    if (!opening) throw new Error(`Missing opening for authored lesson ${String(index)}`);
    return {
      id: `unit-v1-${roleKey}-g${String(grade)}-${String(index % 2 + 1)}`,
      roleKey,
      grade,
      title: lesson.title,
      objective: lesson.objective,
      scene: [
        { speaker: "narrator" as const, english: opening.english.replaceAll("{name}", role.name).replaceAll("{place}", place), chinese: opening.chinese.replaceAll("{name}", role.name).replaceAll("{placeZh}", placeZh) },
        { speaker: "character" as const, english: lesson.line.replaceAll("{name}", role.name), chinese: lesson.translation.replaceAll("{name}", role.name) },
      ],
      questions: lesson.questions,
    };
  }),
);
