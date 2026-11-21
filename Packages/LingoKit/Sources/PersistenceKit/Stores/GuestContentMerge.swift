import Foundation

extension ContentSyncStore {
    public func guestRecords() throws -> [LocalContentRecord] { try exportLocalRecords() }

    /// Merges a legacy guest into an already-created account store using current sync versions.
    public func importGuestRecords(_ incoming: [LocalContentRecord]) throws {
        let current = Dictionary(uniqueKeysWithValues: try exportLocalRecords().map {
            (metadataKey($0.resourceType, $0.resourceID), $0)
        })
        for local in incoming {
            let key = metadataKey(local.resourceType, local.resourceID)
            let version = try metadata(resourceType: local.resourceType, resourceID: local.resourceID)?.version ?? 0
            let candidate = RemoteContentRecord(createdAt: .now, deletedAt: nil, parentID: local.parentID,
                payloadJSON: local.payloadJSON, resourceID: local.resourceID, resourceType: local.resourceType,
                updatedAt: .now, version: version)
            let record: RemoteContentRecord
            if let existing = current[key] {
                let remote = RemoteContentRecord(createdAt: .now, deletedAt: nil, parentID: existing.parentID,
                    payloadJSON: existing.payloadJSON, resourceID: existing.resourceID, resourceType: existing.resourceType,
                    updatedAt: .now, version: version)
                guard let merged = try Self.mergeGuest(local: local, remote: remote), merged.payloadJSON != existing.payloadJSON else { continue }
                record = merged
            } else {
                // Metadata without an entity represents an account-side deletion.
                guard version == 0 else { continue }
                record = candidate
            }
            try apply(record)
            try ContentMutationJournal.upsert(in: modelContext, resourceType: record.resourceType,
                resourceID: record.resourceID, parentID: record.parentID, payloadJSON: record.payloadJSON)
        }
        try modelContext.save()
    }

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
            let guestCard = guest["card"] as? [String: Any] ?? [:]
            let remoteCard = merged["card"] as? [String: Any] ?? [:]
            if (guestCard["settingVersion"] as? Int ?? 0) > (remoteCard["settingVersion"] as? Int ?? 0) {
                merged["card"] = guestCard
            }
            for key in ["isFriend", "isFavorite", "publicIdentityRegistered"] {
                merged[key] = (merged[key] as? Bool == true) || (guest[key] as? Bool == true)
            }
            if merged["contactStatus"] as? String == "removed" {
                merged["isFriend"] = false
            } else if merged["isFriend"] as? Bool == true { merged["contactStatus"] = "friend" }
            else if guest["contactStatus"] as? String == "removed" { merged["contactStatus"] = "removed" }
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
