import Foundation
import SwiftData

/// 票根快照。
public struct TicketStubDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var fromRegionID: String
    public var toRegionID: String
    public var usedAt: Date
    public var serialNumber: String
    /// 决定票根配色花纹。
    public var artSeed: Int
}

/// 票根仓库：每次旅行后生成，票根夹翻阅。
@ModelActor
public actor TicketStubStore {
    @discardableResult
    public func addStub(fromRegionID: String, toRegionID: String) throws -> TicketStubDTO {
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

    /// 全部票根（新→旧）。
    public func all() throws -> [TicketStubDTO] {
        var descriptor = FetchDescriptor<TicketStubEntity>()
        descriptor.sortBy = [SortDescriptor(\.usedAt, order: .reverse)]
        return try modelContext.fetch(descriptor).map(Self.dto(from:))
    }

    static func makeSerialNumber() -> String {
        let digits = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        return "LT-\(digits)"
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
