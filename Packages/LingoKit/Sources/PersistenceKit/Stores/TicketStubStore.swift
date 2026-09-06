import Foundation
import SwiftData

/// 首次抵达城市时保存的纪念票根。
public struct TicketStubDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var fromRegionID: String
    public var toRegionID: String
    public var usedAt: Date
    public var serialNumber: String
    /// 决定票根配色花纹。
    public var artSeed: Int

    public init(
        id: UUID,
        fromRegionID: String,
        toRegionID: String,
        usedAt: Date,
        serialNumber: String,
        artSeed: Int
    ) {
        self.id = id
        self.fromRegionID = fromRegionID
        self.toRegionID = toRegionID
        self.usedAt = usedAt
        self.serialNumber = serialNumber
        self.artSeed = artSeed
    }
}

/// 票根仓库：每个目的地只收藏首次抵达的唯一票根。
@ModelActor
public actor TicketStubStore {
    @discardableResult
    public func addFirstArrival(
        fromRegionID: String,
        toRegionID: String
    ) throws -> TicketStubDTO {
        if let existing = try firstArrivalEntity(toRegionID: toRegionID) {
            return Self.dto(from: existing)
        }
        let entity = TicketStubEntity(
            fromRegionID: fromRegionID,
            toRegionID: toRegionID,
            serialNumber: Self.makeSerialNumber(),
            artSeed: Int.random(in: 0..<6)
        )
        modelContext.insert(entity)
        try modelContext.save()
        return Self.dto(from: entity)
    }

    /// 缓存服务端首次抵达事实；同一目的地或相同 travel ID 重试时保持幂等。
    public func cacheFirstServerArrival(
        id: UUID,
        fromRegionID: String,
        toRegionID: String,
        usedAt: Date
    ) throws -> TicketStubDTO {
        if let existing = try modelContext.fetch(
            FetchDescriptor<TicketStubEntity>(
                predicate: #Predicate { $0.stubID == id }
            )
        ).first {
            return Self.dto(from: existing)
        }
        if let existing = try firstArrivalEntity(toRegionID: toRegionID) {
            return Self.dto(from: existing)
        }
        let entity = TicketStubEntity(
            stubID: id,
            fromRegionID: fromRegionID,
            toRegionID: toRegionID,
            usedAt: usedAt,
            serialNumber: Self.serialNumber(for: id),
            artSeed: Int(UInt(bitPattern: id.hashValue) % 6)
        )
        modelContext.insert(entity)
        try modelContext.save()
        return Self.dto(from: entity)
    }

    /// 全部首次抵达票根（新→旧）；旧版本遗留的重复航段只投影最早一张。
    public func all() throws -> [TicketStubDTO] {
        var descriptor = FetchDescriptor<TicketStubEntity>()
        descriptor.sortBy = [SortDescriptor(\.usedAt)]
        var destinations: Set<String> = []
        var firstArrivals: [TicketStubEntity] = []
        var removedDuplicate = false
        for entity in try modelContext.fetch(descriptor) {
            if destinations.insert(entity.toRegionID).inserted {
                firstArrivals.append(entity)
            } else {
                modelContext.delete(entity)
                removedDuplicate = true
            }
        }
        if removedDuplicate {
            try modelContext.save()
        }
        return firstArrivals
            .sorted { $0.usedAt > $1.usedAt }
            .map(Self.dto(from:))
    }

    static func makeSerialNumber() -> String {
        let digits = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        return "LT-\(digits)"
    }

    private static func serialNumber(for id: UUID) -> String {
        let compact = id.uuidString.replacingOccurrences(of: "-", with: "")
        return "LT-\(compact.prefix(6).uppercased())"
    }

    private func firstArrivalEntity(toRegionID: String) throws -> TicketStubEntity? {
        var descriptor = FetchDescriptor<TicketStubEntity>(
            predicate: #Predicate { $0.toRegionID == toRegionID }
        )
        descriptor.sortBy = [SortDescriptor(\.usedAt)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    static func dto(from entity: TicketStubEntity) -> TicketStubDTO {
        TicketStubDTO(
            id: entity.stubID,
            fromRegionID: entity.fromRegionID,
            toRegionID: entity.toRegionID,
            usedAt: entity.usedAt,
            serialNumber: entity.serialNumber,
            artSeed: entity.artSeed
        )
    }
}
