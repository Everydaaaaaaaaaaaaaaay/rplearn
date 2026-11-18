import BackendKit
import DomainKit
import Foundation
import PersistenceKit
import SpeechKit
import SwiftUI

@MainActor
final class CityOutingModel: ObservableObject {
    @Published private(set) var snapshot: BackendOuting?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var hasRecoverableOuting = false
    @Published private(set) var synchronizationMessage: String?
    @Published private(set) var conflict = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var character: CharacterDTO?
    @Published private(set) var contactBusy = false
    @Published private(set) var contactMessage: String?
    private(set) var archive: CityOutingArchive
    let region: Region
    let deps: HomeDependencies
    private let namespace: String
    private let gateway: any OutingGateway
    private var requestTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var generation = UUID()
    private let speechQueue: SpeechPlaybackQueue
    private var speechIDs: [String: UUID] = [:]
    private var autoRead = true

    var activity: SceneActivity {
        .init(id: archive.place.id, scene: .park, title: archive.place.titleZh, symbol: "mappin.and.ellipse",
              introduction: "去这里走走，看看今天会发生什么。", steps: [], closing: "把这一刻留在旅途中。")
    }
    var isPreparing: Bool { archive.cancelled != true && snapshot == nil && busy }
    var isRunning: Bool { archive.cancelled != true && (pendingCount > 0 || (snapshot.map { ![.completed, .abandoned].contains($0.status) } ?? true)) }
    var chapters: [EncounterChapter] { snapshot.map(PlaceOutingProgress.chapters) ?? [] }
    var currentBeats: [BackendOutingBeat] { snapshot.map(PlaceOutingProgress.beats) ?? [] }
    var choices: [BackendOutingStory.Node.Choice] {
        guard let snapshot, snapshot.mode == .first_meeting,
              snapshot.beatIndex == currentBeats.count - 1, snapshot.status != .reserved else { return [] }
        return snapshot.story?.nodes.first { $0.id == snapshot.nodeId }?.choices ?? []
    }
    var isAtEnding: Bool {
        guard let snapshot, snapshot.status != .reserved else { return false }
        return snapshot.mode == .solitude || (snapshot.beatIndex == currentBeats.count - 1 && choices.isEmpty)
    }

    init(archive: CityOutingArchive, region: Region, deps: HomeDependencies,
         namespace: String, gateway: any OutingGateway) {
        self.archive = archive; self.region = region; self.deps = deps
        self.namespace = namespace; self.gateway = gateway
        snapshot = archive.snapshot; pendingCount = archive.pending.count
        speechQueue = SpeechPlaybackQueue(speech: deps.speech)
    }

