import Foundation
import PersistenceKit

/// 没有自由文本可交给模型审阅时，使用保守、确定性的社会事件结算。
///
/// 活动与剧情只证明“共同经历发生过”，不推断用户的英语水平、具体情绪或隐藏动机。
public enum RelationshipContextEvent {
    public static func sharedActivity(
        title: String,
        companionName: String
    ) -> RelationshipSignal {
        RelationshipSignal(
            warmth: 0.62,
            responsiveness: 0.58,
            respect: 0.72,
            empathy: 0.42,
            reciprocity: 0.62,
            disclosure: 0.18,
            resonance: 0.56,
            engagement: 0.72,
            boundaryHarm: 0,
            repair: 0,
            significance: 0.58,
            confidence: 0.92,
            reasonZh: "与\(firstName(companionName))一起完成了「\(compact(title))」"
        )
    }

    public static func completedStory(characterName: String) -> RelationshipSignal {
        RelationshipSignal(
            warmth: 0.66,
            responsiveness: 0.62,
            respect: 0.74,
            empathy: 0.48,
            reciprocity: 0.66,
            disclosure: 0.28,
            resonance: 0.64,
            engagement: 0.78,
            boundaryHarm: 0,
            repair: 0,
            significance: 0.72,
            confidence: 0.95,
            reasonZh: "与\(firstName(characterName))共同经历了一段城市故事"
        )
    }

    /// 当前城市的同行人必须已经是好友；多个候选时优先特别关心、主角色与更早认识的人。
    public static func preferredCompanion(
        in regionID: String,
        characters: [CharacterDTO]
    ) -> CharacterDTO? {
        characters
            .filter { $0.isFriend && $0.card.regionID == regionID }
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                if $0.isMainCharacter != $1.isMainCharacter { return $0.isMainCharacter }
                if $0.metAt != $1.metAt { return $0.metAt < $1.metAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    /// 只把脚本中真实出场的已知主角色视为剧情参与者，避免同名路人或未出场角色串账。
    public static func storyParticipants(
        in characters: [CharacterDTO],
        speakerNames: Set<String>
    ) -> [CharacterDTO] {
        let normalizedSpeakers = Set(speakerNames.map(normalizedName))
        return characters
            .filter { character in
                guard character.isMainCharacter else { return false }
                let fullName = normalizedName(character.card.name)
                let givenName = normalizedName(firstName(character.card.name))
                return normalizedSpeakers.contains(fullName)
                    || normalizedSpeakers.contains(givenName)
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// 同一章节与角色始终得到同一个 ID，使剧情重玩和完成回调重试保持幂等。
    public static func storyCompletionID(
        storyID: String,
        characterID: UUID
    ) -> UUID {
        stableUUID("story|\(storyID)|\(characterID.uuidString.lowercased())")
    }

    private static func stableUUID(_ value: String) -> UUID {
        let bytes = Array(value.utf8)
        let first = fnv1a(bytes, seed: 0xcbf29ce484222325)
        let second = fnv1a(bytes.reversed(), seed: 0x84222325cbf29ce4)
        var uuidBytes = withUnsafeBytes(of: first.bigEndian, Array.init)
            + withUnsafeBytes(of: second.bigEndian, Array.init)
        // 版本 8 明确表示这是应用定义的稳定 UUID，而不是随机 UUID 或标准 SHA-1 v5。
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x80
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    private static func fnv1a<S: Sequence>(
        _ bytes: S,
        seed: UInt64
    ) -> UInt64 where S.Element == UInt8 {
        bytes.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100000001b3
        }
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func firstName(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? value
    }

    private static func compact(_ value: String) -> String {
        String(
            value
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .prefix(36)
        )
    }
}

public struct RelationshipContextEventService: Sendable {
    private let rosterStore: RosterStore

    public init(rosterStore: RosterStore) {
        self.rosterStore = rosterStore
    }

    @discardableResult
    public func apply(
        characterID: UUID,
        signal: RelationshipSignal,
        source: RelationshipEventRecord.Source,
        eventID: UUID,
        at date: Date = .now
    ) async throws -> RelationshipSnapshot {
        try await rosterStore.mutateRelationship(characterID: characterID) { latest in
            RelationshipEngine.apply(
                signal,
                to: latest,
                source: source,
                messageID: eventID,
                messageCreatedAt: date,
                messageOrderIndex: -1,
                at: date
            )
        }
    }
}
