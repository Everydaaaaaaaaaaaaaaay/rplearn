import BackendKit
import PersistenceKit

/// 公共 NPC 身份只包含稳定人物卡；好友状态、记忆、关系和成长始终留在用户私有分支。
public enum PublicNPCAdapter {
    public static func backendCard(from card: CharacterCard) -> BackendPublicNPCCard {
        BackendPublicNPCCard(
            age: card.age,
            appearance: card.appearance,
            background: card.background,
            birthday: card.birthday,
            gender: card.gender.rawValue,
            hobbies: card.hobbies,
            hometown: card.hometown,
            languages: card.languages ?? [],
            name: card.name,
            nationality: card.nationality,
            occupation: card.occupation,
            personaVoice: BackendPublicNPCVoice(
                anchorLines: card.personaVoice?.anchorLines ?? [],
                boundaries: card.personaVoice?.boundaries ?? [],
                conversationalHabits: card.personaVoice?.conversationalHabits ?? [],
                flaws: card.personaVoice?.flaws ?? [],
                values: card.personaVoice?.values ?? []
            ),
            personality: card.personality,
            regionId: card.regionID,
            signature: card.signature,
            speechStyle: card.speechStyle
        )
    }

    public static func characterCard(from npc: BackendPublicNPC) -> CharacterCard {
        let source = npc.card
        return CharacterCard(
            name: source.name,
            age: source.age,
            gender: CharacterGender(rawValue: source.gender) ?? .other,
            nationality: source.nationality,
            regionID: source.regionId,
            occupation: source.occupation,
            hobbies: source.hobbies,
            appearance: source.appearance,
            personality: source.personality,
            speechStyle: source.speechStyle,
            background: source.background,
            avatarID: npc.avatar?.id.uuidString.lowercased(),
            avatarRemoteURL: npc.avatar?.url.absoluteString,
            avatarAttribution: npc.avatar?.attribution,
            avatarSourceURL: npc.avatar?.sourceUrl?.absoluteString,
            signature: source.signature,
            birthday: source.birthday,
            hometown: source.hometown,
            languages: source.languages,
            personaVoice: PersonaVoiceProfile(
                values: source.personaVoice.values,
                flaws: source.personaVoice.flaws,
                conversationalHabits: source.personaVoice.conversationalHabits,
                boundaries: source.personaVoice.boundaries,
                anchorLines: source.personaVoice.anchorLines
            )
        )
    }
}
