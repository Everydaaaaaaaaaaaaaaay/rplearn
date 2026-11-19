import Foundation

public enum ChatCharacterMood: String, Codable, CaseIterable, Sendable {
    case happy, amused, relieved, hope, excited, proud, touched, grateful, expecting, curious
    case hesitant, worried, nervous, low, sad, grief, disappointed, lonely, missing, irritated, angry
    case frustrated, disgust, fear, panicked, startled, surprise, confused, distracted, shy
    case embarrassed, ashamed, guilt, hurt, jealous, tired, bored, numb, calm, relaxed

    public var chinesePhrase: String {
        switch self {
        case .happy: "心情不错"
        case .amused: "被逗笑了"
        case .relieved: "松了口气"
        case .hope: "抱有希望"
        case .excited: "有些兴奋"
        case .proud: "有些自豪"
        case .touched: "有些感动"
        case .grateful: "心怀感激"
        case .expecting: "很期待"
        case .curious: "有些好奇"
        case .hesitant: "还有些犹豫"
        case .worried: "有些担心"
        case .nervous: "有些紧张"
        case .low: "情绪有些低落"
        case .sad: "有些伤心"
        case .grief: "很悲痛"
        case .disappointed: "有些失望"
        case .lonely: "有些孤单"
        case .missing: "心里有些想念"
        case .irritated: "有些烦躁"
        case .angry: "有些生气"
        case .frustrated: "感到挫败"
        case .disgust: "感到反感"
        case .fear: "有些害怕"
        case .panicked: "有些惊慌"
        case .startled: "吓了一跳"
        case .surprise: "感到意外"
        case .confused: "有些困惑"
        case .distracted: "有些心不在焉"
        case .shy: "有点害羞"
        case .embarrassed: "有些尴尬"
        case .ashamed: "有些羞愧"
        case .guilt: "心里内疚"
        case .hurt: "心里受伤了"
        case .jealous: "心里有些嫉妒"
        case .tired: "有些疲惫"
        case .bored: "感到无聊"
        case .numb: "心里有些麻木"
        case .calm: "很平静"
        case .relaxed: "很放松"
        }
    }
}

public struct ChatMoodObservation: Equatable, Sendable {
    public let primary: ChatCharacterMood
    public let secondary: ChatCharacterMood?
    public let intensity: Int

    public init(primary: ChatCharacterMood, secondary: ChatCharacterMood? = nil, intensity: Int) {
        self.primary = primary
        self.secondary = secondary
        self.intensity = min(max(intensity, 1), 3)
    }
}

/// Looks for a character's direct report of a present feeling in their delivered reply.
public enum ChatMoodEvidence {
    public static func observe(in reply: String) -> ChatMoodObservation? {
        let visible = quotedText.replacingMatches(in: reply, withTemplate: " \u{FFFC} ")
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        guard !instruction.hasMatch(in: visible), !retraction.hasMatch(in: visible) else { return nil }

        var readings: [Reading] = []
        for sentence in sentences.matches(in: visible) {
            guard !sentence.contains("?"), !sentence.contains("？"),
                  !unassertedContext.hasMatch(in: sentence) else { continue }

            let clause = sentence.trimmingCharacters(in: sentenceEnding)
            readings += readingsIn(clause, opening: englishOpening, separator: englishSeparator, reading: englishReading)
            readings += readingsIn(clause, opening: chineseOpening, separator: chineseSeparator, reading: chineseReading)
        }

        let ranked = readings.sorted { $0.intensity > $1.intensity }
        guard let strongest = ranked.first else { return nil }
        let second = ranked.first { $0.mood != strongest.mood }
        return ChatMoodObservation(primary: strongest.mood, secondary: second?.mood, intensity: strongest.intensity)
    }

    private struct Reading {
        let mood: ChatCharacterMood
        let intensity: Int
        let hasBarePredicate: Bool
    }

    private static func readingsIn(
        _ sentence: String,
        opening: Pattern,
        separator: Pattern,
        reading: (String, Bool) -> Reading?
    ) -> [Reading] {
        let content = opening.removingPrefix(from: sentence) ?? sentence
        var readings: [Reading] = []
        var sharesSubject = false
        for clause in separator.separate(content) {
            let evidence = reading(trimClause(clause), sharesSubject)
            sharesSubject = evidence?.hasBarePredicate == true
            if let evidence { readings.append(evidence) }
        }
        return readings
    }

