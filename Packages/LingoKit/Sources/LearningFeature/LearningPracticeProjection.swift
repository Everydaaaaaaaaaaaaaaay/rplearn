import BackendKit
import Foundation

/// Projects public question identities into whole passages. No solutions are read or inferred.
struct LearningPracticeProjection {
    let task: LearningPracticeTask
    let optionIDs: [String: [String: String]]

    init?(unit: LearningUnit) {
        guard let family = unit.originalGroup?.family,
              !unit.questions.isEmpty,
              unit.questions.allSatisfy({ [.choice, .completion].contains($0.type) && $0.audio == nil && $0.imageAssetIDs.isEmpty }),
              ["reading_choice", "choice_cloze", "shared_insertion", "shared_insertion_passage_form", "passage_form"].contains(family)
        else { return nil }
        var sections: [LearningPracticeSection] = []
        var maps: [String: [String: String]] = [:]
        var visited = Set<String>()
        for question in unit.questions {
            let plan = LearningReadingPlan(unit: unit, question: question)
            guard let reading = plan.sections.first(where: { $0.id == plan.preferredSectionID }) ?? plan.sections.first,
                  !reading.text.isEmpty else { return nil }
            let group = unit.questions.filter { ($0.material ?? "") == (question.material ?? "") && reading.questionIDs.contains($0.id) }
            guard !group.isEmpty else { return nil }
            let key = group.map(\.id).joined(separator: "|")
            guard visited.insert(key).inserted else { continue }
            let kind: LearningPracticeSection.Kind = question.goalId.contains("shared_insertion") || family == "shared_insertion" ? .insertion
                : question.type == .completion ? .grammar : family == "choice_cloze" ? .cloze : .reading
            var text = reading.text
            // Normalize only explicit numbered blanks, preserving numbering and the source prose.
            for number in 1...group.count {
                for marker in ["[\(number)]", "(\(number)) ____", "（\(number)）____"] {
                    text = text.replacingOccurrences(of: marker, with: "____\(number)____")
                }
            }
            // Independent exam sections retain source question numbers (e.g. 36–40).
            // Only the displayed blanks become local ordinals; answer identities stay intact.
            if kind != .reading, let pattern = try? NSRegularExpression(pattern: "____([0-9]+)____") {
                let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                if matches.count == group.count {
                    let original = text as NSString
                    var rendered = ""; var cursor = 0
                    for (index, match) in matches.enumerated() {
                        rendered += original.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                        rendered += "____\(index + 1)____"
                        cursor = NSMaxRange(match.range)
                    }
                    rendered += original.substring(from: cursor)
                    text = rendered
                }
            }
            if kind != .reading && !(1...group.count).allSatisfy({ text.contains("____\($0)____") }) { return nil }
            var candidates = question.options ?? []
            if kind == .insertion {
                guard candidates.count > group.count && candidates.count <= 12 else { return nil }
                // Older public snapshots put the full sentence bank in the material.
                let raw = question.material ?? ""
                let bank = (0..<candidates.count).compactMap { index -> LearningOption? in
                    let letter = String(UnicodeScalar(65 + index)!)
                    guard let line = raw.components(separatedBy: "\n").last(where: { $0.hasPrefix(letter + ". ") }),
                          let data = try? JSONSerialization.data(withJSONObject: ["id": candidates[index].id, "text": line]),
                          let option = try? JSONDecoder().decode(LearningOption.self, from: data) else { return nil }
                    return option
                }
                if bank.count == candidates.count {
                    candidates = bank
                    if let range = text.range(of: bank[0].text), text[range.lowerBound...].contains(bank[bank.count - 1].text) {
                        text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            let presentation = Self.contentForDisplay(text, instruction: question.instruction)
            text = presentation.text
            let title = presentation.title
            var questions: [LearningPracticeQuestion] = []
            for (index, source) in group.enumerated() {
                let rawOptions = source.options ?? []
                let display = kind == .insertion ? candidates : rawOptions
                if kind == .insertion && rawOptions.map(\.id) != candidates.map(\.id) { return nil }
                let options = display.enumerated().map { offset, option in
                    LearningPracticeQuestion.Option(id: String(UnicodeScalar(65 + offset)!), text: Self.withoutLetter(option.text))
                }
                maps[source.id] = Dictionary(uniqueKeysWithValues: zip(options, rawOptions).map { ($0.0.id, $0.1.id) })
                let paragraph = text.components(separatedBy: "\n\n").firstIndex(where: { $0.contains("____\(index + 1)____") }) ?? 0
                questions.append(.init(id: source.id, prompt: source.prompt, options: options,
                                       correctOption: nil, acceptedAnswers: [], rejectedAnswers: [], explanation: "", evidenceParagraph: paragraph))
            }
            sections.append(.init(id: group[0].id + ".passage", kind: kind, title: title, text: text,
                                  instruction: question.instruction, questions: questions))
        }
        guard sections.flatMap(\.questions).map(\.id).count == unit.questions.count else { return nil }
        task = .init(id: unit.id, label: unit.originalGroup?.label ?? "练习", headline: unit.originalGroup?.label ?? unit.title,
                     detail: unit.summary, minutes: unit.estimatedMinutes, sections: sections)
        optionIDs = maps
    }
    private static func contentForDisplay(_ text: String, instruction: String) -> (title: String, text: String) {
        let paragraphs = text.components(separatedBy: "\n\n")
        guard let first = paragraphs.first?.trimmingCharacters(in: .whitespacesAndNewlines), paragraphs.count > 1 else { return ("", text) }
        let remainder = paragraphs.dropFirst().joined(separator: "\n\n")
        // Passage codes duplicate the existing section counter; they are presentation metadata, not prose.
        if first.range(of: #"(?i)^(?:[A-Z](?:[0-9]{1,2})?|(?:Passage|Text)\s*[A-Z0-9]+)$"#, options: .regularExpression) != nil
            || !LearningQuestionText.showsPrompt(first, instruction: instruction, material: nil) { return ("", remainder) }
        if first.count < 110, !first.contains("\n"), !first.contains("____"),
           !".?!。？！".contains(first.last ?? ".") { return (first, remainder) }
        return ("", text)
    }
    private static func withoutLetter(_ value: String) -> String {
        value.replacingOccurrences(of: #"^[A-G][.．]\s*"#, with: "", options: .regularExpression)
    }
}
