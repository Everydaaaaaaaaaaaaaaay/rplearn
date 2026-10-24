#if DEBUG
import Foundation
import Observation

// A local interaction prototype. Its answers and progress never enter the live learning API.
struct PracticePreviewTask: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let headline: String
    let detail: String
    let minutes: Int
    let sections: [PracticePreviewSection]
    var count: Int { sections.reduce(0) { $0 + $1.questions.count } }
}

struct PracticePreviewSection: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case reading, cloze, insertion, grammar }
    let id: String
    let kind: Kind
    let title: String
    let text: String
    let instruction: String
    let questions: [PracticePreviewQuestion]
    var paragraphs: [String] { text.components(separatedBy: "\n\n") }
}

struct PracticePreviewQuestion: Codable, Identifiable, Sendable {
    struct Option: Codable, Identifiable, Sendable { let id: String; let text: String }
    let id: String
    let prompt: String
    let options: [Option]
    let correctOption: String?
    let acceptedAnswers: [String]
    let rejectedAnswers: [String]
    let explanation: String
    let evidenceParagraph: Int
}

struct PracticePreviewDraft: Codable {
    var sectionIndex = 0
    var questionIndex = 0
    var answers: [String: String] = [:]
    var flagged: Set<String> = []
    var reviewed: Set<String> = []
    var offsets: [String: Double] = [:]
    var isReviewing = false
    var started = false
    var completed = false
}

@MainActor @Observable
final class PracticePreviewModel {
    enum Page { case cover, work, summary }
    enum Result { case correct, incorrect, needsReview }
    let tasks: [PracticePreviewTask]
    var taskIndex = 0
    var draft: PracticePreviewDraft
    var page: Page = .cover
    var returningToSummary = false
    private let defaults: UserDefaults
    private let namespace: String
    @ObservationIgnored private var readingOffsets: [String: Double] = [:]
    var task: PracticePreviewTask { tasks[taskIndex] }
    var section: PracticePreviewSection { task.sections[draft.sectionIndex] }
    var question: PracticePreviewQuestion { section.questions[draft.questionIndex] }
    var answeredCount: Int { section.questions.filter { !answer(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    var canReview: Bool { answeredCount == section.questions.count }
    var correctCount: Int { task.sections.flatMap(\.questions).filter { result(for: $0) == .correct }.count }
    var needsReviewCount: Int { task.sections.flatMap(\.questions).filter { result(for: $0) == .needsReview }.count }
    var flaggedCount: Int { draft.flagged.count }
    var hasProgress: Bool { draft.started }
    var totalAnswered: Int { draft.answers.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }

    init(tasks: [PracticePreviewTask] = PracticePreviewFixtures.tasks,
         defaults: UserDefaults = .standard, namespace: String = "practice.preview.v1") {
        precondition(!tasks.isEmpty && tasks.allSatisfy { !$0.sections.isEmpty && $0.sections.allSatisfy { !$0.questions.isEmpty } })
        self.tasks = tasks; self.defaults = defaults; self.namespace = namespace
        self.draft = Self.read(tasks[0], defaults: defaults, namespace: namespace)
    }
    private static func read(_ task: PracticePreviewTask, defaults: UserDefaults, namespace: String) -> PracticePreviewDraft {
        guard let data = defaults.data(forKey: "\(namespace).\(task.id)"),
              var value = try? JSONDecoder().decode(PracticePreviewDraft.self, from: data),
              task.sections.indices.contains(value.sectionIndex),
              task.sections[value.sectionIndex].questions.indices.contains(value.questionIndex)
        else { return PracticePreviewDraft() }
        let ids = Set(task.sections.flatMap(\.questions).map(\.id))
        value.answers = value.answers.filter { ids.contains($0.key) }
        value.flagged.formIntersection(ids)
        return value
    }
    func selectTask(_ index: Int) {
        guard tasks.indices.contains(index) else { return }
        save(); taskIndex = index
        draft = Self.read(task, defaults: defaults, namespace: namespace)
        readingOffsets = [:]
        page = .cover; returningToSummary = false
    }
    func start() {
        draft.started = true; page = draft.completed ? .summary : .work; save()
    }
    func goToCover() { save(); page = .cover }
    func readingOffset(for sectionID: String) -> Double { readingOffsets[sectionID] ?? draft.offsets[sectionID] ?? 0 }
    func rememberReadingOffset(_ offset: Double, for sectionID: String) { readingOffsets[sectionID] = offset }
    func save() {
        var snapshot = draft
        snapshot.offsets.merge(readingOffsets) { _, current in current }
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "\(namespace).\(task.id)") }
    }
    func answer(for question: PracticePreviewQuestion) -> String { draft.answers[question.id] ?? "" }
    func selectQuestion(_ index: Int) {
        guard section.questions.indices.contains(index) else { return }
        draft.questionIndex = index; save()
    }
    func setAnswer(_ value: String) {
        guard !draft.isReviewing && !draft.reviewed.contains(section.id) else { return }
        if section.kind == .insertion, !value.isEmpty {
            // One sentence may occupy only one gap. Moving it clears the previous gap.
            for other in section.questions where other.id != question.id && draft.answers[other.id] == value {
                draft.answers.removeValue(forKey: other.id)
            }
        }
        draft.answers[question.id] = value; save()
    }
    func toggleFlag() {
        if draft.flagged.contains(question.id) { draft.flagged.remove(question.id) }
        else { draft.flagged.insert(question.id) }
        save()
    }
    func submitSection() {
        guard canReview else { return }
        draft.isReviewing = true; draft.reviewed.insert(section.id); draft.questionIndex = 0; save()
    }
    func finishReview() {
        guard draft.isReviewing else { return }
        if returningToSummary { page = .summary; returningToSummary = false }
        else if draft.sectionIndex + 1 < task.sections.count {
            draft.sectionIndex += 1; draft.questionIndex = 0; draft.isReviewing = false
        } else { draft.completed = true; page = .summary }
        save()
    }
    func revisit(section index: Int, question: Int) {
        guard task.sections.indices.contains(index), task.sections[index].questions.indices.contains(question) else { return }
        draft.sectionIndex = index; draft.questionIndex = question; draft.isReviewing = true
        returningToSummary = true; page = .work; save()
    }
    func result(for question: PracticePreviewQuestion) -> Result? {
        guard let owner = task.sections.first(where: { $0.questions.contains(where: { $0.id == question.id }) }),
              draft.reviewed.contains(owner.id) else { return nil }
        let response = normalized(answer(for: question))
        if let option = question.correctOption { return response == normalized(option) ? .correct : .incorrect }
        if question.acceptedAnswers.map(normalized).contains(response) { return .correct }
        return question.rejectedAnswers.map(normalized).contains(response) ? .incorrect : .needsReview
    }
    func answerLabel(_ question: PracticePreviewQuestion) -> String {
        let response = answer(for: question)
        return question.options.first(where: { $0.id == response }).map { "\($0.id). \($0.text)" } ?? response
    }
    func referenceLabel(_ question: PracticePreviewQuestion) -> String {
        question.options.first(where: { $0.id == question.correctOption }).map { "\($0.id). \($0.text)" }
            ?? question.acceptedAnswers.joined(separator: " / ")
    }
    private func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
#endif
