import BackendKit
import CoreKit
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// Place, communication and recency are constraints; age, job and hobbies are not.
enum CafeEncounterPolicy {
    static func eligible(_ person: CharacterDTO, regionID: String) -> Bool {
        guard !person.isMainCharacter, person.contactStatus != .removed,
              person.card.regionID == regionID else { return false }
        // Legacy cards omit languages. An explicit non-English card must not be rewritten.
        guard let languages = person.card.languages, !languages.isEmpty else { return true }
        return languages.contains {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value == "english" || value == "英语" || value == "英文" || value == "en" || value.hasPrefix("en-")
        }
    }
    static func allowsReunion(lastSpokenAt: Date?, now: Date) -> Bool {
        lastSpokenAt.map { now.timeIntervalSince($0) >= 86_400 } ?? true
    }
}

@MainActor
final class SocialEncounterModel: ObservableObject {
    @Published private(set) var character: CharacterDTO?
    @Published private(set) var started = false
    @Published private(set) var busy = false
    @Published private(set) var step = 0
    @Published private(set) var selected: Int?
    @Published private(set) var selections: [Int] = []
    @Published private(set) var reply: SocialDialogueService.Reply?
    @Published private(set) var error: String?
    @Published private(set) var contactMessage: String?
    @Published private(set) var alreadyKnown = false
    @Published private(set) var registrationPending = false
    @Published private(set) var contactBusy = false
    @Published private(set) var completed = false
    let runID = UUID()
    let activity: SceneActivity
    let region: Region
    let deps: HomeDependencies
    private let roster: RosterStore
    private let chat: ChatStore
    private var task: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var contactTask: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?
    private var transcript = ""
    private var cachedReplies: [Int: SocialDialogueService.Reply] = [:]
    private var committedReplies = Set<Int>()
    private let openingID = UUID()
    private let userIDs = [UUID(), UUID()]
    private let replyIDs = [UUID(), UUID()]
    private var pendingPublic: BackendPublicNPC?
    private var generatedCard: CharacterCard?
    private let generatedID = UUID()
    private var generationOrigin: EncounterService.Origin = .local
    private let isFixture: Bool
    var summary: Bool { step == activity.steps.count }
    var responses: [String] { (0..<activity.steps.count).map { cachedReplies[$0]?.chinese ?? "" } }
    var canConnect: Bool { summary && (reply?.acceptsContact == true || character?.isFriend == true) }

    init(activity: SceneActivity, region: Region, deps: HomeDependencies) {
        self.activity = activity; self.region = region; self.deps = deps
        #if DEBUG
        isFixture = ProcessInfo.processInfo.environment["UI_TEST_SOCIAL_FIXTURE"] == "1"
            && ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"] != nil
        #else
        isFixture = false
        #endif
        // App supplies one isolated in-memory container for the UI fixture, so
        // handing off to its real ChatView tests the same stores without user writes.
        roster = deps.rosterStore; chat = deps.chatStore
    }

    func start() {
        guard !busy else { return }
        started = true
        launch {
            if self.character == nil { try await self.prepareCharacter() }
            try await self.obtainReply(index: -1)
        }
    }
    func choose(_ index: Int) {
        guard !busy, !summary, selected == nil,
              activity.steps[step].choices.indices.contains(index) else { return }
        selected = index
        stopSpeech()
        reply = nil
        launch { try await self.performSelection() }
    }
    func retry() {
        guard !busy else { return }
        if selected == nil { start() }
        else { launch { try await self.performSelection() } }
    }
    func advance() {
        guard !busy, let selected, reply != nil, !summary else { return }
        selections.append(selected)
        self.selected = nil
        step += 1
        if summary { completed = true }
    }
    func pause() {
        task?.cancel(); task = nil
        contactTask?.cancel(); contactTask = nil
        contactBusy = false
        registrationTask?.cancel(); registrationTask = nil
        if busy { error = "交流已暂停。回来后可重试，不会重新生成人物。" }
        busy = false
        stopSpeech()
    }
    func stopSpeech() {
        speechTask?.cancel(); speechTask = nil
        let speech = deps.speech
        Task { await speech.stopSpeaking() }
    }
    func speak() {
        guard let reply, let character, !isFixture else { return }
        speechTask?.cancel()
        let speech = deps.speech
        let card = character.card
        speechTask = Task {
            await speech.speak(SpeechRequest(text: reply.english,
                language: AccentMapper.language(forNationality: card.nationality), purpose: .characterDialogue,
                voiceHint: SpeechVoiceHint(stableID: character.id.uuidString.lowercased(), gender: card.gender.rawValue,
                                          nationality: card.nationality)))
        }
    }
    func addFriend() {
        guard canConnect, let character, !character.isFriend, !contactBusy else { return }
        contactBusy = true; contactMessage = nil
        contactTask = Task {
            defer { contactBusy = false }
            do {
                let profile = try await deps.economyStore.profile()
                try Task.checkCancellation()
                try await roster.makeFriend(characterID: character.id, slotLimit: profile.friendSlotLimit)
                self.character = try await roster.character(id: character.id)
                contactMessage = "已加入好友，可以在联系人和消息中继续聊天。"
                if !isFixture, character.publicIdentityRegistered, let registry = deps.npcRegistry {
                    do {
                        try await registry.linkPublicNPC(npcID: character.id, localCharacterID: character.id, status: .friend)
                    } catch { contactMessage = "已在本机加为好友；云端同步暂未完成。" }
                }
            } catch RosterStore.RosterError.friendSlotsFull {
                contactMessage = "好友位已满。这次交流仍会保留，无需删除已有好友。"
            } catch is CancellationError {
            } catch { contactMessage = "暂时未能添加，请重试。原有关系未改动。" }
        }
    }

