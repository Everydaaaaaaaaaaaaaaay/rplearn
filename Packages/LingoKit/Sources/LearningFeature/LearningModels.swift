import BackendKit
import Foundation
import Observation

@MainActor @Observable
public final class CharacterLearningModel {
    public private(set) var state: BackendLearningCharacter?
    public private(set) var journey: LearningJourney?
    public private(set) var history: [LearningHistory.Item] = []
    public private(set) var nextCursor: String?
    public private(set) var isBusy = false
    public private(set) var error: String?
    public private(set) var isPreparing = false
    public var presentedAttempt: LearningAttempt?
    public let characterID: UUID
    let service: any LearningServing
    private let cycleChanged: @Sendable () async -> Void
    private var startRequestID = UUID()

    public init(characterID: UUID, service: any LearningServing,
                cycleChanged: @escaping @Sendable () async -> Void = {}) {
        self.characterID = characterID; self.service = service
        self.cycleChanged = cycleChanged
    }
    public func load() async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            async let character = service.learningCharacter(characterID)
            async let global = service.learningJourney()
            async let page = service.learningHistory(characterID, cursor: nil)
            let values = try await (character, global, page)
            guard !Task.isCancelled else { return }
            state = values.0; journey = values.1; history = values.2.items; nextCursor = values.2.nextCursor
            isPreparing = ["pending", "running", "review"].contains(state?.generationStatus ?? "")
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    public func loadMore() async {
        guard !isBusy, let nextCursor else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let page = try await service.learningHistory(characterID, cursor: nextCursor)
            history += page.items.filter { item in !history.contains(where: { $0.id == item.id }) }
            self.nextCursor = page.nextCursor
        } catch { self.error = error.localizedDescription }
    }
    public func open(_ id: UUID? = nil) async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            if let id = id ?? state?.activeAttemptId {
                presentedAttempt = try await service.learningAttempt(id)
            } else {
                let response = try await service.startLearning(characterID, requestID: startRequestID)
                // 202 也是已完成的幂等请求；下次查询可发起新的抽取。
                startRequestID = UUID()
                isPreparing = response.status == "preparing"
                presentedAttempt = response.attempt
            }
        } catch { self.error = error.localizedDescription }
    }
    public func refreshCycle() async { await cycleChanged() }
    public func challengeClosed() async { await load() }
}

@MainActor @Observable
public final class LearningChallengeModel {
    public enum Stage: Hashable { case cover, story(Int), question(String), summary }
    public private(set) var attempt: LearningAttempt
    public private(set) var stage: Stage
    public private(set) var isBusy = false
    public private(set) var error: String?
    public private(set) var feedback: LearningGrade?
    public private(set) var awardedPoints = 0
    public private(set) var roundPoints: Int
    public private(set) var hasUnconfirmedAnswer = false
    public var choice: String?
    public var tokens: [String] = []
    public var text = ""
    public var pairs: [LearningAnswer.Pair] = []
    public var selectedLeft: String?
    let service: any LearningServing
    private var pendingAnswer: LearningAnswerCommand?
    private var finishRequestID = UUID()
    private var retryRequestID = UUID()
    private var seenBeats: Set<String> = []
    private let afterFinish: @Sendable () async -> Void

