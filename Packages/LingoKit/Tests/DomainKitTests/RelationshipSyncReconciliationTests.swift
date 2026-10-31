import Foundation
import SwiftData
import Testing
import PersistenceKit
@testable import DomainKit

@Suite("Relationship sync reconciliation")
struct RelationshipSyncReconciliationTests {
    let date = Date(timeIntervalSince1970: 1_793_534_400)

    private var signal: RelationshipSignal {
        RelationshipSignal(warmth: 0.4, responsiveness: 0.5, respect: 0.5, empathy: 0.3,
            reciprocity: 0.3, disclosure: 0, resonance: 0.2, engagement: 0.5,
            boundaryHarm: 0, repair: 0, significance: 0.4, confidence: 0.9, reasonZh: "认真回应对方")
    }

    @Test("同一真实输入在同一快照上重放产生相同事件编号与结果")
    func engineUsesStableEvidenceEventIdentity() {
        let id = UUID()
        let first = RelationshipEngine.apply(signal, to: .initial, source: .textChat,
            messageID: id, messageCreatedAt: date, messageOrderIndex: 1, at: date)
        let second = RelationshipEngine.apply(signal, to: .initial, source: .textChat,
            messageID: id, messageCreatedAt: date, messageOrderIndex: 1, at: date)
        #expect(first == second)
        #expect(first.recentEvents.last?.id == id)
    }

    @Test("真实聊天信号重放到远端赴约之后，双方变化保留且赴约不重复")
    func rebasesGenuineChatOntoAppointment() throws {
        let appointmentID = UUID(), chatID = UUID()
        var remote = RelationshipEngine.apply(signal, to: .initial, source: .appointment,
            messageID: appointmentID, messageCreatedAt: date, messageOrderIndex: -1, at: date)
        remote.settledAppointmentIDs = [appointmentID]
        let input = try RelationshipReplay.reviewed(signal, source: .textChat, messageID: chatID,
            messageCreatedAt: date.addingTimeInterval(60), messageOrderIndex: 4, at: date.addingTimeInterval(60))
        let local = try RelationshipReplay.apply([input], to: .initial)
        let result = try ContentRelationshipReconciliation.reconcile(currentJSON: payload(remote, note: "remote"),
            desiredJSON: payload(local, note: "my note"), inputs: [input], replay: RelationshipReplay.apply)
        let actual = try relationship(result)
        let expected = try RelationshipReplay.apply([input], to: remote)
        #expect(actual == expected)
        #expect(actual.settledAppointmentIDs == [appointmentID])
        #expect(actual.recentEvaluatedMessageIDs?.contains(chatID) == true)
        #expect(actual.recentEvents.filter { $0.id == appointmentID }.count == 1)
        #expect(try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] != nil)
        #expect(result.contains("my note"))
        #expect(try RelationshipReplay.apply([input], to: actual) == actual)
    }

    @Test("其他设备已经接受同一消息时不再加分；中性联系沿用原引擎")
    func deduplicatesAcceptedMessageAndReplaysContact() throws {
        let input = try RelationshipReplay.reviewed(signal, source: .voiceChat, messageID: UUID(),
            messageCreatedAt: date, messageOrderIndex: 2, at: date)
        let accepted = try RelationshipReplay.apply([input], to: .initial)
        #expect(try RelationshipReplay.apply([input], to: accepted) == accepted)
        let contact = RelationshipReplayInput.contact(messageID: UUID(), messageCreatedAt: date.addingTimeInterval(60),
            messageOrderIndex: 3, at: date.addingTimeInterval(60))
        let actual = try RelationshipReplay.apply([contact], to: accepted)
        let expected = RelationshipEngine.recordContact(in: accepted, messageID: contact.messageID,
            messageCreatedAt: contact.messageCreatedAt, messageOrderIndex: contact.messageOrderIndex,
            at: contact.evaluatedAt, calendar: contact.calendar)
        #expect(actual == expected)
    }