    private func launch(_ operation: @escaping @MainActor () async throws -> Void) {
        task?.cancel(); error = nil; busy = true
        task = Task {
            do {
                try await operation()
                try Task.checkCancellation()
                busy = false
            } catch is CancellationError {
                // pause() owns visible state. An obsolete task cannot overwrite a retry.
            } catch {
                guard !Task.isCancelled else { return }
                busy = false
                self.error = Self.message(for: error)
            }
        }
    }

    enum PreparationError: Error { case characterUnavailable }

    static func message(for error: Error) -> String {
        if let error = error as? SocialDialogueService.DialogueError {
            return error.localizedDescription
        }
        if error is PreparationError {
            return "暂时未能准备好这次相遇的人物，请稍后重试。"
        }
        if case LLMError.accessRestricted(let message) = error {
            return message
        }
        return "暂时无法连接交流服务，请稍后重试。当前人物和你的选择会保留。"
    }

    private func prepareCharacter() async throws {
        let profile = try await deps.economyStore.profile()
        try Task.checkCancellation()
        if isFixture {
            let card = CharacterCard(name: "Alex", age: 46, gender: .male, nationality: "British",
                regionID: region.id, occupation: "维修技师", hobbies: ["烘焙", "爵士乐"],
                appearance: "", personality: "reserved, kind, practical", avatarAssetName: "avatar_oliver")
            let id = try await roster.addCharacter(characterID: generatedID, card: card,
                difficulty: profile.difficultyLevel, isFriend: false)
            character = try await roster.character(id: id)
            return
        }
        let all = try await roster.allCharacters()
        // A current local person may meet us in a different activity, but never
        // silently restore removed contacts, teleport cities or reset their card.
        let possible = all.filter { CafeEncounterPolicy.eligible($0, regionID: region.id) }
        if pendingPublic == nil && generatedCard == nil {
            // Leave room for unfamiliar library people even with a large local roster.
            let reunions = Double.random(in: 0..<1) < 0.25 ? Array(possible.shuffled().prefix(12)) : []
            for person in reunions {
                let recent = try await chat.recentMessages(characterID: person.id, limit: 1)
                try Task.checkCancellation()
                if CafeEncounterPolicy.allowsReunion(lastSpokenAt: recent.last?.createdAt, now: Date()) {
                    character = person
                    alreadyKnown = !recent.isEmpty
                    break
                }
            }
            if character == nil, let registry = deps.npcRegistry {
                // Deliberately not prefetched on scene appearance. Legacy server
                // records selection as exposure; reserve/reveal is a later migration.
                pendingPublic = try await registry.selectEncounter(context: encounterContext)
                try Task.checkCancellation()
            }
        }
        if character == nil, let npc = pendingPublic {
            if let existing = try await roster.character(id: npc.id) {
                guard existing.contactStatus != .removed else { throw RosterStore.RosterError.identityConflict }
                character = existing
            } else {
                let id = try await roster.addCharacter(characterID: npc.id, travelerID: npc.travelerId,
                    card: PublicNPCAdapter.characterCard(from: npc), difficulty: profile.difficultyLevel, isFriend: false)
                character = try await roster.character(id: id)
            }
        }
        if character == nil {
            if generatedCard == nil {
                generationOrigin = EncounterService.rollOrigin(roll: Double.random(in: 0..<1))
                let generated = try await EncounterService(llm: deps.llm).generateEncounter(
                    origin: generationOrigin, region: region, userLevel: profile.difficultyLevel,
                    existingNames: Set(all.map { $0.card.name }),
                    activityContext: activity.scene.encounterContext)
                try Task.checkCancellation()
                // Local template fallback must not masquerade as a newly generated identity.
                guard !generated.isFallback else { throw PreparationError.characterUnavailable }
                generatedCard = generated.card
            }
            guard let card = generatedCard else { throw RosterStore.RosterError.characterNotFound }
            let id = try await roster.addCharacter(characterID: generatedID, card: card,
                difficulty: profile.difficultyLevel, isFriend: false)
            character = try await roster.character(id: id)
            registrationPending = true
        }
        if let character {
            let recent = try await chat.recentMessages(characterID: character.id, limit: 8)
            alreadyKnown = !recent.isEmpty
            transcript = recent.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        }
    }

