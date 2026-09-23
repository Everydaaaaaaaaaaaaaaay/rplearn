import BackendKit
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
        var context: LearningChallengeContext? = nil
    }
    struct ReviewReceipt: Codable {
        let id: UUID
        let date: Date
        let summary: String
    }
    struct State: Codable {
        var receipts: [UUID: ReviewReceipt]? = nil
        var presentation: LearningChatPresentation? = nil
        var enabled = false
        var challenge: Challenge?
        var usedTasks: Set<String> = []
        var ledger = LearningSystemPolicy.Ledger()
        var listening: [LearningListeningSession] = []
        var pending: [Pending] = []
        var calls: [Int: Int] = [:]
        var batches: [Int: Int] = [:]
        var successfulBatches: [Int: Int]? = nil
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
    private var syncTask: Task<Void, Never>?
    private weak var syncEnvironment: AppEnvironment?
    private var syncRequested = false
    private var lastSyncedPayload: Data?
    var syncError: String?
    private struct CloudSnapshot: Codable, Sendable { let revision: Int; let payload: String? }
    private struct CloudWrite: Codable, Sendable { let revision: Int; let payload: String }
    private struct CloudState: Codable {
        let enabled: Bool
        let ledger: LearningSystemPolicy.Ledger
        let listening: [LearningListeningSession]
        let pending: [Int] // Queued source messages and unfinished tasks stay device-local.
    }
    private var active = Set<UUID>()
    private var activeReplyOwners = Set<UUID>()
    init(owner: UUID, evaluationID: UUID? = nil, sourceChatStore: ChatStore? = nil) {
        self.owner = owner; file = LearningSystemFile(owner: owner, evaluationID: evaluationID); self.sourceChatStore = sourceChatStore
    }
    func waitForPersistence() async -> Bool { await saving?.value ?? true }
    func load() async {
        while loading {
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
        }
        guard !ready, !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            if let data = try await file.read() {
                let restored = try JSONDecoder().decode(State.self, from: data)
                try restored.ledger.validateStorageCompatibility()
                state = restored
            }
            // Existing opt-in remains opt-in; never silently enable a paid feature.
            if state.presentation == nil, state.enabled {
                presentation.hasChosenRecording = true
            }
            ready = true
            if state.ledger.ruleRevision != LearningSystemPolicy.ruleRevision {
                state.ledger.adoptCurrentRules(); persist()
            }
        } catch { self.error = "学习记录暂时无法读取，原文件已保留。\(error.localizedDescription)" }
    }
    func persist(sync: Bool = true) {
        guard ready else { return }
        do {
            let data = try JSONEncoder().encode(state), previous = saving
            if sync { requestSync() }
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
    var presentation: LearningChatPresentation {
        get { state.presentation ?? LearningChatPresentation() }
        set { state.presentation = newValue }
    }
    func deactivate() {
        timer?.cancel(); reviewTask?.cancel(); syncTask?.cancel(); syncEnvironment = nil; activeReplyOwners.removeAll()
    }
    func setEnabled(_ value: Bool) {
        state.enabled = value
        presentation.hasChosenRecording = true
        if !value { timer?.cancel(); reviewTask?.cancel(); state.challenge = nil }
        persist()
    }
    func acknowledge(_ evidence: LearningSystemPolicy.Evidence?) {
        if let evidence {
            presentation.acknowledgedEvidence.formUnion(state.ledger.evidence.filter {
                $0.characterID == evidence.characterID && $0.date <= evidence.date
            }.map(\.id))
        }
        persist()
    }
    func unreadReceipt(characterID: UUID) -> ReviewReceipt? {
        guard let receipt = state.receipts?[characterID], !presentation.acknowledgedEvidence.contains(receipt.id) else { return nil }
        return receipt
    }
    func acknowledgeReceipt(characterID: UUID) {
        if let receipt = state.receipts?[characterID] { presentation.acknowledgedEvidence.insert(receipt.id) }
        persist()
    }
    func deferLearning() {
        presentation.deferToday(now: .now)
        state.ledger.deferredUntil = presentation.deferredUntil
        persist()
    }
    func unreadEvidence(characterID: UUID) -> LearningSystemPolicy.Evidence? {
        state.ledger.evidence.last { !$0.deleted && $0.characterID == characterID && !presentation.acknowledgedEvidence.contains($0.id) }
    }
    func chatInstruction(characterID: UUID) -> String? {
        guard state.enabled, let challenge = state.challenge, challenge.characterID == characterID else { return nil }
        return LearningChatPresentation.instruction(for: challenge.task)
    }
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
        guard state.enabled, !reviewing, activeReplyOwners.isEmpty, !storageFailed, (state.successfulBatches?[day] ?? 0) < LearningSystemPolicy.dailyBatches, state.calls[day, default: 0] < LearningSystemPolicy.dailyBatches * 2 else { return }
        let waits = candidates.compactMap { $0.delay(now: .now) }
        guard let delay = waits.min() else { return }
        timer = Task { [weak self, weak environment] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self, let environment else { return }
            self.reviewTask = Task { await self.review(environment: environment) }
        }
    }
    private var candidates: [LearningReviewQueue.Candidate] {
        state.pending.filter { !active.contains($0.id) }.map {
            .init(id: $0.id, count: $0.turns.count, lastDate: $0.lastDate,
                  blocked: $0.failure != nil,
                  idleSeconds: $0.challenge == nil ? LearningSystemPolicy.idleSeconds : 12,
                  waitForIdleWhenFull: $0.challenge != nil)
        }
    }
    func replyActivity(owner: UUID, active: Bool, environment: AppEnvironment) {
        if active { activeReplyOwners.insert(owner) } else { activeReplyOwners.remove(owner) }
        schedule(environment: environment)
    }
    func resume(environment: AppEnvironment) {
        syncEnvironment = environment
        lastSyncedPayload = nil // Foreground recovery also pulls another device's completed evidence.
        requestSync()
        schedule(environment: environment)
    }
    func retrySync(environment: AppEnvironment) { syncEnvironment = environment; requestSync() }
    private func requestSync() {
        guard ready, syncEnvironment != nil else { return }
        syncRequested = true
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            defer { self.syncTask = nil }
            while self.syncRequested && !Task.isCancelled {
                self.syncRequested = false
                await self.synchronize()
            }
        }
    }
    private func cloudPayload() throws -> Data {
        let cloud = CloudState(enabled: state.enabled, ledger: state.ledger,
            listening: state.listening.filter { $0.finishedAt != nil }, pending: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(cloud)
    }
    private func synchronize() async {
        guard let environment = syncEnvironment,
              case .signedIn(let identity) = environment.authSession.phase, identity.userID == owner else { return }
        do {
            let before = try cloudPayload()
            if before == lastSyncedPayload { return }
            for attempt in 0..<2 {
                let remote: CloudSnapshot = try await environment.backendClient.get("/v1/learning/state")
                guard !Task.isCancelled, case .signedIn(let current) = environment.authSession.phase, current.userID == owner else { return }
                if let payload = remote.payload {
                    let cloud = try JSONDecoder().decode(CloudState.self, from: Data(payload.utf8))
                    try state.ledger.merge(cloud.ledger)
                    // A completed attempt wins over a stale unfinished copy. Ongoing
                    // audio sessions remain local, avoiding cross-device answer races.
                    var sessions = Dictionary(state.listening.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    for session in cloud.listening where session.finishedAt != nil {
                        if sessions[session.id]?.finishedAt == nil { sessions[session.id] = session }
                    }
                    state.listening = sessions.values.sorted { $0.startedAt < $1.startedAt }
                }
                let data = try cloudPayload()
                let payload = String(decoding: data, as: UTF8.self)
                do {
                    let _: CloudSnapshot = try await environment.backendClient.send(path: "/v1/learning/state", method: "PUT", body: CloudWrite(revision: remote.revision, payload: payload))
                    guard !Task.isCancelled else { return }
                    syncError = nil
                    lastSyncedPayload = data
                    // Save the merged cache without scheduling another cloud write.
                    persist(sync: false)
                    return
                } catch let error as BackendClientError where error.code == "LEARNING_STATE_CONFLICT" && attempt == 0 { continue }
            }
        } catch {
            if !Task.isCancelled { syncError = "学习记录已保存在本机，暂未同步。联网后可重试。" }
        }
    }
    func review(environment: AppEnvironment, force: Bool = false) async {
        guard state.enabled, ready, !reviewing, activeReplyOwners.isEmpty,
              case .signedIn(let identity) = environment.authSession.phase, identity.userID == owner else { return }
        let day = LearningSystemPolicy.utcDay(.now)
        guard Date.now >= state.ledger.latestDate else { error = "设备时间早于已保存记录，请恢复正确时间后重试。"; return }
        guard (state.successfulBatches?[day] ?? 0) < LearningSystemPolicy.dailyBatches, state.calls[day, default: 0] < LearningSystemPolicy.dailyBatches * 2,
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
        var turns = count == 0 ? [] : batch.turns
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
        let previousContext: LearningChallengeContext?
        if let challenge = batch.challenge, state.challenge?.task.id == challenge.task.id {
            previousContext = state.challenge?.context
        } else { previousContext = batch.challenge?.context }
        let combined = (previousContext ?? LearningChallengeContext()).appending(turns, assisted: batch.assisted, available: Set(messages.map(\.id)))
        if batch.challenge != nil { turns = combined.turns }
        let context = turns.enumerated().map { offset, turn in
            let index = messages.firstIndex(where: { $0.id == turn.id }) ?? 0
            let preceding = messages.prefix(index).suffix(3).filter { $0.role == .assistant }.map(\.text).joined(separator: " ")
            return "Before learner message m\(offset + 1): \(preceding.prefix(500))"
        }.joined(separator: "\n")
            + (batch.challenge.map { "\nExplicit user-selected task: \($0.task.instruction)" } ?? "")
        for attempt in 0..<2 {
            guard LearningReviewQueue.reserveCall(&state.calls, now: .now) else {
                error = "今日学习回顾请求已达上限，表达已保留，可之后重试。"; break
            }
            guard await checkpoint(), state.enabled, !Task.isCancelled,
                  case .signedIn(let current) = environment.authSession.phase, current.userID == owner else { return }
            do {
                let result = try await LearningSystemReviewer.assess(turns: Array(turns), context: context, task: batch.challenge?.task, llm: environment.llmRouter)
                guard !Task.isCancelled, state.enabled, case .signedIn(let current) = environment.authSession.phase, current.userID == owner else { return }
                let items = result.paused ? [] : result.assessments.map { item in
                    LearningSystemPolicy.Evidence(batchID: batch.id, characterID: batch.characterID, date: batch.lastDate,
                        skill: item.skill, band: item.band, topic: item.topic, scores: item.scores, quote: LearningChallengeContext.evidenceQuote(item, turns: turns),
                        explanation: item.explanation, independent: !(batch.challenge == nil ? batch.assisted : combined.assisted),
                        confirmation: batch.challenge.map { state.challenge?.task.id == $0.task.id && $0.confirmation && $0.task.skill == item.skill && $0.task.band == item.band && $0.task.topic == item.topic } ?? false)
                }
                guard state.ledger.record(items, batchID: batch.id, now: .now) else {
                    self.error = "记录时间异常或批次重复，原文已保留，未增加经验。"; return
                }
                if state.successfulBatches == nil { state.successfulBatches = [:] }
                state.successfulBatches?[LearningSystemPolicy.utcDay(.now), default: 0] += 1
                state.pending.removeAll { $0.id == batch.id }
                if let challenge = batch.challenge, state.challenge?.task.id == challenge.task.id {
                    if LearningReviewQueue.endsChallenge(paused: result.paused, assessments: result.assessments) {
                        state.challenge = nil
                    } else { state.challenge?.context = combined }
                }
                if state.receipts == nil { state.receipts = [:] }
                state.receipts?[batch.characterID] = ReviewReceipt(id: batch.id, date: .now,
                    summary: result.paused ? "已结束这次练习，接下来照常聊天。" : items.isEmpty
                        ? "这次聊天已回顾，暂未出现足够的能力证据。问候、简短回应也很自然，不需要刻意凑答案。"
                        : "这次表达已记录。能力判断会结合不同日期和情境的表现。")
                error = nil; persist(); return
            } catch {
                if Task.isCancelled { return }
                if attempt == 0 && LearningSystemReviewer.isRetryable(error) { try? await Task.sleep(for: .seconds(2)); continue }
                self.error = "这次表达还未完成回顾，已保留，稍后可重试；不会扣分。"
            }
        }
    }
    var reviewLimitReached: Bool {
        let day = LearningSystemPolicy.utcDay(.now)
        return (state.successfulBatches?[day] ?? 0) >= LearningSystemPolicy.dailyBatches || state.calls[day, default: 0] >= LearningSystemPolicy.dailyBatches * 2
    }
    func startRecommendedChallenge(characterID: UUID) {
        guard !reviewLimitReached else { error = "今日学习回顾已达上限，新表达会保留到之后处理。正常聊天不受影响。"; return }
        for skill in LearningSystemPolicy.Skill.allCases {
            for band in 1...3 where state.ledger.status(skill: skill, band: band, now: .now) == .ready
                && (state.ledger.nextConfirmationDate(skill: skill, band: band, now: .now).map { $0 <= .now } ?? true) {
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
        guard !reviewLimitReached else { error = "今日学习回顾已达上限，新表达会保留到之后处理。正常聊天不受影响。"; return }
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
        else {
            #if DEBUG
            guard ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "learningSystem"
                || (ProcessInfo.processInfo.environment["UI_TEST_SKIP_ONBOARDING"] == "1" && ProcessInfo.processInfo.environment["UI_TEST_LEARNING_CHAT_PREVIEW"] == "1"),
                  let workspace else { return nil }
            owner = UUID(uuidString: ProcessInfo.processInfo.environment["UI_TEST_LEARNING_V1_OWNER"] ?? "") ?? workspace.userID
            #else
            return nil
            #endif
        }
        if let current = learningSystemInstance, current.owner == owner { return current }
        learningSystemInstance?.deactivate()
        let model = ConversationLearningSystem(owner: owner)
        learningSystemInstance = model
        return model
    }
}
