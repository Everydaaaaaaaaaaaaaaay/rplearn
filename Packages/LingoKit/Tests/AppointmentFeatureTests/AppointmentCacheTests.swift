import Foundation
import Testing
@testable import AppointmentFeature
import BackendKit

@Suite("Appointment account cache")
struct AppointmentCacheTests {
    @Test("Pending command survives recreation with original input and revision")
    func pendingCommandSurvivesRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let cache = AppointmentCache(namespace: "account-a", directory: directory)
        let pending = AppointmentPendingCommand(appointmentID: id, action: .choice, request: .init(commandId: UUID(), expectedRevision: 7, input: "想去运河散步"))
        try await cache.savePending(pending)
        let reopened = AppointmentCache(namespace: "account-a", directory: directory)
        let recovered = try await reopened.pending(id)
        #expect(recovered == pending)
        let otherAccount = AppointmentCache(namespace: "account-b", directory: directory)
        let otherPending = try await otherAccount.pending(id)
        #expect(otherPending == nil)
    }

    @Test("Draft and reading cursor survive pause")
    func draftAndReadingCursorSurvivePause() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let cache = AppointmentCache(namespace: "account-a", directory: directory)
        try await cache.saveReading(id, cursor: .init(blockID: "accepted-block", beatIndex: 2), draft: "Could we sit here?")
        let reopened = AppointmentCache(namespace: "account-a", directory: directory)
        let reading = try await reopened.reading(id)
        #expect(reading.cursor?.blockID == "accepted-block")
        #expect(reading.cursor?.beatIndex == 2)
        #expect(reading.draft == "Could we sit here?")
    }
}
