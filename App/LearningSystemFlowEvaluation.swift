#if DEBUG
import Foundation
import UIKit
import SwiftData
import ChatFeature
import DomainKit
import PersistenceKit

/// Actual chat VM + production reply timing + v1 queue, with isolated local stores.
@MainActor enum LearningSystemFlowEvaluation {
    private static var runner: Task<Void, Never>?
    struct Step: Codable { let name: String; let passed: Bool; let detail: String }
    struct Report: Codable { let startedAt: Date; let complete: Bool; let steps: [Step] }
    static func runIfRequested(environment: AppEnvironment) {
        guard ProcessInfo.processInfo.environment["LINGOTRIP_LEARNING_V1_FLOW"] == "1", runner == nil,
              environment.workspace != nil, case .signedIn(let identity) = environment.authSession.phase else { return }
        runner = Task { await run(environment: environment, owner: identity.userID) }
    }
    private static func run(environment: AppEnvironment, owner: UUID) async {
        let start = Date.now, evaluationID = UUID()
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdle }
        let output = URL.documentsDirectory.appendingPathComponent("learning-v1-flow.json")
        var steps: [Step] = []
        func save(_ complete: Bool = false) {
            if let data = try? JSONEncoder().encode(Report(startedAt: start, complete: complete, steps: steps)) { try? data.write(to: output, options: .atomic) }
        }
        func check(_ name: String, _ passed: Bool, _ detail: String = "") { steps.append(.init(name: name, passed: passed, detail: detail)); save() }
        do {
            let characters = try await environment.rosterStore.allCharacters()
            guard let original = characters.first(where: { $0.displayName.lowercased() == "ruby" }) ?? characters.first else {
                check("available-character", false); return
            }
            let directory = URL.applicationSupportDirectory.appendingPathComponent("LearningFlowEvaluation/\(evaluationID)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let container = try ModelContainerFactory.makeContainer(storeURL: directory.appendingPathComponent("flow.sqlite"))
            let roster = RosterStore(modelContainer: container), chat = ChatStore(modelContainer: container)
            let economy = EconomyStore(modelContainer: container), items = ItemStore(modelContainer: container)
            let stories = StoryProgressStore(modelContainer: container)
            let id = try await roster.addCharacter(characterID: original.id, card: original.card, difficulty: original.difficultyLevel, isFriend: true)
            guard let character = try await roster.character(id: id) else { check("clone-character", false); return }
            _ = try await economy.updateProfile { $0.currentRegionID = character.card.regionID; $0.hasCompletedOnboarding = true }
            let learning = ConversationLearningSystem(owner: owner, evaluationID: evaluationID, sourceChatStore: chat)
            await learning.load(); learning.setEnabled(true)
            var dependencies = ChatDependencies(accessClient: environment.backendClient,
                chatStore: chat, rosterStore: roster, favorites: FavoritesStore(modelContainer: container), llm: environment.llmRouter,
                dictionary: environment.dictionary, grammarPoints: environment.grammarPoints, speech: environment.speech,
                translator: environment.translator, audioSession: environment.audioSession, memoryStore: MemoryStore(modelContainer: container),
                itemStore: items, economyStore: economy,
                progression: LocalUserStateCoordinator(economyStore: economy, itemStore: items, storyProgressStore: stories),
                voiceMedia: environment.voiceMedia)
            dependencies.learningReplyActivity = { owner, active in
                learning.replyActivity(owner: owner, active: active, environment: environment)
            }
            dependencies.learningEnabled = { true }
            dependencies.learningRecorder = { character, conversation, event in
                learning.observe(character: character, conversation: conversation, event: event, environment: environment)
            }
            let vm = ChatViewModel(character: character, deps: dependencies)
            await vm.load()
            learning.startChallenge(skill: .preference, band: 1, characterID: id)
            check("challenge-started", learning.state.challenge != nil)
            func sendAndWait(_ text: String) async -> Bool {
                let before = vm.messages.filter { $0.role == .assistant }.count
                for letter in text { vm.draft.append(letter) }
                let sentAt = Date.now
                await vm.sendDraft()
                let callsBeforeReply = learning.state.calls.values.reduce(0,+)
                await learning.review(environment: environment, force: true)
                check("main-reply-priority", learning.state.calls.values.reduce(0,+) == callsBeforeReply)
                var typingDelay: Double?
                let deadline = Date.now.addingTimeInterval(120)
                while Date.now < deadline {
                    if typingDelay == nil, vm.isStreaming { typingDelay = Date.now.timeIntervalSince(sentAt) }
                    if vm.messages.filter({ $0.role == .assistant }).count > before, !vm.isStreaming, !vm.isWaitingForUserBurst {
                        check("real-reply-timing", (typingDelay ?? 0) > 0.5 && Date.now.timeIntervalSince(sentAt) > 1,
                              "typing=\(typingDelay ?? -1)s, reply=\(Date.now.timeIntervalSince(sentAt))s")
                        return true
                    }
                    if vm.errorMessage != nil { check("reply-error", false, vm.errorMessage ?? ""); return false }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                vm.cancelPendingReply(); check("reply-timeout", false); return false
            }
            guard await sendAndWait("Hi Ruby!") else { save(true); return }
            await learning.review(environment: environment, force: true)
            check("greeting-keeps-task", learning.state.challenge != nil && learning.state.ledger.evidence.isEmpty, learning.error ?? "")
            guard await sendAndWait("For our weekend trip, I'd choose the park because it is quiet and close to home.") else { save(true); return }
            await learning.review(environment: environment, force: true)
            check("answer-completes-task", learning.state.challenge == nil, learning.error ?? "")
            check("independent-evidence-recorded", learning.state.ledger.evidence.contains { $0.successful && $0.independent })
            check("not-instant-level-up", learning.state.ledger.status(skill: .preference, band: 1, now: .now) != .confirmed)
            let saved = await learning.waitForPersistence(); check("saved", saved)
            let restored = ConversationLearningSystem(owner: owner, evaluationID: evaluationID, sourceChatStore: chat)
            await restored.load()
            check("restored-exact-ledger", restored.state.ledger == learning.state.ledger && restored.state.pending.isEmpty)
            learning.setEnabled(false); check("paused", !learning.state.enabled)
            save(true)
        } catch { check("execution-error", false, "\((error as NSError).domain):\((error as NSError).code)"); save(true) }
    }
}
#endif
