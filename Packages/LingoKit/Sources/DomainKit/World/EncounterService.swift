import CoreKit
import Foundation
import LLMKit
import PersistenceKit

/// 偶遇系统（plan.md §3.7）：
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

    /// 一次偶遇结果：角色卡 + 开场白。
    public struct Encounter: Sendable, Equatable {
        public var card: CharacterCard
        public var openingLine: String
        public var origin: Origin
        /// 是否 LLM 生成失败后的本地模板卡。
        public var isFallback: Bool
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

    /// 生成偶遇角色卡：LLM 失败或姓名重复时重试 1 次，再失败回退本地模板卡。
    public func generateEncounter(
        origin: Origin,
        region: Region,
        userLevel: DifficultyLevel,
        existingNames: Set<String>
    ) async -> Encounter {
        for _ in 0..<2 {
            if let generated = try? await generateOnce(
                origin: origin,
                region: region,
                userLevel: userLevel,
                existingNames: existingNames
            ) {
                return generated
            }
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
    }

    private func generateOnce(
        origin: Origin,
        region: Region,
        userLevel: DifficultyLevel,
        existingNames: Set<String>
    ) async throws -> Encounter {
        let request = LLMRequest(
            task: .characterGeneration,
            tier: .balanced,
            system: Self.generationPrompt(origin: origin, region: region, userLevel: userLevel, existingNames: existingNames),
            messages: [.user("Generate one character now.")],
            maxTokens: 900,
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

        // 字段校验：不合格则抛错触发重试
        guard !generated.name.trimmingCharacters(in: .whitespaces).isEmpty,
              !existingNames.contains(generated.name),
              (14...85).contains(generated.age),
              !generated.openingLine.isEmpty,
              !generated.hobbies.isEmpty else {
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
            background: generated.background
        )
        return Encounter(card: card, openingLine: generated.openingLine, origin: origin, isFallback: false)
    }

    static func generationPrompt(
        origin: Origin,
        region: Region,
        userLevel: DifficultyLevel,
        existingNames: Set<String>
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
        return """
        You create a believable stranger the user bumps into in \(region.nameEn) \
        (\(region.countryNameEn)). \(originRule)

        Requirements:
        - Diverse and specific: a real-feeling occupation, 3-4 concrete hobbies, distinctive \
        personality with one small flaw, vivid appearance, one-sentence speech style, \
        a two-sentence background. \(namesRule)
        - The user is a Chinese English learner at level: \(PromptBuilder.languageGuidance(for: userLevel))
        - opening_line: the character's first casual words to the user in English \
        (they just met during an activity), matching that level. 1-2 sentences, friendly, natural.
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
        ],
        "required": [
            "name", "age", "gender", "nationality", "occupation", "hobbies",
            "appearance", "personality", "speech_style", "background", "opening_line",
        ],
        "additionalProperties": false,
    ]

    // MARK: - 本地模板兜底

    static func fallbackEncounter(origin: Origin, region: Region, existingNames: Set<String>) -> Encounter {
        let templates: [(String, Int, CharacterGender, String, [String])] = [
            ("Sam Porter", 29, .male, "street food vendor", ["cooking", "cycling", "old movies"]),
            ("Mia Chen", 24, .female, "graduate student", ["photography", "board games", "hiking"]),
            ("Alex Novak", 33, .other, "freelance designer", ["sketching", "coffee tasting", "vinyl records"]),
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
            background: "Has lived around \(region.nameEn) for a few years and knows the area well."
        )
        return Encounter(
            card: card,
            openingLine: "Oh hey! Sorry, didn't mean to bump into you - first time around here?",
            origin: origin,
            isFallback: true
        )
    }
}