    func start() {
        guard !busy, archive.cancelled != true, !hasRecoverableOuting else { return }
        error = nil
        if snapshot != nil {
            flush(); recordCompletionIfNeeded()
            if snapshot?.status != .reserved { Task { await prepareLocalCharacter() } }
            if snapshot?.beatIndex == -1, snapshot?.mode != .solitude { enqueue(.read, beatIndex: 0) }
            return
        }
        do { try archive.save(namespace: namespace) }
        catch { self.error = "外出记录暂时无法保存，请重试。"; return }
        busy = true
        requestTask = Task {
            defer { busy = false }
            do {
                let result: BackendOuting
                do {
                    result = try await gateway.startOuting(id: archive.runID, releaseID: archive.releaseID, placeID: archive.place.id)
                } catch let failure as BackendClientError where failure.code == "OUTING_ALREADY_ACTIVE" {
                    guard let active = try await gateway.activeOuting() else { throw failure }
                    try Task.checkCancellation()
                    try recoverActiveOuting(active)
                    return
                }
                try Task.checkCancellation()
                try PlaceOutingProgress.validate(result)
                guard result.runId == archive.runID, result.placeId == archive.place.id,
                      result.releaseId == archive.releaseID, result.cityId == region.id else {
                    throw PlaceOutingProgress.ProgressError.invalidContent
                }
                var next = archive; next.snapshot = result
                try next.save(namespace: namespace)
                archive = next; snapshot = result
                if ![.completed, .abandoned].contains(result.status), result.mode != .solitude, result.beatIndex == -1 {
                    enqueue(.read, beatIndex: 0)
                }
                recordCompletionIfNeeded()
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func recoverActiveOuting(_ active: BackendOuting) throws {
        try PlaceOutingProgress.validate(active)
        guard ![.completed, .abandoned].contains(active.status),
              deps.regionCatalog.region(id: active.cityId) != nil else { throw PlaceOutingProgress.ProgressError.invalidContent }
        if let current = try CityOutingArchive.load(namespace: namespace), current.runID == archive.runID,
           current.snapshot == nil, current.pending.isEmpty, current.cancelled != true {
            // Only replace the unaccepted draft. The place list will open the saved outing in its original scene.
            try CityOutingArchive(restoring: active).save(namespace: namespace)
        }
        hasRecoverableOuting = true
        error = "另一台设备已有外出进度，请返回地点页恢复。"
    }

    func confirmVisibleOpening() {
        guard let snapshot, snapshot.status == .reserved,
              snapshot.mode == .solitude || snapshot.beatIndex == currentBeats.count - 1 else { return }
        enqueue(.presented)
        Task { await prepareLocalCharacter() }
    }
    func advance() {
        guard let snapshot, !conflict, ![.completed, .abandoned].contains(snapshot.status) else { return }
        if snapshot.mode != .solitude && snapshot.beatIndex + 1 < currentBeats.count {
            enqueue(.read, beatIndex: snapshot.beatIndex + 1)
        } else if isAtEnding { enqueue(.complete); recordCompletionIfNeeded() }
    }
    func choose(_ index: Int) {
        guard choices.indices.contains(index), let snapshot, !conflict else { return }
        enqueue(.choice, choiceID: "\(snapshot.nodeId):\(index)")
        if self.snapshot?.beatIndex == -1 { enqueue(.read, beatIndex: 0) }
    }
    func abandon() {
        guard !hasRecoverableOuting else { return }
        if snapshot != nil { enqueue(.abandon); recordCompletionIfNeeded(); return }
        requestTask?.cancel()
        archive.cancelled = true
        do { try archive.save(namespace: namespace) }
        catch { self.error = "出发状态暂未保存，请重试。" }
        // The next place-list load checks the server's active session in case a cancelled request reached it.
    }

    private func enqueue(_ type: BackendOutingOperation.Kind, beatIndex: Int? = nil, choiceID: String? = nil) {
        guard let snapshot, !conflict else { return }
        do {
            let operation = BackendOutingOperation(expectedRevision: snapshot.revision, type: type, beatIndex: beatIndex, choiceID: choiceID)
            let result = try PlaceOutingProgress.apply(operation, to: snapshot)
            var next = archive; next.snapshot = result; next.pending.append(operation)
            try next.save(namespace: namespace)
            archive = next; self.snapshot = result; pendingCount = next.pending.count
            error = nil
            flush()
        } catch { self.error = "进度暂时无法保存，原记录已保留。请重试。" }
    }

    func retrySynchronization() { synchronizationMessage = nil; flush() }
    private func flush() {
        guard syncTask == nil, !conflict, !archive.pending.isEmpty else { return }
        let currentGeneration = generation
        syncTask = Task {
            defer { if generation == currentGeneration { syncTask = nil } }
            do {
                while let operation = archive.pending.first {
                    let response = try await gateway.applyOuting(id: archive.runID, operation: operation)
                    try Task.checkCancellation()
                    guard generation == currentGeneration else { return }
                    try PlaceOutingProgress.validate(response)
                    guard response.runId == archive.runID, response.revision == operation.expectedRevision + 1,
                          archive.pending.first?.id == operation.id else { throw PlaceOutingProgress.ProgressError.staleRevision }
                    var next = archive; next.pending.removeFirst()
                    if next.pending.isEmpty {
                        guard response == snapshot else { throw PlaceOutingProgress.ProgressError.staleRevision }
                        next.snapshot = response
                    }
                    try next.save(namespace: namespace)
                    archive = next; pendingCount = next.pending.count
                }
                synchronizationMessage = nil
            } catch is CancellationError {
            } catch let failure as BackendClientError where ["OUTING_CONFLICT", "OUTING_NOT_FOUND", "GUEST_ALREADY_CLAIMED"].contains(failure.code ?? "") {
                conflict = true
                synchronizationMessage = "另一台设备的进度已有变化。本机选择已保留，可恢复服务器进度。"
            } catch is PlaceOutingProgress.ProgressError {
                conflict = true
                synchronizationMessage = "进度与服务器不一致。本机选择已保留，可恢复服务器进度。"
            } catch {
                synchronizationMessage = "选择已保存在本机，联网后可继续同步。"
            }
        }
    }

    func restoreServerProgress() {
        guard !busy else { return }
        busy = true; requestTask?.cancel(); syncTask?.cancel(); syncTask = nil; generation = UUID()
        requestTask = Task {
            defer { busy = false }
            do {
                let result = try await gateway.outing(id: archive.runID)
                try PlaceOutingProgress.validate(result)
                guard result.runId == archive.runID, result.placeId == archive.place.id,
                      result.releaseId == archive.releaseID else { throw PlaceOutingProgress.ProgressError.invalidContent }
                // Preserve the divergent local choices as a separate, read-only recovery copy.
                let recovery = CityOutingArchive.key(namespace: namespace) + ".conflict." + UUID().uuidString
                UserDefaults.standard.set(try JSONEncoder().encode(archive), forKey: recovery)
                var next = archive; next.snapshot = result; next.pending = []
                try next.save(namespace: namespace)
                archive = next; snapshot = result; pendingCount = 0; conflict = false
                synchronizationMessage = nil; error = nil
                if result.mode != .solitude && result.beatIndex == -1 { enqueue(.read, beatIndex: 0) }
                recordCompletionIfNeeded()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func recordCompletionIfNeeded() {
        guard let snapshot, [.completed, .abandoned].contains(snapshot.status) else { return }
        do { _ = try ActivityJournal(namespace: namespace, city: snapshot.cityId).endPlaceOuting(snapshot) }
        catch { self.error = "外出已结束，足迹暂未保存。重试会保留原有记录。" }
    }
    func retry() { if let status = snapshot?.status, [.completed, .abandoned].contains(status) { recordCompletionIfNeeded() } else { start() } }

    private func prepareLocalCharacter() async {
        guard let npc = snapshot?.npc else { return }
        do {
            if let existing = try await deps.rosterStore.character(id: npc.id) {
                try await CityActivityRelease.bundled()?.migrateContacts(in: deps.rosterStore, characterID: existing.id)
                character = try await deps.rosterStore.character(id: existing.id)
                return
            }
            let profile = try await deps.economyStore.profile()
            let id = try await deps.rosterStore.addCharacter(characterID: npc.id, travelerID: npc.travelerId,
                card: PublicNPCAdapter.characterCard(from: npc), difficulty: profile.difficultyLevel, isFriend: false)
            try await CityActivityRelease.bundled()?.migrateContacts(in: deps.rosterStore, characterID: id)
            character = try await deps.rosterStore.character(id: id)
        } catch { contactMessage = "人物资料暂未保存，故事进度仍会保留。" }
    }
    func addFriend() {
        guard snapshot?.status == .completed, pendingCount == 0, !contactBusy else { return }
        contactBusy = true; contactMessage = nil
        Task {
            defer { contactBusy = false }
            await prepareLocalCharacter()
            guard let character, character.contactStatus != .removed else { return }
            do {
                let profile = try await deps.economyStore.profile()
                try await deps.rosterStore.makeFriend(characterID: character.id, slotLimit: profile.friendSlotLimit)
                self.character = try await deps.rosterStore.character(id: character.id)
                try await deps.npcRegistry?.linkPublicNPC(npcID: character.id, localCharacterID: character.id, status: .friend)
                contactMessage = "已加入好友，可以继续聊天。"
            } catch RosterStore.RosterError.friendSlotsFull { contactMessage = "好友位已满，这次相遇仍会保留。" }
            catch { contactMessage = "本机关系已保留，云端暂未同步，请稍后重试。" }
        }
    }

    func updateAutoReading(enabled: Bool) {
        autoRead = enabled
        guard let snapshot, let npc = snapshot.npc else { return }
        var items: [SpeechPlaybackQueue.Item] = []
        for (stage, chapter) in chapters.enumerated() {
            let last = stage == chapters.count - 1 ? snapshot.beatIndex : chapter.beats.count - 1
            for (index, beat) in chapter.beats.enumerated() where index <= last {
                let key = "\(stage):\(index)"; let id = speechIDs[key] ?? UUID(); speechIDs[key] = id
                let narrator = StoryVoiceCasting.isNarrator(beat.speaker)
                items.append(.init(id: id, request: SpeechRequest(text: beat.english,
                    language: narrator ? "en-GB" : AccentMapper.language(forNationality: npc.card.nationality),
                    purpose: .characterDialogue, voiceHint: narrator ? StoryVoiceCasting.narrator : .init(
                        stableID: npc.id.uuidString.lowercased(), gender: npc.card.gender,
                        nationality: npc.card.nationality, supertonicVoice: npc.card.readingVoice))))
            }
        }
        speechQueue.configure(enabled: autoRead, existingIDs: items.dropLast().map(\.id)); speechQueue.observe(items)
    }
    @discardableResult func stopSpeech() -> Task<Void, Never>? { speechQueue.interrupt() }
    func pause() {
        requestTask?.cancel(); syncTask?.cancel(); syncTask = nil; generation = UUID()
        busy = false; stopSpeech()
    }
}
