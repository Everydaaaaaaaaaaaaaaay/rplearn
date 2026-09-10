import Foundation

public struct GrammarTermExample: Equatable, Sendable {
    public let english: String
    public let chinese: String
    public let highlights: [String]

    public init(english: String, chinese: String, highlights: [String]) {
        self.english = english
        self.chinese = chinese
        self.highlights = highlights
    }
}

public struct GrammarTermEntry: Equatable, Identifiable, Sendable {
    public let term: String
    public let definition: String
    public let usage: String
    public let commonForms: [String]
    public let examples: [GrammarTermExample]

    public var id: String { term }

    public init(
        term: String,
        definition: String,
        usage: String,
        commonForms: [String],
        examples: [GrammarTermExample]
    ) {
        self.term = term
        self.definition = definition
        self.usage = usage
        self.commonForms = commonForms
        self.examples = examples
    }
}

/// 面向聊天建议的端上语法术语库。内容固定随包提供，离线也能立即打开。
public enum GrammarTermCatalog {
    public enum Segment: Equatable, Sendable {
        case text(String)
        case term(String)
    }

    public static let entries: [GrammarTermEntry] = [
        entry("主语", "句子所谈论的人、事物或概念。", "通常位于谓语之前，决定句子主要在说“谁”或“什么”。", ["名词", "代词", "名词短语", "动名词"], "Ruby loves coffee.", "Ruby 喜欢咖啡。", ["Ruby"]),
        entry("谓语", "说明主语做什么、是什么或处于什么状态的核心部分。", "谓语以动词为中心，并随时态、人称和数发生变化。", ["动词", "动词短语", "系动词 + 表语"], "Marcus takes photos.", "Marcus 拍照片。", ["takes photos"]),
        entry("宾语", "动作直接或间接涉及的对象。", "常放在及物动词或介词之后，回答“对谁”或“对什么”。", ["直接宾语", "间接宾语", "介词宾语"], "Oliver reads old books.", "Oliver 阅读旧书。", ["old books"]),
        entry("表语", "位于系动词之后，用来说明主语的身份、性质或状态。", "表语可由形容词、名词或短语充当，不能当作动作的宾语理解。", ["形容词", "名词", "介词短语"], "The café is quiet.", "这家咖啡馆很安静。", ["quiet"]),
        entry("定语", "修饰或限定名词、代词的成分。", "英语中常见前置形容词和后置介词短语、从句。", ["形容词", "名词", "介词短语", "定语从句"], "We found a quiet table.", "我们找到了一张安静的桌子。", ["quiet"]),
        entry("状语", "说明动作或状态发生的时间、地点、方式、原因或程度。", "可修饰动词、形容词、副词或整句，位置比较灵活。", ["副词", "介词短语", "状语从句"], "She answered very calmly.", "她非常平静地回答了。", ["very calmly"]),
        entry("补语", "补充说明主语或宾语，使句意完整的成分。", "常见于 make、find、call 等结构之后，也可补充主语状态。", ["主语补语", "宾语补语"], "The news made him happy.", "这个消息让他很开心。", ["happy"]),
        entry("名词", "表示人、地点、事物或抽象概念的词。", "可作主语、宾语、表语，也可被冠词和形容词修饰。", ["可数名词", "不可数名词", "专有名词"], "The bridge looks beautiful.", "这座桥看起来很美。", ["bridge"]),
        entry("代词", "用来代替名词或名词短语的词。", "可避免重复；形式会随人称、数和句法位置变化。", ["I / me", "he / him", "they / them", "this / that"], "She waved at us.", "她向我们挥手。", ["She", "us"]),
        entry("动词", "表示动作、状态或变化的词。", "动词是谓语核心，会体现时态、语态，有时还随主语变化。", ["实义动词", "系动词", "助动词", "情态动词"], "They travel often.", "他们经常旅行。", ["travel"]),
        entry("系动词", "连接主语与表语，描述主语的身份、状态、感受或变化。", "系动词后通常接形容词或名词作表语，不表示动作作用于某个宾语。", ["be: am / is / are / was / were", "seem / appear", "become / get / grow", "look / feel / sound", "smell / taste", "remain / stay"], "The coffee smells wonderful.", "这杯咖啡闻起来很香。", ["smells"]),
        entry("实义动词", "自身带有具体动作或状态含义的动词。", "可单独构成谓语；否定、疑问和部分时态可能需要助动词。", ["walk", "read", "know", "want"], "Ruby walks by the river.", "Ruby 沿河散步。", ["walks"]),
        entry("助动词", "帮助主要动词构成时态、否定、疑问或语态的词。", "助动词本身通常不是句子的主要语义中心。", ["be", "do", "have"], "Do you know this place?", "你知道这个地方吗？", ["Do"]),
        entry("情态动词", "表达能力、可能、许可、义务、建议或推测的助动词。", "后面通常接动词原形，第三人称单数不加 -s。", ["can / could", "may / might", "must", "should", "will / would"], "You should try the cake.", "你应该尝尝蛋糕。", ["should"]),
        entry("形容词", "描述名词或代词的性质、状态和特征的词。", "可放在名词前作定语，也可放在系动词后作表语。", ["quiet", "friendly", "interesting"], "The market is lively.", "市场很热闹。", ["lively"]),
        entry("副词", "修饰动词、形容词、副词或整句话的词。", "常表达方式、频率、程度、时间或说话者态度。", ["slowly", "often", "very", "perhaps"], "He speaks slowly.", "他说得很慢。", ["slowly"]),
        entry("介词", "表示名词或代词与句中其他成分之间关系的词。", "后接名词、代词宾格或动名词，构成介词短语。", ["in", "on", "at", "for", "with", "about"], "We met at the station.", "我们在车站见面。", ["at"]),
        entry("连词", "连接词、短语或分句的词。", "并列连词连接同级成分；从属连词引导从句。", ["and / but / or", "because", "although", "if", "when"], "I stayed because it was raining.", "我留下了，因为当时在下雨。", ["because"]),
        entry("冠词", "放在名词前，帮助说明其是否特指以及可数性。", "a/an 表泛指单数可数名词；the 表特指；某些复数或不可数名词前用零冠词。", ["a", "an", "the", "零冠词"], "She ordered a coffee.", "她点了一杯咖啡。", ["a"]),
        entry("不定式", "通常由 to + 动词原形构成的非谓语形式。", "可表示目的，也可作主语、宾语、表语、定语或补语。", ["to do", "not to do", "疑问词 + to do"], "I came to meet Oliver.", "我是来见 Oliver 的。", ["to meet"]),
        entry("动名词", "动词的 -ing 形式在句中承担名词功能。", "可作主语、宾语或表语；介词后使用动名词。", ["doing", "not doing", "having done"], "Meeting new people takes courage.", "认识新朋友需要勇气。", ["Meeting"]),
        entry("现在分词", "动词的 -ing 形式，用于进行时、分词短语或形容词化表达。", "与动名词形式相同，但在句中承担动词或修饰功能。", ["doing", "being done", "having done"], "A runner is crossing the lawn.", "一名跑者正在穿过草坪。", ["crossing"]),
        entry("过去分词", "动词的分词形式，规则动词通常以 -ed 结尾。", "用于完成时、被动语态，也可像形容词一样修饰名词或描述状态。", ["done", "written", "seen", "-ed 规则形式"], "The café is closed.", "咖啡馆关门了。", ["closed"]),
        entry("时态", "通过动词形式表达动作发生时间及其状态的语法系统。", "选择时态时同时考虑时间、是否完成、是否持续以及与现在的关系。", ["一般时", "进行时", "完成时", "完成进行时"], "I have visited London twice.", "我去过伦敦两次。", ["have visited"]),
        entry("从句", "含有主语和谓语、作为更大句子一部分的结构。", "从句可承担名词、定语或状语功能，也可能由连接词引导。", ["名词性从句", "定语从句", "状语从句"], "I know that she is busy.", "我知道她很忙。", ["that she is busy"]),
        entry("主句", "复合句中能够承载主要意思、在结构上不依附另一分句的部分。", "主句可带一个或多个从句；删去从句后通常仍保留基本骨架。", ["主句 + 从句"], "I'll call you when I arrive.", "我到了会给你打电话。", ["I'll call you"]),
        entry("宾语从句", "在句中充当动词或介词宾语的从句。", "常由 that、whether、if 或疑问词引导，并使用陈述语序。", ["that 从句", "whether / if 从句", "疑问词从句"], "I wonder where he lives.", "我想知道他住在哪里。", ["where he lives"]),
        entry("定语从句", "修饰名词或代词、补充说明其身份或特征的从句。", "通常紧跟先行词，由 who、which、that、whose、where 等引导。", ["who", "which", "that", "whose", "where"], "The runner who waved is Ruby.", "挥手的那位跑者是 Ruby。", ["who waved"]),
        entry("状语从句", "在句中说明时间、原因、条件、让步、结果等背景的从句。", "由 when、because、if、although 等引导；句首从句后通常加逗号。", ["时间", "原因", "条件", "让步"], "If it rains, we'll stay inside.", "如果下雨，我们就待在室内。", ["If it rains"]),
        entry("被动语态", "把动作承受者放在主语位置的表达方式。", "基本结构是 be + 过去分词；施动者不重要或未知时尤其常用。", ["be + 过去分词", "情态动词 + be + 过去分词"], "The bridge was built in 1932.", "这座桥建于 1932 年。", ["was built"]),

        entry("名词短语", "以名词为中心的一组词，整体承担名词的功能。", "可包含冠词、形容词及后置修饰语，作主语、宾语或表语。", ["名词", "定语", "冠词"], "The small café is open.", "那家小咖啡馆开门了。", ["The small café"]),
        entry("动词短语", "以动词为中心、连同其相关成分构成的短语。", "可含助动词、宾语或状语；部分动词与小品词构成固定搭配。", ["动词", "助动词", "宾语"], "She has been reading a book.", "她一直在读一本书。", ["has been reading a book"]),
        entry("介词短语", "由介词及其宾语组成的短语。", "常作定语、状语或表语；介词后的人称代词通常用宾格。", ["介词", "介词宾语", "宾格"], "The keys are on the table.", "钥匙在桌上。", ["on the table"]),
        entry("可数名词", "可以按个体计数、有单复数形式的名词。", "单数通常需要冠词或其他限定词；复数可与 many、few 搭配。", ["名词", "单数", "复数", "限定词"], "I bought two apples.", "我买了两个苹果。", ["apples"]),
        entry("不可数名词", "通常不能直接按个体计数的名词。", "一般不用 a/an 或复数词尾；可用量词结构表达数量。", ["名词", "量词"], "We need some water.", "我们需要一些水。", ["water"]),
        entry("专有名词", "表示特定人、地点或机构等名称的名词。", "首字母通常大写；是否用冠词取决于名称惯例。", ["名词", "冠词"], "Ruby lives in London.", "Ruby 住在伦敦。", ["London"]),
        entry("限定词", "放在名词前限定指代范围或数量的词。", "包括冠词、指示词、物主限定词和数量词；排列有一定规则。", ["冠词", "指示代词", "物主代词"], "These two books are mine.", "这两本书是我的。", ["These"]),
        entry("数词", "表示数量或顺序的词。", "基数词回答多少，序数词回答第几。", ["基数词", "序数词"], "We need three tickets.", "我们需要三张票。", ["three"]),
        entry("基数词", "表示数量的数词。", "常修饰可数名词；数量大于一时通常用复数。", ["数词", "可数名词", "复数"], "I have two sisters.", "我有两个姐妹。", ["two"]),
        entry("序数词", "表示顺序的数词。", "名词前通常加 the，但有物主限定词时不用再加 the。", ["数词", "定冠词"], "This is my first visit.", "这是我第一次来访。", ["first"]),
        entry("量词", "用单位或容器等表达事物数量的词语。", "英语常用 a piece of、a cup of 等结构量化不可数名词。", ["不可数名词", "名词短语"], "I'd like a cup of tea.", "我想要一杯茶。", ["a cup of"]),
        entry("感叹词", "独立表达惊讶、喜悦等情感或反应的词。", "常与句子其他部分用逗号或感叹号隔开。", ["感叹句"], "Wow, that's beautiful!", "哇，真漂亮！", ["Wow"]),
        entry("人称代词", "指代说话者、听话者或其他人和事物的代词。", "根据人称、单复数及主语或宾语位置选择形式。", ["主格", "宾格", "代词"], "They invited me.", "他们邀请了我。", ["They"]),
        entry("主格", "人称代词作主语时使用的形式。", "常见形式为 I、you、he、she、it、we、they。", ["人称代词", "主语", "宾格"], "He knows Ruby.", "他认识 Ruby。", ["He"]),
        entry("宾格", "人称代词作动词或介词宾语时使用的形式。", "常见形式为 me、you、him、her、it、us、them。", ["人称代词", "宾语", "介词"], "Ruby called him.", "Ruby 给他打了电话。", ["him"]),
        entry("物主代词", "表达所属关系的代词。", "my 等形容词性物主代词后接名词；mine 等名词性物主代词独立使用。", ["代词", "限定词"], "This book is mine.", "这本书是我的。", ["mine"]),
        entry("反身代词", "指回同一分句主语的代词，也可用于强调。", "常以 -self 或 -selves 结尾；主语和宾语指同一对象时使用。", ["代词", "主语", "宾语"], "She taught herself English.", "她自学了英语。", ["herself"]),
        entry("指示代词", "用来指示人或事物的代词。", "this/these 常指近处，that/those 常指远处；注意单复数。", ["代词", "单数", "复数"], "Those are my bags.", "那些是我的包。", ["Those"]),
        entry("不定代词", "不明确指向某一特定人或事物的代词。", "如 someone、anything、each；someone 等作主语时通常用单数谓语。", ["代词", "主谓一致"], "Someone is outside.", "有人在外面。", ["Someone"]),
        entry("疑问代词", "在疑问句中询问人或事物的代词。", "who、whom、whose、what、which 可作不同句子成分。", ["特殊疑问句", "代词"], "Who called you?", "谁给你打了电话？", ["Who"]),
        entry("关系代词", "引导定语从句并在从句中充当成分的代词。", "如 who、whom、whose、which、that；根据先行词和句中作用选择。", ["定语从句", "先行词", "关系副词"], "The book that I bought is useful.", "我买的那本书很有用。", ["that"]),
        entry("关系副词", "引导定语从句并作状语的词。", "when、where、why 分别表示时间、地点或原因关系。", ["定语从句", "状语", "关系代词"], "This is the café where we met.", "这是我们见面的咖啡馆。", ["where"]),
        entry("先行词", "被定语从句修饰的名词、代词或其他表达。", "判断关系词时，要同时看先行词含义及从句中缺少的成分。", ["定语从句", "关系代词"], "The woman who waved is Ruby.", "挥手的那位女士是 Ruby。", ["woman"]),
        entry("及物动词", "能够直接带宾语的动词。", "不需介词即可连接直接宾语；部分动词可兼有及物和不及物用法。", ["宾语", "直接宾语", "不及物动词"], "I enjoy music.", "我喜欢音乐。", ["enjoy"]),
        entry("不及物动词", "在相应用法中不直接带宾语的动词。", "若要连接对象，常需介词；如 arrive at the station。", ["及物动词", "介词"], "The baby slept.", "宝宝睡着了。", ["slept"]),
        entry("直接宾语", "动作直接作用或涉及的对象。", "双宾语结构中常指事物；可跟在间接宾语后。", ["宾语", "间接宾语", "双宾语"], "She gave me a map.", "她给了我一张地图。", ["a map"]),
        entry("间接宾语", "表示接受者或受益者的宾语。", "双宾语结构中通常位于直接宾语前；部分结构可改为 to/for 短语。", ["宾语", "直接宾语", "双宾语"], "She gave me a map.", "她给了我一张地图。", ["me"]),
        entry("介词宾语", "跟在介词之后、与介词构成短语的成分。", "可以是名词、宾格代词或动名词等。", ["介词短语", "宾格", "动名词"], "We talked about music.", "我们聊了音乐。", ["music"]),
        entry("双宾语", "一个动词同时带间接宾语和直接宾语的结构。", "常见于 give、send、tell 等；并非每个动词都允许这种结构。", ["间接宾语", "直接宾语"], "He sent me a photo.", "他寄给我一张照片。", ["me a photo"]),
        entry("主语补语", "补充说明主语身份、性质或状态的成分。", "系动词后的表语属于主语补语；不要误判为宾语。", ["补语", "表语", "系动词"], "Ruby became a doctor.", "Ruby 成为了一名医生。", ["a doctor"]),
        entry("宾语补语", "补充说明宾语身份、状态或动作的成分。", "常见结构为动词 + 宾语 + 形容词、名词或非谓语形式。", ["补语", "宾语", "非谓语动词"], "We found the room empty.", "我们发现房间是空的。", ["empty"]),
        entry("同位语", "用另一个名词性成分解释或说明前一个成分。", "补充说明的同位语常用逗号隔开，紧密限定的则不一定。", ["名词短语", "同位语从句"], "My friend Ruby is here.", "我的朋友 Ruby 在这里。", ["Ruby"]),
        entry("非谓语动词", "不独立充当句子谓语的动词形式。", "包括不定式、动名词和分词；仍可带宾语或状语。", ["不定式", "动名词", "现在分词", "过去分词"], "I want to leave.", "我想离开。", ["to leave"]),
        entry("动词原形", "动词未加时态、人称等变化的基本形式。", "用于情态动词之后、祈使句以及部分不定式结构。", ["情态动词", "不定式", "祈使句"], "You can go now.", "你现在可以走了。", ["go"]),
        entry("第三人称单数", "指除说话者、听话者外的单个人或事物。", "一般现在时肯定句中，实义动词通常加 -s 或 -es。", ["一般现在时", "主谓一致", "单数"], "She works here.", "她在这里工作。", ["works"]),
        entry("单数", "表示一个人、事物或一个语法单位的数形式。", "单数可数名词通常需要限定词；谓语应与主语保持一致。", ["复数", "可数名词", "主谓一致"], "A bird is singing.", "一只鸟在唱歌。", ["bird"]),
        entry("复数", "通常表示两个或更多人、事物的数形式。", "名词常加 -s/-es，也有 children 等不规则形式。", ["单数", "可数名词", "主谓一致"], "The children are playing.", "孩子们在玩耍。", ["children"]),
        entry("主谓一致", "谓语在人称和数上与主语保持一致的规则。", "以主语中心词为准；主语与动词之间的修饰语通常不影响一致关系。", ["主语", "谓语", "第三人称单数"], "The box of books is heavy.", "那箱书很重。", ["is"]),
        entry("定冠词", "表示特指的冠词 the。", "用于双方知道、前文提过或语境中唯一的对象等情况。", ["冠词", "不定冠词", "零冠词"], "Please close the door.", "请关门。", ["the"]),
        entry("不定冠词", "表示非特指单数可数名词的冠词 a/an。", "按后面紧接的发音选择：辅音音素前用 a，元音音素前用 an。", ["冠词", "可数名词", "定冠词"], "She is an engineer.", "她是一名工程师。", ["an"]),
        entry("零冠词", "名词前不使用 a、an 或 the 的情况。", "泛指的复数名词、不可数名词及部分固定表达常用零冠词。", ["冠词", "不可数名词", "复数"], "Music helps me relax.", "音乐帮助我放松。", ["Music"]),
        entry("比较级", "表示两者之间程度差异的形式。", "常用 -er 或 more 构成，与 than 搭配；避免 more better 这样的重复。", ["形容词", "副词", "最高级"], "This route is shorter.", "这条路线更短。", ["shorter"]),
        entry("最高级", "表示某一范围内程度最高的形式。", "常用 -est 或 most 构成；形容词最高级前通常用 the。", ["比较级", "形容词"], "This is the tallest building here.", "这是这里最高的建筑。", ["tallest"]),
        entry("语态", "表示主语与动作之间施动或受动关系的语法范畴。", "同一事件可根据表达重点选择主动或被动。", ["主动语态", "被动语态"], "Ruby opened the door.", "Ruby 打开了门。", ["opened"]),
        entry("主动语态", "通常以动作发出者作主语的表达方式。", "强调谁做了什么；动词形式仍需符合时态和主谓一致。", ["语态", "被动语态", "主语"], "Ruby wrote the letter.", "Ruby 写了这封信。", ["wrote"]),
        entry("名词性从句", "在句中起名词作用的从句。", "可作主语、宾语、表语或同位语，通常采用陈述语序。", ["主语从句", "宾语从句", "表语从句", "同位语从句"], "What she said surprised me.", "她说的话让我惊讶。", ["What she said"]),
        entry("主语从句", "在句中充当主语的从句。", "可置于句首，也常用 it 作形式主语，将从句后置。", ["名词性从句", "形式主语"], "What you need is rest.", "你需要的是休息。", ["What you need"]),
        entry("表语从句", "位于系动词后、充当表语的从句。", "常由 that、whether 或疑问词引导，解释主语的具体内容。", ["名词性从句", "系动词", "表语"], "The problem is that we are late.", "问题是我们迟到了。", ["that we are late"]),
        entry("同位语从句", "解释抽象名词具体内容的从句。", "常跟在 fact、news、idea 等名词后；that 通常只起连接作用。", ["名词性从句", "同位语", "定语从句"], "The news that she won made us happy.", "她获胜的消息让我们高兴。", ["that she won"]),
        entry("限制性定语从句", "用来确定先行词所指对象、不可随意省略的定语从句。", "通常不用逗号隔开；关系词作宾语时有时可以省略。", ["定语从句", "先行词", "非限制性定语从句"], "People who exercise often feel better.", "经常运动的人往往感觉更好。", ["who exercise often"]),
        entry("非限制性定语从句", "对已明确的对象补充信息的定语从句。", "通常用逗号隔开，一般不用 that 引导，关系词不能省略。", ["定语从句", "限制性定语从句"], "Ruby, who lives nearby, is coming.", "Ruby 住在附近，她要来了。", ["who lives nearby"]),
        entry("时间状语从句", "说明主句动作发生时间的从句。", "常由 when、while、before、after、until 引导；表达将来时常用一般现在时。", ["状语从句", "一般现在时"], "Call me when you arrive.", "你到达时给我打电话。", ["when you arrive"]),
        entry("条件状语从句", "说明主句成立条件的从句。", "常由 if、unless 引导；真实将来条件常用主句将来时、从句一般现在时。", ["状语从句", "虚拟语气"], "If it rains, we will stay home.", "如果下雨，我们就待在家里。", ["If it rains"]),
        entry("原因状语从句", "说明主句原因的从句。", "常由 because、since、as 引导；because 与 so 通常不同时连接同一对分句。", ["状语从句", "连词"], "I left because I was tired.", "我离开了，因为我累了。", ["because I was tired"]),
        entry("让步状语从句", "说明存在某种不利条件但主句仍成立的从句。", "常由 although、though、even if 引导；although 通常不与 but 成对使用。", ["状语从句", "连词"], "Although it rained, we went out.", "虽然下雨，我们还是出门了。", ["Although it rained"]),
        entry("目的状语从句", "说明主句动作目的的从句。", "常由 so that、in order that 引导，常含 can、could 等情态动词。", ["状语从句", "情态动词"], "Speak slowly so that I can understand.", "说慢一点，好让我听懂。", ["so that I can understand"]),
        entry("结果状语从句", "说明某种行为或程度所造成结果的从句。", "常用 so + 形容词/副词 + that 或 such + 名词短语 + that。", ["状语从句", "形容词", "副词"], "It was so cold that we stayed inside.", "天气太冷了，所以我们待在室内。", ["that we stayed inside"]),
        entry("陈述句", "陈述事实、观点或情况的句子。", "常用主语在谓语前的语序，可为肯定或否定。", ["肯定句", "否定句", "疑问句"], "She likes tea.", "她喜欢茶。", ["She likes tea."]),
        entry("肯定句", "肯定某种事实或情况的句子。", "谓语形式需与时态、人称和数相符。", ["陈述句", "否定句"], "I know Ruby.", "我认识 Ruby。", ["know"]),
        entry("否定句", "否定某种事实或情况的句子。", "常在 be、助动词或情态动词后加 not；一般实义动词常需 do/does/did。", ["助动词", "情态动词", "肯定句"], "I do not know him.", "我不认识他。", ["do not"]),
        entry("疑问句", "用来提出问题的句子。", "包括一般疑问句、特殊疑问句、选择疑问句和反意疑问句。", ["一般疑问句", "特殊疑问句", "选择疑问句", "反意疑问句"], "Are you ready?", "你准备好了吗？", ["Are you ready?"]),
        entry("一般疑问句", "通常可用 yes 或 no 回答的疑问句。", "常将 be、助动词或情态动词放在主语前。", ["疑问句", "助动词"], "Do you like coffee?", "你喜欢咖啡吗？", ["Do"]),
        entry("特殊疑问句", "用疑问词询问具体信息的句子。", "常用疑问词加一般疑问句语序；疑问词作主语时通常不倒装。", ["疑问句", "疑问代词", "倒装句"], "Where do you live?", "你住在哪里？", ["Where"]),
        entry("选择疑问句", "提供两个或更多选项让对方选择的疑问句。", "常用 or 连接选项，回答时一般直接说明选择。", ["疑问句", "连词"], "Would you like tea or coffee?", "你想喝茶还是咖啡？", ["tea or coffee"]),
        entry("反意疑问句", "在陈述后附加简短问句以确认信息的结构。", "通常前肯后否或前否后肯；附加问句的助动词和代词与前句对应。", ["疑问句", "助动词", "人称代词"], "You're Ruby, aren't you?", "你是 Ruby，对吧？", ["aren't you"]),
        entry("祈使句", "表达请求、指令、建议或邀请的句子。", "通常以动词原形开头，省略主语 you；否定形式常以 don't 开头。", ["动词原形", "否定句"], "Please sit down.", "请坐。", ["sit down"]),
        entry("感叹句", "表达强烈感受的句子。", "常用 what 修饰名词短语，how 修饰形容词或副词。", ["形容词", "名词短语", "感叹词"], "What a lovely day!", "多美好的一天！", ["What a lovely day!"]),
        entry("简单句", "只有一个独立分句的句子。", "主语或谓语可以并列，仍不一定构成并列句。", ["主语", "谓语", "并列句"], "Ruby and Oliver laughed.", "Ruby 和 Oliver 笑了。", ["Ruby and Oliver laughed."]),
        entry("并列句", "由两个或多个独立分句连接而成的句子。", "常用 and、but、or、so 等并列连词连接，也可使用分号。", ["简单句", "连词", "复合句"], "I called, but no one answered.", "我打了电话，但没人接。", ["but"]),
        entry("复合句", "包含主句和至少一个从句的句子。", "从句承担名词、定语或状语等作用。", ["主句", "从句", "并列句"], "I stayed because she asked me to.", "我留下了，因为她请我留下。", ["because she asked me to"]),
        entry("虚拟语气", "表达假设、愿望或与事实不符情况的动词表达方式。", "如现在非真实条件常用 if + 过去式，主句用 would + 动词原形。", ["条件状语从句", "情态动词"], "If I were you, I would wait.", "如果我是你，我会等一等。", ["were"]),
        entry("倒装句", "将谓语或部分谓语放到主语之前的句子。", "疑问、否定词置首或地点引导等情况可触发倒装；需区分部分与全部倒装。", ["主语", "谓语", "助动词"], "Never have I seen this before.", "我以前从未见过这个。", ["have I"]),
        entry("强调句", "用特定结构突出句中某个成分的句子。", "常用 it is/was + 被强调部分 + that/who + 其余部分。", ["主语", "宾语", "状语"], "It was Ruby who called.", "打电话的是 Ruby。", ["It was Ruby who"]),
        entry("省略句", "省去可由上下文补全成分的句子。", "常见于口语、并列结构和简短回答；正式写作要确保句意清楚。", ["主语", "谓语", "并列句"], "Want some tea?", "想喝点茶吗？", ["Want some tea?"]),
        entry("直接引语", "直接引用别人原话的表达。", "通常使用引号，保留原话的人称和时态。", ["间接引语", "时态"], "Ruby said, \"I am tired.\"", "Ruby 说：“我累了。”", ["I am tired"]),
        entry("间接引语", "用自己的句子转述别人话语的表达。", "人称、时间词和时态按转述语境调整；转述疑问句时采用陈述语序。", ["直接引语", "宾语从句"], "Ruby said that she was tired.", "Ruby 说她累了。", ["that she was tired"]),
        entry("形式主语", "占据主语位置、把较长的真正主语后置的 it。", "常用于 it is + 形容词 + 不定式或从句结构。", ["主语从句", "不定式", "主语"], "It is easy to learn.", "学习起来很容易。", ["It"]),
        entry("形式宾语", "占据宾语位置、把真正宾语后置的 it。", "常见于 find/think/make + it + 补语 + 不定式或从句。", ["宾语", "宾语补语", "不定式"], "I find it easy to learn.", "我觉得这很容易学。", ["it"]),
        entry("存在句", "用 there be 等结构表达某处存在某人或某物的句子。", "there 在此不是地点副词；be 的数通常与后面的名词短语相应。", ["主谓一致", "名词短语"], "There is a café nearby.", "附近有一家咖啡馆。", ["There is"]),
        entry("一般现在时", "表达习惯、事实或较稳定的状态。", "实义动词用原形或第三人称单数；be 用 am/is/are。", ["时态", "助动词", "动词原形"], "She walks to work.", "她步行上班。", ["walks"]),
        entry("一般过去时", "表达过去发生的动作或状态。", "动词使用过去式；疑问和否定中 did 后接原形。", ["时态", "助动词", "动词原形"], "We visited London yesterday.", "我们昨天游览了伦敦。", ["visited"]),
        entry("一般将来时", "表达将来的动作、安排或预测。", "常用 will + 动词原形；be going to 也可表达计划或有迹象的预测。", ["时态", "助动词", "动词原形"], "I will call tomorrow.", "我明天会打电话。", ["will call"]),
        entry("过去将来时", "从过去的时间点看将要发生的动作。", "常用 would + 动词原形或 was/were going to。", ["时态", "助动词", "过去分词"], "She said she would come.", "她说她会来。", ["would come"]),
        entry("现在进行时", "表达现在或现阶段正在进行的动作。", "使用 am/is/are + 现在分词，也可表达已安排的将来活动。", ["时态", "助动词", "现在分词"], "She is reading now.", "她现在正在读书。", ["is reading"]),
        entry("过去进行时", "表达过去某一时刻或阶段正在进行的动作。", "使用 was/were + 现在分词，常用于交代过去事件的背景。", ["时态", "助动词", "现在分词"], "I was cooking when she called.", "她打电话时我正在做饭。", ["was cooking"]),
        entry("将来进行时", "表达将来某个时刻正在进行的动作。", "使用 will be + 现在分词。", ["时态", "助动词", "现在分词"], "This time tomorrow, I will be flying.", "明天这个时候，我将在飞行途中。", ["will be flying"]),
        entry("现在完成时", "表达过去动作与现在的联系、经历或持续至今的状态。", "使用 have/has + 过去分词；通常不与 yesterday 等已结束的明确过去时间搭配。", ["时态", "助动词", "过去分词"], "I have lost my keys.", "我的钥匙丢了。", ["have lost"]),
        entry("过去完成时", "表达在过去某一参照时间之前已完成的动作。", "使用 had + 过去分词，强调过去的过去。", ["时态", "助动词", "过去分词"], "She had left before I arrived.", "我到达前她就离开了。", ["had left"]),
        entry("将来完成时", "表达在将来某个时间之前将完成的动作。", "使用 will have + 过去分词，常与 by 引导的截止时间连用。", ["时态", "助动词", "过去分词"], "I will have finished by Friday.", "到周五我就会完成。", ["will have finished"]),
        entry("现在完成进行时", "表达过去开始并持续到现在或刚结束的活动。", "使用 have/has been + 现在分词，强调持续过程或其当前影响。", ["时态", "助动词", "现在分词"], "I have been waiting for an hour.", "我已经等了一个小时。", ["have been waiting"]),
        entry("过去完成进行时", "表达持续到过去某个参照时间的活动。", "使用 had been + 现在分词，强调此前持续的过程。", ["时态", "助动词", "现在分词"], "She had been working all day when I arrived.", "我到达时，她已经工作一整天了。", ["had been working"]),
        entry("将来完成进行时", "表达持续到将来某个时间的活动。", "使用 will have been + 现在分词，强调截至该时点的持续时长。", ["时态", "助动词", "现在分词"], "By June, I will have been teaching for ten years.", "到六月我就连续教书十年了。", ["will have been teaching"]),
        entry("一般时", "不以进行或完成形式呈现动作的时态类别。", "根据现在、过去或将来的参照时间，选择对应形式。", ["一般现在时", "一般过去时", "一般将来时", "过去将来时"], "I work here.", "我在这里工作。", ["work"]),
        entry("进行时", "把动作呈现为某一时段内正在进行的时态类别。", "根据现在、过去或将来的参照时间，选择对应形式。", ["现在进行时", "过去进行时", "将来进行时"], "I am working.", "我正在工作。", ["am working"]),
        entry("完成时", "表达动作在某一参照时间前的完成或相关性的时态类别。", "根据现在、过去或将来的参照时间，选择对应形式。", ["现在完成时", "过去完成时", "将来完成时"], "I have finished.", "我已完成。", ["have finished"]),
        entry("完成进行时", "结合完成与进行，强调延续到参照时间的过程。", "根据现在、过去或将来的参照时间，选择对应形式。", ["现在完成进行时", "过去完成进行时", "将来完成进行时"], "I have been reading.", "我一直在读书。", ["have been reading"]),
    ]

