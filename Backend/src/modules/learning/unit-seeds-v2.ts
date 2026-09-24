import type { UnitQuestion, UnitTemplate } from "./unit-seeds.js";
import { expandedUnitSeedsV2 } from "./unit-seeds-v2-expanded.js";

type Role = "oliver" | "ruby" | "marcus";
type Beat = Readonly<{ speaker: "narrator" | "character"; english: string; chinese: string }>;
type Check = Readonly<{ prompt: string; options: readonly string[]; answer: string; explanation: string }>;
type Draft = Readonly<{
  role: Role;
  grade: 3 | 7 | 8 | 9 | 10;
  title: string;
  objective: string;
  scene: readonly Beat[];
  choice: Check;
  order: Check;
  write: Omit<Check, "options">;
}>;

const scene = (speaker: Beat["speaker"], english: string, chinese: string): Beat => ({ speaker, english, chinese });
const select = (prompt: string, options: string[], answer: string, explanation: string): Check =>
  ({ prompt, options, answer, explanation });
const arrange = (prompt: string, options: string[], answer: string, explanation: string): Check =>
  ({ prompt, options, answer, explanation });
const complete = (prompt: string, answer: string, explanation: string): Omit<Check, "options"> =>
  ({ prompt, answer, explanation });

// 每个角色的事件、材料和答案独立编写；借鉴公开教材页的任务链，不搬用课文或练习题。
const drafts: readonly Draft[] = [
  {
    role: "oliver", grade: 3, title: "旧书里的家庭卡", objective: "从人物关系卡中辨认家庭成员并补全介绍",
    scene: [
      scene("narrator", "Oliver finds a family card inside an old storybook.", "Oliver 在一本旧故事书里找到一张家庭卡。"),
      scene("character", "This is Mia. Tom is her dad. Ben is her brother.", "这是 Mia。Tom 是她的爸爸，Ben 是她的哥哥。"),
      scene("narrator", "The card has an empty box next to Mia marked 'brother'.", "卡片上 Mia 旁边有一个标着“哥哥”的空格。"),
    ],
    choice: select("谁应该填在 Mia 旁边的空格里？", ["Ben", "Tom", "Oliver"], "Ben", "空格标为 brother，对话说明 Ben is her brother。"),
    order: arrange("用卡片的信息介绍 Ben", ["brother", "is", "Ben", "Mia's", "."], "Ben is Mia's brother.", "先确定 Ben，再用 Mia's brother 说明关系。"),
    write: complete("补全卡片：Tom is Mia's ____。只写一个英文词。", "dad", "卡片直接说明 Tom is her dad；her 指 Mia。"),
  },
  {
    role: "ruby", grade: 3, title: "海边的联络卡", objective: "根据联络卡与对话核对家人关系",
    scene: [
      scene("narrator", "At Ruby's beach rescue desk, a child gives her a contact card.", "在 Ruby 的海滩救助台，一个孩子递来联络卡。"),
      scene("character", "The child's name is Leo. His mum is Anna. His sister is May.", "孩子叫 Leo。他的妈妈是 Anna，姐姐是 May。"),
      scene("narrator", "May is waiting by the blue flag. Ruby checks whom Leo can meet there.", "May 正在蓝旗旁等待。Ruby 核对 Leo 可以在那里找到谁。"),
    ],
    choice: select("Leo 在蓝旗旁能找到哪位家人？", ["姐姐 May", "妈妈 Anna", "爸爸"], "姐姐 May", "先用 His sister is May 确定关系，再结合 May 在蓝旗旁。"),
    order: arrange("替 Ruby 介绍联络卡上的妈妈", ["mum", "is", "Anna", "Leo's", "."], "Anna is Leo's mum.", "联络卡将 Anna 标为 Leo 的妈妈。"),
    write: complete("补全联络卡：May is Leo's ____。只写一个英文词。", "sister", "His sister is May 说明 May 与 Leo 的关系。"),
  },
  {
    role: "marcus", grade: 3, title: "照片墙上的名字", objective: "把照片说明中的人物关系对应到位置",
    scene: [
      scene("narrator", "Marcus is making a small family photo wall for a neighbour.", "Marcus 正在为邻居制作一面家庭照片墙。"),
      scene("character", "Nina is in the middle. Her grandma is Rose. Her brother is Sam.", "Nina 在中间。她的奶奶是 Rose，弟弟是 Sam。"),
      scene("narrator", "A note says, 'Put Grandma above Nina.' The top label is missing.", "便条写着“把奶奶放在 Nina 上方”。最上面的姓名标签缺失。"),
    ],
    choice: select("最上面的姓名标签该写谁？", ["Rose", "Sam", "Nina"], "Rose", "先找 Her grandma is Rose，再按便条放在 Nina 上方。"),
    order: arrange("写出照片墙上的奶奶关系", ["grandma", "is", "Rose", "Nina's", "."], "Rose is Nina's grandma.", "Rose 是 Nina 的奶奶。"),
    write: complete("补全另一张标签：Sam is Nina's ____。只写一个英文词。", "brother", "Her brother is Sam 中 her 指 Nina。"),
  },
  {
    role: "oliver", grade: 7, title: "书店午休安排", objective: "从日程和身体感受中提出可行的健康建议",
    scene: [
      scene("narrator", "Oliver's note says: open the bookshop at 10; lunch break at 1; reading club at 4.", "Oliver 的便条写着：十点开书店，一点午休，四点读书会。"),
      scene("character", "I skipped lunch yesterday and felt tired at the club. Today I have fruit and a sandwich.", "我昨天没吃午饭，读书会时很疲倦。今天我带了水果和三明治。"),
      scene("narrator", "A customer wants help at 1. Oliver must decide when to eat.", "一位顾客想在一点得到帮助。Oliver 得决定什么时候吃饭。"),
    ],
    choice: select("哪种安排最照顾 Oliver 的健康，也能回应顾客？", ["说明午休时间，饭后帮忙", "再次不吃午饭", "取消整天营业"], "说明午休时间，饭后帮忙", "便条规定一点午休；昨天跳过午饭造成疲倦。"),
    order: arrange("替 Oliver 礼貌说明安排", ["lunch", "after", "help", "can", "I", "."], "I can help after lunch.", "after lunch 既保留午餐，又说明帮助时间。"),
    write: complete("补全给顾客的短句：I have a lunch ____ at one. 只写一个英文词。", "break", "日程表用 lunch break 表示一点的午休。"),
  },
  {
    role: "ruby", grade: 7, title: "咖啡馆的值班午餐", objective: "比较菜单与值班任务，选择可执行的午餐",
    scene: [
      scene("narrator", "Ruby's café menu offers water, fruit, and a very sweet milkshake.", "Ruby 的咖啡馆菜单上有水、水果和一杯很甜的奶昔。"),
      scene("character", "I will help at the turtle rescue desk after lunch. I need water and food that will keep me comfortable outside.", "午饭后我要去海龟救助台。我需要水和适合户外工作时吃的食物。"),
      scene("narrator", "The rescue shift starts in thirty minutes. Ruby can choose two items now.", "救助值班半小时后开始。Ruby 现在可以选两样东西。"),
    ],
    choice: select("根据菜单与 Ruby 的需求，哪两样最合适？", ["水和水果", "两杯奶昔", "只喝奶昔"], "水和水果", "她明确需要水与食物；菜单提供水和水果。"),
    order: arrange("替 Ruby 告诉同伴她的选择", ["fruit", "and", "water", "choose", "I", "."], "I choose water and fruit.", "句子同时说明饮水和食物的选择。"),
    write: complete("补全值班便条：The rescue shift starts in thirty ____。只写一个英文词。", "minutes", "旁白给出 starts in thirty minutes。"),
  },
  {
    role: "marcus", grade: 7, title: "拍摄路线的休息点", objective: "依据路线与身体状态安排休息",
    scene: [
      scene("narrator", "Marcus's photo walk has two stops: the market at 11 and the gallery at 2.", "Marcus 的拍摄路线有两站：十一点到市场，两点到画廊。"),
      scene("character", "Last time I walked for hours without water. I felt dizzy before the gallery visit.", "上次我走了好几个小时没喝水，去画廊前觉得头晕。"),
      scene("narrator", "A water station is beside the market. Marcus can stop there before the next walk.", "市场旁有饮水点。Marcus 可以在继续走之前停一下。"),
    ],
    choice: select("Marcus 应该在哪个地点安排喝水？", ["市场旁的饮水点", "画廊参观结束后", "不需要喝水"], "市场旁的饮水点", "市场旁有饮水点，且在下一段步行之前。"),
    order: arrange("给同伴写一条简短建议", ["market", "the", "at", "water", "Drink", "."], "Drink water at the market.", "这条建议有动作和可执行的地点。"),
    write: complete("补全行程：The gallery visit is at ____。用英文单词写时间。", "two", "路线把画廊时间列为 at 2，英文可写作 two。"),
  },
  {
    role: "oliver", grade: 8, title: "两种读书会", objective: "比较论坛意见、理由与具体例子",
    scene: [
      scene("narrator", "Bookshop forum: Lee wants a quiet reading hour because shy readers need time to think.", "书店论坛：Lee 想要安静阅读时段，因为害羞的读者需要思考时间。"),
      scene("character", "Ava prefers a discussion. She says readers discover new ideas when they explain a page to others.", "Ava 更喜欢讨论。她认为读者向他人解释一页内容时会发现新想法。"),
      scene("narrator", "Oliver can divide the club into a quiet first half and a discussion second half.", "Oliver 可以把读书会分成先安静阅读、再讨论的两段。"),
    ],
    choice: select("哪项准确比较了两人的理由？", ["Lee 重视思考时间，Ava 重视交流新想法", "两人都反对讨论", "Ava 想取消读书会"], "Lee 重视思考时间，Ava 重视交流新想法", "两条论坛信息分别给出思考与交流的理由。"),
    order: arrange("用英语概括 Oliver 的折中安排", ["discuss", "then", "first", "Read", "."], "Read first, then discuss.", "先后顺序同时回应了两种需求。"),
    write: complete("补全对 Lee 的回应：We will have a quiet first ____。只写一个英文词。", "half", "旁白说明 quiet first half。"),
  },
  {
    role: "ruby", grade: 8, title: "救助活动的两种招募方式", objective: "从不同观点中提取理由并形成折中",
    scene: [
      scene("narrator", "Volunteer board: Jo wants a short online form because it is quick to share.", "志愿者留言板：Jo 想用简短的线上表单，因为它容易分享。"),
      scene("character", "Kim asks for a paper form at my café. Some neighbours do not use the website.", "Kim 希望我在咖啡馆放纸质表单。有些邻居不用网站。"),
      scene("narrator", "Ruby can keep the online form and place paper copies beside the café counter.", "Ruby 可以保留线上表单，也在咖啡馆柜台旁放纸质版。"),
    ],
    choice: select("Kim 提出纸质表单的理由是什么？", ["让不用网站的邻居也能报名", "线上表单填写太慢", "咖啡馆没有网络"], "让不用网站的邻居也能报名", "Kim 的证据是 Some neighbours do not use the website。"),
    order: arrange("写出 Ruby 的折中决定", ["forms", "both", "use", "can", "We", "."], "We can use both forms.", "both 指线上和纸质两种表单。"),
    write: complete("补全说明：Paper copies will be beside the café ____。只写一个英文词。", "counter", "旁白给出纸质版的具体放置地点。"),
  },
  {
    role: "marcus", grade: 8, title: "社区展览的照片说明", objective: "比较两位观众的观点与受众需求",
    scene: [
      scene("narrator", "Gallery forum: Dana likes very short captions because she wants to focus on the photographs.", "画廊论坛：Dana 喜欢很短的说明，因为她想专注看照片。"),
      scene("character", "Ravi asks for more context. Without a date or place, he cannot understand what a street photo shows.", "Ravi 想要更多背景。没有日期或地点，他不明白街拍展示什么。"),
      scene("narrator", "Marcus can put a short caption under each photo and a longer note nearby.", "Marcus 可以在每张照片下写短说明，旁边再放较长的介绍。"),
    ],
    choice: select("哪项安排同时回应 Dana 和 Ravi？", ["照片下短说明，旁边提供日期地点", "删掉所有说明", "只写很长的说明挡住照片"], "照片下短说明，旁边提供日期地点", "Dana 要简短，Ravi 要日期地点；旁白提供两层信息。"),
    order: arrange("写给展览团队的执行句", ["nearby", "note", "longer", "a", "Add", "."], "Add a longer note nearby.", "较长说明放在旁边，不遮挡照片。"),
    write: complete("补全 Ravi 的需求：Each photo needs a date and a ____。只写一个英文词。", "place", "Ravi 明确需要 date or place 才能理解照片。"),
  },
  {
    role: "oliver", grade: 9, title: "书店旧海报的日期", objective: "整理不同记录的时间线并保留不确定性",
    scene: [
      scene("narrator", "A poster says Oliver's bookshop opened in 1998. A newspaper photo is dated 1997.", "海报说 Oliver 的书店在 1998 年开业；一张报纸照片标着 1997 年。"),
      scene("character", "The photo may show the building before it became a bookshop. We need the opening record.", "照片可能拍的是它成为书店之前的建筑。我们需要开业记录。"),
      scene("narrator", "The archive has a dated opening notice, but Oliver has not read it yet.", "档案馆有标注日期的开业通知，但 Oliver 还没读。"),
    ],
    choice: select("目前哪项判断有足够依据？", ["1997 年照片不能单独推翻开业年份", "书店一定在 1997 年开业", "海报一定是假的"], "1997 年照片不能单独推翻开业年份", "照片可能只是建筑旧照；开业通知尚未核对。"),
    order: arrange("写出下一步核查动作", ["notice", "opening", "the", "Check", "."], "Check the opening notice.", "开业通知比建筑照片更直接对应开业时间。"),
    write: complete("补全审慎说明：The photo ____ show the building before 1998. 只写一个英文词。", "may", "may 保留了照片用途尚未确认的不确定性。"),
  },
  {
    role: "ruby", grade: 9, title: "海龟救助记录的数字", objective: "区分记录事实与无法证实的原因",
    scene: [
      scene("narrator", "Rescue log: six turtles were brought in on Monday; nine on Tuesday.", "救助记录：周一送来六只海龟，周二送来九只。"),
      scene("character", "A post says the rise was caused by the storm. The log has no information about why each turtle was found.", "一则帖子说增加是暴风雨造成的，但记录没有每只海龟被发现原因的信息。"),
      scene("narrator", "Ruby is writing a brief update for new volunteers.", "Ruby 正给新志愿者写简报。"),
    ],
    choice: select("简报中哪项说法最有依据？", ["周二记录九只，原因尚不明确", "暴风雨导致每一只海龟获救", "周二的数量比周一少"], "周二记录九只，原因尚不明确", "数量来自记录；原因不在记录里。"),
    order: arrange("写出可以核对的数量变化", ["Tuesday", "on", "nine", "records", "log", "The", "."], "The log records nine on Tuesday.", "说明证据来自记录，并注明日期。"),
    write: complete("补全给志愿者的限定句：The cause is still ____。只写一个英文词。", "unclear", "记录没有原因字段，因此不能把帖子当成已证实结论。"),
  },
  {
    role: "marcus", grade: 9, title: "照片报道中的先后顺序", objective: "从图注与采访中重建事件顺序",
    scene: [
      scene("narrator", "Photo archive: the market lights went out at 6:10; a crowd gathered at 6:20.", "照片档案：市场灯光 6:10 熄灭，人群 6:20 聚集。"),
      scene("character", "An interview says the music began after people gathered. My photo of the band is dated 6:35.", "采访说音乐在人群聚集后开始。我拍的乐队照片标着 6:35。"),
      scene("narrator", "Marcus must write a caption that follows the documented order.", "Marcus 必须按记录的顺序写图注。"),
    ],
    choice: select("哪种事件顺序符合两份记录？", ["停电→人群聚集→音乐开始", "音乐开始→停电→人群聚集", "人群聚集→音乐开始→停电"], "停电→人群聚集→音乐开始", "档案给出 6:10 和 6:20，采访把音乐放在聚集之后。"),
    order: arrange("写出图注的第一句", ["first", "out", "went", "lights", "The", "."], "The lights went out first.", "first 对应最早的 6:10 事件。"),
    write: complete("补全图注：The crowd gathered at ____。按记录写出时间。", "6:20", "档案明确给出人群聚集的时间。"),
  },
  {
    role: "oliver", grade: 10, title: "青少年读书社的时间冲突", objective: "整合日程与参与者需求，写出可执行调整",
    scene: [
      scene("narrator", "Club plan: the teen reading group meets at 4 on Thursday. The school debate team ends at 4:30.", "社团计划：青少年读书组周四四点聚会；学校辩论队四点半结束。"),
      scene("character", "Three members are on the debate team. I can move the reading group to 5, but the bookshop closes at 6.", "三位成员也参加辩论队。我可以把读书组改到五点，但书店六点关门。"),
      scene("narrator", "Oliver needs an invitation with a feasible start and end time.", "Oliver 需要在邀请函上写可行的开始和结束时间。"),
    ],
    choice: select("哪段活动时间既照顾辩论队成员，也符合营业时间？", ["周四 5:00–6:00", "周四 4:00–5:00", "周四 6:00–7:00"], "周四 5:00–6:00", "辩论队 4:30 才结束，书店 6 点关门。"),
    order: arrange("排出邀请函上的核心句", ["five", "at", "starts", "group", "reading", "The", "."], "The reading group starts at five.", "五点开始符合两个时间约束。"),
    write: complete("补全邀请函的时间段：The group runs from ____。用英文词写起止时间。", "five to six", "辩论队 4:30 结束，书店 6 点关门，因此活动可从五点到六点。"),
  },
  {
    role: "ruby", grade: 10, title: "学生志愿者的周末安排", objective: "根据训练、值班与交通时间确定合理计划",
    scene: [
      scene("narrator", "Volunteer note: turtle care training is Saturday 9–11; the rescue desk shift starts at 11:30.", "志愿者便条：海龟护理培训周六 9–11 点；救助台值班 11:30 开始。"),
      scene("character", "Students need twenty minutes to walk from the training room to the desk. I will leave a short break between the two activities.", "学生从培训室走到救助台要二十分钟。我会在两项活动之间留一点休息时间。"),
      scene("narrator", "Ruby must send a clear message to the new student volunteers.", "Ruby 必须给新来的学生志愿者发送清楚的消息。"),
    ],
    choice: select("为什么不能把值班时间提前到 11:10？", ["培训后步行需要二十分钟", "培训在十点结束", "救助台周六不开"], "培训后步行需要二十分钟", "11 点培训结束，20 分钟步行后至少 11:20 才到。"),
    order: arrange("排出给学生的路线提醒", ["training", "after", "desk", "the", "to", "Walk", "."], "Walk to the desk after training.", "先培训，再去救助台，时间顺序明确。"),
    write: complete("补全消息：The rescue shift starts ____ after training ends. 用英文写时间间隔。", "thirty minutes", "培训 11 点结束，值班 11:30 开始，间隔三十分钟。"),
  },
  {
    role: "marcus", grade: 10, title: "青少年摄影展的提交期限", objective: "核对多个截止时间并向明确受众写提醒",
    scene: [
      scene("narrator", "Exhibition notice: students submit photos by Friday; selected photos need captions by Monday.", "展览通知：学生周五前提交照片；入选照片的说明文字周一前提交。"),
      scene("character", "A student asks if the caption must be ready on Friday. I should explain the two deadlines clearly.", "一位学生问说明文字是否也必须周五准备好。我应当解释清楚两个截止时间。"),
      scene("narrator", "Marcus replies to that student, who has already chosen a photograph.", "Marcus 回复这位已经选好照片的学生。"),
    ],
    choice: select("给这位学生的哪条提醒准确？", ["周五交照片；若入选，周一前交说明", "照片和说明都在周一后交", "周五只交说明"], "周五交照片；若入选，周一前交说明", "通知给出两个不同的截止日期和入选条件。"),
    order: arrange("排出第一项明确任务", ["Friday", "by", "photo", "your", "Submit", "."], "Submit your photo by Friday.", "学生已选好照片，应先按周五截止时间提交。"),
    write: complete("补全给学生的第二句：Send your caption ____。写出截止时间和前提。", "by Monday if selected", "说明文字仅对入选照片要求，截止周一。"),
  },
];

