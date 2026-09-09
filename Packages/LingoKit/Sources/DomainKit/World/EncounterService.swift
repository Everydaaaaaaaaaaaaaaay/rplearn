import CoreKit
import Foundation
import LLMKit
import PersistenceKit

/// 偶遇系统：
/// 活动 → 默认 P(偶遇)=0.35（可由活动配置覆盖）→ 60/30/10 掷来源 →
/// balanced 档 LLM 生成角色卡（失败重试 1 次，再失败回退本地模板卡）→ 偶遇卡 + 开场白。
public struct EncounterService: Sendable {
    /// 偶遇者来源。
    public enum Origin: String, Sendable, Equatable, CaseIterable {
        /// 当地人（60%）
        case local
        /// 本国其他地区的人（30%）
        case domestic
        /// 外国人（10%）
        case foreigner
    }

    /// Non-visual dimensions used to prevent two generated identities from filling
    /// effectively the same role. Raw story text remains on `CharacterCard`.
    public struct DiversityProfile: Sendable, Equatable {
        public var occupationDomain: String
        public var socialRole: String
        public var interactionStyle: String
        public var interestDomains: [String]
        public var traits: [String]
        public var backgroundMotif: String
        public var energy: String
        public var warmth: String
        public var structure: String

        public init(
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

        fileprivate var isValid: Bool {
            Self.occupationDomains.contains(occupationDomain)
                && Self.socialRoles.contains(socialRole)
                && Self.interactionStyles.contains(interactionStyle)
                && (1...4).contains(interestDomains.count)
                && Set(interestDomains).count == interestDomains.count
                && interestDomains.allSatisfy(Self.interestDomainValues.contains)
                && (2...4).contains(traits.count)
                && Set(traits).count == traits.count
                && traits.allSatisfy(Self.traitValues.contains)
                && Self.backgroundMotifs.contains(backgroundMotif)
                && ["low", "medium", "high"].contains(energy)
                && ["reserved", "balanced", "warm"].contains(warmth)
                && ["spontaneous", "balanced", "structured"].contains(structure)
        }

        static let occupationDomains = [
            "agriculture-nature", "arts-media", "business-finance", "education", "healthcare",
            "hospitality-food", "public-service", "retired", "science-technology", "service-retail",
            "skilled-trades", "sports-fitness", "student", "transport-logistics", "other",
        ]
        static let socialRoles = [
            "caregiver", "connector", "creator", "explorer", "helper", "learner", "mentor", "observer",
            "organizer", "performer", "problem-solver", "storyteller",
        ]
        static let interactionStyles = [
            "analytical", "animated", "blunt", "formal", "gentle", "humorous", "playful", "practical",
            "reflective", "reserved", "reassuring", "curious",
        ]
        static let interestDomainValues = [
            "arts", "books-learning", "community", "crafts-making", "food-drink", "games",
            "history-culture", "music", "nature", "photography-film", "sports", "technology", "travel", "wellness",
        ]
        static let traitValues = [
            "adventurous", "ambitious", "calm", "candid", "careful", "curious", "disciplined", "empathetic",
            "independent", "optimistic", "pragmatic", "reserved", "sociable", "spontaneous", "witty",
        ]
        static let backgroundMotifs = [
            "belonging", "career-change", "exploration", "family-duty", "fresh-start", "mastery", "migration",
            "ordinary-life", "recovery", "rivalry", "self-discovery", "service", "tradition",
        ]
    }

    /// 一次偶遇结果：角色卡 + 开场白。
    public struct Encounter: Sendable, Equatable {
        public var card: CharacterCard
        public var diversityProfile: DiversityProfile
        public var openingLine: String
        public var origin: Origin
        /// 是否 LLM 生成失败后的本地模板卡。
        public var isFallback: Bool
        public init(
            card: CharacterCard,
            diversityProfile: DiversityProfile,
            openingLine: String,
            origin: Origin,
            isFallback: Bool
        ) {
            self.card = card
            self.diversityProfile = diversityProfile
            self.openingLine = openingLine
            self.origin = origin
            self.isFallback = isFallback
        }
    }

