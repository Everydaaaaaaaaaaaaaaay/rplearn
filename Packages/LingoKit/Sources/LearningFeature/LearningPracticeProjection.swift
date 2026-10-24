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
            if kind != .reading && !(1...group.count).allSatisfy({ text.contains("____\($0)____") }) { return nil }
            let paragraphs = text.components(separatedBy: "\n\n")
            let title = paragraphs.first.map { $0.count < 110 && !$0.contains("____") ? $0 : unit.originalGroup!.label } ?? unit.title
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
    private static func withoutLetter(_ value: String) -> String {
        value.replacingOccurrences(of: #"^[A-G][.．]\s*"#, with: "", options: .regularExpression)
    }
}
