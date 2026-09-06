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

        public init(id: UUID, url: URL) {
            self.id = id
            self.url = url
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
    func selectEncounter(context: BackendNPCEncounterContext) async throws -> BackendPublicNPC?
    func registerEncounterNPC(id: UUID, card: BackendPublicNPCCard, context: BackendNPCEncounterContext) async throws -> BackendPublicNPC
    func findPublicNPC(travelerID: String) async throws -> BackendPublicNPC
    func linkPublicNPC(
        npcID: UUID,
        localCharacterID: UUID,
        status: BackendNPCRelationshipStatus
    ) async throws
    func registerPublicNPC(id: UUID, card: BackendPublicNPCCard) async throws -> BackendPublicNPC
}

public struct BackendNPCEncounterContext: Codable, Sendable {
    public let regionId: String
    public let activityId: String
    public let category: String
    public let language: String
    public init(regionID: String, activityID: String, category: String, language: String = "English") {
        self.regionId = regionID; self.activityId = activityID; self.category = category; self.language = language
    }
}

extension PublicNPCRegistry {
    public func selectEncounter(context: BackendNPCEncounterContext) async throws -> BackendPublicNPC? { nil }
    public func registerEncounterNPC(id: UUID, card: BackendPublicNPCCard, context: BackendNPCEncounterContext) async throws -> BackendPublicNPC {
        try await registerPublicNPC(id: id, card: card)
    }
}

private struct RegisterPublicNPCBody: Encodable, Sendable {
    let card: BackendPublicNPCCard
    let id: UUID
    var encounterContext: BackendNPCEncounterContext? = nil
}

private struct LinkPublicNPCBody: Encodable, Sendable {
    let localCharacterId: UUID
    let status: BackendNPCRelationshipStatus
}

extension BackendClient: PublicNPCRegistry {
    public func selectEncounter(context: BackendNPCEncounterContext) async throws -> BackendPublicNPC? {
        struct Selection: Decodable, Sendable { let npc: BackendPublicNPC? }
        let result: Selection = try await actorClient().send(path: "/v1/npcs/encounters", method: "POST", body: context)
        return result.npc
    }

    public func registerEncounterNPC(id: UUID, card: BackendPublicNPCCard, context: BackendNPCEncounterContext) async throws -> BackendPublicNPC {
        try await actorClient().send(path: "/v1/npcs", method: "POST", body: RegisterPublicNPCBody(card: card, id: id, encounterContext: context))
    }
    public func findPublicNPC(travelerID: String) async throws -> BackendPublicNPC {
        try await publicGet("/v1/npcs/by-traveler-id/\(travelerID)")
    }

    public func registerPublicNPC(
        id: UUID,
        card: BackendPublicNPCCard
    ) async throws -> BackendPublicNPC {
        try await actorClient().send(
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
        try await actorClient().sendWithoutResponse(
            path: "/v1/npcs/\(npcID.uuidString.lowercased())/relationship",
            method: "PUT",
            body: LinkPublicNPCBody(localCharacterId: localCharacterID, status: status)
        )
    }
}
