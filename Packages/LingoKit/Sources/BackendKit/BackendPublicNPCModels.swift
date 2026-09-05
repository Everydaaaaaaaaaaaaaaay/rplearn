import Foundation

public struct BackendPublicNPCVoice: Codable, Sendable, Equatable {
    public let anchorLines: [String]
    public let boundaries: [String]
    public let conversationalHabits: [String]
    public let flaws: [String]
    public let values: [String]

    public init(
        anchorLines: [String],
        boundaries: [String],
        conversationalHabits: [String],
        flaws: [String],
        values: [String]
    ) {
        self.anchorLines = anchorLines
        self.boundaries = boundaries
        self.conversationalHabits = conversationalHabits
        self.flaws = flaws
        self.values = values
    }
}

public struct BackendPublicNPCCard: Codable, Sendable, Equatable {
    public let age: Int
    public let appearance: String
    public let background: String?
    public let birthday: String?
    public let gender: String
    public let hobbies: [String]
    public let hometown: String?
    public let languages: [String]
    public let name: String
    public let nationality: String
    public let occupation: String
    public let personaVoice: BackendPublicNPCVoice
    public let personality: String
    public let regionId: String
    public let signature: String?
    public let speechStyle: String?

    public init(
        age: Int,
        appearance: String,
        background: String?,
        birthday: String?,
        gender: String,
        hobbies: [String],
        hometown: String?,
        languages: [String],
        name: String,
        nationality: String,
        occupation: String,
        personaVoice: BackendPublicNPCVoice,
        personality: String,
        regionId: String,
        signature: String?,
        speechStyle: String?
    ) {
        self.age = age
        self.appearance = appearance
        self.background = background
        self.birthday = birthday
        self.gender = gender
        self.hobbies = hobbies
        self.hometown = hometown
        self.languages = languages
        self.name = name
        self.nationality = nationality
        self.occupation = occupation
        self.personaVoice = personaVoice
        self.personality = personality
        self.regionId = regionId
        self.signature = signature
        self.speechStyle = speechStyle
    }
}

public struct BackendPublicNPC: Codable, Sendable, Equatable {
    public struct Avatar: Codable, Sendable, Equatable {
        public let id: UUID
        public let url: URL
        public let attribution: String?
        public let sourceUrl: URL?

        public init(id: UUID, url: URL, attribution: String? = nil, sourceUrl: URL? = nil) {
            self.id = id
            self.url = url
            self.attribution = attribution
            self.sourceUrl = sourceUrl
        }
    }

    public let avatar: Avatar?
    public let card: BackendPublicNPCCard
    public let createdAt: String
    public let id: UUID
    public let travelerId: String

    public init(
        avatar: Avatar?,
        card: BackendPublicNPCCard,
        createdAt: String,
        id: UUID,
        travelerId: String
    ) {
        self.avatar = avatar
        self.card = card
        self.createdAt = createdAt
        self.id = id
        self.travelerId = travelerId
    }
}

public enum BackendNPCRelationshipStatus: String, Codable, Sendable {
    case candidate
    case friend
    case removed
}

public protocol PublicNPCRegistry: Sendable {
    func findPublicNPC(travelerID: String) async throws -> BackendPublicNPC
    func linkPublicNPC(
        npcID: UUID,
        localCharacterID: UUID,
        status: BackendNPCRelationshipStatus
    ) async throws
    func registerPublicNPC(id: UUID, card: BackendPublicNPCCard) async throws -> BackendPublicNPC
}

private struct RegisterPublicNPCBody: Encodable, Sendable {
    let card: BackendPublicNPCCard
    let id: UUID
}

private struct LinkPublicNPCBody: Encodable, Sendable {
    let localCharacterId: UUID
    let status: BackendNPCRelationshipStatus
}

extension BackendClient: PublicNPCRegistry {
    public func findPublicNPC(travelerID: String) async throws -> BackendPublicNPC {
        try await get("/v1/npcs/by-traveler-id/\(travelerID)")
    }

    public func registerPublicNPC(
        id: UUID,
        card: BackendPublicNPCCard
    ) async throws -> BackendPublicNPC {
        try await send(
            path: "/v1/npcs",
            method: "POST",
            body: RegisterPublicNPCBody(card: card, id: id)
        )
    }

    public func linkPublicNPC(
        npcID: UUID,
        localCharacterID: UUID,
        status: BackendNPCRelationshipStatus
    ) async throws {
        try await sendWithoutResponse(
            path: "/v1/npcs/\(npcID.uuidString.lowercased())/relationship",
            method: "PUT",
            body: LinkPublicNPCBody(localCharacterId: localCharacterID, status: status)
        )
    }
}
