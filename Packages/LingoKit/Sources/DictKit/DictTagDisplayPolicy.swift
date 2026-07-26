/// 词典标签的统一展示策略：优先呈现由低到高的考试等级，并限制可见数量。
enum DictTagDisplayPolicy {
    static let maximumVisibleCount = 3

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

    static func visibleTitles(for entry: DictEntry) -> [String] {
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

        return Array(titles.prefix(maximumVisibleCount))
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
