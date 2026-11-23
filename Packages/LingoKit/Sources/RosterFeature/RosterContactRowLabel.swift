import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 联系人行：头像带在线小圆点，名字旁是状态标签。在线时钟只属于行本身，不参与分组与搜索。
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

    var body: some View {
        let isRemoved = character.contactStatus == .removed
        let inputs = PresenceInputs(
            character: character,
            lastAssistantMessageAt: lastAssistantMessageAt,
            pendingReplyPlan: pendingReplyPlan,
            isActive: scenePhase == .active && !isRemoved
        )
        let state = isRemoved ? .offline : (presence ?? currentPresence())
        content(presence: state)
            .task(id: inputs) {
                guard inputs.isActive else { return }
                while !Task.isCancelled {
                    let current = currentPresence()
                    if current != presence { presence = current }
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                }
            }
    }

    private func content(presence: NPCPresenceState) -> some View {
        let isRemoved = character.contactStatus == .removed
        return HStack(spacing: Puff.Space.s) {
            PuffAvatar(
                name: character.displayName,
                size: 52,
                imageName: character.card.avatarAssetName,
                remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                presence: isRemoved ? nil : puffPresence(presence)
            )
            .saturation(isRemoved ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(character.displayName)
                        .font(.puff(.headline, Puff.Weight.title))
                        .foregroundStyle(Puff.Palette.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if isRemoved {
                        PuffTag("可重新添加", systemImage: "arrow.uturn.left", candy: .grape)
                    } else {
                        switch presence {
                        case .online: PuffTag("在线", candy: .mint)
                        case .recentlyActive: PuffTag("刚刚在线", candy: .sunny)
                        case .offline: EmptyView()
                        }
                    }
                }
                Text(profileLine)
                    .font(.puff(.footnote, Puff.Weight.body))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(Puff.Palette.inkFaint)
        }
        .padding(.horizontal, Puff.Space.m)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .animation(Puff.Motion.pop, value: presence)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.card.name)，\(friendStatus(presence))")
    }

    private func puffPresence(_ state: NPCPresenceState) -> PuffPresence {
        switch state {
        case .online: .online
        case .recentlyActive: .recentlyActive
        case .offline: .offline
        }
    }

    private var occupation: String {
        switch character.isMainCharacter ? character.card.avatarAssetName : nil {
        case "avatar_oliver": "Bookshop assistant & aspiring novelist"
        case "avatar_ruby": "Barista, marine biology student & surf instructor"
        case "avatar_marcus": "Street photographer & record shop assistant"
        default: character.card.occupation
        }
    }

    private var profileLine: String {
        "\(character.card.nationality) · \(occupation)"
    }

    private func currentPresence() -> NPCPresenceState {
        NPCAttentionPolicy.standard.presence(
            for: character, at: .now,
            lastAssistantMessageAt: lastAssistantMessageAt,
            pendingReplyPlan: pendingReplyPlan
        ).state
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
        return "\(status) | \(profileLine)"
    }

}
