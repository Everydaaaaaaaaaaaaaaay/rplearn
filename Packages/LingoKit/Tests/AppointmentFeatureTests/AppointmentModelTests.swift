import Foundation
import Testing
import BackendKit
@testable import AppointmentFeature

@Suite("Appointment durable choices") @MainActor
struct AppointmentModelTests {
    @Test("Lost responses retry the original command across model recreation without branching")
    func lostResponse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = AppointmentPreviewService(scenario: "active")
        let service = LostResponseService(fixture: fixture)
        let id = AppointmentListView.previewAppointmentID
        let first = AppointmentModel(id: id, service: service, cache: AppointmentCache(namespace: "a", directory: directory))
        await first.load()
        await first.submit(action: .choice, input: "Can we try the quieter path?")
        let pending = try #require(first.pending)
        #expect(first.detail?.session?.decisions.isEmpty == true)
        let reopened = AppointmentModel(id: id, service: service, cache: AppointmentCache(namespace: "a", directory: directory))
        await reopened.load()
        #expect(reopened.pending == pending)
        await reopened.retry()
        #expect(reopened.pending == nil)
        #expect(reopened.detail?.session?.decisions.count == 1)
        #expect(reopened.detail?.session?.decisions.first?.input == "Can we try the quieter path?")
        let requests = await service.requests
        #expect(requests.count == 2)
        #expect(requests[0] == requests[1])
    }

    @Test("Entry uses server time and application city; ongoing sessions remain readable")
    func trustedEntry() async throws {
        let fixture = AppointmentPreviewService(scenario: "confirmed")
        var detail = try await fixture.appointment(AppointmentListView.previewAppointmentID)
        #expect(AppointmentTime.entryAvailable(detail, cityID: "london"))
        #expect(!AppointmentTime.entryAvailable(detail, cityID: "paris"))
        detail.serverNow = "2026-11-01T17:00:01Z"
        #expect(!AppointmentTime.entryAvailable(detail, cityID: "london"))
        detail.serverNow = "2026-11-01T14:29:59Z"
        #expect(!AppointmentTime.entryAvailable(detail, cityID: "london"))
    }

    @Test("Pending settlement stays distinct from a settled zero and negative result")
    func affinityStates() async throws {
        let id = AppointmentListView.previewAppointmentID
        let pending = try await AppointmentPreviewService(scenario: "pending").appointment(id)
        let zero = try await AppointmentPreviewService(scenario: "zero").appointment(id)
        let negative = try await AppointmentPreviewService(scenario: "negative").appointment(id)
        #expect(pending.summary?.affinity.status == "pending")
        #expect(zero.summary?.affinity.status == "settled")
        #expect(zero.summary?.affinity.delta == 0)
        #expect(negative.summary?.affinity.delta == -1)
    }

    @Test("A running server operation retains the original command instead of treating 409 as a branch conflict")
    func runningOperation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = RunningOperationService()
        let model = AppointmentModel(id: AppointmentListView.previewAppointmentID, service: service, cache: AppointmentCache(namespace: "running", directory: directory))
        await model.load()
        await model.submit(action: .choice, input: "Let's take our time.")
        let original = try #require(model.pending)
        #expect(model.detail?.session?.decisions.count == 0)
        await model.retry()
        #expect(model.pending == nil)
        #expect(model.detail?.session?.decisions.count == 1)
        let requests = await service.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.commandId == original.request.commandId })
    }

    @Test("Version conflict displays the other device's accepted path and releases the rejected command")
    func concurrentChoice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppointmentModel(id: AppointmentListView.previewAppointmentID, service: ConcurrentChoiceService(), cache: AppointmentCache(namespace: "conflict", directory: directory))
        await model.load()
        await model.submit(action: .choice, input: "My unaccepted request")
        #expect(model.pending == nil)
        #expect(model.detail?.session?.decisions.map(\.input) == ["The accepted action from another device"])
        #expect(model.error?.contains("另一处更新") == true)
    }

    @Test("Offline reopening retains accepted story and draft, and cannot submit a new choice")
    func offlineRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = OfflineService()
        let id = AppointmentListView.previewAppointmentID
        let first = AppointmentModel(id: id, service: service, cache: AppointmentCache(namespace: "offline", directory: directory))
        await first.load()
        first.draft = "Could we slow down?"
        await first.advance()
        await service.disconnect()
        let reopened = AppointmentModel(id: id, service: service, cache: AppointmentCache(namespace: "offline", directory: directory))
        await reopened.load()
        #expect(reopened.offline)
        #expect(reopened.beatIndex == 1)
        #expect(reopened.draft == "Could we slow down?")
        #expect(reopened.blocks.count == 1)
        await reopened.submit(action: .choice, input: reopened.draft)
        #expect(reopened.pending == nil)
        let commands = await service.commands
        #expect(commands == 0)
    }

    @Test("A frozen idempotent receipt cannot replace a newer accepted path after restart")
    func olderReceiptAfterNewerPath() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FrozenReceiptService()
        let id = AppointmentListView.previewAppointmentID
        let first = AppointmentModel(id: id, service: service, cache: AppointmentCache(namespace: "frozen", directory: directory))
        await first.load()
        await first.submit(action: .choice, input: "My accepted first choice")
        let original = try #require(first.pending)
        try await service.advanceOnAnotherDevice()
        let cache = AppointmentCache(namespace: "frozen", directory: directory)
        let reopened = AppointmentModel(id: id, service: service, cache: cache)
        await reopened.load()
        #expect(reopened.detail?.appointment.revision == 3)
        await reopened.retry()
        #expect(reopened.pending == nil)
        #expect(reopened.detail?.appointment.revision == 3)
        #expect(reopened.detail?.session?.decisions.map(\.input) == ["My accepted first choice", "Later accepted choice on another device"])
        let persisted = try await AppointmentCache(namespace: "frozen", directory: directory).detail(id)
        #expect(persisted?.appointment.revision == 3)
        #expect(persisted?.session?.decisions.count == 2)
        let commands = await service.commands
        let generations = await service.generations
        #expect(commands.count == 2)
        #expect(commands.allSatisfy { $0.commandId == original.request.commandId })
        #expect(generations == 2, "读取旧回执不能再生成一段故事")

        let laterCommand = AppointmentPendingCommand(appointmentID: id, action: .choice, request: .init(commandId: UUID(), expectedRevision: 3, input: "New unacknowledged command"))
        try await cache.savePending(laterCommand)
        let receipt = try #require(await service.receipt)
        _ = try await cache.saveDetail(receipt, acknowledging: original.request.commandId)
        let remaining = try await cache.pending(id)
        #expect(remaining == laterCommand, "旧回执只能清除自己确认的命令")
    }
}

