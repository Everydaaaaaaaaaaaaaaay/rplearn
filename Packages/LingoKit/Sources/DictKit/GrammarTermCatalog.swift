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
    ]

    public static var terms: [String] {
        entries.map(\.term).sorted {
            if $0.count == $1.count { return $0 < $1 }
            return $0.count > $1.count
        }
    }

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
