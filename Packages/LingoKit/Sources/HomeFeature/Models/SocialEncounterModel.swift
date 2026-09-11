import BackendKit
import CoreKit
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

@MainActor
final class SocialEncounterModel: ObservableObject {
    @Published private(set) var character: CharacterDTO?
    @Published private(set) var started = false
    @Published private(set) var busy = false
    @Published private(set) var step = 0
    @Published private(set) var beatIndex = 0
    @Published private(set) var selected: Int?
    @Published private(set) var selections: [Int] = []
    @Published private(set) var chapters: [EncounterChapter] = []
    var currentBeat: EncounterChapter.Beat? {
        guard chapters.indices.contains(step), chapters[step].beats.indices.contains(beatIndex) else { return nil }
        return chapters[step].beats[beatIndex]
    }
    var reply: SocialDialogueService.Reply? {
        currentBeat.map { .init(english: $0.english, chinese: $0.chinese) }
    }
    var atChoice: Bool { !summary && chapters.indices.contains(step) && !chapters[step].choices.isEmpty && beatIndex == chapters[step].beats.count - 1 }
    var chapterCount: Int { alreadyKnown ? 1 : 3 }
    var atEnding: Bool { chapters.indices.contains(step) && chapters[step].choices.isEmpty && beatIndex == chapters[step].beats.count - 1 }
    @Published private(set) var error: String?
    @Published private(set) var contactMessage: String?
    @Published private(set) var alreadyKnown = false
    @Published private(set) var registrationPending = false
    @Published private(set) var contactBusy = false
    @Published private(set) var completed = false
    @Published private(set) var revealAt: Date?
    @Published private(set) var isSolitude = false
    @Published private(set) var openingReady = false
    private let history: ActivityEncounterHistory
    var canReveal: Bool { canReveal(at: Date()) }
    func canReveal(at date: Date) -> Bool {
        started && (revealAt.map { date >= $0 } ?? false) && (isSolitude || openingReady)
    }
    let runID = UUID()
    private let authoredActivity: SceneActivity
    var activity: SceneActivity {
        let steps = chapters.prefix(2).map { part in
            SceneActivity.Step(context: part.title, question: "你想怎么做？", choices: part.choices.map {
                .init(english: $0.english, chinese: $0.chinese, response: "")
            })
        }
        guard steps.count == 2 else { return authoredActivity }
        return SceneActivity(id: authoredActivity.id, scene: authoredActivity.scene,
            title: chapters.first?.title ?? authoredActivity.title, symbol: authoredActivity.symbol,
            introduction: authoredActivity.introduction, steps: steps, closing: "把这一刻留在旅途中。")
    }
    let region: Region
    let deps: HomeDependencies
    private let roster: RosterStore
    private let chat: ChatStore
    private var task: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var contactTask: Task<Void, Never>?
    private let userIDs = [UUID(), UUID()]
    private let beatIDs = (0..<3).map { _ in (0..<6).map { _ in UUID() } }
    private var pendingStage = 0
    private var library: AuthoredEncounterLibrary?
    private var pendingPublic: BackendPublicNPC?
    private let generatedID = UUID()
    private let encounterRoll: @Sendable () -> Double
    private let isFixture: Bool
    #if DEBUG
    private var fixtureFailed = false
    #endif
    var summary: Bool { completed }
    var responses: [String] { chapters.dropFirst().map { $0.beats.map(\.chinese).joined(separator: "\n") } }
    var canConnect: Bool { summary && character != nil }

    init(activity: SceneActivity, region: Region, deps: HomeDependencies, namespace: String,
         encounterRoll: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
         library: AuthoredEncounterLibrary? = nil) {
        self.library = library
        self.encounterRoll = encounterRoll
        self.authoredActivity = activity; self.region = region; self.deps = deps
        history = ActivityEncounterHistory(namespace: namespace, city: region.id)
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
        guard !busy, !isSolitude, !openingReady else { return }
        if revealAt == nil { revealAt = Date().addingTimeInterval(15) }
        started = true
        launch {
            var roll = self.encounterRoll()
            #if DEBUG
            if self.isFixture {
                roll = ProcessInfo.processInfo.environment["UI_TEST_SOLITUDE"] == "1" ? 0.99 : 0
            }
            #endif
            let receipt = try self.history.reserve(runID: self.runID, roll: roll)
            #if DEBUG
            if self.isFixture, ProcessInfo.processInfo.environment["UI_TEST_JOURNEY_FAILURE_FIRST"] == "1", !self.fixtureFailed {
                self.fixtureFailed = true
                throw SocialDialogueService.DialogueError.invalidReply
            }
            if self.isFixture, ProcessInfo.processInfo.environment["UI_TEST_JOURNEY_DELAY"] == "1" {
                try await Task.sleep(for: .seconds(18))
            }
            #endif
            if !receipt.encountersPerson {
                try self.history.complete(runID: self.runID, characterID: nil)
                self.isSolitude = true
                return
            }
            if self.character == nil { try await self.prepareCharacter() }
            if self.isSolitude { return }
            try await self.loadChapter(0)
            try self.history.complete(runID: self.runID, characterID: self.character?.id)
            self.openingReady = true
        }
    }
    func choose(_ index: Int) {
        guard !busy, atChoice, selected == nil, chapters[step].choices.indices.contains(index) else { return }
        selected = index
        stopSpeech()
        pendingStage = step + 1
        launch { try await self.performSelection() }
    }
    func retry() {
        guard !busy else { return }
        if !openingReady { start() }
        else if selected != nil { launch { try await self.performSelection() } }
        else { launch { try await self.revealBeat(self.beatIndex) } }
    }
    func advance() {
        guard !busy, !summary, chapters.indices.contains(step) else { return }
        if beatIndex + 1 < chapters[step].beats.count {
            stopSpeech()
            launch { try await self.revealBeat(self.beatIndex + 1) }
        } else if atEnding {
            stopSpeech()
            completed = true
        }
    }
    func pause() {
        task?.cancel(); task = nil
        contactTask?.cancel(); contactTask = nil
        contactBusy = false
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
        guard let reply, currentBeat?.speaker == "npc", let character, !isFixture else { return }
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
        if library == nil { library = try AuthoredEncounterLibrary.bundled() }
        guard let library, let registry = deps.npcRegistry else { throw PreparationError.characterUnavailable }
        if pendingPublic == nil {
            pendingPublic = try await registry.selectAuthoredEncounter(context: encounterContext,
                libraryVersion: library.version, runID: runID)
            try Task.checkCancellation()
        }
        guard let npc = pendingPublic else {
            try history.completeUnavailable(runID: runID)
            isSolitude = true
            return
        }
        guard library.entries[npc.id]?.story.actionId == authoredActivity.id else { throw PreparationError.characterUnavailable }
        if let existing = try await roster.character(id: npc.id) {
            guard existing.contactStatus != .removed else { throw RosterStore.RosterError.identityConflict }
            character = existing
        } else {
            let id = try await roster.addCharacter(characterID: npc.id, travelerID: npc.travelerId,
                card: PublicNPCAdapter.characterCard(from: npc), difficulty: profile.difficultyLevel, isFriend: false)
            character = try await roster.character(id: id)
        }
        if let character {
            let recent = try await chat.recentMessages(characterID: character.id, limit: 1)
            alreadyKnown = character.isFriend || !recent.isEmpty
        }
    }

