import BackendKit
import Foundation
import Observation

// Shared presentation state for the real practice flow and its isolated offline fixtures.
struct LearningPracticeTask: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let headline: String
    let detail: String
    let minutes: Int
    let sections: [LearningPracticeSection]
    var count: Int { sections.reduce(0) { $0 + $1.questions.count } }
}

struct LearningPracticeSection: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case reading, cloze, insertion, grammar }
    let id: String
    let kind: Kind
    let title: String
    let text: String
    let instruction: String
    let questions: [LearningPracticeQuestion]
    var paragraphs: [String] { text.components(separatedBy: "\n\n") }
}

struct LearningPracticeQuestion: Codable, Identifiable, Sendable {
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

struct LearningPracticeDraft: Codable {
    var sectionIndex = 0
    var questionIndex = 0
    var answers: [String: String] = [:]
    var flagged: Set<String> = []
    var reviewed: Set<String> = []
    var offsets: [String: Double] = [:]
    var isReviewing = false
    var started = false
    var completed = false
    var pendingCommand: LearningAnswerCommand?
    var finishRequestID: UUID?
    var awardedPoints: [String: Int]?
}

@MainActor @Observable
final class LearningPracticeModel {
    enum Page { case cover, work, summary }
    enum Result { case correct, incorrect, needsReview }
    let tasks: [LearningPracticeTask]
    var taskIndex = 0
    var draft: LearningPracticeDraft
    var page: Page = .cover
    var returningToSummary = false
    var isBusy = false
    var error: String?
    private(set) var currentAttempt: LearningAttempt?
    @ObservationIgnored private var backend: (any LearningServing)?
    @ObservationIgnored private var afterFinish: @Sendable () async -> Void = {}
    @ObservationIgnored private var optionIDs: [String: [String: String]] = [:]
    var isProduction: Bool { backend != nil }
    var hasUnconfirmedAnswer: Bool { draft.pendingCommand != nil }
    var questionCount: Int { currentAttempt?.round.questionIds.count ?? task.count }
    func isRequired(_ question: LearningPracticeQuestion) -> Bool { currentAttempt?.round.questionIds.contains(question.id) ?? true }
    func isLocked(_ question: LearningPracticeQuestion) -> Bool {
        !isRequired(question) || currentAttempt?.round.answers.contains(where: { $0.questionId == question.id }) == true
    }
    private let defaults: UserDefaults
    private let namespace: String
    @ObservationIgnored private var readingOffsets: [String: Double] = [:]
    var task: LearningPracticeTask { tasks[taskIndex] }
    var section: LearningPracticeSection { task.sections[draft.sectionIndex] }
    var question: LearningPracticeQuestion { section.questions[draft.questionIndex] }
    var answeredCount: Int { section.questions.filter { isRequired($0) && !answer(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    var isSevenOfFive: Bool { section.kind == .insertion && section.questions.count == 5 && question.options.count == 7 }
    var sectionQuestionCount: Int { section.questions.filter(isRequired).count }
    var canReview: Bool { sectionQuestionCount > 0 && answeredCount == sectionQuestionCount }
    var correctCount: Int { task.sections.flatMap(\.questions).filter { isRequired($0) && result(for: $0) == .correct }.count }
    var earnedPoints: Int {
        currentAttempt?.round.answers.reduce(0) { $0 + ($1.awardedPoints ?? draft.awardedPoints?[$1.questionId] ?? 0) } ?? 0
    }
    var needsReviewCount: Int { task.sections.flatMap(\.questions).filter { result(for: $0) == .needsReview }.count }
    var flaggedCount: Int { draft.flagged.count }
    var hasProgress: Bool { draft.started }
    var totalAnswered: Int { task.sections.flatMap(\.questions).filter { isRequired($0) && !answer(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }

    init(tasks: [LearningPracticeTask],
         defaults: UserDefaults = .standard, namespace: String = "practice.preview.v1") {
        precondition(!tasks.isEmpty && tasks.allSatisfy { !$0.sections.isEmpty && $0.sections.allSatisfy { !$0.questions.isEmpty } })
        self.tasks = tasks; self.defaults = defaults; self.namespace = namespace
        self.draft = Self.read(tasks[0], defaults: defaults, namespace: namespace)
    }
    convenience init?(attempt: LearningAttempt, service: any LearningServing,
                      defaults: UserDefaults = .standard,
                      afterFinish: @escaping @Sendable () async -> Void = {}) {
        guard let projection = LearningPracticeProjection(unit: attempt.unit) else { return nil }
        self.init(tasks: [projection.task], defaults: defaults,
                  namespace: "learning.practice.v1.\(attempt.characterId).\(attempt.id).\(attempt.round.id)")
        self.backend = service; self.currentAttempt = attempt
        self.optionIDs = projection.optionIDs; self.afterFinish = afterFinish
        reconcile(attempt)
    }
    private func reconcile(_ attempt: LearningAttempt) {
        currentAttempt = attempt
        for submission in attempt.round.answers {
            if let option = submission.answer.optionId {
                draft.answers[submission.questionId] = optionIDs[submission.questionId]?.first(where: { $0.value == option })?.key
            } else if let text = submission.answer.text { draft.answers[submission.questionId] = text }
        }
        if let pending = draft.pendingCommand, attempt.round.id == pending.roundId,
           attempt.round.answers.contains(where: { $0.questionId == pending.questionId }) { draft.pendingCommand = nil }
        if !attempt.round.answers.isEmpty { draft.started = true }
        if attempt.round.completed { draft.completed = true }
        if let first = task.sections.firstIndex(where: { $0.questions.contains(where: isRequired) }),
           !section.questions.contains(where: isRequired) { draft.sectionIndex = first; draft.questionIndex = 0 }
        if !isRequired(question), let first = section.questions.firstIndex(where: isRequired) { draft.questionIndex = first }
        let required = section.questions.filter(isRequired)
        if !required.isEmpty && required.allSatisfy({ q in attempt.round.answers.contains(where: { $0.questionId == q.id }) }) {
            draft.reviewed.insert(section.id); draft.isReviewing = true
        }
        save()
    }
    private static func read(_ task: LearningPracticeTask, defaults: UserDefaults, namespace: String) -> LearningPracticeDraft {
        guard let data = defaults.data(forKey: "\(namespace).\(task.id)"),
              var value = try? JSONDecoder().decode(LearningPracticeDraft.self, from: data),
              task.sections.indices.contains(value.sectionIndex),
              task.sections[value.sectionIndex].questions.indices.contains(value.questionIndex)
        else { return LearningPracticeDraft() }
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
    func answer(for question: LearningPracticeQuestion) -> String { draft.answers[question.id] ?? "" }
    func selectQuestion(_ index: Int) {
        guard section.questions.indices.contains(index) else { return }
        draft.questionIndex = index; save()
    }
    func setAnswer(_ value: String) {
        guard !isBusy, !hasUnconfirmedAnswer, !isLocked(question), !draft.isReviewing && !draft.reviewed.contains(section.id) else { return }
        if section.kind == .insertion, !value.isEmpty {
            guard !section.questions.contains(where: { $0.id != question.id && isLocked($0) && draft.answers[$0.id] == value }) else { return }
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
    func submitSection() async {
        guard !isBusy, canReview else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        if let backend {
            do {
                for question in section.questions where isRequired(question) {
                    guard let attempt = currentAttempt else { return }
                    if attempt.round.answers.contains(where: { $0.questionId == question.id }) { continue }
                    if draft.pendingCommand == nil {
                        let value = answer(for: question)
                        let answer: LearningAnswer
                        if let option = optionIDs[question.id]?[value] { answer = .choice(option) }
                        else { answer = .text(value) }
                        draft.pendingCommand = .init(requestId: UUID(), attempt: attempt, questionId: question.id, answer: answer)
                        save()
                    }
                    guard let command = draft.pendingCommand, command.questionId == question.id else {
                        error = "还有一份提交等待确认，请先重试。"; return
                    }
                    let receipt = try await backend.answerLearning(attempt.id, command: command)
                    currentAttempt = receipt.attempt
                    if draft.awardedPoints == nil { draft.awardedPoints = [:] }
                    draft.awardedPoints?[question.id] = receipt.awardedPoints
                    draft.pendingCommand = nil; save()
                }
            } catch {
                if case BackendClientError.api(let code, let message, _, _) = error {
                    if code == "LEARNING_ANSWER_REVIEW_REQUIRED" {
                        if let id = draft.pendingCommand?.questionId,
                           let index = section.questions.firstIndex(where: { $0.id == id }) { draft.questionIndex = index }
                        draft.pendingCommand = nil; save()
                    }
                    if ["LEARNING_REVISION_CONFLICT", "LEARNING_ALREADY_ANSWERED"].contains(code),
                       let attempt = currentAttempt,
                       let fresh = try? await backend.learningAttempt(attempt.id), fresh.round.id == attempt.round.id {
                        // These explicit rejections did not commit this command. Rebase remaining answers on server state.
                        draft.pendingCommand = nil; reconcile(fresh)
                    }
                    self.error = message
                } else { self.error = "提交尚未全部确认。重试会继续核对同一份答案，不会重复计分。\n\(error.localizedDescription)" }
                return
            }
        }
        draft.isReviewing = true; draft.reviewed.insert(section.id)
        draft.questionIndex = section.questions.firstIndex(where: isRequired) ?? 0; save()
    }
    func recover() async {
        guard !isBusy, let backend, let attempt = currentAttempt else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let fresh = try await backend.learningAttempt(attempt.id)
            guard fresh.round.id == attempt.round.id else { error = "作答轮已更新，请退出后重新进入。"; return }
            reconcile(fresh); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func finishReview() async {
        guard !isBusy, draft.isReviewing else { return }
        if returningToSummary { page = .summary; returningToSummary = false }
        else if let next = task.sections.indices.first(where: { $0 > draft.sectionIndex && task.sections[$0].questions.contains(where: isRequired) }) {
            draft.sectionIndex = next; draft.questionIndex = section.questions.firstIndex(where: isRequired) ?? 0
            let alreadySubmitted = section.questions.filter(isRequired).allSatisfy { q in
                currentAttempt?.round.answers.contains(where: { $0.questionId == q.id }) == true
            }
            draft.isReviewing = alreadySubmitted
            if alreadySubmitted { draft.reviewed.insert(section.id) }
        } else {
            isBusy = true; error = nil
            defer { isBusy = false }
            if let backend, let attempt = currentAttempt {
                if attempt.firstCompletedAt == nil {
                    if draft.finishRequestID == nil { draft.finishRequestID = UUID(); save() }
                    do { currentAttempt = try await backend.finishLearning(attempt, requestID: draft.finishRequestID!, skipRemaining: false) }
                    catch { await afterFinish(); self.error = error.localizedDescription; return }
                }
                await afterFinish()
            }
            draft.completed = true; page = .summary
        }
        save()
    }
    func revisit(section index: Int, question: Int) {
        guard task.sections.indices.contains(index), task.sections[index].questions.indices.contains(question) else { return }
        draft.sectionIndex = index; draft.questionIndex = question; draft.isReviewing = true
        returningToSummary = true; page = .work; save()
    }
    func result(for question: LearningPracticeQuestion) -> Result? {
        guard let owner = task.sections.first(where: { $0.questions.contains(where: { $0.id == question.id }) }),
              draft.reviewed.contains(owner.id) else { return nil }
        if isProduction {
            guard let grade = grade(for: question) else { return nil }
            return grade.outcome == .correct ? .correct : .incorrect
        }
        let response = normalized(answer(for: question))
        if let option = question.correctOption { return response == normalized(option) ? .correct : .incorrect }
        if question.acceptedAnswers.map(normalized).contains(response) { return .correct }
        return question.rejectedAnswers.map(normalized).contains(response) ? .incorrect : .needsReview
    }
    func answerLabel(_ question: LearningPracticeQuestion) -> String {
        let response = answer(for: question)
        return question.options.first(where: { $0.id == response }).map { "\($0.id). \($0.text)" } ?? response
    }
    func grade(for question: LearningPracticeQuestion) -> LearningGrade? {
        guard draft.reviewed.contains(task.sections.first(where: { $0.questions.contains(where: { $0.id == question.id }) })?.id ?? "") else { return nil }
        return currentAttempt?.round.answers.first(where: { $0.questionId == question.id })?.result
    }
    func explanation(for question: LearningPracticeQuestion) -> String { grade(for: question)?.explanation ?? question.explanation }
    func referenceLabel(_ question: LearningPracticeQuestion) -> String {
        let content = referenceContent(question)
        if let option = content.option { return "\(option). \(content.text)" }
        return content.text
    }
    func referenceContent(_ question: LearningPracticeQuestion) -> (option: String?, text: String) {
        if isProduction, let solution = grade(for: question)?.solution {
            if let option = solution.optionId, let letter = optionIDs[question.id]?.first(where: { $0.value == option })?.key,
               let display = question.options.first(where: { $0.id == letter }) { return (letter, display.text) }
            return (nil, solution.text ?? "")
        }
        if let option = question.options.first(where: { $0.id == question.correctOption }) { return (option.id, option.text) }
        return (nil, question.acceptedAnswers.joined(separator: " / "))
    }
    func reviewSentence(for question: LearningPracticeQuestion, in section: LearningPracticeSection) -> String? {
        guard section.kind != .reading, let index = section.questions.firstIndex(where: { $0.id == question.id }) else { return nil }
        return PracticePassageText.sentence(in: section.text, containingGap: index + 1)
    }
    private func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

extension LearningPracticeTask {
    var kindTitle: String {
        var titles: [String] = []
        for section in sections {
            let title = switch section.kind {
            case .reading: "阅读理解"
            case .cloze: "完形填空"
            case .grammar: "语法填空"
            case .insertion: section.questions.count == 5 && section.questions.first?.options.count == 7 ? "七选五" : "选句填空"
            }
            if !titles.contains(title) { titles.append(title) }
        }
        return titles.joined(separator: " · ")
    }
}

extension LearningUnit {
    var practiceKindTitle: String {
        var titles: [String] = []
        for question in questions {
            let title = switch question.type {
            case .choice: "选择题"
            case .listeningChoice, .audioChoice: "听力选择"
            case .arrange: "语句排序"
            case .audioArrange: "听力排序"
            case .completion: "填空题"
            case .dictation: "听写"
            case .listeningCompletion: "听力填空"
            case .matching: "配对题"
            case .audioMatching: "听力配对"
            case .cloze: "选词填空"
            }
            if !titles.contains(title) { titles.append(title) }
        }
        return titles.joined(separator: " · ")
    }
}
