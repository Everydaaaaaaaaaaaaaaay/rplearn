#if DEBUG
import Foundation
import Observation
import DomainKit
import LLMKit
import PersistenceKit

actor LearningSystemFile {
    let url: URL
    init(owner: UUID, evaluationID: UUID? = nil) {
        let directory = evaluationID.map { "LearningSystemEvaluation/\($0.uuidString)" } ?? "LearningSystem-v1"
        url = URL.applicationSupportDirectory.appendingPathComponent("\(directory)/\(owner.uuidString).json")
    }
    func read() throws -> Data? { FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil }
    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

@MainActor @Observable
final class ConversationLearningSystem {
    struct Pending: Codable {
        var id = UUID()
        let characterID: UUID
        let conversationID: UUID
        var turns: [LearningSystemReviewer.Turn] = []
        var assisted = false
        var failure: String?
        var challenge: Challenge?
        var lastDate: Date = .now
    }
    struct Challenge: Codable {
        let task: LearningTask
        let characterID: UUID
        let startedAt: Date
        let confirmation: Bool
    }
    struct State: Codable {
        var enabled = false
        var challenge: Challenge?
        var usedTasks: Set<String> = []
        var ledger = LearningSystemPolicy.Ledger()
        var listening: [LearningListeningSession] = []
        var pending: [Pending] = []
        var calls: [Int: Int] = [:]
        var batches: [Int: Int] = [:]
    }
    let owner: UUID
    private let file: LearningSystemFile
    private let sourceChatStore: ChatStore?
    var state = State()
    var ready = false
    private var loading = false
    private var storageFailed = false
    var error: String?
    var reviewing = false
    private var timer: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var saving: Task<Bool, Never>?
    private var active = Set<UUID>()
    private var activeReplyOwners = Set<UUID>()
    init(owner: UUID, evaluationID: UUID? = nil, sourceChatStore: ChatStore? = nil) {
        self.owner = owner; file = LearningSystemFile(owner: owner, evaluationID: evaluationID); self.sourceChatStore = sourceChatStore
    }
    func waitForPersistence() async -> Bool { await saving?.value ?? true }
    func load() async {
        guard !ready, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            if let data = try await file.read() { state = try JSONDecoder().decode(State.self, from: data) }
            ready = true
        } catch { self.error = "学习记录暂时无法读取，原文件已保留。\(error.localizedDescription)" }
    }
    func persist() {
        guard ready else { return }
        do {
            let data = try JSONEncoder().encode(state), previous = saving
            saving = Task { [weak self, file] in
                _ = await previous?.value
                do {
                    try await file.write(data)
                    self?.storageFailed = false
                    if self?.error == "学习记录保存失败，请稍后重试。" { self?.error = nil }
                    return true
                } catch { self?.storageFailed = true; self?.error = "学习记录保存失败，请稍后重试。"; return false }
            }
        } catch { storageFailed = true; saving = Task { false }; self.error = "学习记录编码失败，未覆盖原文件。" }
    }
    private func checkpoint() async -> Bool {
        persist()
        return await saving?.value ?? false
    }
    func setEnabled(_ value: Bool) { state.enabled = value; if !value { timer?.cancel(); reviewTask?.cancel() }; persist() }
    func observe(character: UUID, conversation: UUID, event: ConversationLearningObservation, environment: AppEnvironment) {
        guard ready, state.enabled else { return }
        let challenge = state.challenge?.characterID == character ? state.challenge : nil
        if !state.pending.contains(where: { $0.conversationID == conversation && $0.challenge?.task.id == challenge?.task.id && $0.failure == nil && !active.contains($0.id) }) {
            state.pending.append(Pending(characterID: character, conversationID: conversation, challenge: challenge))
        }
        guard let i = state.pending.lastIndex(where: { $0.conversationID == conversation && $0.challenge?.task.id == challenge?.task.id && $0.failure == nil && !active.contains($0.id) }) else { return }
        switch event {
        case .assistance, .unattributed: state.pending[i].assisted = true
        case .sent(let id, let text, let voice):
            guard !state.pending.contains(where: { $0.turns.contains(where: { $0.id == id }) }) else { return }
            state.pending[i].assisted = state.pending[i].assisted || voice
            state.pending[i].turns.append(.init(id: id, text: text))
            state.pending[i].lastDate = .now
        }
        persist()
        schedule(environment: environment)
    }
    private func schedule(environment: AppEnvironment) {
        timer?.cancel()
        let day = LearningSystemPolicy.utcDay(.now)
        guard state.enabled, !reviewing, activeReplyOwners.isEmpty, !storageFailed, state.batches[day, default: 0] < 6, state.calls[day, default: 0] < 12 else { return }
        let waits = candidates.compactMap { $0.delay(now: .now) }
        guard let delay = waits.min() else { return }
        timer = Task { [weak self, weak environment] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self, let environment else { return }
            self.reviewTask = Task { await self.review(environment: environment) }
        }
    }
    private var candidates: [LearningReviewQueue.Candidate] {
        state.pending.filter { !active.contains($0.id) }.map { .init(id: $0.id, count: $0.turns.count, lastDate: $0.lastDate, blocked: $0.failure != nil) }
    }
    func replyActivity(owner: UUID, active: Bool, environment: AppEnvironment) {
        if active { activeReplyOwners.insert(owner) } else { activeReplyOwners.remove(owner) }
        schedule(environment: environment)
    }
    func resume(environment: AppEnvironment) { schedule(environment: environment) }
    func review(environment: AppEnvironment, force: Bool = false) async {
        guard state.enabled, ready, !reviewing, activeReplyOwners.isEmpty,
              case .signedIn(let identity) = environment.authSession.phase, identity.userID == owner else { return }
        let day = LearningSystemPolicy.utcDay(.now)
        guard Date.now >= state.ledger.latestDate else { error = "设备时间早于已保存记录，请恢复正确时间后重试。"; return }
        guard state.batches[day, default: 0] < 6, state.calls[day, default: 0] < 12,
              let batchID = LearningReviewQueue.next(candidates, now: .now, force: force),
              let index = state.pending.firstIndex(where: { $0.id == batchID }) else { schedule(environment: environment); return }
        var batch = state.pending[index]
        batch.failure = nil
        let count = LearningReviewQueue.prefixCount(batch.turns.map(\.text))
        let consumed = max(1, count)
        if consumed < batch.turns.count {
            var remainder = batch
            remainder.id = UUID(); remainder.turns = Array(batch.turns.dropFirst(consumed))
            state.pending.insert(remainder, at: index + 1)
        }
        batch.turns = Array(batch.turns.prefix(consumed))
        state.pending[index] = batch
        error = nil
        reviewing = true; active.insert(batch.id)
        defer {
            if let error, let index = state.pending.firstIndex(where: { $0.id == batch.id }) { state.pending[index].failure = error }
            reviewing = false; active.remove(batch.id); persist(); schedule(environment: environment)
        }
        state.batches[day, default: 0] += 1
        guard await checkpoint() else { return }
        let turns = count == 0 ? [] : batch.turns
        guard !turns.isEmpty else {
            state.pending.removeAll { $0.id == batch.id }
            error = "这条消息较长，本次不作能力判断。完整原文仍在聊天记录中。"; persist(); return
        }
        let messages: [MessageDTO]
        do { messages = try await (sourceChatStore ?? environment.chatStore).messages(conversationID: batch.conversationID) }
        catch { self.error = "聊天上下文暂时无法读取，已保留表达，稍后可重试。"; return }
        guard turns.allSatisfy({ turn in messages.contains(where: { $0.id == turn.id }) }) else {
            error = "部分原消息已不可用，本次不作能力判断。"; return
        }
        let context = turns.enumerated().map { offset, turn in
            let index = messages.firstIndex(where: { $0.id == turn.id }) ?? 0
            let preceding = messages.prefix(index).suffix(3).filter { $0.role == .assistant }.map(\.text).joined(separator: " ")
            return "Before learner message m\(offset + 1): \(preceding.prefix(500))"
        }.joined(separator: "\n")
            + (batch.challenge.map { "\nExplicit user-selected task: \($0.task.instruction)" } ?? "")
        for attempt in 0..<2 {
            guard state.calls[day, default: 0] < 12 else { break }
            state.calls[day, default: 0] += 1
            guard await checkpoint(), state.enabled, !Task.isCancelled,
                  case .signedIn(let current) = environment.authSession.phase, current.userID == owner else { return }
            do {
                let result = try await LearningSystemReviewer.assess(turns: Array(turns), context: context, task: batch.challenge?.task, llm: environment.llmRouter)
                guard !Task.isCancelled, state.enabled, case .signedIn(let current) = environment.authSession.phase, current.userID == owner else { return }
                let items = result.paused ? [] : result.assessments.map { item in
                    LearningSystemPolicy.Evidence(batchID: batch.id, characterID: batch.characterID, date: batch.lastDate,
                        skill: item.skill, band: item.band, topic: item.topic, scores: item.scores, quote: item.quote,
                        explanation: item.explanation, independent: !batch.assisted,
                        confirmation: batch.challenge.map { state.challenge?.task.id == $0.task.id && $0.confirmation && $0.task.skill == item.skill && $0.task.band == item.band && $0.task.topic == item.topic } ?? false)
                }
                guard state.ledger.record(items, batchID: batch.id, now: .now) else {
                    self.error = "记录时间异常或批次重复，原文已保留，未增加经验。"; return
                }
                state.pending.removeAll { $0.id == batch.id }
                if let challenge = batch.challenge, state.challenge?.task.id == challenge.task.id,
                   LearningReviewQueue.endsChallenge(paused: result.paused, assessments: result.assessments) {
                    state.challenge = nil
                }
                error = nil; persist(); return
            } catch {
                if Task.isCancelled { return }
                if attempt == 0 && LearningSystemReviewer.isRetryable(error) { try? await Task.sleep(for: .seconds(2)); continue }
                self.error = "这次表达还未完成回顾，已保留，稍后可重试；不会扣分。"
            }
        }
    }
    func startRecommendedChallenge(characterID: UUID) {
        for skill in LearningSystemPolicy.Skill.allCases {
            for band in 1...3 where state.ledger.status(skill: skill, band: band, now: .now) == .ready {
                startChallenge(skill: skill, band: band, characterID: characterID); return
            }
        }
        if let due = state.ledger.nextReview(now: .now) {
            startChallenge(skill: due.skill, band: due.band, characterID: characterID); return
        }
        let skill = LearningSystemPolicy.Skill.allCases.min { a, b in
            let ac = state.ledger.evidence.filter { !$0.deleted && $0.skill == a }.count
            let bc = state.ledger.evidence.filter { !$0.deleted && $0.skill == b }.count
            return ac < bc
        } ?? .preference
        let band = (1...3).first { state.ledger.status(skill: skill, band: $0, now: .now) != .confirmed } ?? 3
        startChallenge(skill: skill, band: band, characterID: characterID)
    }
    func startChallenge(skill: LearningSystemPolicy.Skill, band: Int, characterID: UUID) {
        guard state.enabled, state.challenge == nil else { return }
        if let next = state.ledger.nextConfirmationDate(skill: skill, band: band, now: .now), next > .now {
            error = "下次独立确认可在\(next.formatted(date: .abbreviated, time: .shortened))开始。现在可以照常聊天。"; return
        }
        let previousTopic = state.ledger.evidence.last(where: { !$0.deleted && $0.skill == skill })?.topic
        let candidates = LearningTask.bank.filter { $0.skill == skill && $0.band == band && !state.usedTasks.contains($0.id) && $0.topic != previousTopic }
        let used = LearningTask.bank.filter { state.usedTasks.contains($0.id) && $0.skill == skill && $0.band == band }
        guard let task = candidates.min(by: { a, b in used.filter { $0.topic == a.topic }.count < used.filter { $0.topic == b.topic }.count }) else {
            error = "这个目标暂无未做过的新情境。可以继续正常聊天积累表达。"; return
        }
        state.challenge = Challenge(task: task, characterID: characterID, startedAt: .now,
            confirmation: state.ledger.status(skill: skill, band: band, now: .now) == .ready)
        state.usedTasks.insert(task.id); persist()
        NotificationCenter.default.post(name: .learningChallengeDidBegin, object: characterID)
    }
    func endChallenge() { state.challenge = nil; persist() }
    func delete(_ id: UUID) { state.ledger.delete(id); persist() }
    func startListening(band: Int, bank: [LearningListeningItem]) {
        if let last = state.listening.last(where: { $0.band == band && $0.finishedAt != nil }),
           Date.now.timeIntervalSince(last.finishedAt!) < 7 * LearningSystemPolicy.day {
            error = "新的听力测评需与上次间隔至少7天；现在可以复听已有题目的原文。"; return
        }
        let seen = Set(state.listening.flatMap { $0.items.map(\.id) })
        guard let session = LearningListeningSession(band: band, bank: bank, seen: seen, now: .now, audioVersion: "supertonic3-F5-default-v1") else {
            error = "这个难度暂无未做过的新题，已有题目仍可在记录中复习。"; return
        }
        state.listening.append(session); error = nil; persist()
    }
    func completedPlayback(sessionID: UUID, itemID: String) {
        guard let i = state.listening.firstIndex(where: { $0.id == sessionID }) else { return }
        state.listening[i].completedPlayback(itemID: itemID); persist()
    }
    func answer(sessionID: UUID, choice: Int) {
        guard let i = state.listening.firstIndex(where: { $0.id == sessionID }), state.listening[i].answer(choice, now: .now) else { return }
        if state.listening[i].finishedAt != nil { state.ledger.award(key: "listening:\(sessionID)", now: .now) }
        persist()
    }
}

extension AppEnvironment {
    func learningSystem() -> ConversationLearningSystem? {
        let owner: UUID
        if case .signedIn(let identity) = authSession.phase { owner = identity.userID }
        else if ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "learningSystem", let workspace {
            owner = UUID(uuidString: ProcessInfo.processInfo.environment["UI_TEST_LEARNING_V1_OWNER"] ?? "") ?? workspace.userID
        } else { return nil }
        if let current = learningSystemInstance, current.owner == owner { return current }
        let model = ConversationLearningSystem(owner: owner)
        learningSystemInstance = model
        Task { await model.load() }
        return model
    }
}
#endif
