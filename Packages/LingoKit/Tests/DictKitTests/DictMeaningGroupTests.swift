import DictKit
import Testing

@Suite("词性显示")
struct DictMeaningGroupTests {
    @Test("中文词性提供标准英文缩写")
    func partOfSpeechAbbreviations() {
        let expectations = [
            (prefix: "n.", label: "名词", abbreviation: "n."),
            (prefix: "v.", label: "动词", abbreviation: "v."),
            (prefix: "adj.", label: "形容词", abbreviation: "adj."),
            (prefix: "adv.", label: "副词", abbreviation: "adv."),
            (prefix: "prep.", label: "介词", abbreviation: "prep."),
            (prefix: "pron.", label: "代词", abbreviation: "pron."),
            (prefix: "conj.", label: "连词", abbreviation: "conj."),
            (prefix: "interj.", label: "感叹词", abbreviation: "interj."),
            (prefix: "aux.", label: "助动词", abbreviation: "aux."),
            (prefix: "num.", label: "数词", abbreviation: "num."),
            (prefix: "art.", label: "冠词", abbreviation: "art."),
            (prefix: "vt.", label: "及物动词", abbreviation: "vt."),
            (prefix: "vi.", label: "不及物动词", abbreviation: "vi."),
        ]

        for expectation in expectations {
            let group = DictEntry(
                word: "test",
                translation: "\(expectation.prefix) 释义"
            ).meaningGroups.first
            #expect(group?.partOfSpeech == expectation.label)
            #expect(group?.partOfSpeechAbbreviation == expectation.abbreviation)
        }
    }

    @Test("未知词性不显示臆测缩写")
    func unknownPartOfSpeechHasNoAbbreviation() {
        let unknown = DictEntry(word: "test", translation: "[短语]释义").meaningGroups.first
        let missing = DictEntry(word: "test", translation: "普通释义").meaningGroups.first

        #expect(unknown?.partOfSpeechAbbreviation == nil)
        #expect(missing?.partOfSpeechAbbreviation == nil)
    }
}
