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
    private var task: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var contactTask: Task<Void, Never>?
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
        // UI fixtures use the App-provided isolated in-memory stores.
        roster = deps.rosterStore
    }

    func start() {
        guard !busy, !isSolitude, !openingReady else { return }
        if revealAt == nil { revealAt = Date().addingTimeInterval(deps.tutorial == nil ? 15 : 1.5) }
        started = true
        launch {
            if let tutorial = self.deps.tutorial {
                if self.character == nil { try await self.prepareCharacter() }
                try await self.loadChapter(0)
                self.openingReady = true
                tutorial.onEvent("encounter")
                return
            }
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
            deps.tutorial?.onEvent("summary")
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
        guard let beat = currentBeat, let character, !isFixture else { return }
        speechTask?.cancel()
        let speech = deps.speech
        let card = character.card
        speechTask = Task {
            await speech.speak(SpeechRequest(text: beat.english,
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
                deps.tutorial?.onEvent("friend")
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
        if isFixture || deps.tutorial != nil {
            let card = deps.tutorial != nil
                ? CharacterCard(name: "Elliot Shaw", age: 38, gender: .male, nationality: "British",
                    regionID: region.id, occupation: "bus accessibility route surveyor",
                    hobbies: ["making jam", "collecting bad jokes"], appearance: "",
                    personality: "Practical and blunt, with dry humour.", avatarAssetName: "tutorial-elliot")
                : CharacterCard(name: "Alex", age: 46, gender: .male, nationality: "British",
                    regionID: region.id, occupation: "bicycle mechanic", hobbies: ["烘焙", "爵士乐"],
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
            let recent = try await deps.chatStore.recentMessages(characterID: character.id, limit: 1)
            let metBefore = try history.receipts().contains { $0.characterID == character.id }
            alreadyKnown = character.isFriend || !recent.isEmpty || metBefore
        }
    }

    private var encounterContext: BackendNPCEncounterContext {
        .init(regionID: region.id, activityID: authoredActivity.id, category: "social")
    }
    private func performSelection() async throws {
        guard let selected else { return }
        let source = pendingStage - 1
        if selections.count == source { selections.append(selected) }
        try await loadChapter(pendingStage)
        self.selected = nil
    }

    private func loadChapter(_ stage: Int) async throws {
        guard let character else { throw RosterStore.RosterError.characterNotFound }
        if chapters.count == stage {
            let part: EncounterChapter
            if deps.tutorial != nil {
                part = try Self.tutorialChapter(stage, selections: selections, location: authoredActivity.title)
            } else if isFixture {
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
        try Task.checkCancellation()
        beatIndex = index
    }
    static func tutorialChapter(_ stage: Int, selections: [Int], location: String) throws -> EncounterChapter {
        let opening = [
            EncounterChapter.Beat(speaker: "narrator", english: "A folded map slips off a nearby seat. You catch it before the wind does.", chinese: "一张折叠地图从旁边的座位滑落，你赶在风吹走它之前接住了。"),
            EncounterChapter.Beat(speaker: "npc", english: "Thanks! I marked a few quiet places on it. Do you like exploring?", chinese: "谢谢！我在上面标了几个安静的地方。你喜欢探索吗？")
        ]
        let middle = [
            EncounterChapter.Beat(speaker: "narrator", english: "Elliot smooths out the map and points to a tiny drawing.", chinese: "Elliot 展平地图，指了指上面的一幅小画。"),
            EncounterChapter.Beat(speaker: "npc", english: selections.first == 0 ? "Same here. I found this corner by taking a wrong turn." : "This one has a great view. I drew it so I wouldn't forget.", chinese: selections.first == 0 ? "我也是。我是拐错弯才发现这个角落的。" : "这里景色很好。我画下来，免得自己忘了。")
        ]
        let ending = [
            EncounterChapter.Beat(speaker: "narrator", english: "Elliot folds the map carefully this time, smiling at your reply.", chinese: "听了你的回答，Elliot 笑了，这次仔细地把地图折好。"),
            EncounterChapter.Beat(speaker: "npc", english: "Thanks for rescuing my map. It's been lovely chatting with you!", chinese: "谢谢你救下我的地图，很高兴和你聊了聊！")
        ]
        return EncounterChapter(title: "风里的地图", outline: location,
            beats: stage == 0 ? opening : stage == 1 ? middle : ending,
            choices: stage == 2 ? [] : [
                .init(english: stage == 0 ? "Yes, especially quiet places." : "A wrong turn can be a good thing.", chinese: stage == 0 ? "喜欢，尤其是安静的地方。" : "拐错弯也可能是好事。"),
                .init(english: stage == 0 ? "Which place is your favourite?" : "I'll keep my eyes open.", chinese: stage == 0 ? "你最喜欢哪个地方？" : "我也会留意身边的风景。")
            ])
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