const references: Record<Draft["grade"], NonNullable<UnitTemplate["learningReference"]>> = {
  3: { volumeId: "pep-elementary-3upper-revised", unitNumber: 2,
    evidenceUrl: "https://www.pep.com.cn/xw/zt/hd/12/xjcjs/xx/202409/t20240920_1995564.html",
    designFocus: "家庭关系识别、信息图与简短介绍的连续任务", evidenceLevel: "sample-page" },
  7: { volumeId: "pep-junior-7lower-revised", unitNumber: 4,
    evidenceUrl: "https://www.pep.com.cn/xw/zt/hd/12/xjcjs/cz/202510/t20251024_2004130.html",
    designFocus: "健康主题的事实提取、建议与回应", evidenceLevel: "sample-page" },
  8: { volumeId: "pep-junior-8upper-revised", unitNumber: 3,
    evidenceUrl: "https://www.pep.com.cn/xw/zt/hd/12/xjcjs/cz/202510/t20251024_2004130.html",
    designFocus: "不同观点的理由比较与折中回应", evidenceLevel: "sample-page" },
  9: { volumeId: "pep-junior-9upper-revised", unitNumber: 4,
    evidenceUrl: "https://www.pep.com.cn/xw/zt/hd/12/xjcjs/cz/202510/t20251024_2004130.html",
    designFocus: "多轮信息记录、时间顺序与证据界限", evidenceLevel: "sample-page" },
  10: { volumeId: "pep-senior-mandatory-1", unitNumber: 1,
    evidenceUrl: "https://www.pep.com.cn/ebook/rjs11gzjksjsyy/",
    designFocus: "青少年活动的日程约束与面向受众的表达", evidenceLevel: "sample-page" },
};