    private var encounterContext: BackendNPCEncounterContext {
        .init(regionID: region.id, activityID: authoredActivity.id, category: "social")
    }
    private var sceneContext: String {
        "城市：\(region.nameZh)。\(authoredActivity.scene.title) · \(authoredActivity.title)。本次相遇：\(chapters.first?.title ?? authoredActivity.title)。"
    }
    private func visibleContext(through index: Int) -> String {
        guard chapters.indices.contains(step) else { return sceneContext }
        let narration = chapters[step].beats.prefix(index + 1)
            .filter { $0.speaker == "narrator" }.map(\.english).joined(separator: " ")
        return narration.isEmpty ? sceneContext : sceneContext + "\n已读场景：" + narration
    }
    private func performSelection() async throws {
        guard let selected, let character else { return }
        let source = pendingStage - 1
        let choice = chapters[source].choices[selected]
        try await chat.appendActivityLineIfNeeded(messageID: userIDs[source], characterID: character.id,
            role: .user, text: choice.english, translation: choice.chinese, context: visibleContext(through: beatIndex))
        if selections.count == source { selections.append(selected) }
        try await loadChapter(pendingStage)
        self.selected = nil
    }

    private func loadChapter(_ stage: Int) async throws {
        guard let character else { throw RosterStore.RosterError.characterNotFound }
        if chapters.count == stage {
            let part: EncounterChapter
            if isFixture {
                part = try Self.fixtureChapter(stage)
            } else {
                guard let library else { throw PreparationError.characterUnavailable }
                part = try library.chapter(characterID: character.id, actionID: authoredActivity.id,
                    choices: selections, reunion: alreadyKnown)
            }
            chapters.append(part)
        }
        try Task.checkCancellation()
        step = stage
        beatIndex = 0
        try await revealBeat(0)
    }
    private func revealBeat(_ index: Int) async throws {
        guard let character else { return }
        let beat = chapters[step].beats[index]
        if beat.speaker == "npc" {
            try await chat.appendActivityLineIfNeeded(messageID: beatIDs[step][index], characterID: character.id,
                role: .assistant, text: beat.english, translation: beat.chinese, context: visibleContext(through: index))
        }
        try Task.checkCancellation()
        beatIndex = index
    }
    static func fixtureChapter(_ stage: Int) throws -> EncounterChapter {
        let beats: [[String: String]] = [
            ["speaker":"narrator","english":"A gust of wind lifts a folded map off the table. It catches beneath a nearby chair.","chinese":"一阵风把桌上的折叠地图吹了起来，卡在旁边的椅子下。"],
            ["speaker":"npc","english":"That map seems keen to explore without us. Could you hold this corner while I flatten it?","chinese":"这张地图好像想自己去探险。你能帮我按住这一角，让我把它铺平吗？"],
            ["speaker":"narrator","english":"The paper settles between two cups. A pencilled route appears beside the bridge.","chinese":"纸张在两只杯子之间平整下来，桥边有一条铅笔画的路线。"],
            ["speaker":"npc","english":stage == 2 ? "Thanks for the help. A small detour turned into the best part of my break. Enjoy your walk!" : "I drew this route myself. I like finding quiet corners, even when getting there takes a little longer.","chinese":stage == 2 ? "谢谢你帮忙。这个小插曲成了我休息时最有趣的部分，祝你散步愉快！" : "这条路线是我自己画的。我喜欢找安静的角落，哪怕绕点路。"]
        ]
        let choices = stage == 2 ? [] : [["english":"Let's check the route together.","chinese":"我们一起看看这条路线吧。"],["english":"What makes that corner special?","chinese":"那个角落有什么特别的地方？"]]
        let data = try JSONSerialization.data(withJSONObject: ["title":"风里的地图","outline":"地图被吹起，两人一起整理路线，带着各自的发现告别。","beats":beats,"choices":choices])
        return try EncounterChapter.decode(String(decoding: data, as: UTF8.self), stage: stage)
    }
}