    public static let terms: [String] = {
        entries.map(\.term).sorted {
            if $0.count == $1.count { return $0 < $1 }
            return $0.count > $1.count
        }
    }()

    public static func entry(for term: String) -> GrammarTermEntry? {
        entries.first { $0.term == term.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// 从左向右最长优先匹配，保证“系动词”不会再拆成“动词”。普通文字按字符切分，
    /// 让 SwiftUI FlowLayout 在窄聊天卡中自然换行。
    public static func segments(in text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        var result: [Segment] = []
        var index = text.startIndex
        while index < text.endIndex {
            if let match = terms.first(where: { text[index...].hasPrefix($0) }) {
                result.append(.term(match))
                index = text.index(index, offsetBy: match.count)
            } else {
                let next = text.index(after: index)
                result.append(.text(String(text[index..<next])))
                index = next
            }
        }
        return result
    }

    private static func entry(
        _ term: String,
        _ definition: String,
        _ usage: String,
        _ commonForms: [String],
        _ english: String,
        _ chinese: String,
        _ highlights: [String]
    ) -> GrammarTermEntry {
        GrammarTermEntry(
            term: term,
            definition: definition,
            usage: usage,
            commonForms: commonForms,
            examples: [GrammarTermExample(english: english, chinese: chinese, highlights: highlights)]
        )
    }
}
