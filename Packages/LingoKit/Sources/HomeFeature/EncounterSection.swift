import CoreKit
import DomainKit
import PersistenceKit
import SwiftUI

/// 主页「开展活动」区 + 偶遇流程（plan.md §3.7）。
struct EncounterSection: View {
    let region: Region
    let deps: HomeDependencies
    /// 由组合根注入：为偶遇角色构建聊天页（Feature 间零依赖）。
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView

    @State private var isRolling = false
    @State private var noEncounterMessage: String?
    @State private var encounterResult: EncounterPresentation?

    struct EncounterPresentation: Identifiable {
        let id = UUID()
        let character: CharacterDTO
        let openingLine: String
        let origin: EncounterService.Origin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("开展活动")
                .font(.headline)
            Text("出门走走，也许会遇到有趣的人")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(region.activities) { activity in
                    Button {
                        runActivity(activity)
                    } label: {
                        VStack(spacing: 4) {
                            Text(activityEmoji(activity.id))
                                .font(.title3)
                            Text(activity.titleZh)
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRolling)
                }
            }
            if let noEncounterMessage {
                Text(noEncounterMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $encounterResult) { result in
            EncounterCardSheet(
                presentation: result,
                deps: deps,
                chatBuilder: chatBuilder
            ) {
                encounterResult = nil
            }
        }
        .animation(.default, value: noEncounterMessage)
    }

    private func activityEmoji(_ id: String) -> String {
        switch id {
        case "stroll_market": "🛍️"
        case "cafe": "☕️"
        case "park": "🌳"
        default: "🚶"
        }
    }

    private func runActivity(_ activity: Region.Activity) {
        isRolling = true
        noEncounterMessage = nil
        Task {
            defer { isRolling = false }
            guard EncounterService.shouldEncounter(roll: .random(in: 0..<1)) else {
                noEncounterMessage = "☁️ \(activity.detailZh)，很惬意，但这次没遇到什么人。"
                return
            }
            let origin = EncounterService.rollOrigin(roll: .random(in: 0..<1))
            let profile = try? await deps.economyStore.profile()
            let existingNames = Set(((try? await deps.rosterStore.allCharacters()) ?? []).map(\.card.name))
            let service = EncounterService(llm: deps.llm)
            let encounter = await service.generateEncounter(
                origin: origin,
                region: region,
                userLevel: profile?.difficultyLevel ?? .junior3,
                existingNames: existingNames
            )
            // 保存角色（未加好友）+ 建偶遇会话 + 开场白落库
            guard let characterID = try? await deps.rosterStore.addCharacter(
                card: encounter.card,
                difficulty: profile?.difficultyLevel ?? .junior3,
                isFriend: false
            ) else { return }
            if let conversation = try? await deps.chatStore.openConversation(
                characterID: characterID,
                isEncounterSession: true
            ) {
                _ = try? await deps.chatStore.appendMessage(
                    conversationID: conversation.id,
                    role: .assistant,
                    text: encounter.openingLine,
                    tokenEstimate: TokenEstimator.estimate(encounter.openingLine)
                )
            }
            if let character = try? await deps.rosterStore.character(id: characterID) {
                encounterResult = EncounterPresentation(
                    character: character,
                    openingLine: encounter.openingLine,
                    origin: encounter.origin
                )
            }
        }
    }
}

/// 偶遇卡：角色信息 + 开场白 + 聊聊/加好友/离开。
private struct EncounterCardSheet: View {
    let presentation: EncounterSection.EncounterPresentation
    let deps: HomeDependencies
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    let onDismiss: () -> Void

    @State private var showChat = false
    @State private var friendMessage: String?
    @State private var isFriend = false

    private var card: CharacterCard { presentation.character.card }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 8)
            Text(originLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Text(String(card.name.prefix(1)))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 88, height: 88)
            Text(card.name)
                .font(.title3.bold())
            Text("\(card.nationality) · \(card.age) 岁 · \(card.occupation)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("“\(presentation.openingLine)”")
                .font(.subheadline.italic())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 6) {
                ForEach(card.hobbies.prefix(3), id: \.self) { hobby in
                    Text(hobby)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
            }
            if let friendMessage {
                Text(friendMessage)
                    .font(.footnote)
                    .foregroundStyle(isFriend ? .green : .red)
            }
            HStack(spacing: 10) {
                Button {
                    showChat = true
                } label: {
                    Label("聊聊", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    addFriend()
                } label: {
                    Label(isFriend ? "已加好友" : "加好友", systemImage: isFriend ? "checkmark" : "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isFriend)
            }
            Button("下次再见", role: .cancel) {
                leave()
            }
            .font(.footnote)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showChat) {
            NavigationStack {
                chatBuilder(presentation.character)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("返回") {
                                showChat = false
                            }
                        }
                    }
            }
        }
    }

    private var originLabel: String {
        switch presentation.origin {
        case .local: "偶遇 · 当地人"
        case .domestic: "偶遇 · 来自本国其他城市"
        case .foreigner: "偶遇 · 外国旅人"
        }
    }

    private func addFriend() {
        Task {
            do {
                let profile = try await deps.economyStore.profile()
                try await deps.rosterStore.makeFriend(
                    characterID: presentation.character.id,
                    slotLimit: profile.friendSlotLimit
                )
                isFriend = true
                friendMessage = "已加入好友，以后随时可以在消息里找到 TA"
            } catch RosterStore.RosterError.friendSlotsFull {
                friendMessage = "好友位已满（上限 \((try? await deps.economyStore.profile())?.friendSlotLimit ?? 10) 个）"
            } catch {
                friendMessage = "操作失败：\(error.localizedDescription)"
            }
        }
    }

    /// 未加好友离开：会话归档只读（只能在遇到时聊）。
    private func leave() {
        Task {
            if !isFriend {
                try? await deps.chatStore.archiveConversations(characterID: presentation.character.id)
            }
            onDismiss()
        }
    }
}
