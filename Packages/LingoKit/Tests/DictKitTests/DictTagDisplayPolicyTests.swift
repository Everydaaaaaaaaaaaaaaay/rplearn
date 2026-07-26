import Testing
@testable import DictKit

@Suite("词典标签展示策略")
struct DictTagDisplayPolicyTests {
    @Test("返回全部标签并按考试等级由低到高排列")
    func ordersAllExamLevelsWithoutPrematureTruncation() {
        let entry = DictEntry(
            word: "example",
            collins: 4,
            oxford: true,
            tag: "gre ielts toefl ky cet6 cet4 gk zk"
        )

        #expect(
            DictTagDisplayPolicy.orderedTitles(for: entry)
                == [
                    "中考", "高考", "四级", "六级", "考研",
                    "托福", "雅思", "GRE", "牛津3000", "柯林斯4星",
                ]
        )
    }

    @Test("考试标签之后继续保留其它词典标签")
    func appendsOtherDictionaryTags() {
        let entry = DictEntry(
            word: "example",
            collins: 5,
            oxford: true,
            tag: "ky cet6"
        )

        #expect(
            DictTagDisplayPolicy.orderedTitles(for: entry)
                == ["六级", "考研", "牛津3000", "柯林斯5星"]
        )
    }

    @Test("未知标签去重并排在已知考试等级之后")
    func keepsUnknownTagsStableAndUnique() {
        let entry = DictEntry(
            word: "example",
            tag: "custom gk custom zk"
        )

        #expect(
            DictTagDisplayPolicy.orderedTitles(for: entry)
                == ["中考", "高考", "custom"]
        )
    }
}
