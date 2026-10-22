import BackendKit
import Foundation

/// A display projection only: answer identities, source material and grading stay intact.
struct LearningReadingPlan: Equatable {
    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        let text: String
        let questionIDs: [String]
    }
    let originalText: String
    let introduction: String
    let sections: [Section]
    let preferredSectionID: String?
    let optionLabels: [String: String]
    let usesPane: Bool

    init(unit: LearningUnit, question: LearningQuestion) {
        originalText = question.material ?? ""
        let names = Self.compactLabels(unit: unit, question: question)
        // Remove a repeated trailing bank only from the reading preview. Sentence
        // answers stay complete on their cards; paragraph candidates get their
        // own reading tabs below. The full original is always available.
        let reading = names.isEmpty
            ? Self.withoutRepeatedBank(originalText, options: question.options ?? [])
            : originalText
        let parsed = Self.split(reading, questions: unit.questions)
        introduction = parsed.introduction
        if unit.originalGroup?.family == "paragraph_gap_insertion", reading != originalText,
           let options = question.options {
            // The answer is a whole paragraph. Read every candidate in its own
            // tab, then choose its identity; never abbreviate the paragraph itself.
            sections = [Section(id: "whole", title: "正文", text: reading, questionIDs: unit.questions.map(\.id))]
                + options.map { option in
                    let parts = option.text.components(separatedBy: ". ")
                    return Section(id: "candidate.\(option.id)", title: "段落 \(parts[0])",
                        text: String(option.text.dropFirst(parts[0].count + 2)), questionIDs: [])
                }
            optionLabels = Dictionary(uniqueKeysWithValues: options.map { option in
                (option.id, "段落 \(option.text.components(separatedBy: ". ")[0])")
            })
        } else {
            sections = parsed.sections
            optionLabels = names
        }
        preferredSectionID = sections.first { $0.questionIDs.contains(question.id) }?.id
        usesPane = !originalText.isEmpty && (originalText.count > 240 || sections.count > 1 || (question.materialImages?.count ?? 0) > 1)
    }

    func progress(questionID: String) -> String? {
        guard let section = sections.first(where: { $0.questionIDs.contains(questionID) }),
              let index = section.questionIDs.firstIndex(of: questionID), section.questionIDs.count > 1 else { return nil }
        return "本篇第 \(index + 1) / \(section.questionIDs.count) 题"
    }

    private static func captures(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: value).map { String(value[$0]) } ?? ""
        }
    }

    private static func split(_ text: String, questions: [LearningQuestion]) -> (introduction: String, sections: [Section]) {
        struct Heading {
            let line: Int
            let id: String
            let title: String
            let questionIDs: [String]
        }
        let lines = text.components(separatedBy: "\n")
        var headings: [Heading] = []
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Only explicit source boundaries; do not split ordinary paragraphs,
            // dialogue turns, A1 subcards or answer sentences into new articles.
            if let match = captures(#"^([A-Z])组[（(]第([0-9]+)[—–−-]([0-9]+)题[）)]$"#, in: line),
               let first = Int(match[2]), let last = Int(match[3]), first > 0, last >= first, last <= questions.count {
                headings.append(Heading(line: index, id: match[1], title: line,
                    questionIDs: Array(questions[(first - 1)..<last]).map(\.id)))
            } else if let match = captures(#"^(Passage|Text) ([0-9]+)$"#, in: line) {
                let prefix = match[0]
                headings.append(Heading(line: index, id: prefix, title: prefix,
                    questionIDs: questions.filter { q in
                        q.prompt.hasPrefix(prefix + " —") || q.prompt.hasPrefix(prefix + " ·") || q.prompt.hasPrefix(prefix + ":")
                    }.map(\.id)))
            } else if let match = captures(#"^([A-Z]) [—·] (.{1,80})$"#, in: line) {
                headings.append(Heading(line: index, id: match[1], title: line, questionIDs: []))
            }
        }
        guard !headings.isEmpty, Set(headings.map(\.id)).count == headings.count else {
            return ("", text.isEmpty ? [] : [Section(id: "whole", title: "阅读材料", text: text, questionIDs: questions.map(\.id))])
        }
        let intro = lines[..<headings[0].line].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = headings.enumerated().map { index, heading in
            let end = index + 1 < headings.count ? headings[index + 1].line : lines.count
            let body = lines[(heading.line + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return Section(id: heading.id, title: heading.title, text: body,
                questionIDs: headings.count == 1 ? questions.map(\.id) : heading.questionIDs)
        }
        return (intro, sections)
    }

    private static func compactLabels(unit: LearningUnit, question: LearningQuestion) -> [String: String] {
        guard unit.originalGroup?.family == "reading_choice", let options = question.options,
              options.count >= 3, options.allSatisfy({ $0.imageAssetId == nil }),
              // Only a repeated named candidate set with its complete descriptions
              // already present verbatim. Ordinary comprehension answers stay whole.
              unit.questions.filter({ $0.options == options }).count > 1,
              options.allSatisfy({ (question.material ?? "").contains($0.text) }) else { return [:] }
        var result: [String: String] = [:]
        for option in options {
            if option.text.count < 60 { return [:] }
            let named = captures(#"^([A-Z]\. [A-Z][A-Za-z'’ -]{1,60}): "#, in: option.text)
                ?? captures(#"^([A-Z]\. [A-Z][A-Za-z'’-]*(?: [A-Z][A-Za-z'’-]*){0,5}) (?:offers|gives|contains|helps|provides|arranges|has|checks|lets|looks|runs|meets|starts)\b"#, in: option.text)
            guard let label = named?[1] else { return [:] }
            result[option.id] = label
        }
        return result
    }

    private static func withoutRepeatedBank(_ text: String, options: [LearningOption]) -> String {
        guard options.count >= 3 else { return text }
        var cursor = text.startIndex
        var start: String.Index?
        for option in options {
            guard let match = captures(#"^([A-Z])\. (.+)$"#, in: option.text) else { return text }
            let variants = [option.text, match[1] + "\n\n" + match[2]]
            let ranges = variants.compactMap { text.range(of: $0, range: cursor..<text.endIndex) }
            guard let range = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else { return text }
            if start == nil { start = range.lowerBound }
            else if !text[cursor..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            cursor = range.upperBound
        }
        guard let start, !text[..<start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text[cursor...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return text[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
