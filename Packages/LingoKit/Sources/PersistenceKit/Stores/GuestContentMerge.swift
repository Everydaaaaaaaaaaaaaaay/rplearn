import Foundation

extension ContentSyncStore {
    /// UUID histories coexist. Shared character/story keys merge only known monotonic fields;
    /// the pre-migration archive retains both interpretations of conflicting private fields.
    static func mergeGuest(local: LocalContentRecord, remote: RemoteContentRecord) throws -> RemoteContentRecord? {
        guard remote.deletedAt == nil, [.character, .storyProgress].contains(remote.resourceType),
              let guest = try JSONSerialization.jsonObject(with: Data(local.payloadJSON.utf8)) as? [String: Any],
              var merged = try JSONSerialization.jsonObject(with: Data(remote.payloadJSON.utf8)) as? [String: Any]
        else { return nil }
        if remote.resourceType == .storyProgress {
            if merged["completedAt"] == nil, let completed = guest["completedAt"] { merged["completedAt"] = completed }
            let remoteFlags = merged["flags"] as? [String: Bool] ?? [:]
            let guestFlags = guest["flags"] as? [String: Bool] ?? [:]
            merged["flags"] = remoteFlags.merging(guestFlags) { $0 || $1 }
            if merged["currentNodeId"] == nil { merged["currentNodeId"] = guest["currentNodeId"] }
        } else {
            for key in ["isFriend", "isFavorite", "publicIdentityRegistered"] {
                merged[key] = (merged[key] as? Bool == true) || (guest[key] as? Bool == true)
            }
            if merged["isFriend"] as? Bool == true { merged["contactStatus"] = "friend" }
            let remoteRelationship = merged["relationship"] as? [String: Any] ?? [:]
            let guestRelationship = guest["relationship"] as? [String: Any] ?? [:]
            if (guestRelationship["interactionCount"] as? Int ?? 0) > (remoteRelationship["interactionCount"] as? Int ?? 0) {
                merged["relationship"] = guest["relationship"]
            }
            for key in ["privateNote", "remarkName"] where merged[key] == nil { merged[key] = guest[key] }
            if let note = guest["privateNote"] as? String, !note.isEmpty,
               let existing = merged["privateNote"] as? String, !existing.contains(note) {
                merged["privateNote"] = existing + "\n游客旅程备注：" + note
            }
        }
        let data = try JSONSerialization.data(withJSONObject: merged, options: .sortedKeys)
        return RemoteContentRecord(createdAt: remote.createdAt, deletedAt: nil, parentID: remote.parentID,
            payloadJSON: String(decoding: data, as: UTF8.self), resourceID: remote.resourceID,
            resourceType: remote.resourceType, updatedAt: remote.updatedAt, version: remote.version)
    }
}
