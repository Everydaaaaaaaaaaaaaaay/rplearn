import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// Presence clocks belong to contact labels, outside list grouping and search.
struct RosterContactRowLabel: View {
    private struct PresenceInputs: Equatable {
        let character: CharacterDTO
        let lastAssistantMessageAt: Date?
        let pendingReplyPlan: NPCReplyPlan?
        let isActive: Bool
    }

    let character: CharacterDTO
    let lastAssistantMessageAt: Date?
    let pendingReplyPlan: NPCReplyPlan?
    @State private var presence: NPCPresenceState?
    @Environment(\.scenePhase) private var scenePhase
    private var scenePrimaryText: Color { .dsSceneTextPrimary }
    private var sceneSecondaryText: Color { .dsSceneTextSecondary }

    var body: some View {
        let isActive = scenePhase == .active && character.contactStatus != .removed
        let state = character.contactStatus == .removed ? .offline : (presence ?? currentPresence())
        content(state: state)
            .task(id: PresenceInputs(character: character, lastAssistantMessageAt: lastAssistantMessageAt,
                                     pendingReplyPlan: pendingReplyPlan, isActive: isActive)) {
                guard isActive else { return }
                while !Task.isCancelled {
                    let current = currentPresence()
                    if current != presence { presence = current }
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                }
            }
    }

    private func content(state: NPCPresenceState) -> some View {
        let status = friendStatus(state)
        return HStack(spacing: DSSpacing.sm) {
            AvatarBadge(
                name: character.displayName,
                size: 56,
                imageName: character.card.avatarAssetName,
                remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                usesPendingPlaceholder: true
            )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(character.displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(scenePrimaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                HStack(spacing: 5) {
                    if character.contactStatus != .removed {
                        Circle()
                            .fill(presenceDotColor(state))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(sceneSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.card.name)，\(status)")
    }

    private func currentPresence() -> NPCPresenceState {
        NPCAttentionPolicy.standard.presence(
            for: character, at: .now,
            lastAssistantMessageAt: lastAssistantMessageAt,
            pendingReplyPlan: pendingReplyPlan
        ).state
    }

    private func presenceDotColor(_ state: NPCPresenceState) -> Color {
        switch state {
        case .online: Color(red: 0.55, green: 0.90, blue: 0.65)
        case .recentlyActive: Color(red: 0.96, green: 0.77, blue: 0.40)
        case .offline: Color(white: 0.66)
        }
    }

    private func friendStatus(_ state: NPCPresenceState) -> String {
        if character.contactStatus == .removed {
            return "过往联系人 · 可重新添加"
        }
        let status = switch state {
        case .online: "在线"
        case .recentlyActive: "近期在线"
        case .offline: "离线"
        }
        let occupation: String
        switch character.isMainCharacter ? character.card.avatarAssetName : nil {
        case "avatar_oliver": occupation = "Bookshop assistant & aspiring novelist"
        case "avatar_ruby": occupation = "Barista, marine biology student & surf instructor"
        case "avatar_marcus": occupation = "Street photographer & record shop assistant"
        default: occupation = character.card.occupation
        }
        return "\(status) | \(character.card.nationality) · \(occupation)"
    }

}
