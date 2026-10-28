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
    public private(set) var historyError: String?
    private var historyRetryIsPagination = false
    public private(set) var isPreparing = false
    public private(set) var directions: LearningDirections?
    public private(set) var directionError: String?
    public private(set) var isChangingDirection = false
    public private(set) var pendingDirection: String?
    public var presentedAttempt: LearningAttempt?
    public var presentedPromotion: LearningPromotion?
    private(set) var starAward: LearningStarAward?
    var presentedAutomaticPromotion: LearningAutomaticPromotion?
    private var pendingAutomaticPromotion: LearningAutomaticPromotion?
    private var synchronizedLevel: String?
    private struct RewardSession {
        let level: String
        let before: LearningJourney?
        var didEarnPoints = false
        var returned = false
    }
    private var rewardSession: RewardSession?
    private var promotionRequestID = UUID()
    private var reloadAfterBusy = false
    var canOpenPromotion: Bool {
        guard service is any LearningPromotionServing, let eligibility = journey?.promotion,
              eligibility.level == journey?.currentLevel else { return false }
        return eligibility.activePromotionId != nil
    }
    public let characterID: UUID
    let service: any LearningServing & LearningDirectionServing
    private let cycleChanged: @Sendable () async -> Void
    private let profileChanged: @MainActor () async throws -> Void
    private var startRequestID = UUID()
    private var directionRequest: (id: UUID, revision: Int)?

    public var selectedDirection: LearningDirectionOption? {
        directions?.directions.first { $0.id == directions?.selectedDirection }
    }
    public var canStartNewChallenge: Bool {
        pendingDirection == nil && selectedDirection?.status == "available"
    }

    public init(characterID: UUID, service: any LearningServing & LearningDirectionServing,
                cycleChanged: @escaping @Sendable () async -> Void = {},
                profileChanged: @escaping @MainActor () async throws -> Void = {}) {
        self.characterID = characterID; self.service = service
        self.cycleChanged = cycleChanged
        self.profileChanged = profileChanged
    }
    public func load() async {
        guard !isBusy, !isChangingDirection else {
            reloadAfterBusy = true
            return
        }
        isBusy = true; error = nil; historyError = nil; historyRetryIsPagination = false
        directions = nil
        directionError = pendingDirection == nil ? nil : "上次方向切换尚未确认，请重试。"
        defer { finishBusyOperation() }
        do {
            async let character = service.learningCharacter(characterID)
            async let global = service.learningJourney()
            async let page = readHistory()
            let values = try await (character, global, page)
            guard !Task.isCancelled else { return }
            state = values.0; journey = values.1
            switch values.2 {
            case .success(let page): history = page.items; nextCursor = page.nextCursor
            case .failure(let failure):
                if !(failure is CancellationError) { historyError = failure.localizedDescription }
            }
            if let session = rewardSession, session.returned {
                starAward = LearningStarAward(before: session.before, after: values.1, rewardedLevel: session.level, didEarnPoints: session.didEarnPoints)
                pendingAutomaticPromotion = LearningAutomaticPromotion(before: session.before, after: values.1, rewardedLevel: session.level, didEarnPoints: session.didEarnPoints)
                rewardSession = nil
            }
            isPreparing = ["pending", "running", "review"].contains(state?.generationStatus ?? "")
            if synchronizedLevel != values.1.currentLevel {
                do {
                    try await profileChanged()
                    guard !Task.isCancelled else { return }
                    synchronizedLevel = values.1.currentLevel
                } catch is CancellationError { return }
                catch { self.error = "学习进度已保存，档案暂未同步完成。请联网后重试。" }
            }
            presentAutomaticPromotionIfReady()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
        do {
            let current = try await service.learningDirections()
            guard !Task.isCancelled else { return }
            directions = current
        } catch is CancellationError {} catch { directionError = error.localizedDescription }
    }
    public func selectDirection(_ direction: String) async {
        guard !isBusy, !isChangingDirection else { return }
        if let pendingDirection {
            guard pendingDirection == direction else { return }
        } else {
            guard let directions, directions.directions.contains(where: { $0.id == direction }),
                  direction != directions.selectedDirection else { return }
            directionRequest = (UUID(), directions.revision)
            pendingDirection = direction
        }
        guard let request = directionRequest else { return }
        isChangingDirection = true; directionError = nil; directions = nil
        defer { isChangingDirection = false; reloadIfNeeded() }
        do {
            _ = try await service.selectLearningDirection(direction, requestID: request.id, expectedRevision: request.revision)
            pendingDirection = nil; directionRequest = nil
            // 幂等重放可能返回较早的收据，展示前重新读取跨设备权威选择。
            directions = try await service.learningDirections()
        } catch {
            if case BackendClientError.api(let code, _, _, _) = error,
               code == "LEARNING_DIRECTION_CONFLICT" {
                pendingDirection = nil; directionRequest = nil
                directions = try? await service.learningDirections()
            }
            directionError = error.localizedDescription
        }
    }
    public func loadMore() async {
        guard !isBusy, !isChangingDirection, let nextCursor else { return }
        isBusy = true; historyError = nil; historyRetryIsPagination = false
        defer { finishBusyOperation() }
        do {
            let page = try await service.learningHistory(characterID, cursor: nextCursor)
            history += page.items.filter { item in !history.contains(where: { $0.id == item.id }) }
            self.nextCursor = page.nextCursor
        } catch is CancellationError {} catch {
            historyError = error.localizedDescription; historyRetryIsPagination = true
        }
    }
    public func retryHistory() async {
        if historyRetryIsPagination { await loadMore() }
        else { await load() }
    }
    private func readHistory() async -> Result<LearningHistory, Error> {
        do { return .success(try await service.learningHistory(characterID, cursor: nil)) }
        catch { return .failure(error) }
    }
    private func finishBusyOperation() {
        isBusy = false; reloadIfNeeded()
    }
    private func reloadIfNeeded() {
        guard reloadAfterBusy, !isBusy, !isChangingDirection else { return }
        reloadAfterBusy = false
        Task { await load() }
    }
    public func open(_ id: UUID? = nil) async {
        guard !isBusy, !isChangingDirection else { return }
        // 方向不可用只阻止新开；历史和进行中的挑战按原快照继续。
        guard id != nil || state?.activeAttemptId != nil || canStartNewChallenge else { return }
        isBusy = true; error = nil
        defer { finishBusyOperation() }
        do {
            let opened: LearningAttempt?
            if let id = id ?? state?.activeAttemptId {
                opened = try await service.learningAttempt(id)
            } else {
                let response = try await service.startLearning(characterID, requestID: startRequestID)
                // 202 也是已完成的幂等请求；下次查询可发起新的抽取。
                startRequestID = UUID()
                isPreparing = response.status == "preparing"
                opened = response.attempt
            }
            if let opened {
                let baseline = try? await service.learningJourney()
                guard !Task.isCancelled else { return }
                rewardSession = RewardSession(level: opened.level, before: baseline)
                presentedAttempt = opened
            }
        } catch { self.error = error.localizedDescription }
    }
    public func refreshCycle() async { await cycleChanged() }
    public func challengeClosed() async { rewardSession?.returned = true; await load() }
    func recordReward(level: String, points: Int) {
        guard points > 0, rewardSession?.level == level else { return }
        rewardSession?.didEarnPoints = true
    }
    func consumeStarAward(_ id: UUID? = nil) {
        if id == nil || starAward?.id == id { starAward = nil }
        presentAutomaticPromotionIfReady()
    }
    private func presentAutomaticPromotionIfReady() {
        guard starAward == nil, let promotion = pendingAutomaticPromotion,
              synchronizedLevel == promotion.toLevel else { return }
        presentedAutomaticPromotion = promotion
        pendingAutomaticPromotion = nil
    }
    #if DEBUG
    /// Only the isolated in-memory replay service can synthesize this return receipt.
    func previewReward(toStars stars: Int) async {
        guard let preview = service as? LearningAchievementPreviewService, let journey else { return }
        rewardSession = RewardSession(level: journey.currentLevel, before: journey)
        recordReward(level: journey.currentLevel, points: 1)
        await preview.set(stars: stars, nearNext: false)
        await challengeClosed()
    }
    #endif
    func openPromotion() async {
        guard !isBusy, canOpenPromotion, let service = service as? any LearningPromotionServing,
              let eligibility = journey?.promotion else { return }
        isBusy = true; error = nil
        defer { finishBusyOperation() }
        do {
            let promotion: LearningPromotion
            if let id = eligibility.activePromotionId { promotion = try await service.learningPromotion(id) }
            else { promotion = try await service.beginLearningPromotion(level: eligibility.level, requestID: promotionRequestID) }
            guard !Task.isCancelled else { return }
            promotionRequestID = UUID(); consumeStarAward(); presentedPromotion = promotion
        } catch { self.error = error.localizedDescription }
    }
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
    private var receiptPoints: [String: Int] = [:]
    public var earnedPoints: Int {
        attempt.round.answers.reduce(0) { $0 + ($1.awardedPoints ?? receiptPoints[$1.questionId] ?? 0) }
    }
    public private(set) var hasUnconfirmedAnswer = false
    public var choice: String?
    public var tokens: [String] = []
    public var text = ""
    public var pairs: [LearningAnswer.Pair] = []
    public var selectedLeft: String?
    public private(set) var fills: [LearningAnswer.Fill] = []
    public private(set) var selectedSlot: String?
    public var activeSlot: String? {
        selectedSlot ?? question?.clozeSlotIDs.first(where: { id in !fills.contains { $0.slotId == id } }) ?? question?.clozeSlotIDs.first
    }
    let service: any LearningServing
    private var pendingAnswer: LearningAnswerCommand?
    private var finishRequestID = UUID()
    private var retryRequestID = UUID()
    private var seenBeats: Set<String> = []
    private let afterFinish: @Sendable () async -> Void
    private let didEarnPoints: @Sendable (String, Int) async -> Void

    public init(attempt: LearningAttempt, service: any LearningServing, afterFinish: @escaping @Sendable () async -> Void = {},
                didEarnPoints: @escaping @Sendable (String, Int) async -> Void = { _, _ in }) {
        self.attempt = attempt; self.service = service; self.afterFinish = afterFinish; self.didEarnPoints = didEarnPoints
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
        case .choice, .listeningChoice, .audioChoice: return choice.map(LearningAnswer.choice)
        case .arrange, .audioArrange: return tokens.isEmpty ? nil : .arrange(tokens)
        case .completion, .dictation:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(text)
        case .listeningCompletion:
            guard let limit = question.wordLimit, (1...8).contains(limit),
                  answerWordCount > 0, answerWordCount <= limit else { return nil }
            return .text(text)
        case .audioMatching: return pairs.count == question.audioOptions?.count ? .matching(pairs) : nil
        case .matching: return pairs.count == question.left?.count ? .matching(pairs) : nil
        case .cloze:
            return !question.clozeSlotIDs.isEmpty && fills.count == question.clozeSlotIDs.count ? .cloze(fills) : nil
        }
    }
    public var answerWordCount: Int { LearningQuestion.answerWordCount(text) }
    public func advance() {
        guard !isBusy, !hasUnconfirmedAnswer else { return }
        if case .story(let index) = stage { seenBeats.insert(attempt.unit.beats[index].id) }
        feedback = nil; awardedPoints = 0
        choice = nil; tokens = []; text = ""; pairs = []; selectedLeft = nil
        fills = []; selectedSlot = nil
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
            receiptPoints[command.questionId] = receipt.awardedPoints
            roundPoints = attempt.round.answers.filter { $0.result.outcome == .correct }.count
            pendingAnswer = nil; hasUnconfirmedAnswer = false
            if receipt.awardedPoints > 0 { await didEarnPoints(attempt.level, receipt.awardedPoints) }
        } catch BackendClientError.api(let code, let message, _, _) where code == "LEARNING_ANSWER_REVIEW_REQUIRED" {
            pendingAnswer = nil; hasUnconfirmedAnswer = false
            self.error = message
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
                if let points = stored.awardedPoints, points > 0 { await didEarnPoints(fresh.level, points) }
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
            receiptPoints = [:]
            retryRequestID = UUID(); feedback = nil; roundPoints = attempt.round.answers.filter { $0.result.outcome == .correct }.count
            isBusy = false; advance()
        } catch { self.error = error.localizedDescription }
    }
    public func selectPair(right: String) {
        guard let left = selectedLeft, !hasUnconfirmedAnswer, feedback == nil else { return }
        pairs.removeAll { $0.left == left || $0.right == right }
        pairs.append(.init(left: left, right: right)); selectedLeft = nil
    }
    public func selectSlot(_ id: String) {
        guard !isBusy, !hasUnconfirmedAnswer, feedback == nil, question?.clozeSlotIDs.contains(id) == true else { return }
        selectedSlot = id
    }
    public func fillSlot(with tokenID: String) {
        guard !isBusy, !hasUnconfirmedAnswer, feedback == nil,
              let question, question.type == .cloze, let slot = activeSlot,
              question.tokens?.contains(where: { $0.id == tokenID }) == true else { return }
        fills.removeAll { $0.slotId == slot || $0.tokenId == tokenID }
        fills.append(.init(slotId: slot, tokenId: tokenID))
        selectedSlot = question.clozeSlotIDs.first { id in !fills.contains { $0.slotId == id } } ?? slot
    }
    public func clearSlot(_ id: String) {
        guard !isBusy, !hasUnconfirmedAnswer, feedback == nil, question?.clozeSlotIDs.contains(id) == true else { return }
        fills.removeAll { $0.slotId == id }; selectedSlot = id
    }
}