    private static func englishReading(_ text: String, sharesSubject: Bool) -> Reading? {
        let predicate: String
        let lexicon: Lexicon
        if let remainder = englishSelf.removingPrefix(from: text) {
            predicate = remainder
            lexicon = englishFeelings
        } else if let remainder = englishSubject.removingPrefix(from: text) {
            predicate = remainder
            lexicon = englishVerbs
        } else if sharesSubject {
            predicate = text
            lexicon = englishFeelings
        } else {
            return nil
        }

        let (body, intensity) = removeModifiers(from: predicate, modifiers: englishModifiers)
        guard let (word, term, tail) = lexicon.read(body) else { return nil }
        let isBare = tail.isEmpty || englishAside.hasMatch(in: tail)

        if word == "miss" {
            guard knownObjectOfMissing.hasMatch(in: tail) else { return nil }
        } else if term.acceptsObject {
            guard (!tail.isEmpty || term.mood == .grief), !englishNegatedTail.hasMatch(in: tail) else { return nil }
        } else if !isBare && !englishReason.hasMatch(in: tail) {
            return nil
        }

        // Conventional offers of help and lasting traits give little evidence of current mood.
        if term.mood == .happy, englishPoliteOffer.hasMatch(in: tail) { return nil }
        if term.mood == .shy, !englishFeelingVerb.hasMatch(in: text), !englishCurrentTime.hasMatch(in: tail) { return nil }
        if (word == "blue" || word == "down"), !englishFeelingVerb.hasMatch(in: text) { return nil }
        if word == "guilty", !englishFeelingVerb.hasMatch(in: text), !tail.hasPrefix("about ") { return nil }
        if word == "hurt", !englishFeelingVerb.hasMatch(in: text), !englishEmotionalContext.hasMatch(in: tail) { return nil }
        if word == "afraid", tail.hasPrefix("that "), !englishFeelingVerb.hasMatch(in: text) { return nil }
        if word == "mad", !tail.hasPrefix("at ") { return nil }
        if word == "tired", tail.hasPrefix("of ") { return nil }

        return Reading(mood: term.mood, intensity: max(term.intensity, intensity), hasBarePredicate: isBare)
    }

    private static func chineseReading(_ text: String, sharesSubject: Bool) -> Reading? {
        let predicate: String
        if let remainder = chineseSelf.removingPrefix(from: text) {
            predicate = remainder
        } else if sharesSubject {
            predicate = text
        } else {
            return nil
        }

        let (modified, intensity) = removeModifiers(from: predicate, modifiers: chineseModifiers)
        let body = chineseSharedFeeling.removingPrefix(from: modified) ?? modified
        if chineseAmused.hasMatch(in: body) { return Reading(mood: .amused, intensity: intensity, hasBarePredicate: true) }
        if chineseStartled.hasMatch(in: body) { return Reading(mood: .startled, intensity: intensity, hasBarePredicate: true) }

        guard let (word, term, tail) = chineseFeelings.read(body) else { return nil }
        if (word == "受伤" || word == "麻木"), !chineseEmotionalContext.hasMatch(in: predicate) { return nil }
        let isBare = tail.isEmpty || chineseAside.hasMatch(in: tail)
        if !isBare && !chineseReason.hasMatch(in: tail) {
            guard term.acceptsObject, !chineseAttribution.hasMatch(in: tail) else { return nil }
        }
        return Reading(mood: term.mood, intensity: max(term.intensity, intensity), hasBarePredicate: isBare)
    }

    private static func removeModifiers(from text: String, modifiers: [Modifier]) -> (String, Int) {
        var remaining = text
        var intensity: Int?
        while let match = modifiers.lazy.compactMap({ modifier in
            modifier.pattern.removingPrefix(from: remaining).map { ($0, modifier.intensity) }
        }).first {
            remaining = match.0
            if let level = match.1 { intensity = max(intensity ?? level, level) }
        }
        return (remaining, intensity ?? 2)
    }

    private struct Modifier {
        let pattern: Pattern
        let intensity: Int?

        init(_ expression: String, intensity: Int? = nil) {
            pattern = Pattern(expression)
            self.intensity = intensity
        }
    }