    public init(attempt: LearningAttempt, service: any LearningServing, afterFinish: @escaping @Sendable () async -> Void = {}) {
        self.attempt = attempt; self.service = service; self.afterFinish = afterFinish
        roundPoints = attempt.round.answers.filter { $0.result.outcome == .correct }.count
        if attempt.round.completed { stage = .summary }
        else if attempt.round.ordinal == 0 && attempt.round.answers.isEmpty { stage = .cover }
        else if let id = attempt.round.questionIds.first(where: { id in !attempt.round.answers.contains { $0.questionId == id } }) {
            stage = .question(id)
        } else { stage = .summary }
        // 重开已开始的挑战跳过已看开场；不会强迫重复剧情。
        if !attempt.round.answers.isEmpty || attempt.round.ordinal > 0 {
            seenBeats = Set(attempt.unit.beats.map(\.id))
        }
    }
    public var question: LearningQuestion? {
        guard case .question(let id) = stage else { return nil }
        return attempt.unit.questions.first { $0.id == id }
    }
    /// 只演绎开场；历史版本的题间镜头不再打断连续作答。
    public var openingBeatIndices: [Int] {
        attempt.unit.beats.indices.filter { attempt.unit.beats[$0].afterQuestion == 0 }
    }
    public var isLastOpeningBeat: Bool {
        guard case .story(let index) = stage else { return false }
        return openingBeatIndices.last == index
    }
    public var answer: LearningAnswer? {
        guard let question else { return nil }
        switch question.type {
        case .choice, .listeningChoice: return choice.map(LearningAnswer.choice)
        case .arrange, .audioArrange: return tokens.isEmpty ? nil : .arrange(tokens)
        case .completion, .dictation:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(text)
        case .matching: return pairs.count == question.left?.count ? .matching(pairs) : nil
        }
    }
    public func advance() {
        guard !isBusy, !hasUnconfirmedAnswer else { return }
        if case .story(let index) = stage { seenBeats.insert(attempt.unit.beats[index].id) }
        feedback = nil; awardedPoints = 0
        choice = nil; tokens = []; text = ""; pairs = []; selectedLeft = nil
        if attempt.round.ordinal == 0, attempt.round.answers.isEmpty,
           let index = openingBeatIndices.first(where: { !seenBeats.contains(attempt.unit.beats[$0].id) }) {
            stage = .story(index); return
        }
        if !attempt.round.completed,
           let id = attempt.round.questionIds.first(where: { id in !attempt.round.answers.contains { $0.questionId == id } }) {
            stage = .question(id)
        } else { stage = .summary }
    }
    public func skipStory() {
        seenBeats.formUnion(attempt.unit.beats.map(\.id))
        advance()
    }
    public func submit(skip: Bool = false) async {
        guard !isBusy, feedback == nil, let question else { return }
        if pendingAnswer == nil {
            guard let answer = skip ? LearningAnswer.skip : answer else { return }
            pendingAnswer = .init(requestId: UUID(), attempt: attempt, questionId: question.id, answer: answer)
        }
        guard let command = pendingAnswer else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let receipt = try await service.answerLearning(attempt.id, command: command)
            attempt = receipt.attempt; feedback = receipt.result; awardedPoints = receipt.awardedPoints
            roundPoints = attempt.round.answers.filter { $0.result.outcome == .correct }.count
            pendingAnswer = nil; hasUnconfirmedAnswer = false
        } catch {
            hasUnconfirmedAnswer = true
            self.error = "还未确认提交结果。重试会核对同一次答案，不会重复加分。\n\(error.localizedDescription)"
        }
    }
    /// 网络响应丢失或另一设备作答后，重新读取权威记录。
    public func recover() async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let fresh = try await service.learningAttempt(attempt.id)
            if let command = pendingAnswer,
               let stored = fresh.round.answers.first(where: { $0.questionId == command.questionId }), fresh.round.id == command.roundId {
                feedback = stored.result; awardedPoints = 0
            } else {
                stage = .summary
            }
            attempt = fresh; pendingAnswer = nil; hasUnconfirmedAnswer = false
            roundPoints = fresh.round.answers.filter { $0.result.outcome == .correct }.count
            finishRequestID = UUID(); retryRequestID = UUID()
            if feedback == nil { isBusy = false; advance() }
        } catch { self.error = error.localizedDescription }
    }
    public func finish(skipRemaining: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            attempt = try await service.finishLearning(attempt, requestID: finishRequestID, skipRemaining: skipRemaining)
            await afterFinish()
            finishRequestID = UUID(); stage = .summary
        } catch {
            // 结束可能已提交但响应丢失；旧周期不能继续签入新消息。
            await afterFinish()
            self.error = error.localizedDescription
        }
    }
    public func retry() async {
        guard !isBusy, attempt.firstCompletedAt != nil, attempt.remainingCount > 0 else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            attempt = try await service.retryLearning(attempt, requestID: retryRequestID)
            retryRequestID = UUID(); feedback = nil; roundPoints = attempt.round.answers.filter { $0.result.outcome == .correct }.count
            isBusy = false; advance()
        } catch { self.error = error.localizedDescription }
    }
    public func selectPair(right: String) {
        guard let left = selectedLeft, !hasUnconfirmedAnswer, feedback == nil else { return }
        pairs.removeAll { $0.left == left || $0.right == right }
        pairs.append(.init(left: left, right: right)); selectedLeft = nil
    }
}
