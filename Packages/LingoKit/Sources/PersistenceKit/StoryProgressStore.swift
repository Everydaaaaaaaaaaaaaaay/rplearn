import Foundation
import SwiftData

/// 剧情进度快照。
public struct StoryProgressDTO: Sendable, Equatable {
    public var storyID: String
    public var currentNodeID: String?
    public var flags: [String: Bool]
    public var completedAt: Date?

    public var isCompleted: Bool { completedAt != nil }

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
        let entity = try fetchOrCreate(storyID)
        entity.currentNodeID = nodeID
        entity.flagsJSON = Self.encodeFlags(flags)
        try modelContext.save()
    }

    public func markCompleted(storyID: String) throws {
        let entity = try fetchOrCreate(storyID)
        entity.completedAt = .now
        entity.currentNodeID = nil
        try modelContext.save()
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