    public static let encounterProbability = 0.35

    private let llm: any LLMClient

    public init(llm: any LLMClient) {
        self.llm = llm
    }

    // MARK: - 掷骰（纯函数，注入随机值可测）

    public static func shouldEncounter(roll: Double, probability: Double = encounterProbability) -> Bool {
        roll < probability
    }

    public static func rollOrigin(roll: Double) -> Origin {
        switch roll {
        case ..<0.6: .local
        case ..<0.9: .domestic
        default: .foreigner
        }
    }

    // MARK: - 生成

    /// An existing public identity gets a new opening, never a rewritten identity or relationship.
    public func openingForExisting(card: CharacterCard, activityContext: String, alreadyKnown: Bool) async throws -> String {
        let fallback = alreadyKnown ? "Hey, good to see you again! How have you been?" : "Hi! What brought you here today?"
        let request = LLMRequest(
            task: .characterGeneration, tier: .balanced,
            system: "Write one short natural English opening line for this activity. Return only the spoken line. Do not invent shared experiences, personal memories, a new job, or a change of identity. The scene is \(activityContext). Character: \(card.name), \(card.occupation), personality: \(card.personality), hobbies: \(card.hobbies.joined(separator: ", ")). The listener \(alreadyKnown ? "has met this person before; acknowledge a reunion without inventing past events" : "is meeting them for the first time").",
            messages: [.user("Say the opening line.")], maxTokens: 120, temperature: 0.7
        )
        do {
            let line = try await llm.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? fallback : line
        } catch let error as LLMError {
            if case .accessRestricted = error { throw error }
            return fallback
        } catch { return fallback }
    }