    @Test("重放保留原来的历法和具名时区，不在重试设备上换日界")
    func preservesOriginalCalendarAndTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        calendar.firstWeekday = 2
        let input = try RelationshipReplay.reviewed(signal, source: .textChat, messageID: UUID(),
            messageCreatedAt: date, messageOrderIndex: 1, at: date, calendar: calendar)
        let restored = try RelationshipReplayInput.decodeList(RelationshipReplayInput.encodeList([input]))
        #expect(restored.first?.calendar == calendar)
        #expect(try RelationshipReplay.apply(restored, to: .initial).activityDayStart == calendar.startOfDay(for: date))
    }

    @Test("角色城市决定共同日界；上海与洛杉矶旧快照迁移后同一天额度一致")
    func characterDayPreservesCapsAcrossLegacyDeviceCalendars() throws {
        let calendar = RelationshipCalendar.forRegionID("london")
        #expect(calendar.timeZone.identifier == "Europe/London")
        let lastInteraction = date.addingTimeInterval(-3600)
        let id = UUID()
        let results = try ["Asia/Shanghai", "America/Los_Angeles"].map { zone in
            var legacyCalendar = Calendar(identifier: .gregorian)
            legacyCalendar.timeZone = try #require(TimeZone(identifier: zone))
            let seed = RelationshipSnapshot(affinity: 30, activityDayStart: legacyCalendar.startOfDay(for: date),
                activityCountToday: 4, positiveGainToday: 3.9, repairGainToday: 1.4,
                lastInteractionAt: lastInteraction)
            let result = RelationshipEngine.apply(signal, to: seed, source: .textChat, messageID: id,
                messageCreatedAt: date, messageOrderIndex: 1, at: date, calendar: calendar)
            #expect(result.affinity - seed.affinity <= 0.100_001)
            #expect(result.positiveGainToday >= 3.9)
            #expect(result.activityCountToday == 5)
            #expect(result.repairGainToday == 1.4)
            #expect(result.activityDayStart == calendar.startOfDay(for: date))
            return result
        }
        #expect(results[0] == results[1])
    }

    @Test("中性联系沿用角色日界；跨过角色午夜才重置，缺少旧互动时间时兼容原日界")
    func characterDayContactAndFallback() throws {
        let calendar = RelationshipCalendar.forRegionID("london")
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let seed = RelationshipSnapshot(affinity: 30, activityDayStart: shanghai.startOfDay(for: date),
            activityCountToday: 4, positiveGainToday: 3.9, repairGainToday: 1.4,
            lastInteractionAt: date.addingTimeInterval(-3600))
        let sameDay = RelationshipEngine.recordContact(in: seed, messageID: UUID(), messageCreatedAt: date,
            messageOrderIndex: 1, at: date, calendar: calendar)
        #expect(sameDay.positiveGainToday == 3.9)
        #expect(sameDay.repairGainToday == 1.4)
        #expect(sameDay.activityCountToday == 5)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: date))
        let nextDay = RelationshipEngine.recordContact(in: seed, messageID: UUID(), messageCreatedAt: tomorrow,
            messageOrderIndex: 1, at: tomorrow, calendar: calendar)
        #expect(nextDay.positiveGainToday == 0)
        #expect(nextDay.repairGainToday == 0)
        #expect(nextDay.activityCountToday == 1)
        var fallback = seed
        fallback.lastInteractionAt = nil
        fallback.activityDayStart = calendar.startOfDay(for: date)
        let compatible = RelationshipEngine.recordContact(in: fallback, messageID: UUID(), messageCreatedAt: date,
            messageOrderIndex: 1, at: date, calendar: calendar)
        #expect(compatible.positiveGainToday == 3.9)
        #expect(compatible.activityCountToday == 5)
    }

    @Test("角色日界复用已有城市映射，海外城市和未知地区都有稳定时区")
    func characterCalendarUsesExistingCityTimeZones() {
        #expect(RelationshipCalendar.forRegionID("melbourne").timeZone.identifier == "Australia/Melbourne")
        #expect(RelationshipCalendar.forRegionID("newyork").timeZone.identifier == "America/New_York")
        #expect(RelationshipCalendar.forRegionID("auckland").timeZone.identifier == "Pacific/Auckland")
        #expect(RelationshipCalendar.forRegionID("kingston").timeZone.identifier == "America/Jamaica")
        #expect(RelationshipCalendar.forRegionID("unknown").timeZone.secondsFromGMT(for: date) == 0)
    }

    @Test("真实中性联系和共同活动都保存角色城市日历，重试无需依赖设备时区")
    func genuineContactAndContextSourcesCaptureCharacterCalendar() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        try await store.activateOwner(userID: UUID())
        let id = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: true)
        let initial = try #require(try await store.takePending().first)
        try await store.complete(commandID: initial.commandID, record: record(initial, relationship: .initial, version: 1))
        let message = MessageDTO(id: UUID(), role: .user, kind: .text, text: "Hello", orderIndex: 1, createdAt: date)
        try await RelationshipService(llm: MockLLMProvider(), rosterStore: roster)
            .recordContact(characterID: id, message: message, at: date)
        let activityID = UUID()
        _ = try await RelationshipContextEventService(rosterStore: roster).apply(characterID: id,
            signal: signal, source: .sharedActivity, eventID: activityID, at: date.addingTimeInterval(60))
        let pending = try #require(try await store.takePending().first)
        #expect(pending.relationshipReplayInputs.map(\.messageID) == [message.id, activityID])
        #expect(pending.relationshipReplayInputs.allSatisfy { $0.calendar == RelationshipCalendar.forRegionID("london") })
        #expect(pending.relationshipReplayInputs.map(\.kind) == [.contact, .reviewed])
    }

    @Test("仅修改备注时保留服务端关系，不需要伪造关系信号")
    func preservesNonRelationshipEditWithoutSignals() throws {
        var remote = RelationshipSnapshot.initial
        remote.affinity = 30; remote.revision = 4; remote.settledAppointmentIDs = [UUID()]
        let result = try ContentRelationshipReconciliation.reconcile(currentJSON: payload(remote),
            desiredJSON: payload(.initial, note: "My updated note"), inputs: [], replay: nil)
        #expect(try relationship(result) == remote)
        #expect(result.contains("My updated note"))
    }

    @Test("真实审阅调用一次，精确信号随 outbox 保存；并发重放不再调用模型")
    func capturesActualReviewWithoutSecondModelCall() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        try await store.activateOwner(userID: UUID())
        let id = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: true)
        let initial = try #require(try await store.takePending().first)
        try await store.complete(commandID: initial.commandID, record: record(initial, relationship: .initial, version: 1))
        let counter = ReviewCounter()
        let provider = MockLLMProvider(completeHandler: { _ in
            await counter.record()
            return """
            {"coach_review":{"has_issues":false,"issues":[]},"relationship":{"warmth":0.4,"responsiveness":0.5,"respect":0.5,"empathy":0.3,"reciprocity":0.3,"disclosure":0,"resonance":0.2,"engagement":0.5,"boundary_harm":0,"repair":0,"significance":0.4,"confidence":0.9,"reason_zh":"认真回应对方"}}
            """
        })
        let message = MessageDTO(id: UUID(), role: .user, kind: .text, text: "Would you prefer a quiet break?",
            orderIndex: 2, createdAt: date)
        let character = try #require(try await roster.character(id: id))
        _ = try await RelationshipService(llm: provider, rosterStore: roster).reviewAndApply(
            character: character, history: [], userMessage: message, source: .textChat, at: date)
        let pending = try #require(try await store.takePending().first)
        let captured = try #require(pending.relationshipReplayInputs.first)
        #expect(captured.messageID == message.id)
        #expect(captured.messageCreatedAt == date)
        #expect(captured.source == .textChat)
        #expect(captured.kind == .reviewed)
        #expect(captured.calendar == RelationshipCalendar.forRegionID("london"))
        let storedSignal = try JSONDecoder().decode(RelationshipSignal.self, from: Data(try #require(captured.signalJSON).utf8))
        #expect(storedSignal == signal)
        var remote = RelationshipEngine.apply(signal, to: .initial, source: .appointment,
            messageID: UUID(), messageCreatedAt: date, messageOrderIndex: -1, at: date)
        remote.settledAppointmentIDs = remote.recentEvaluatedMessageIDs
        try await store.reject(commandID: pending.commandID, code: "CONTENT_VERSION_CONFLICT",
            current: record(pending, relationship: remote, version: 2), replayRelationship: RelationshipReplay.apply)
        #expect(await counter.calls == 1)
        let rebased = try #require(try await store.takePending().first)
        #expect(try relationship(try #require(rebased.payloadJSON)) == RelationshipReplay.apply([captured], to: remote))
    }

    @Test("没有真实信号的旧快照冲突明确暂停，不能把原载荷无限重新排队")
    func stallsUnreplayableLegacySnapshot() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        try await store.activateOwner(userID: UUID())
        let characterID = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: true)
        var legacy = RelationshipSnapshot.initial
        legacy.affinity = 20; legacy.revision = 1
        _ = try await roster.updateRelationship(characterID: characterID, snapshot: legacy, expectedRevision: 0)
        let pending = try #require(try await store.takePending().first)
        var remote = RelationshipSnapshot.initial
        remote.affinity = 30; remote.revision = 8; remote.settledAppointmentIDs = [UUID()]
        let current = record(pending, relationship: remote, version: 4)
        await #expect(throws: ContentSyncStore.SyncStoreError.self) {
            try await store.reject(commandID: pending.commandID, code: "CONTENT_VERSION_CONFLICT", current: current,
                replayRelationship: RelationshipReplay.apply)
        }
        #expect(try await store.takePending().isEmpty)
        #expect(try await store.unresolvedErrorCount() == 1)
    }

    @Test("信号与本地变更一起持久化；冲突后只保留一个新命令，确认后清除")
    func persistsRebasesAndAcknowledgesInputs() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        try await store.activateOwner(userID: UUID())
        let characterID = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: true)
        let initial = try #require(try await store.takePending().first)
        try await store.complete(commandID: initial.commandID, record: record(initial, relationship: .initial, version: 1))
        let first = try RelationshipReplay.reviewed(signal, source: .textChat, messageID: UUID(),
            messageCreatedAt: date, messageOrderIndex: 1, at: date)
        try await roster.mutateRelationship(characterID: characterID, replayInput: first) {
            (try? RelationshipReplay.apply([first], to: $0)) ?? $0
        }
        let pending = try #require(try await store.takePending().first)
        let second = RelationshipReplayInput.contact(messageID: UUID(), messageCreatedAt: date.addingTimeInterval(60),
            messageOrderIndex: 2, at: date.addingTimeInterval(60))
        try await roster.mutateRelationship(characterID: characterID, replayInput: second) {
            (try? RelationshipReplay.apply([second], to: $0)) ?? $0
        }
        var remote = RelationshipEngine.apply(signal, to: .initial, source: .appointment,
            messageID: UUID(), messageCreatedAt: date, messageOrderIndex: -1, at: date)
        remote.settledAppointmentIDs = remote.recentEvaluatedMessageIDs
        try await store.reject(commandID: pending.commandID, code: "CONTENT_VERSION_CONFLICT",
            current: record(pending, relationship: remote, version: 2), replayRelationship: RelationshipReplay.apply)
        let replacement = try #require(try await store.takePending().first)
        #expect(replacement.commandID != pending.commandID)
        #expect(replacement.expectedVersion == 2)
        #expect(replacement.relationshipReplayInputs.map(\.messageID) == [first.messageID, second.messageID])
        #expect(try relationship(try #require(replacement.payloadJSON)) == RelationshipReplay.apply([first, second], to: remote))
        #expect(try await store.takePending().isEmpty)
        try await store.complete(commandID: replacement.commandID, record: record(replacement,
            relationship: try RelationshipReplay.apply([first, second], to: remote), version: 3))
        #expect(try await store.takePending().isEmpty)
        #expect(try await store.unresolvedErrorCount() == 0)
    }

    @Test("同一资源的后续版本等待前一条确认，不能在前条冲突后越过它上传")
    func serializesContingentCharacterCommands() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        try await store.activateOwner(userID: UUID())
        let id = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: true)
        let first = try #require(try await store.takePending(serialPerResource: true).first)
        try await roster.setDifficulty(characterID: id, level: .advanced)
        #expect(try await store.takePending(serialPerResource: true).isEmpty)
        try await store.resetInFlight(commandIDs: [first.commandID])
        let retry = try await store.takePending(serialPerResource: true)
        #expect(retry.map(\.commandID) == [first.commandID])
        try await store.complete(commandID: first.commandID, record: record(first, relationship: .initial, version: 1))
        let second = try #require(try await store.takePending(serialPerResource: true).first)
        #expect(second.commandID != first.commandID)
        #expect(second.expectedVersion == 1)
    }

    private var card: CharacterCard {
        CharacterCard(name: "Oliver", age: 29, gender: .male, nationality: "British", regionID: "london",
            occupation: "Translator", hobbies: ["walking"], appearance: "Brown hair", personality: "Thoughtful")
    }
    private func payload(_ value: RelationshipSnapshot, note: String = "") throws -> String {
        let object: [String: Any] = ["relationship": try JSONSerialization.jsonObject(with: Data(value.encodedJSON().utf8)), "remarkName": note]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }
    private func relationship(_ payload: String) throws -> RelationshipSnapshot {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: try #require(object["relationship"]))
        return try #require(RelationshipSnapshot.decode(fromJSON: String(decoding: data, as: UTF8.self)))
    }
    private func record(_ mutation: PendingContentMutation, relationship: RelationshipSnapshot, version: Int) -> RemoteContentRecord {
        var object = (try? JSONSerialization.jsonObject(with: Data((mutation.payloadJSON ?? "{}").utf8))) as? [String: Any] ?? [:]
        object["relationship"] = try? JSONSerialization.jsonObject(with: Data(relationship.encodedJSON().utf8))
        let data = (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data()
        return RemoteContentRecord(createdAt: date, deletedAt: nil, parentID: mutation.parentID,
            payloadJSON: String(decoding: data, as: UTF8.self), resourceID: mutation.resourceID,
            resourceType: mutation.resourceType, updatedAt: date, version: version)
    }

    private actor ReviewCounter {
        var calls = 0
        func record() { calls += 1 }
    }
}