const initialUnitSeedsV2: readonly UnitTemplate[] = drafts.map((draft) => {
  const questions: readonly UnitQuestion[] = [
    { id: "q1", kind: "choice", ...draft.choice },
    { id: "q2", kind: "order", ...draft.order },
    { id: "q3", kind: "write", options: [], ...draft.write },
  ];
  return {
    id: `unit-v2-${draft.role}-g${String(draft.grade)}-1`, roleKey: draft.role, grade: draft.grade,
    title: draft.title, objective: draft.objective, learningReference: references[draft.grade],
    scene: draft.scene, questions,
  };
});

const concludingBeats: Readonly<Record<string, readonly [english: string, chinese: string]>> = {
  "unit-v2-oliver-g10-1": ["The club has already printed a draft timetable, so any change must be clear to everyone who plans to attend.", "读书社已经印出暂定时间表，任何改动都要明确告知准备参加的人。"],
  "unit-v2-ruby-g10-1": ["Several students also need time to travel home after their shift, so the closing time matters to them.", "几名学生值班后还要赶路回家，因此结束时间也很重要。"],
  "unit-v2-marcus-g10-1": ["The organiser will print the exhibition labels after selecting photographs, making the two deadlines important for different students.", "主办方选好照片后才印展签，因此两个截止日影响不同学生。"],
  "unit-v2-oliver-g7-2": ["Oliver writes both times on the group notice so students can decide.", "Oliver 把两个时间都写在通知上，方便学生选择。"],
  "unit-v2-ruby-g7-2": ["Ruby checks the timetable before inviting the student.", "Ruby 邀请学生前先核对课程表。"],
  "unit-v2-marcus-g7-2": ["The group wants a clear reminder before the weekend.", "小组希望在周末前收到清楚提醒。"],
  "unit-v2-oliver-g7-3": ["One student asks which activity fits the available hour.", "一名学生问空出的那一小时适合哪项活动。"],
  "unit-v2-ruby-g7-3": ["The student can attend only one of the events.", "这名学生只能参加其中一项活动。"],
  "unit-v2-marcus-g7-3": ["Marcus asks the student to check the meeting times first.", "Marcus 请学生先核对两项活动的时间。"],
  "unit-v2-oliver-g7-4": ["A new visitor has not read the sign yet.", "一位新访客还没读到告示。"],
  "unit-v2-ruby-g7-4": ["A family is waiting beside the quiet area.", "一家人正在安静区旁等候。"],
  "unit-v2-marcus-g7-4": ["The wall sign also explains the rule near the photographs.", "照片旁的墙面告示也说明了这条规则。"],
  "unit-v2-oliver-g8-2": ["Oliver must tell people who already reserved seats.", "Oliver 还得通知已经预订座位的人。"],
  "unit-v2-marcus-g8-2": ["The group needs a safe replacement location.", "小组需要一个安全的替代拍摄地点。"],
  "unit-v2-marcus-g8-3": ["He reads both reviews before deciding what to display.", "他决定展出什么之前先读两篇评论。"],
  "unit-v2-oliver-g8-4": ["The incorrect note could confuse the next employee.", "错误便条可能误导下一位店员。"],
  "unit-v2-ruby-g8-4": ["Several volunteers may rely on the copied note when planning their shift.", "几位志愿者安排值班时可能会依据转发便条。"],
  "unit-v2-marcus-g8-4": ["The student wants to submit work before the deadline.", "学生希望在截止时间前交作品。"],
  "unit-v2-ruby-g9-2": ["Ruby asks for the map of each survey before describing a trend.", "Ruby 在谈论趋势前要求核对每次调查的区域图。"],
  "unit-v2-marcus-g9-2": ["Marcus cannot see the same stretch of road in both pictures.", "Marcus 在两张照片里看不到完全相同的路段。"],
  "unit-v2-ruby-g9-3": ["Her message should give the public a reason to trust its numbers.", "她的消息需要让公众知道数字的核实范围。"],
  "unit-v2-marcus-g9-3": ["The correction will appear beside the original photograph.", "更正说明会展示在原照片旁。"],
  "unit-v2-oliver-g9-4": ["Oliver still wants to reduce the number of receipts he prints each week.", "Oliver 仍希望减少每周打印的收据数量。"],
  "unit-v2-ruby-g9-4": ["The sign will stand where visitors make safety decisions.", "标牌将立在访客需要作出安全决定的地方。"],
  "unit-v2-marcus-g9-4": ["Marcus wants every visitor to understand the basic story.", "Marcus 希望每位访客都能理解作品的基本故事。"],
  "unit-v2-oliver-g10-2": ["The organiser says late arrivals may enter only after the opening reading. Oliver also has to bring a signed ticket, which he will keep in his bag.", "主办方说迟到者要等开场朗读结束才能入场。Oliver 还须携带已签名的票，并把票放在包里。"],
  "unit-v2-ruby-g10-2": ["The registration desk closes just before the opening talk, and Ruby is introducing one speaker. She checks the bus plan against both the desk time and her own seating deadline.", "登记台在开幕发言前关闭，而 Ruby 要介绍一位发言人；她同时核对登记时间与自己的入座期限。"],
  "unit-v2-marcus-g10-2": ["The workshop leader asks participants to be inside the hall when the demonstration begins. Marcus has no extra transfer time in this estimate, so a delay would make the plan less reliable.", "讲习班主持人要求学员在演示开始时已进场。这份估计未包含换乘余量，延误会降低行程可靠性。"],
  "unit-v2-oliver-g10-3": ["A visitor with limited time asks to inspect every letter, but the owner has agreed to a short display of the original only. Oliver must explain why the digital version can support detailed reading.", "时间有限的访客想看清每个字母，但所有者只同意原件短时展出；Oliver 要解释数字图为何更适合细读。"],
  "unit-v2-ruby-g10-3": ["The model shows the tower's old shape and the route of its light. Ruby can guide a large group there before offering a smaller, supervised upstairs visit when conditions allow.", "模型展示灯塔旧貌与灯光路线。Ruby 可先带大团体看模型，条件允许时再安排小规模上楼。"],
  "unit-v2-marcus-g10-3": ["The gallery plans to place a label beside each photograph, including its date and whether visitors are seeing an original or a copy. This prevents a conservation decision from changing the historical claim.", "画廊计划在每张照片旁标注日期与原件或复制品身份，避免保存方式误导历史信息。"],
  "unit-v2-oliver-g10-4": ["Several readers are still in the building, but none has reported a lost wallet yet. Oliver can record where and when he found it so staff have details to verify later.", "楼里还有读者，但尚无人报告丢钱包。Oliver 可记录发现地点和时间，供工作人员稍后核对。"],
  "unit-v2-ruby-g10-4": ["The animal is close to the path, where curious visitors are gathering. Ruby can keep people back while giving the trained team a landmark they can recognise quickly.", "动物靠近人群聚集的小路。Ruby 可让访客后退，并给救助队报容易辨认的地标。"],
  "unit-v2-marcus-g10-4": ["The child is not the subject of the photograph, and the street scene still makes sense without the foreground figure. Marcus can show the cropped version to the parent before sharing it.", "孩子并非照片主题；裁掉前景人物后街景仍完整。Marcus 可在分享前给家长看裁切版。"],
  "unit-v2-ruby-g11-1": ["She records the patrol length beside the count so future volunteers can compare like with like.", "她把巡查长度与计数并列记录，方便以后按相同范围比较。"],
  "unit-v2-marcus-g11-1": ["He keeps the untouched scan beside any edited copy so viewers can see which details were reconstructed.", "他把原始扫描件与修复版并列保存，让观众分辨哪些细节经过重建。"],
  "unit-v2-ruby-g11-2": ["She offers a quieter place for the next instruction.", "她为下一条指示安排更安静的位置。"],
  "unit-v2-marcus-g11-2": ["He prepares to ask permission before raising the camera again.", "他准备在再次举起相机前先征求同意。"],
  "unit-v2-oliver-g11-3": ["He saves the original poster and the organiser's reply so readers can see why the description changed.", "他保存原海报和主办方回复，让读者看见说明修改的依据。"],
  "unit-v2-ruby-g11-3": ["She asks whether the guest wants examples from both families.", "她询问客人是否想了解两个家庭的例子。"],
  "unit-v2-marcus-g11-3": ["The corrected caption will credit the photographer and identify the school setting.", "更正后的图注会标明摄影师和学校场合。"],
};

export const authoredUnitSeedsV2: readonly UnitTemplate[] = [...initialUnitSeedsV2, ...expandedUnitSeedsV2].map(unit => {
  const extra = concludingBeats[unit.id];
  return extra ? { ...unit, scene: [...unit.scene, { speaker: "narrator", english: extra[0], chinese: extra[1] }] } : unit;
});
