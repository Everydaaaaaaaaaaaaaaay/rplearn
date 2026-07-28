import Foundation

public struct BackendUserProfile: Codable, Sendable, Equatable {
    public let coins: Int
    public let currentRegionId: String
    public let difficulty: String
    public let displayName: String
    public let experiencePoints: Int
    public let friendSlotLimit: Int
    public let gameLevel: Int
    public let hasCompletedOnboarding: Bool
    public let quizGloballyEnabled: Bool
    public let starterRegionId: String?
    public let unlockedRegionIds: [String]
    public let updatedAt: String
    public let version: Int
}

public struct BackendTicket: Codable, Sendable, Equatable, Identifiable {
    public let countryCode: String?
    public let createdAt: String
    public let id: UUID
    public let source: String
    public let type: String
}

public struct BackendFirstArrival: Codable, Sendable, Equatable, Identifiable {
    public let arrivedAt: String
    public let fromRegionId: String
    public let id: UUID
    public let toRegionId: String
}

public struct BackendUserSnapshot: Codable, Sendable, Equatable {
    public let firstArrivals: [BackendFirstArrival]
    public let profile: BackendUserProfile
    public let tickets: [BackendTicket]

    public init(
        firstArrivals: [BackendFirstArrival] = [],
        profile: BackendUserProfile,
        tickets: [BackendTicket]
    ) {
        self.firstArrivals = firstArrivals
        self.profile = profile
        self.tickets = tickets
    }

    private enum CodingKeys: String, CodingKey {
        case firstArrivals
        case profile
        case tickets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstArrivals = try container.decodeIfPresent(
            [BackendFirstArrival].self,
            forKey: .firstArrivals
        ) ?? []
        profile = try container.decode(BackendUserProfile.self, forKey: .profile)
        tickets = try container.decode([BackendTicket].self, forKey: .tickets)
    }
}

public struct BackendSyncSnapshot: Codable, Sendable, Equatable {
    public let cursor: String
    public let state: BackendUserSnapshot

    public init(cursor: String, state: BackendUserSnapshot) {
        self.cursor = cursor
        self.state = state
    }
}

public struct BackendSyncChange: Decodable, Sendable, Equatable {
    public let commandId: UUID
    public let eventId: UUID
    public let eventType: String
    public let occurredAt: String
    public let payload: BackendJSONValue?
    public let sequence: String
}

public struct BackendSyncPage: Decodable, Sendable, Equatable {
    public let changes: [BackendSyncChange]
    public let hasMore: Bool
    public let nextCursor: String
}

public struct BackendTravelResult: Decodable, Sendable, Equatable {
    public let consumedTicketId: UUID?
    public let fromRegionId: String
    public let profileVersion: Int
    public let toRegionId: String
    public let travelId: UUID
    public let traveledAt: String
    public let unlockedNow: Bool
}

public struct BackendTicketPurchaseResult: Decodable, Sendable, Equatable {
    public let coins: Int
    public let ticket: BackendTicket
}

public struct BackendStoryCompletion: Decodable, Sendable, Equatable {
    public let coins: Int
    public let rewardCoins: Int
    public let storyId: String
}
