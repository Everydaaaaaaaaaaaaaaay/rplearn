import BackendKit
import Foundation
import Observation

@MainActor @Observable
final class AppointmentModel {
    var detail: BackendAppointmentDetail? {
        didSet {
            let ordered = detail?.session?.blocks.sorted { $0.sequence < $1.sequence } ?? []
            if blocks != ordered { blocks = ordered }
        }
    }
    private(set) var blocks: [BackendAppointmentBlock] = []
    var loading = false
    var submitting = false
    var offline = false
    var error: String?
    var pending: AppointmentPendingCommand?
    var cursor: AppointmentReadingCursor?
    var draft = ""
    let id: UUID
    private let service: any AppointmentServing
    private let cache: AppointmentCache
    private let settle: (@Sendable (UUID) async throws -> Void)?
    var settling = false

    init(id: UUID, service: any AppointmentServing, cache: AppointmentCache, settle: (@Sendable (UUID) async throws -> Void)? = nil) {
        self.id = id; self.service = service; self.cache = cache; self.settle = settle
    }

    var block: BackendAppointmentBlock? { blocks.first { $0.id == cursor?.blockID } ?? blocks.last }
    var beatIndex: Int { min(max(cursor?.beatIndex ?? 0, 0), max((block?.beats.count ?? 1) - 1, 0)) }
    var beat: BackendAppointmentBeat? { guard let block, block.beats.indices.contains(beatIndex) else { return nil }; return block.beats[beatIndex] }
    var isLastBeat: Bool { beatIndex >= (block?.beats.count ?? 0) - 1 }
    var isLatestBlock: Bool { block?.id == blocks.last?.id }
    var mayRespond: Bool { isLatestBlock && isLastBeat && detail?.appointment.status == "in_progress" && block?.ending == false && pending == nil && !submitting && !offline }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let reading = try await cache.reading(id)
            cursor = reading.cursor; draft = reading.draft
            pending = try await cache.pending(id)
            if detail == nil { detail = try await cache.detail(id) }
            let fresh = try await service.appointment(id)
            detail = try await cache.saveDetail(fresh)
            offline = false; error = nil
            normalizeCursor()
            await settleIfPending()
        } catch {
            offline = true
            self.error = detail == nil ? "这次约定暂时无法载入，请重试。" : "当前为离线回看。联网刷新后才能继续回应。"
            normalizeCursor()
        }
    }

    func submit(action: BackendAppointmentAction, choiceID: String? = nil, input: String? = nil, finish: Bool? = nil) async {
        guard !submitting, !offline, let detail else { return }
        // A pending operation is never replaced by a new command after a lost response.
        if pending != nil { await retry(); return }
        let command = AppointmentPendingCommand(appointmentID: id, action: action, request: .init(commandId: UUID(), expectedRevision: detail.appointment.revision, choiceId: choiceID, input: input, finish: finish))
        do {
            try await cache.savePending(command)
            pending = command
            await transmit(command)
        } catch { self.error = "未能保存这次回应，请重试。回应尚未发送。" }
    }

    func retry() async {
        guard let pending, !submitting else { return }
        await transmit(pending)
    }

    private func transmit(_ command: AppointmentPendingCommand) async {
        submitting = true; error = nil
        defer { submitting = false }
        do {
            let accepted = try await service.appointmentCommand(id, action: command.action, request: command.request)
            let retained = try await cache.saveDetail(accepted, acknowledging: command.request.commandId)
            detail = retained; pending = try await cache.pending(id); offline = false
            if command.action == .choice {
                if pending == nil { draft = "" }
                if retained.appointment.revision == accepted.appointment.revision {
                    cursor = retained.session?.blocks.last.map { .init(blockID: $0.id, beatIndex: 0) }
                }
            }
            normalizeCursor()
            await persistReading()
            await settleIfPending()
        } catch let failure as BackendClientError {
            if case .api(let code, let message, _, let status) = failure,
               status == 409,
               ["APPOINTMENT_VERSION_CONFLICT", "APPOINTMENT_WRONG_CITY", "APPOINTMENT_OUTSIDE_WINDOW", "APPOINTMENT_CLOSED", "APPOINTMENT_NOT_STARTED"].contains(code) {
                do {
                    let accepted = try await service.appointment(id)
                    detail = try await cache.saveDetail(accepted, acknowledging: command.request.commandId)
                    pending = try await cache.pending(id); offline = false; normalizeCursor()
                    error = code == "APPOINTMENT_VERSION_CONFLICT" ? "这次约定已在另一处更新。这里已载入实际发生的进展，请查看后继续。" : message
                } catch { self.error = "进度已更新，暂时无法同步。请联网重试原回应。" }
            } else { error = "这一段暂时没接上。你的回应已经保留，可以重试或稍后继续。" }
        } catch { self.error = "这一段暂时没接上。你的回应已经保留，可以重试或稍后继续。" }
    }

    func advance() async {
        guard let block else { return }
        if !isLastBeat { cursor = .init(blockID: block.id, beatIndex: beatIndex + 1) }
        else if let index = blocks.firstIndex(where: { $0.id == block.id }), blocks.indices.contains(index + 1) {
            cursor = .init(blockID: blocks[index + 1].id, beatIndex: 0)
        }
        await persistReading()
    }

    func persistReading() async {
        do { try await cache.saveReading(id, cursor: cursor, draft: draft) }
        catch { self.error = "阅读位置暂时未能保存。已发生的故事仍保存在服务端。" }
    }

    func settleIfPending() async {
        guard detail?.summary?.affinity.status == "pending", let settle, !settling, !offline else { return }
        settling = true
        defer { settling = false }
        do {
            try await settle(id)
            let accepted = try await service.appointment(id)
            detail = try await cache.saveDetail(accepted)
        } catch { self.error = "经历已保存，关系变化仍待结算。联网后可重试整理回顾。" }
    }

    private func normalizeCursor() {
        guard let block else { return }
        cursor = .init(blockID: block.id, beatIndex: beatIndex)
    }
}

enum AppointmentTime {
    static func entryAvailable(_ detail: BackendAppointmentDetail, cityID: String) -> Bool {
        let item = detail.appointment
        guard item.status == "confirmed", item.cityId == cityID,
              let now = AppointmentDisplayTime.date(detail.serverNow), let opens = AppointmentDisplayTime.date(item.windowOpensAt), let closes = AppointmentDisplayTime.date(item.windowClosesAt) else { return false }
        return now >= opens && now <= closes
    }

    static func status(_ item: BackendAppointment) -> String {
        switch item.status {
        case "confirmed": "已约好"
        case "in_progress": "进行中 · 可继续"
        case "finishing": "正在整理回顾"
        case "completed": "已完成"
        case "cancelled": "已取消"
        case "expired": "这次时段已过"
        default: "等待更新"
        }
    }
}
