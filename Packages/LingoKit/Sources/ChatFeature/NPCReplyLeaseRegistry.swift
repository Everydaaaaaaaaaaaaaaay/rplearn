import Foundation

/// 进程内避免同一会话被两个仍存活的 ChatViewModel 重复生成回复。
/// 跨重启幂等性由 ChatStore 对时间线末端消息的再次校验保证。
@MainActor
final class NPCReplyLeaseRegistry {
    static let shared = NPCReplyLeaseRegistry()

    private struct Lease: Equatable {
        let ownerID: UUID
        let cycleID: UUID
        let messageID: UUID
    }

    private var leases: [UUID: Lease] = [:]

    private init() {}

    func acquire(
        conversationID: UUID,
        ownerID: UUID,
        cycleID: UUID,
        messageID: UUID
    ) -> Bool {
        if let active = leases[conversationID] {
            // Two pages restoring the same user message must share one producer. A genuinely
            // newer message may take over after the caller has verified it is the timeline tail.
            guard active.ownerID == ownerID || active.messageID != messageID else {
                return false
            }
        }
        // A newer cycle from the same view model atomically takes over. The old cycle's
        // deferred release cannot clear this replacement lease.
        leases[conversationID] = Lease(
            ownerID: ownerID,
            cycleID: cycleID,
            messageID: messageID
        )
        return true
    }

    func release(
        conversationID: UUID,
        ownerID: UUID,
        cycleID: UUID,
        messageID: UUID
    ) {
        guard leases[conversationID] == Lease(
            ownerID: ownerID,
            cycleID: cycleID,
            messageID: messageID
        ) else {
            return
        }
        leases[conversationID] = nil
    }

    func waitUntilAvailable(conversationID: UUID) async throws {
        while leases[conversationID] != nil {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
