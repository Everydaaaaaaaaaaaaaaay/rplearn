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

public struct BackendNPCDiversityProfile: Codable, Sendable, Equatable {
    public let version: Int
    public let occupationDomain: String
    public let socialRole: String
    public let interactionStyle: String
    public let interestDomains: [String]
    public let traits: [String]
    public let backgroundMotif: String
    public let energy: String
    public let warmth: String
    public let structure: String

    public init(
        version: Int = 1,
        occupationDomain: String,
        socialRole: String,
        interactionStyle: String,
        interestDomains: [String],
        traits: [String],
        backgroundMotif: String,
        energy: String,
        warmth: String,
        structure: String
    ) {
        self.version = version
        self.occupationDomain = occupationDomain
        self.socialRole = socialRole
        self.interactionStyle = interactionStyle
        self.interestDomains = interestDomains
        self.traits = traits
        self.backgroundMotif = backgroundMotif
        self.energy = energy
        self.warmth = warmth
        self.structure = structure
    }
}

public struct BackendNPCDiversityReview: Codable, Sendable, Equatable {
    public enum Decision: String, Codable, Sendable {
        case accept
        case revise
    }

    public let decision: Decision
    public let similarityScore: Int
    public let dimensions: [String]
    public let guidance: [String]

    public init(
        decision: Decision,
        similarityScore: Int,
        dimensions: [String],
        guidance: [String]
    ) {
        self.decision = decision
        self.similarityScore = similarityScore
        self.dimensions = dimensions
        self.guidance = guidance
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
    func reviewEncounterNPC(
        card: BackendPublicNPCCard,
        diversityProfile: BackendNPCDiversityProfile,
        context: BackendNPCEncounterContext
    ) async throws -> BackendNPCDiversityReview
    func registerEncounterNPC(id: UUID, card: BackendPublicNPCCard, context: BackendNPCEncounterContext) async throws -> BackendPublicNPC
    func registerEncounterNPC(
        id: UUID,
        card: BackendPublicNPCCard,
        diversityProfile: BackendNPCDiversityProfile,
        context: BackendNPCEncounterContext
    ) async throws -> BackendPublicNPC
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
    public func reviewEncounterNPC(
        card: BackendPublicNPCCard,
        diversityProfile: BackendNPCDiversityProfile,
        context: BackendNPCEncounterContext
    ) async throws -> BackendNPCDiversityReview {
        BackendNPCDiversityReview(decision: .accept, similarityScore: 0, dimensions: [], guidance: [])
    }
    public func registerEncounterNPC(id: UUID, card: BackendPublicNPCCard, context: BackendNPCEncounterContext) async throws -> BackendPublicNPC {
        try await registerPublicNPC(id: id, card: card)
    }
    public func registerEncounterNPC(
        id: UUID,
        card: BackendPublicNPCCard,
        diversityProfile: BackendNPCDiversityProfile,
        context: BackendNPCEncounterContext
    ) async throws -> BackendPublicNPC {
        try await registerEncounterNPC(id: id, card: card, context: context)
    }
}

private struct RegisterPublicNPCBody: Encodable, Sendable {
    let card: BackendPublicNPCCard
    var diversityProfile: BackendNPCDiversityProfile? = nil
    let id: UUID
    var encounterContext: BackendNPCEncounterContext? = nil
}

private struct ReviewNPCDiversityBody: Encodable, Sendable {
    let card: BackendPublicNPCCard
    let diversityProfile: BackendNPCDiversityProfile
    let encounterContext: BackendNPCEncounterContext
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
    public func reviewEncounterNPC(
        card: BackendPublicNPCCard,
        diversityProfile: BackendNPCDiversityProfile,
        context: BackendNPCEncounterContext
    ) async throws -> BackendNPCDiversityReview {
        try await actorClient().send(
            path: "/v1/npcs/diversity-review",
            method: "POST",
            body: ReviewNPCDiversityBody(
                card: card,
                diversityProfile: diversityProfile,
                encounterContext: context
            )
        )
    }

    public func registerEncounterNPC(
        id: UUID,
        card: BackendPublicNPCCard,
        diversityProfile: BackendNPCDiversityProfile,
        context: BackendNPCEncounterContext
    ) async throws -> BackendPublicNPC {
        try await actorClient().send(
            path: "/v1/npcs",
            method: "POST",
            body: RegisterPublicNPCBody(
                card: card,
                diversityProfile: diversityProfile,
                id: id,
                encounterContext: context
            )
        )
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
