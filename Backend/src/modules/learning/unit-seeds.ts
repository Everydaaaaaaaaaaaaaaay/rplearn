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

// 第二组原创情境补充同一年级的不同交际任务，避免升星过度依赖同一种句型。
const expandedLessons: readonly Lesson[] = [
  { title: "借一张地图", objective: "礼貌请求与致谢", line: "Please show me the map. Thank you!", translation: "请把地图给我看看。谢谢！", questions: [
    choice("q1", "说话者想看什么？", ["地图", "书包", "照片"], "地图", "show me the map 表示想看地图。"),
    order("q2", "排成礼貌请求", ["me", "the", "map", "show", "Please", "."], "Please show me the map.", "Please 放在请求开头。"),
    write("q3", "写出英语：谢谢", "thank you", "Thank you 是表示感谢的常用语。"),
  ] },
  { title: "窗边的小动物", objective: "数字与简单观察", line: "I see two birds and one cat by the window.", translation: "我看见窗边有两只鸟和一只猫。", questions: [
    choice("q1", "鸟有几只？", ["一只", "两只", "三只"], "两只", "two birds 表示两只鸟。"),
    order("q2", "排成“我看见两只鸟”", ["birds", "two", "see", "I", "."], "I see two birds.", "数字放在名词前，复数名词用 birds。"),
    write("q3", "写出英语：猫", "cat", "cat 表示猫。"),
  ] },
  { title: "门边是谁的包", objective: "家庭成员与 her", line: "My mother is here. Her bag is by the door.", translation: "我妈妈在这里。她的包在门边。", questions: [
    choice("q1", "门边的包是谁的？", ["妈妈的", "朋友的", "说话者的"], "妈妈的", "Her 回指前一句的 mother。"),
    order("q2", "排成“她的包在门边”", ["door", "the", "by", "is", "bag", "Her", "."], "Her bag is by the door.", "her 表示“她的”。"),
    write("q3", "写出英语：妈妈", "mother", "mother 表示妈妈。"),
  ] },
  { title: "椅子下面", objective: "物品位置与 under", line: "My keys are under the chair. Can you see them?", translation: "我的钥匙在椅子下面。你看见它们了吗？", questions: [
    choice("q1", "钥匙在哪里？", ["椅子下面", "桌子上面", "门后面"], "椅子下面", "under the chair 表示在椅子下面。"),
    order("q2", "排成“钥匙在椅子下面”", ["chair", "the", "under", "are", "keys", "The", "."], "The keys are under the chair.", "under 表示在下方。"),
    write("q3", "写出英语：在……下面", "under", "under 表示位置在下方。"),
  ] },
  { title: "周五四点见", objective: "星期、时间与纠错", line: "Let's meet at four on Friday, not on Thursday.", translation: "我们周五四点见，不是周四。", questions: [
    choice("q1", "约定是哪一天？", ["周四", "周五", "周六"], "周五", "not on Thursday 排除了周四。"),
    order("q2", "排成“我们周五见”", ["Friday", "on", "meet", "We", "."], "We meet on Friday.", "星期前用 on。"),
    write("q3", "写出英语数字：四", "four", "four 是约定的小时数。"),
  ] },
  { title: "画画的日子", objective: "一周安排与对比信息", line: "I read on Monday, but I paint on Wednesday.", translation: "我星期一阅读，星期三画画。", questions: [
    choice("q1", "星期三做什么？", ["阅读", "画画", "跑步"], "画画", "I paint on Wednesday。"),
    order("q2", "排成“我星期一阅读”", ["Monday", "on", "read", "I", "."], "I read on Monday.", "on Monday 表示在星期一。"),
    write("q3", "写出英语：星期三", "Wednesday", "Wednesday 是星期三。"),
  ] },
  { title: "两本笔记本", objective: "价格、大小与比较", line: "The small notebook costs three dollars. The large one costs five.", translation: "小笔记本三美元，大笔记本五美元。", questions: [
    choice("q1", "哪一本更便宜？", ["小笔记本", "大笔记本", "一样贵"], "小笔记本", "three dollars 少于 five dollars。"),
    order("q2", "排成“小笔记本三美元”", ["dollars", "three", "costs", "notebook", "small", "The", "."], "The small notebook costs three dollars.", "单数主语搭配 costs。"),
    write("q3", "写出英语：五", "five", "five 表示五。"),
  ] },
  { title: "天气要变了", objective: "天气预报与实用建议", line: "It's cloudy now, and the forecast says rain. Bring a jacket.", translation: "现在多云，预报说会下雨。带件外套吧。", questions: [
    choice("q1", "为什么建议带外套？", ["可能下雨", "天气炎热", "要去游泳"], "可能下雨", "forecast says rain 提示天气会变。"),
    order("q2", "排成“带件外套”", ["jacket", "a", "Bring", "."], "Bring a jacket.", "祈使句用动词原形开头。"),
    write("q3", "写出英语：多云的", "cloudy", "cloudy 描述现在的天空。"),
  ] },
  { title: "找回车票", objective: "过去事件与转折", line: "I lost my ticket yesterday, but I found it in my bag.", translation: "我昨天弄丢车票，但后来在包里找到了。", questions: [
    choice("q1", "车票最后在哪里找到？", ["包里", "地上", "车站"], "包里", "found it in my bag 说明结果。"),
    order("q2", "排成“我在包里找到了它”", ["bag", "my", "in", "it", "found", "I", "."], "I found it in my bag.", "found 是 find 的过去式。"),
    write("q3", "写出 lose 的过去式", "lost", "lose 的过去式是 lost。"),
  ] },
  { title: "下周去博物馆", objective: "将来计划与提前准备", line: "We're going to visit the museum next week. Let's buy tickets today.", translation: "我们下周打算去博物馆。今天先买票吧。", questions: [
    choice("q1", "什么时候去博物馆？", ["今天", "下周", "上周"], "下周", "next week 是下周。"),
    order("q2", "排成“今天买票”", ["today", "tickets", "buy", "Let's", "."], "Let's buy tickets today.", "Let's 后接动词原形表示提议。"),
    write("q3", "写出英语：下周", "next week", "next week 指下一周。"),
  ] },
  { title: "地址已经改变", objective: "发现错误并礼貌求证", line: "The invitation has the old address, but the event moved. Could you send the new address?", translation: "邀请函上是旧地址，但活动换了地点。你能发一下新地址吗？", questions: [
    choice("q1", "邀请函有什么问题？", ["写着旧地址", "日期缺失", "没有署名"], "写着旧地址", "old address 与 event moved 形成冲突。"),
    order("q2", "排成“你能发新地址吗？”", ["address", "new", "the", "send", "you", "Could", "?"], "Could you send the new address?", "Could you ...? 是礼貌请求。"),
    write("q3", "写出英语：邀请函", "invitation", "invitation 是邀请函。"),
  ] },
  { title: "两条不同的通知", objective: "比较来源并核对事实", line: "The website says the talk begins at seven, but the poster says six. Let's verify the time.", translation: "网站说讲座七点开始，海报却写六点。我们核对一下时间。", questions: [
    choice("q1", "两个来源哪里不一致？", ["开始时间", "讲座地点", "讲者姓名"], "开始时间", "seven 与 six 是不同的开始时间。"),
    order("q2", "排成“我们核对时间”", ["time", "the", "verify", "Let's", "."], "Let's verify the time.", "verify 表示核实信息。"),
    write("q3", "写出英语：核实", "verify", "verify 是核对真实性。"),
  ] },
  { title: "今天与通常", objective: "习惯和此刻的不同", line: "I usually take photos on Saturdays, but today I'm drawing.", translation: "我通常星期六拍照，但今天正在画画。", questions: [
    choice("q1", "今天正在做什么？", ["画画", "拍照", "散步"], "画画", "today I'm drawing 与通常的习惯不同。"),
    order("q2", "排成“我今天正在画画”", ["today", "drawing", "am", "I", "."], "I am drawing today.", "am drawing 表示此刻的动作。"),
    write("q3", "写出英语：通常", "usually", "usually 描述习惯频率。"),
  ] },
  { title: "靠窗的空桌", objective: "there are 与位置描述", line: "There are three tables near the window, and the largest one is free.", translation: "窗边有三张桌子，最大的一张空着。", questions: [
    choice("q1", "哪张桌子空着？", ["最大的一张", "最小的一张", "三张都空着"], "最大的一张", "the largest one is free。"),
    order("q2", "排成“这里有三张桌子”", ["tables", "three", "are", "There", "."], "There are three tables.", "复数名词前用 There are。"),
    write("q3", "写出 large 的最高级", "largest", "large 以 e 结尾，最高级加 st。"),
  ] },
  { title: "电话响的时候", objective: "过去进行时与打断事件", line: "I was reading when the phone rang, so I missed the final sentence.", translation: "电话响时我正在阅读，所以漏看了最后一句。", questions: [
    choice("q1", "电话响时说话者在做什么？", ["阅读", "打电话", "写字"], "阅读", "was reading 是当时正在进行的动作。"),
    order("q2", "排成“电话响了”", ["rang", "phone", "The", "."], "The phone rang.", "rang 是 ring 的过去式。"),
    write("q3", "写出 ring 的过去式", "rang", "rang 表示电话曾响起。"),
  ] },
  { title: "涨水时走哪边", objective: "条件与权衡安全", line: "If the street floods, we should take the higher road, even though it is longer.", translation: "如果街道积水，我们该走地势更高的路，虽然它更远。", questions: [
    choice("q1", "积水时该选择哪条路？", ["地势更高的路", "更短的低路", "原地等待"], "地势更高的路", "take the higher road 是安全建议。"),
    order("q2", "排成“我们应该走高处的路”", ["road", "higher", "the", "take", "should", "We", "."], "We should take the higher road.", "should 表示建议。"),
    write("q3", "抄写台词中表示“虽然”的短语", "even though", "even though 引出与主句相对的情况。"),
  ] },
  { title: "志愿者写的通知", objective: "被动语态与关系从句", line: "The notice was written by volunteers who know the neighborhood well.", translation: "这份通知由熟悉社区的志愿者写成。", questions: [
    choice("q1", "谁写了通知？", ["志愿者", "游客", "店主"], "志愿者", "was written by volunteers 指明作者。"),
    order("q2", "排成“通知由志愿者写成”", ["volunteers", "by", "written", "was", "notice", "The", "."], "The notice was written by volunteers.", "was written 是被动语态。"),
    write("q3", "写出英语：志愿者（复数）", "volunteers", "volunteers 是 volunteer 的复数。"),
  ] },
  { title: "海报上的照片", objective: "定语从句与署名义务", line: "The photo that was chosen for the poster must be credited to its maker.", translation: "选作海报的照片必须注明作者。", questions: [
    choice("q1", "海报使用照片时必须做什么？", ["注明作者", "裁掉标题", "改变颜色"], "注明作者", "must be credited to its maker。"),
    order("q2", "排成“照片必须署名”", ["credited", "be", "must", "photo", "The", "."], "The photo must be credited.", "must be credited 表示必须注明来源。"),
    write("q3", "抄写台词中表示“创作者”的词", "maker", "maker 在此指照片的创作者。"),
  ] },
  { title: "节日期间的销量", objective: "区分同时发生与因果", line: "Sales rose during the festival, but the shop also changed its hours. We cannot tell which change mattered more.", translation: "节日期间销量上升，但商店同时调整了营业时间。无法断定哪项变化影响更大。", questions: [
    choice("q1", "为什么不能断定节日是唯一原因？", ["营业时间也改变了", "销量没有上升", "没有举办节日"], "营业时间也改变了", "两个因素同时变化，不能只归因于节日。"),
    order("q2", "排成“节日期间销量上升”", ["festival", "the", "during", "rose", "Sales", "."], "Sales rose during the festival.", "during 表示事件发生的期间。"),
    write("q3", "抄写台词中表示“无法断定”的短语", "cannot tell", "cannot tell 表示证据不足以确定。"),
  ] },
  { title: "两组访客的偏好", objective: "比较群体并限定结论", line: "Visitors under twenty preferred the short tour, whereas older visitors preferred the full tour. Neither group represents everyone.", translation: "二十岁以下访客偏好短路线，年长访客偏好完整路线；两组都不能代表所有人。", questions: [
    choice("q1", "哪项结论符合材料？", ["两组偏好不同", "所有人都喜欢短路线", "年长者没有参与"], "两组偏好不同", "whereas 对比了两组的选择。"),
    order("q2", "排成“两组都不能代表所有人”", ["everyone", "represents", "group", "Neither", "."], "Neither group represents everyone.", "Neither 限定两组均不具有完全代表性。"),
    write("q3", "抄写台词中的对比连接词", "whereas", "whereas 用来对比两种情况。"),
  ] },
  { title: "数字导览的代价", objective: "方案权衡与可及性", line: "A digital guide costs less to update, yet visitors without phones would need a printed option.", translation: "数字导览更新成本更低，但没有手机的访客仍需要纸质版本。", questions: [
    choice("q1", "只提供数字导览会漏掉谁？", ["没有手机的访客", "所有工作人员", "会用手机的访客"], "没有手机的访客", "without phones 指这组可能被排除的人。"),
    order("q2", "排成“有些访客需要纸质版本”", ["option", "printed", "a", "need", "visitors", "Some", "."], "Some visitors need a printed option.", "保留纸质选项照顾不同访客。"),
    write("q3", "抄写台词中的转折词", "yet", "yet 引出数字方案的限制。"),
  ] },
  { title: "一段访谈与一份调查", objective: "评估证据覆盖范围", line: "The interview describes one visitor's experience; the survey covers two hundred. Both help, but neither alone explains why attendance changed.", translation: "访谈记录一位访客的经历，调查覆盖两百人。两者都有价值，但单独任何一个都不能解释到访人数变化的原因。", questions: [
    choice("q1", "作者如何看待这两种证据？", ["都有价值但不足以单独解释原因", "访谈证明全部原因", "调查毫无用处"], "都有价值但不足以单独解释原因", "Both help, but neither alone explains why。"),
    order("q2", "排成“调查覆盖两百人”", ["hundred", "two", "covers", "survey", "The", "."], "The survey covers two hundred.", "covers 说明调查范围。"),
    write("q3", "写出英语：两者都不", "neither", "neither 指两者中没有一个。"),
  ] },
  { title: "不能直接比较的数字", objective: "综合证据与比较限制", line: "Three sites reported gains, but two did not track the same measure. The evidence suggests improvement, with a limit on direct comparison.", translation: "三个地点报告了改善，但其中两个使用的衡量指标不同。证据提示有改善，直接比较仍受限制。", questions: [
    choice("q1", "最稳妥的结论是什么？", ["可能改善，但直接比较有限", "所有地点改善幅度相同", "没有任何改善"], "可能改善，但直接比较有限", "suggests improvement 同时限定 direct comparison。"),
    order("q2", "排成“证据提示有改善”", ["improvement", "suggests", "evidence", "The", "."], "The evidence suggests improvement.", "suggests 比 proves 更审慎。"),
    write("q3", "抄写台词中表示“比较”的名词", "comparison", "comparison 是比较。"),
  ] },
  { title: "写给新志愿者的摘要", objective: "按受众重组重要信息", line: "The technical report lists every method. For new volunteers, explain the safety steps first and link the full report for details.", translation: "技术报告列出所有方法。给新志愿者时，应先解释安全步骤，再附完整报告供查细节。", questions: [
    choice("q1", "给新志愿者的摘要应先写什么？", ["安全步骤", "全部方法细节", "报告作者的履历"], "安全步骤", "safety steps first 指信息优先级。"),
    order("q2", "排成“先解释安全步骤”", ["first", "steps", "safety", "the", "Explain", "."], "Explain the safety steps first.", "first 明确受众最需要的信息。"),
    write("q3", "写出英语：志愿者（复数）", "volunteers", "volunteers 是新读者群体。"),
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

const expandedSceneOpenings: readonly { english: string; chinese: string }[] = [
  { english: "{name} has a map. Ask to see it.", chinese: "{name} 有一张地图。请对方拿给你看看。" },
  { english: "{name} looks out of the window with you.", chinese: "{name} 和你一起望向窗外。" },
  { english: "{name} points to a bag near the door.", chinese: "{name} 指着门边的包。" },
  { english: "{name} looks for some keys beside a chair.", chinese: "{name} 在椅子旁找钥匙。" },
  { english: "At {place}, {name} corrects the time on a meeting note.", chinese: "在{placeZh}，{name} 更正便条上的见面时间。" },
  { english: "{name} shows you two activities written on a weekly calendar.", chinese: "{name} 给你看周历上写的两项活动。" },
  { english: "At {place}, {name} compares the prices of two notebooks.", chinese: "在{placeZh}，{name} 比较两本笔记本的价格。" },
  { english: "{name} checks the weather before going outside.", chinese: "出门前，{name} 查看天气。" },
  { english: "{name} tells you how a missing ticket was found.", chinese: "{name} 告诉你丢失的票后来是怎么找到的。" },
  { english: "At {place}, {name} makes a plan for next week.", chinese: "在{placeZh}，{name} 安排下周的行程。" },
  { english: "{name} finds that an invitation has the wrong address.", chinese: "{name} 发现邀请函上的地址不对。" },
  { english: "At {place}, {name} compares a website with a poster.", chinese: "在{placeZh}，{name} 对照网站与海报。" },
  { english: "{name} explains how today's activity differs from the usual Saturday routine.", chinese: "{name} 解释今天的活动与平常星期六有什么不同。" },
  { english: "At {place}, {name} checks which table is available.", chinese: "在{placeZh}，{name} 查看哪张桌子空着。" },
  { english: "{name} describes what happened while reading.", chinese: "{name} 描述阅读时发生的事。" },
  { english: "After heavy rain, {name} weighs two routes.", chinese: "大雨过后，{name} 权衡两条路线。" },
  { english: "At {place}, {name} reads a notice from local volunteers.", chinese: "在{placeZh}，{name} 阅读本地志愿者写的通知。" },
  { english: "{name} checks a photograph's credit before a poster is printed.", chinese: "印海报前，{name} 核查照片的署名。" },
  { english: "At {place}, {name} examines a claim about festival sales.", chinese: "在{placeZh}，{name} 核查关于节日期间销量的说法。" },
  { english: "{name} reads survey results from two groups of visitors.", chinese: "{name} 阅读两组访客的调查结果。" },
  { english: "{name} compares a digital guide with a printed one.", chinese: "{name} 比较数字导览和纸质导览。" },
  { english: "At {place}, {name} compares an interview with a larger survey.", chinese: "在{placeZh}，{name} 比较一段访谈和一份更大样本的调查。" },
  { english: "{name} checks whether results from three sites can be compared fairly.", chinese: "{name} 核查三个地点的结果能否公平比较。" },
  { english: "{name} prepares a concise safety note for new volunteers.", chinese: "{name} 为新志愿者准备简明的安全说明。" },
];

export const authoredUnitSeeds: readonly UnitTemplate[] = Object.entries(roleSettings).flatMap(([roleKey, role]) =>
  [lessons, expandedLessons].flatMap((group, batch) => group.map((lesson, index) => {
    const grade = Math.floor(index / 2) + 1;
    const place = role.places[index % 2] ?? "the meeting place";
    const placeZh = role.placesZh[index % 2] ?? "约定地点";
    const opening = (batch === 0 ? sceneOpenings : expandedSceneOpenings)[index];
    if (!opening) throw new Error(`Missing opening for authored lesson ${String(index)}`);
    return {
      id: `unit-v1-${roleKey}-g${String(grade)}-${String(batch * 2 + index % 2 + 1)}`,
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
  })),
);
