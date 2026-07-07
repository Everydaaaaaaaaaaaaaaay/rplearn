import Foundation

/// ECDICT 词条（ecdict_lite.sqlite word 表的一行）。
public struct DictEntry: Sendable, Equatable {
    /// 原始拼写（保留大小写，如 "OK"）。
    public var word: String
    public var phonetic: String?
    /// 英文释义（可能为空，体积超限时会被预处理脚本裁掉）。
    public var definition: String?
    /// 中文释义，行间以字面量 "\n" 分隔。
    public var translation: String?
    public var pos: String?
    public var collins: Int
    public var oxford: Bool
    /// 考试标签，空格分隔（zk/gk/cet4/cet6/ky/toefl/ielts/gre）。
    public var tag: String?
    public var bnc: Int
    public var frq: Int
    public var exchange: String?

    public init(
        word: String,
        phonetic: String? = nil,
        definition: String? = nil,
        translation: String? = nil,
        pos: String? = nil,
        collins: Int = 0,
        oxford: Bool = false,
        tag: String? = nil,
        bnc: Int = 0,
        frq: Int = 0,
        exchange: String? = nil
    ) {
        self.word = word
        self.phonetic = phonetic
        self.definition = definition
        self.translation = translation
        self.pos = pos
        self.collins = collins
        self.oxford = oxford
        self.tag = tag
        self.bnc = bnc
        self.frq = frq
        self.exchange = exchange
    }

    /// 释义按行拆开（数据里换行是字面量 "\n" 两个字符）。
    public var translationLines: [String] {
        guard let translation else { return [] }
        return translation
            .replacingOccurrences(of: "\\n", with: "\n")
            .split(separator: "\n")
            .map(String.init)
    }

    public var tags: [String] {
        tag?.split(separator: " ").map(String.init) ?? []
    }
}