    /// 生成偶遇角色卡：LLM 失败或姓名重复时重试 1 次，再失败回退本地模板卡。
    public func generateEncounter(
        origin: Origin,
        region: Region,
        userLevel: DifficultyLevel,
        existingNames: Set<String>,
        activityContext: String? = nil,
        diversityGuidance: [String] = []
    ) async throws -> Encounter {
        for _ in 0..<2 {
            do {
                return try await generateOnce(
                origin: origin,
                region: region,
                userLevel: userLevel,
                existingNames: existingNames,
                activityContext: activityContext,
                diversityGuidance: diversityGuidance
                )
            } catch let error as LLMError {
                if case .accessRestricted = error { throw error }
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        return Self.fallbackEncounter(origin: origin, region: region, existingNames: existingNames)
    }

    private struct GeneratedCard: Decodable {
        var name: String
        var age: Int
        var gender: String
        var nationality: String
        var occupation: String
        var hobbies: [String]
        var appearance: String
        var personality: String
        var speechStyle: String
        var background: String
        var openingLine: String
        var signature: String?
        var birthday: String?
        var hometown: String?
        var languages: [String]?
        var values: [String]?
        var flaws: [String]?
        var conversationalHabits: [String]?
        var boundaries: [String]?
        var anchorLines: [String]?
        var activityRhythm: String?
        var diversityProfile: GeneratedDiversityProfile
    }

    private struct GeneratedDiversityProfile: Decodable {
        var occupationDomain: String
        var socialRole: String
        var interactionStyle: String
        var interestDomains: [String]
        var traits: [String]
        var backgroundMotif: String
        var energy: String
        var warmth: String
        var structure: String

        var domainValue: DiversityProfile {
            DiversityProfile(
                occupationDomain: occupationDomain,
                socialRole: socialRole,
                interactionStyle: interactionStyle,
                interestDomains: interestDomains,
                traits: traits,
                backgroundMotif: backgroundMotif,
                energy: energy,
                warmth: warmth,
                structure: structure
            )
        }
    }

    private func generateOnce(
        origin: Origin,
        region: Region,
        userLevel: DifficultyLevel,
        existingNames: Set<String>,
        activityContext: String?,
        diversityGuidance: [String]
    ) async throws -> Encounter {
        let request = LLMRequest(
            task: .characterGeneration,
            tier: .balanced,
            system: Self.generationPrompt(
                origin: origin,
                region: region,
                userLevel: userLevel,
                existingNames: existingNames,
                activityContext: activityContext,
                diversityGuidance: diversityGuidance
            ),
            messages: [.user("Generate one character now.")],
            maxTokens: 1_100,
            temperature: 1.0,
            responseFormat: .jsonSchema(name: "character_card", schema: Self.schema)
        )
        let output = try await llm.complete(request)
        guard let data = JSONExtractor.extractJSONData(from: output) else {
            throw LLMError.invalidResponse("角色卡输出无合法 JSON")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let generated = try decoder.decode(GeneratedCard.self, from: data)

        let diversityProfile = generated.diversityProfile.domainValue
        // 字段校验：不合格则抛错触发重试
        guard !generated.name.trimmingCharacters(in: .whitespaces).isEmpty,
              !existingNames.contains(generated.name),
              (14...85).contains(generated.age),
              !generated.openingLine.isEmpty,
              !generated.hobbies.isEmpty,
              generated.hobbies.allSatisfy(Self.isChineseHobbyTag),
              diversityProfile.isValid else {
            throw LLMError.invalidResponse("角色卡字段校验未通过")
        }

        let card = CharacterCard(
            name: generated.name,
            age: generated.age,
            gender: CharacterGender(rawValue: generated.gender) ?? .other,
            nationality: generated.nationality,
            regionID: region.id,
            occupation: generated.occupation,
            hobbies: generated.hobbies,
            appearance: generated.appearance,
            personality: generated.personality,
            speechStyle: generated.speechStyle,
            background: generated.background,
            signature: generated.signature,
            birthday: generated.birthday,
            hometown: generated.hometown,
            languages: generated.languages,
            personaVoice: PersonaVoiceProfile(
                values: generated.values ?? [],
                flaws: generated.flaws ?? [],
                conversationalHabits: generated.conversationalHabits ?? [],
                boundaries: generated.boundaries ?? [],
                anchorLines: generated.anchorLines ?? []
            ),
            activityProfile: NPCAttentionPolicy.defaultActivityProfile(
                regionID: region.id,
                rhythm: NPCActivityRhythm(rawValue: generated.activityRhythm ?? "")
                    ?? .daytime
            )
        )
        return Encounter(
            card: card,
            diversityProfile: diversityProfile,
            openingLine: generated.openingLine,
            origin: origin,
            isFallback: false
        )
    }

    private static func isChineseHobbyTag(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    static func generationPrompt(
        origin: Origin,
        region: Region,
        userLevel: DifficultyLevel,
        existingNames: Set<String>,
        activityContext: String? = nil,
        diversityGuidance: [String] = []
    ) -> String {
        let originRule = switch origin {
        case .local:
            "The character is a LOCAL living in \(region.nameEn): nationality matches \(region.countryNameEn)."
        case .domestic:
            "The character is from ANOTHER city of \(region.countryNameEn) (not \(region.nameEn)), currently in \(region.nameEn) for work/study/travel. Mention the hometown in background."
        case .foreigner:
            "The character is a FOREIGNER (not from \(region.countryNameEn)) who lives in or visits \(region.nameEn). Pick an interesting nationality."
        }
        let namesRule = existingNames.isEmpty
            ? ""
            : "Do NOT use these names: \(existingNames.sorted().joined(separator: ", "))."
        let meetingRule = activityContext.map {
            "The meeting happens during this activity: \($0). The occupation, routine or interests should make the presence plausible, and opening_line must fit this exact moment."
        } ?? "The meeting happens during an ordinary local activity."
        let diversityRule = diversityGuidance.isEmpty
            ? ""
            : "A previous candidate overlapped the library. Follow every correction below:\n- "
                + diversityGuidance.joined(separator: "\n- ")
        return """
        You create a believable stranger the user bumps into in \(region.nameEn) \
        (\(region.countryNameEn)). \(originRule)

        \(meetingRule)
        \(diversityRule)

        Requirements:
        - Diverse and specific: a real-feeling occupation, 3-4 concrete hobbies, distinctive \
        personality with one small flaw, provisional appearance, one-sentence speech style, \
        a two-sentence background. \(namesRule)
        - Write every item in hobbies as a concise, natural Simplified Chinese UI tag \
        (for example: "做手工意面", "收藏黑胶唱片", "打乒乓球"). Do not include English translations \
        or punctuation in those hobby tags.
        - The user is a Chinese English learner at level: \(PromptBuilder.languageGuidance(for: userLevel))
        - opening_line: the character's first casual words to the user in English \
        (they just met during an activity), matching that level. 1-2 sentences, friendly, natural.
        - Add a short personal signature, birthday (MM-DD), hometown and spoken languages.
        - activity_rhythm describes when this person is naturally reachable. Choose earlyBird, daytime, \
        nightOwl or irregular from their occupation, habits and background; do not default everyone to daytime.
        - Define a stable voice bible: 2-4 values, 1-2 human flaws, 3-5 observable conversational habits, \
        1-3 boundaries, and 4 short anchor lines covering ordinary talk, awkwardness, disagreement and care. \
        These must all express the same personality and speech style. Write these fields in English.
        - Choose age (14-85) and gender freely for a believable person. Do not prefer a \
        youthful, conventionally attractive character by default.
        - Classify the identity into diversity_profile using only the allowed enum values. The profile must \
        truthfully summarize the occupation domain, social function, interaction style, interests, traits, \
        background motif, energy, warmth and structure. It is checked against the shared character library.
        - Appearance will be finalized from a reviewed portrait after this narrative is generated. \
        Keep appearance provisional; do not lock hair, eye color, facial features, body build, \
        clothing or pose into background, personality, opening_line or other narrative fields. \
        Nationality, occupation and personality must remain independent of the portrait style.
        - gender is one of: male / female / other.
        Respond with JSON only.
        """
    }

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "age": ["type": "integer"],
            "gender": ["type": "string", "enum": ["male", "female", "other"]],
            "nationality": ["type": "string"],
            "occupation": ["type": "string"],
            "hobbies": ["type": "array", "items": ["type": "string"]],
            "appearance": ["type": "string"],
            "personality": ["type": "string"],
            "speech_style": ["type": "string"],
            "background": ["type": "string"],
            "opening_line": ["type": "string"],
            "signature": ["type": "string"],
            "birthday": ["type": "string"],
            "hometown": ["type": "string"],
            "languages": ["type": "array", "items": ["type": "string"]],
            "values": ["type": "array", "items": ["type": "string"]],
            "flaws": ["type": "array", "items": ["type": "string"]],
            "conversational_habits": ["type": "array", "items": ["type": "string"]],
            "boundaries": ["type": "array", "items": ["type": "string"]],
            "anchor_lines": ["type": "array", "items": ["type": "string"]],
            "activity_rhythm": [
                "type": "string", "enum": ["earlyBird", "daytime", "nightOwl", "irregular"],
            ],
            "diversity_profile": [
                "type": "object",
                "properties": [
                    "occupation_domain": [
                        "type": "string", "enum": .array(DiversityProfile.occupationDomains.map(JSONValue.string)),
                    ],
                    "social_role": [
                        "type": "string", "enum": .array(DiversityProfile.socialRoles.map(JSONValue.string)),
                    ],
                    "interaction_style": [
                        "type": "string", "enum": .array(DiversityProfile.interactionStyles.map(JSONValue.string)),
                    ],
                    "interest_domains": [
                        "type": "array", "minItems": 1, "maxItems": 4, "uniqueItems": true,
                        "items": [
                            "type": "string",
                            "enum": .array(DiversityProfile.interestDomainValues.map(JSONValue.string)),
                        ],
                    ],
                    "traits": [
                        "type": "array", "minItems": 2, "maxItems": 4, "uniqueItems": true,
                        "items": [
                            "type": "string", "enum": .array(DiversityProfile.traitValues.map(JSONValue.string)),
                        ],
                    ],
                    "background_motif": [
                        "type": "string", "enum": .array(DiversityProfile.backgroundMotifs.map(JSONValue.string)),
                    ],
                    "energy": ["type": "string", "enum": ["low", "medium", "high"]],
                    "warmth": ["type": "string", "enum": ["reserved", "balanced", "warm"]],
                    "structure": ["type": "string", "enum": ["spontaneous", "balanced", "structured"]],
                ],
                "required": [
                    "occupation_domain", "social_role", "interaction_style", "interest_domains", "traits",
                    "background_motif", "energy", "warmth", "structure",
                ],
                "additionalProperties": false,
            ],
        ],
        "required": [
            "name", "age", "gender", "nationality", "occupation", "hobbies",
            "appearance", "personality", "speech_style", "background", "opening_line", "activity_rhythm",
            "diversity_profile",
        ],
        "additionalProperties": false,
    ]

    // MARK: - 本地模板兜底

    static func fallbackEncounter(origin: Origin, region: Region, existingNames: Set<String>) -> Encounter {
        let templates: [(String, Int, CharacterGender, String, [String])] = [
            ("Sam Porter", 29, .male, "street food vendor", ["烹饪", "骑行", "经典电影"]),
            ("Mia Chen", 24, .female, "graduate student", ["摄影", "桌游", "徒步"]),
            ("Alex Novak", 33, .other, "freelance designer", ["素描", "咖啡品鉴", "黑胶收藏"]),
        ]
        let pick = templates.first { !existingNames.contains($0.0) } ?? templates[0]
        let nationality = origin == .foreigner ? "Canadian" : region.countryNameEn
        let card = CharacterCard(
            name: pick.0,
            age: pick.1,
            gender: pick.2,
            nationality: nationality,
            regionID: region.id,
            occupation: pick.3,
            hobbies: pick.4,
            appearance: "friendly face, casual clothes",
            personality: "easygoing, chatty, curious about people",
            speechStyle: "casual and simple",
            background: "Has lived around \(region.nameEn) for a few years and knows the area well.",
            signature: "Good stories usually start with taking the long way home.",
            hometown: region.nameEn,
            languages: ["English"],
            personaVoice: PersonaVoiceProfile(
                values: ["curiosity", "fairness"],
                flaws: ["sometimes acts before thinking"],
                conversationalHabits: ["uses short casual sentences", "asks one concrete question", "gently jokes about small mishaps"],
                boundaries: ["does not pressure friends to disclose"],
                anchorLines: [
                    "Okay, that was definitely not my smoothest idea.",
                    "Wait, really? Tell me the short version.",
                    "I don't quite agree, but I get where you're coming from.",
                    "Hey, you don't have to solve everything tonight.",
                ]
            ),
            activityProfile: NPCAttentionPolicy.defaultActivityProfile(
                regionID: region.id,
                rhythm: pick.3 == "graduate student" || pick.3 == "freelance designer"
                    ? .irregular
                    : .daytime
            )
        )
        return Encounter(
            card: card,
            diversityProfile: DiversityProfile(
                occupationDomain: pick.3 == "graduate student"
                    ? "student" : pick.3 == "street food vendor" ? "hospitality-food" : "arts-media",
                socialRole: pick.3 == "freelance designer" ? "creator" : "connector",
                interactionStyle: "curious",
                interestDomains: ["food-drink", "travel"],
                traits: ["curious", "sociable"],
                backgroundMotif: "ordinary-life",
                energy: "medium",
                warmth: "warm",
                structure: "balanced"
            ),
            openingLine: "Oh hey! Sorry, didn't mean to bump into you - first time around here?",
            origin: origin,
            isFallback: true
        )
    }
}
