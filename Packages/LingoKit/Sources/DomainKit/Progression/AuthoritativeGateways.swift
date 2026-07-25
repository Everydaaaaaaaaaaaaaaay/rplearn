import Foundation
import PersistenceKit

public struct TravelCommandResult: Sendable, Equatable {
    public let fromRegionID: String
    public let toRegionID: String
    public let travelID: UUID
    public let traveledAt: Date

    public init(
        fromRegionID: String,
        toRegionID: String,
        travelID: UUID,
        traveledAt: Date
    ) {
        self.fromRegionID = fromRegionID
        self.toRegionID = toRegionID
        self.travelID = travelID
        self.traveledAt = traveledAt
    }
}

/// 资产修改由服务器事务执行；客户端只提交意图。
public protocol TicketPurchaseGateway: Sendable {
    func purchaseTicket(type: ItemType, countryCode: String?) async throws -> ItemDTO
}

public protocol ProfileCommandGateway: Sendable {
    func updateProfile(
        _ mutate: @Sendable (inout UserProfileDTO) -> Void
    ) async throws -> UserProfileDTO
}

public protocol ProgressionRewardGateway: Sendable {
    /// 返回 true 表示本次首次领取；false 表示服务端已发放过。
    func claimStarterTicket() async throws -> Bool
    func completeStory(_ storyID: String) async throws -> Bool
}

/// 旅行命令由服务器决定是否消耗机票以及是否新增解锁。
public protocol TravelCommandGateway: Sendable {
    func travel(targetRegionID: String, ticketID: UUID?) async throws -> TravelCommandResult
}
