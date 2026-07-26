/// 词典标签的统一排序策略：考试等级由低到高，其它来源随后。
///
/// 可见数量由视图根据真实可用宽度决定，策略层不再提前截断。
enum DictTagDisplayPolicy {
    private static let orderedExamTags: [(rawValue: String, title: String)] = [
        ("zk", "中考"),
        ("gk", "高考"),
        ("cet4", "四级"),
        ("cet6", "六级"),
        ("ky", "考研"),
        ("toefl", "托福"),
        ("ielts", "雅思"),
        ("gre", "GRE"),
    ]

    static func orderedTitles(for entry: DictEntry) -> [String] {
        let rawTags = stableUnique(entry.tags)
        let rawTagSet = Set(rawTags)
        let knownRawValues = Set(orderedExamTags.map(\.rawValue))

        var titles = orderedExamTags.compactMap { tag in
            rawTagSet.contains(tag.rawValue) ? tag.title : nil
        }

        // 保留词典将来可能新增的标签，但已知考试等级始终优先。
        titles.append(contentsOf: rawTags.filter { !knownRawValues.contains($0) })

        if entry.oxford {
            titles.append("牛津3000")
        }
        if entry.collins > 0 {
            titles.append("柯林斯\(entry.collins)星")
        }

        return stableUnique(titles)
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
