import Foundation
import SwiftData

/// 道具快照（机票）。
public struct ItemDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var type: ItemType
    public var countryCode: String?
    public var source: ItemSource
    public var createdAt: Date
    public var consumedAt: Date?

    public var isConsumed: Bool { consumedAt != nil }
}

/// 道具仓库（机票的获得与消耗）。
@ModelActor
public actor ItemStore {
    public enum ItemError: Error {
        case itemNotFound
        case alreadyConsumed
    }

    @discardableResult
    public func addTicket(type: ItemType, countryCode: String? = nil, source: ItemSource) throws -> ItemDTO {
        let entity = ItemEntity(
            typeRaw: type.rawValue,
            countryCode: countryCode,
            sourceRaw: source.rawValue
        )
        modelContext.insert(entity)
        try modelContext.save()
        return Self.dto(from: entity)
    }

    /// 是否已从某来源获得过机票（主线只送一张的判定）。
    public func hasTicket(source: ItemSource) throws -> Bool {
        let sourceRaw = source.rawValue
        let count = try modelContext.fetchCount(
            FetchDescriptor<ItemEntity>(predicate: #Predicate { $0.sourceRaw == sourceRaw })
        )
        return count > 0
    }

    /// 未使用的机票。
    public func unconsumedTickets() throws -> [ItemDTO] {
        var descriptor = FetchDescriptor<ItemEntity>(predicate: #Predicate { $0.consumedAt == nil })
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try modelContext.fetch(descriptor).map(Self.dto(from:))
    }

    /// 消耗一张机票（2.3 地图使用）。
    public func consume(itemID: UUID) throws {
        guard let entity = try modelContext.fetch(
            FetchDescriptor<ItemEntity>(predicate: #Predicate { $0.itemID == itemID })
        ).first else {
            throw ItemError.itemNotFound
        }
        guard entity.consumedAt == nil else {
            throw ItemError.alreadyConsumed
        }
        entity.consumedAt = .now
        try modelContext.save()
    }

    static func dto(from entity: ItemEntity) -> ItemDTO {
        ItemDTO(
            id: entity.itemID,
            type: ItemType(rawValue: entity.typeRaw) ?? .ticketUniversal,
            countryCode: entity.countryCode,
            source: ItemSource(rawValue: entity.sourceRaw) ?? .story,
            createdAt: entity.createdAt,
            consumedAt: entity.consumedAt
        )
    }
}