    private static let englishModifiers: [Modifier] = [
        Modifier(#"^(?:a little(?: bit)?|a bit|a touch|slightly|somewhat|kind of|sort of) +"#, intensity: 1),
        Modifier(#"^(?:very|so|extremely|incredibly|absolutely|deeply|terribly|intensely|super|completely|utterly) +"#, intensity: 3),
        Modifier(#"^(?:really|genuinely|honestly|still|also|just|quite|pretty|rather|suddenly|now|actually) +"#),
    ]

    private static let chineseModifiers: [Modifier] = [
        Modifier(#"^(?:有一点点|有一点|有点儿|有点|稍微|一点点)"#, intensity: 1),
        Modifier(#"^(?:非常|特别|相当|极其|超级|太)"#, intensity: 3),
        Modifier(#"^(?:现在|此刻|今天|心里面|心里|心底|情绪上|正在|突然|真的|说真的|真|确实|其实|依然|仍然|还是|终于|觉得|感觉|感到|依旧|又|既|却|也|仍|还|挺|蛮|颇|很|好(?!奇|笑|玩))"#),
    ]

    private struct Word {
        let mood: ChatCharacterMood
        let intensity: Int
        let acceptsObject: Bool

        init(_ mood: ChatCharacterMood, intensity: Int = 1, acceptsObject: Bool = false) {
            self.mood = mood
            self.intensity = intensity
            self.acceptsObject = acceptsObject
        }
    }

    private struct Lexicon {
        let terms: [String: Word]
        let prefix: Pattern

        init(_ groups: [(Word, String)], wordBoundary: Bool = true) {
            terms = Dictionary(uniqueKeysWithValues: groups.flatMap { term, words in
                words.split(separator: "|").map { (String($0), term) }
            })
            let alternatives = terms.keys.sorted { $0.count > $1.count }
                .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            prefix = Pattern("^(?:\(alternatives))" + (wordBoundary ? #"\b"# : ""))
        }

        func read(_ body: String) -> (String, Word, String)? {
            guard let word = prefix.firstMatch(in: body), let term = terms[word] else { return nil }
            let tail = body.dropFirst(word.count).trimmingCharacters(in: .whitespaces)
            return (word, term, tail)
        }
    }

    private static let englishFeelings = Lexicon([
        (Word(.happy), "happy|glad|joyful|cheerful|pleased"),
        (Word(.happy, intensity: 3), "overjoyed|elated|ecstatic|delighted"),
        (Word(.amused), "amused|tickled pink"),
        (Word(.relieved), "relieved"),
        (Word(.hope), "hopeful|optimistic"),
        (Word(.excited), "excited|buzzing"),
        (Word(.excited, intensity: 3), "thrilled"),
        (Word(.proud), "proud"),
        (Word(.touched), "touched|moved"),
        (Word(.grateful), "grateful|thankful|appreciative"),
        (Word(.expecting, acceptsObject: true), "looking forward to|eagerly awaiting"),
        (Word(.curious), "curious|intrigued"),
        (Word(.hesitant), "hesitant|torn|unsure"),
        (Word(.worried), "worried|anxious|concerned|uneasy"),
        (Word(.nervous), "nervous|jittery|tense|on edge"),
        (Word(.low), "down|low|blue|downhearted|deflated"),
        (Word(.sad), "sad|sorrowful|unhappy|heartbroken"),
        (Word(.sad, intensity: 3), "devastated|miserable"),
        (Word(.grief), "in mourning|grief-stricken"),
        (Word(.grief, acceptsObject: true), "grieving|mourning"),
        (Word(.disappointed), "disappointed|let down|disheartened"),
        (Word(.lonely), "lonely|lonesome"),
        (Word(.missing), "homesick"),
        (Word(.irritated), "irritated|annoyed|irritable|peeved"),
        (Word(.angry), "angry|mad|cross"),
        (Word(.angry, intensity: 3), "furious|livid|enraged"),
        (Word(.frustrated), "frustrated|exasperated|fed up"),
        (Word(.disgust), "disgusted|repulsed|grossed out"),
        (Word(.fear), "scared|afraid|frightened"),
        (Word(.fear, intensity: 3), "terrified|petrified"),
        (Word(.panicked, intensity: 3), "panicked|panicking|in a panic"),
        (Word(.startled), "startled|spooked"),
        (Word(.surprise), "surprised|astonished|taken aback|stunned|shocked"),
        (Word(.confused), "confused|bewildered|puzzled|perplexed|baffled"),
        (Word(.distracted), "distracted|preoccupied|absent-minded"),
        (Word(.shy), "shy"),
        (Word(.embarrassed), "embarrassed|self-conscious"),
        (Word(.embarrassed, intensity: 3), "mortified|humiliated"),
        (Word(.ashamed), "ashamed|full of shame"),
        (Word(.guilt), "guilty|remorseful"),
        (Word(.hurt), "emotionally hurt|hurt"),
        (Word(.jealous), "jealous|envious"),
        (Word(.tired), "tired|weary|worn out|drained|sleepy"),
        (Word(.tired, intensity: 3), "exhausted|shattered"),
        (Word(.bored), "bored"),
        (Word(.numb), "emotionally numb"),
        (Word(.calm), "calm|at peace|peaceful|serene"),
        (Word(.relaxed), "relaxed|at ease"),
    ])

    private static let englishVerbs = Lexicon([
        (Word(.hope, acceptsObject: true), "hope"),
        (Word(.excited, acceptsObject: true), "can't wait to|can't wait for|cannot wait to|cannot wait for"),
        (Word(.missing, acceptsObject: true), "miss"),
        (Word(.grief, acceptsObject: true), "mourn|grieve"),
    ])

    private static let chineseFeelings = Lexicon([
        (Word(.happy), "开心|高兴|快乐|欢喜|喜悦|欣喜"),
        (Word(.amused), "好笑|好玩|乐了"),
        (Word(.relieved), "松了一口气|松了口气|松一口气|松口气|轻松多了|如释重负|安心|放心"),
        (Word(.relieved, acceptsObject: true), "庆幸"),
        (Word(.hope), "心怀希望|充满希望|有了希望|有盼头|乐观"),
        (Word(.hope, acceptsObject: true), "希望|抱有希望"),
        (Word(.excited), "兴奋|激动|雀跃"),
        (Word(.excited, acceptsObject: true), "迫不及待"),
        (Word(.proud), "自豪|骄傲"),
        (Word(.touched), "感动|触动"),
        (Word(.grateful, acceptsObject: true), "感激"),
        (Word(.expecting, acceptsObject: true), "期待|期盼|盼望|盼着"),
        (Word(.curious, acceptsObject: true), "好奇"),
        (Word(.hesitant), "犹豫|纠结|拿不定主意"),
        (Word(.worried, acceptsObject: true), "担心|担忧|忧虑"),
        (Word(.worried), "焦虑|不安"),
        (Word(.nervous), "紧张|忐忑|七上八下"),
        (Word(.low), "低落|消沉|提不起精神"),
        (Word(.sad), "难过|伤心|悲伤|心酸|不好受"),
        (Word(.grief, acceptsObject: true), "哀悼|悼念"),
        (Word(.grief), "悲痛|哀痛|悲恸"),
        (Word(.disappointed), "失望|失落"),
        (Word(.lonely), "孤独|孤单|寂寞"),
        (Word(.missing, acceptsObject: true), "想念|思念|怀念"),
        (Word(.missing), "想家|想你|想他|想她"),
        (Word(.irritated), "烦躁|烦|心烦|恼火|不耐烦"),
        (Word(.angry), "生气|愤怒|气愤|火大|气"),
        (Word(.angry, intensity: 3), "气炸了|气坏了|气死了"),
        (Word(.frustrated), "沮丧|挫败|受挫|恼丧"),
        (Word(.disgust), "反感|厌恶|嫌恶"),
        (Word(.fear, acceptsObject: true), "害怕|恐惧"),
        (Word(.fear, intensity: 3), "怕极了|吓坏了"),
        (Word(.panicked, intensity: 3), "惊慌|慌张|慌乱|惊恐|慌"),
        (Word(.startled), "吓了一跳|吓一跳|被吓到了"),
        (Word(.surprise), "惊讶|吃惊|意外|震惊|惊呆了"),
        (Word(.confused), "困惑|迷惑|疑惑|糊涂|一头雾水|不知所措"),
        (Word(.distracted), "心不在焉|走神|分心"),
        (Word(.shy), "害羞|羞涩"),
        (Word(.embarrassed), "尴尬|窘迫|难为情|难堪"),
        (Word(.ashamed), "羞愧|羞耻|惭愧"),
        (Word(.guilt), "内疚|愧疚|自责"),
        (Word(.hurt), "受伤|心痛|不是滋味|委屈"),
        (Word(.jealous), "嫉妒|妒忌|吃醋|眼红"),
        (Word(.tired), "累|疲惫|疲倦|困倦|困"),
        (Word(.tired, intensity: 3), "累坏了|累死了|筋疲力尽|精疲力尽"),
        (Word(.bored), "无聊|厌烦|百无聊赖"),
        (Word(.numb), "麻木|心如死灰"),
        (Word(.calm), "平静|安宁|安稳|平和|淡定|心安"),
        (Word(.relaxed), "放松|自在|松弛"),
    ], wordBoundary: false)

    private static let sentenceEnding = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ".!?。！？"))
    private static let sentences = Pattern(#"[^.!?。！？\r\n]+[.!?。！？]*"#)
    private static let quotedText = Pattern(alternatives: [
        #"(?m:^[\t ]*>[^\r\n]*)"#,
        #"(?s:(`+).*?(?:\1|\z))"#,
        #"“[^”]*(?:”|\z)|「[^」]*(?:」|\z)|『[^』]*(?:』|\z)|«[^»]*(?:»|\z)|"[^"]*(?:"|\z)"#,
        #"‘(?:[^’]|’(?=[\p{L}\p{N}]))*(?:’|\z)"#,
        #"(?<![\p{L}\p{N}])'(?=\S)(?:[^']|'(?=[\p{L}\p{N}]))*(?:'|\z)"#,
    ])
    private static let instruction = Pattern(alternatives: [
        #"(?m:^[\t ]*(?:\[/?(?:system|assistant|user)\]|</?(?:system|assistant|user)>|(?:system|assistant|user)\s*:))"#,
        #"\b(?:repeat after me|ignore (?:the |all )?(?:previous|prior|above) instructions?|system prompt)\b"#,
        #"\breturn (?:only )?(?:the )?(?:mood|emotion) (?:as|json)\b"#,
        #"忽略.{0,12}(?:指令|提示词)|请照着说|只输出.{0,8}(?:情绪|心情)"#,
    ])
    private static let retraction = Pattern(#"\b(?:just kidding|only kidding|i'm joking|just a joke|yeah right)\b|(?:开玩笑的|开个玩笑|才怪)"#)
    private static let unassertedContext = Pattern(alternatives: [
        #"\b(?:if|unless|hypothetically)\b|要是|如果|假如|假设|的话|或者说|也许"#,
        #"^\s*(?:yesterday|last night|last week|back then|at the time|for example)\b"#,
        #"^\s*(?:那时|当时|昨天|昨晚|以前|刚才|举个例子|比如说)"#,
        #"\b(?:in (?:my|the) (?:old )?(?:diary|journal|script|example|story)|just an example)\b"#,
        #"\b(?:say|says|said|write|wrote|tell|told|type|typed|reply|replied|pretend|pretended|quote|quoted)\s*[:,]"#,
        #",\s*(?:(?:[\p{L}]+)\s+)?(?:says|said|replied|wrote|joked|pretended|asked|whispered|typed|quoted)\b"#,
        #"(?:(?:她|他|你|我|角色)说)[，,:：]|[，,](?:她|他|你|我)说"#,
        #",\s*(?:or|maybe|perhaps|i guess)\b|\b(?:by nature|in general|as a person)\b|🙄|🙃"#,
    ])
    private static let englishOpening = Pattern(#"^(?:(?:honestly|to be honest|oh|hey|well|yeah|mate|right now|today),\s*)+"#)
    private static let englishSeparator = Pattern(#"\s*,\s*(?:(?:and|but|yet)\s+)?|\s+(?:and|but|yet)\s+"#)
    private static let englishSelf = Pattern(#"^i(?:(?:'m| am)(?: +feeling)?| +(?:(?:really|still|actually) +)?feel) +"#)
    private static let englishSubject = Pattern(#"^i +"#)
    private static let englishAside = Pattern(#"^(?:now|right now|today|lately|too|actually|honestly|mate|at the moment|these days)$"#)
    private static let englishReason = Pattern(#"^(?:about|of|for|in|by|with|at|that|to|from|over|because|after|around|here|today|now|this|it|you|we|they|he|she)\b"#)
    private static let englishNegatedTail = Pattern(#"^(?:not|never|nothing|no one|in theory)\b"#)
    private static let englishPoliteOffer = Pattern(#"^to (?:help|assist|explain|answer|provide|share|welcome|clarify|show you|tell you|meet you|hear from you)\b"#)
    private static let englishCurrentTime = Pattern(#"\b(?:now|today|at the moment)\b"#)
    private static let englishFeelingVerb = Pattern(#"^i(?: +(?:(?:really|still|actually) +)?feel |(?:'m| am) +feeling )"#)
    private static let englishEmotionalContext = Pattern(#"^(?:about|by (?:what|your|his|her|their)|because)\b"#)
    private static let knownObjectOfMissing = Pattern(#"^(?:you|him|her|them|home|being|seeing|having|talking|going|the way|my (?:family|home|mum|mom|dad|parents|mother|father|brother|sister|friends?|kids?|children|partner|wife|husband|dog|cat))\b"#)

    private static let chineseOpening = Pattern(#"^(?:(?:好吧|嗯|其实|说实话|说真的|老实说|现在|今天|此刻)[,，]\s*)+"#)
    private static let chineseSeparator = Pattern(#"\s*[,，、]\s*(?:但(?:是)?|却|而且|并且|同时)?\s*|但是|而且|并且|同时|却|(?<!我)又"#)
    private static let chineseSelf = Pattern(#"^我(?:(?:为|在)(?:(?!不|没|曾|会|想|该|说|觉得|感到)[^，。！？]){1,18}(?:感到|觉得))?"#)
    private static let chineseSharedFeeling = Pattern(#"^(?:为|替)(?:你们|你俩|大家|你|他|她)(?=开心|高兴|难过|担心|伤心|骄傲|自豪)"#)
    private static let chineseAside = Pattern(#"^(?:的|了|呀|啊|啦|呢|哦|哎|唉|哟|哈|嘛|诶|欸|现在|今天|此刻)+$"#)
    private static let chineseReason = Pattern(#"^(?:是因为|因为|为了|见到|看到|听到|遇到|知道|收到|想到|这么|怎么也)"#)
    private static let chineseAttribution = Pattern(#"^(?:的|地|得|不|没|吗|么|吧|[：:])"#)
    private static let chineseEmotionalContext = Pattern(#"心里|心底|情绪上"#)
    private static let chineseAmused = Pattern(#"^被.{1,18}逗笑(?:了|啦|呀|啊)?$"#)
    private static let chineseStartled = Pattern(#"^被.{1,18}吓了?一跳(?:了|啦|呀|啊)?$"#)

    private static func trimClause(_ clause: String) -> String {
        var text = clause.trimmingCharacters(in: .whitespaces)
        while let last = text.last, last.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) {
            text = text.dropLast().trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private struct Pattern: Sendable {
        private let expression: NSRegularExpression

        init(_ source: String) {
            do {
                expression = try NSRegularExpression(pattern: source)
            } catch {
                preconditionFailure("Invalid chat mood pattern: \(source)")
            }
        }

        init(alternatives: [String]) {
            self.init(alternatives.joined(separator: "|"))
        }

        func hasMatch(in text: String) -> Bool {
            firstMatch(in: text) != nil
        }

        func firstMatch(in text: String) -> String? {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = expression.firstMatch(in: text, range: range),
                  let matchedRange = Range(match.range, in: text) else { return nil }
            return String(text[matchedRange])
        }

        func removingPrefix(from text: String) -> String? {
            firstMatch(in: text).map { String(text.dropFirst($0.count)) }
        }

        func matches(in text: String) -> [String] {
            let range = NSRange(text.startIndex..., in: text)
            return expression.matches(in: text, range: range).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]) }
            }
        }

        func replacingMatches(in text: String, withTemplate template: String) -> String {
            expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }

        func separate(_ text: String) -> [String] {
            var parts: [String] = []
            var start = text.startIndex
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                parts.append(String(text[start..<range.lowerBound]))
                start = range.upperBound
            }
            parts.append(String(text[start...]))
            return parts
        }
    }
}