private actor FrozenReceiptService: AppointmentServing {
    let fixture = AppointmentPreviewService(scenario: "active")
    var receipt: BackendAppointmentDetail?
    var commands: [BackendAppointmentCommand] = []
    var generations = 0
    func appointments() async throws -> BackendAppointmentList { try await fixture.appointments() }
    func appointment(_ id: UUID) async throws -> BackendAppointmentDetail { try await fixture.appointment(id) }
    func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail {
        commands.append(request)
        if let receipt { return receipt }
        generations += 1
        receipt = try await fixture.appointmentCommand(id, action: action, request: request)
        throw BackendClientError.transport("Accepted receipt lost")
    }
    func advanceOnAnotherDevice() async throws {
        let old = try #require(receipt)
        generations += 1
        _ = try await fixture.appointmentCommand(old.appointment.id, action: .choice, request: .init(commandId: UUID(), expectedRevision: old.appointment.revision, input: "Later accepted choice on another device"))
    }
}

private actor ConcurrentChoiceService: AppointmentServing {
    let fixture = AppointmentPreviewService(scenario: "active")
    func appointments() async throws -> BackendAppointmentList { try await fixture.appointments() }
    func appointment(_ id: UUID) async throws -> BackendAppointmentDetail { try await fixture.appointment(id) }
    func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail {
        _ = try await fixture.appointmentCommand(id, action: .choice, request: .init(commandId: UUID(), expectedRevision: request.expectedRevision, input: "The accepted action from another device"))
        throw BackendClientError.api(code: "APPOINTMENT_VERSION_CONFLICT", message: "Already accepted", requestID: nil, status: 409)
    }
}

private actor OfflineService: AppointmentServing {
    let fixture = AppointmentPreviewService(scenario: "active")
    private var offline = false
    var commands = 0
    func disconnect() { offline = true }
    func appointments() async throws -> BackendAppointmentList { try await fixture.appointments() }
    func appointment(_ id: UUID) async throws -> BackendAppointmentDetail {
        if offline { throw BackendClientError.transport("Offline fixture") }
        return try await fixture.appointment(id)
    }
    func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail {
        commands += 1
        throw BackendClientError.transport("Offline fixture")
    }
}

private actor RunningOperationService: AppointmentServing {
    let fixture = AppointmentPreviewService(scenario: "active")
    var requests: [BackendAppointmentCommand] = []
    func appointments() async throws -> BackendAppointmentList { try await fixture.appointments() }
    func appointment(_ id: UUID) async throws -> BackendAppointmentDetail { try await fixture.appointment(id) }
    func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail {
        requests.append(request)
        if requests.count == 1 { throw BackendClientError.api(code: "APPOINTMENT_OPERATION_PENDING", message: "仍在生成", requestID: nil, status: 409) }
        return try await fixture.appointmentCommand(id, action: action, request: request)
    }
}

private actor LostResponseService: AppointmentServing {
    let fixture: AppointmentPreviewService
    var requests: [BackendAppointmentCommand] = []
    private var accepted: BackendAppointmentDetail?
    init(fixture: AppointmentPreviewService) { self.fixture = fixture }
    func appointments() async throws -> BackendAppointmentList { try await fixture.appointments() }
    func appointment(_ id: UUID) async throws -> BackendAppointmentDetail { try await fixture.appointment(id) }
    func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail {
        requests.append(request)
        if let accepted { return accepted }
        accepted = try await fixture.appointmentCommand(id, action: action, request: request)
        throw BackendClientError.transport("Accepted but response was lost")
    }
}
