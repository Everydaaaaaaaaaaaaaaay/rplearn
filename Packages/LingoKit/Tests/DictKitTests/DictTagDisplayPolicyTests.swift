import Testing
@testable import DictKit

@Suite("词典标签展示策略")
struct DictTagDisplayPolicyTests {
    @Test("标签过多时只展示三个最低等级考试标签")
    func limitsAndPrioritizesExamLevels() {
        let entry = DictEntry(
            word: "example",
            collins: 4,
            oxford: true,
            tag: "gre ielts toefl ky cet6 cet4 gk zk"
        )

        #expect(DictTagDisplayPolicy.maximumVisibleCount == 3)
        #expect(
            DictTagDisplayPolicy.visibleTitles(for: entry)
                == ["中考", "高考", "四级"]
        )
    }

    @Test("考试标签不足三个时再补充其它词典标签")
    func fillsRemainingSlots() {
        let entry = DictEntry(
            word: "example",
            collins: 5,
            oxford: true,
            tag: "ky cet6"
        )

        #expect(
            DictTagDisplayPolicy.visibleTitles(for: entry)
                == ["六级", "考研", "牛津3000"]
        )
    }

    @Test("未知标签去重并排在已知考试等级之后")
    func keepsUnknownTagsStableAndUnique() {
        let entry = DictEntry(
            word: "example",
            tag: "custom gk custom zk"
        )

        #expect(
            DictTagDisplayPolicy.visibleTitles(for: entry)
                == ["中考", "高考", "custom"]
        )
    }
}