    private var encounterContext: BackendNPCEncounterContext {
        .init(regionID: region.id, activityID: SceneActivity.encounterPoolID, category: "social")
    }
    private var sceneContext: String {
        "城市：\(region.nameZh)。\(activity.scene.title) · \(activity.title)。\(activity.steps[0].context)"
    }
    private func performSelection() async throws {
        guard let selected, let character else { return }
        let choice = activity.steps[step].choices[selected]
        try Task.checkCancellation()
        try await chat.appendActivityLineIfNeeded(messageID: userIDs[step], characterID: character.id,
            role: .user, text: choice.english, translation: choice.chinese, context: sceneContext)
        try Task.checkCancellation()
        try await obtainReply(index: step)
    }
    private func obtainReply(index: Int) async throws {
        guard let character else { throw RosterStore.RosterError.characterNotFound }
        let choice = index >= 0 ? selected.map { activity.steps[index].choices[$0] } : nil
        if cachedReplies[index] == nil {
            if isFixture {
                cachedReplies[index] = .init(
                    english: index < 0 ? "Hello! Taking a little break too?" : index == 0 ? "Of course. A short break makes a busy day better." : selected == 0 ? "I'd like that. Let's keep in touch." : "It was lovely meeting you. Take care!",
                    chinese: index < 0 ? "你好！你也来歇一会儿吗？" : index == 0 ? "当然。忙碌的一天，歇一会儿很有帮助。" : selected == 0 ? "好啊，我们保持联系吧。" : "很高兴认识你，保重！",
                    acceptsContact: index == 1 && selected == 0)
            } else {
                cachedReplies[index] = try await SocialDialogueService(llm: deps.llm).reply(
                    card: character.card, context: sceneContext, history: transcript,
                    userLine: choice?.english, invitesContact: index == 1 && selected == 0,
                    alreadyKnown: alreadyKnown, difficulty: character.difficultyLevel)
            }
        }
        try Task.checkCancellation()
        guard let result = cachedReplies[index] else { throw SocialDialogueService.DialogueError.invalidReply }
        reply = result
        if !committedReplies.contains(index) {
            try await chat.appendActivityLineIfNeeded(messageID: index < 0 ? openingID : replyIDs[index],
                characterID: character.id, role: .assistant, text: result.english,
                translation: result.chinese, context: sceneContext)
            try Task.checkCancellation()
            committedReplies.insert(index)
            if let choice { transcript += "\nuser: \(choice.english)" }
            transcript += "\nassistant: \(result.english)"
        }
        startRegistration()
    }
    private func startRegistration() {
        guard registrationPending, !isFixture, registrationTask == nil,
              let character, let registry = deps.npcRegistry else { return }
        // Portrait registration must not hold the dialogue's loading state open.
        registrationTask = Task {
            defer { registrationTask = nil }
            do {
                let publicNPC = try await registry.registerEncounterNPC(id: character.id,
                    card: PublicNPCAdapter.backendCard(from: character.card), context: encounterContext)
                try Task.checkCancellation()
                let latest = try await roster.character(id: character.id)
                try await registry.linkPublicNPC(npcID: publicNPC.id, localCharacterID: character.id,
                    status: latest?.contactStatus == .removed ? .removed : latest?.isFriend == true ? .friend : .candidate)
                try await roster.applyPublicIdentity(characterID: character.id, travelerID: publicNPC.travelerId,
                                                     card: PublicNPCAdapter.characterCard(from: publicNPC))
                self.character = try await roster.character(id: character.id)
                registrationPending = false
            } catch {
                // Keep this exact local identity; existing foreground registration
                // coordinator retries missing portraits/network without replacing it.
            }
        }
    }
}
