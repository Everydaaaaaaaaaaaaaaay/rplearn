import Foundation
import SwiftData

/// 剧情进度快照。
public struct StoryProgressDTO: Sendable, Equatable {
    public var storyID: String
    public var currentNodeID: String?
    public var flags: [String: Bool]
    public var completedAt: Date?

    public var isCompleted: Bool { completedAt != nil }
    public var readingFlags: [String: Bool] {
        flags.filter { !$0.key.hasPrefix("experience.") }
    }

    public init(storyID: String, currentNodeID: String?, flags: [String: Bool], completedAt: Date?) {
        self.storyID = storyID
        self.currentNodeID = currentNodeID
        self.flags = flags
        self.completedAt = completedAt
    }
}

/// 剧情进度仓库（断点续播）。
@ModelActor
public actor StoryProgressStore {
    public func progress(storyID: String) throws -> StoryProgressDTO? {
        try fetch(storyID).map(Self.dto(from:))
    }

    /// 每步推进落一次进度。
    public func saveCheckpoint(storyID: String, nodeID: String?, flags: [String: Bool]) throws {
        do {
            let entity = try fetchOrCreate(storyID)
            entity.currentNodeID = nodeID
            let completedEvidence = Self.decodeFlags(entity.flagsJSON).filter { $0.key.hasPrefix("experience.") }
            // Reading/replaying cannot erase or forge the first completed outcome.
            entity.flagsJSON = Self.encodeFlags(flags.filter { !$0.key.hasPrefix("experience.") }
                .merging(completedEvidence) { _, evidence in evidence })
            try journal(entity)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func markCompleted(storyID: String, experienceID: String? = nil,
                              catalogStoryID: String? = nil) throws {
        do {
            let entity = try fetchOrCreate(storyID)
            if entity.completedAt == nil, let experienceID, !experienceID.isEmpty {
                var flags = Self.decodeFlags(entity.flagsJSON)
                flags["experience." + experienceID] = true
                entity.flagsJSON = Self.encodeFlags(flags)
            }
            entity.completedAt = entity.completedAt ?? .now
            entity.currentNodeID = nil
            if let catalogStoryID, catalogStoryID != storyID, try fetch(catalogStoryID) == nil {
                let marker = try fetchOrCreate(catalogStoryID)
                marker.completedAt = entity.completedAt
                try journal(marker)
            }
            try journal(entity)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func completedStoryIDs() throws -> Set<String> {
        let entities = try modelContext.fetch(
            FetchDescriptor<StoryProgressEntity>(predicate: #Predicate { $0.completedAt != nil })
        )
        return Set(entities.map(\.storyID))
    }

    // MARK: - 私有

    private func fetch(_ storyID: String) throws -> StoryProgressEntity? {
        try modelContext.fetch(
            FetchDescriptor<StoryProgressEntity>(predicate: #Predicate { $0.storyID == storyID })
        ).first
    }

    private func fetchOrCreate(_ storyID: String) throws -> StoryProgressEntity {
        if let existing = try fetch(storyID) {
            return existing
        }
        let entity = StoryProgressEntity(storyID: storyID)
        modelContext.insert(entity)
        return entity
    }

    private func journal(_ entity: StoryProgressEntity) throws {
        try ContentMutationJournal.upsert(
            in: modelContext,
            resourceType: .storyProgress,
            resourceID: entity.storyID,
            parentID: nil,
            payloadJSON: try ContentMutationJournal.encode(
                ContentStoryProgressPayload(
                    completedAt: entity.completedAt,
                    currentNodeId: entity.currentNodeID,
                    flags: Self.decodeFlags(entity.flagsJSON)
                )
            )
        )
    }

    static func dto(from entity: StoryProgressEntity) -> StoryProgressDTO {
        StoryProgressDTO(
            storyID: entity.storyID,
            currentNodeID: entity.currentNodeID,
            flags: decodeFlags(entity.flagsJSON),
            completedAt: entity.completedAt
        )
    }

    static func encodeFlags(_ flags: [String: Bool]) -> String {
        guard let data = try? JSONEncoder().encode(flags) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeFlags(_ json: String) -> [String: Bool] {
        (try? JSONDecoder().decode([String: Bool].self, from: Data(json.utf8))) ?? [:]
    }
}
