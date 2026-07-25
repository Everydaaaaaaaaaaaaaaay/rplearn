import CoreKit
import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct ActivitiesView: View {
    private let deps: HomeDependencies
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView

    @State private var profile: UserProfileDTO?
    @State private var isRollingID: String?
    @State private var toast: String?
    @State private var encounterResult: EncounterPresentation?

    public init(
        deps: HomeDependencies,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView
    ) {
        self.deps = deps
        self.chatBuilder = chatBuilder
    }

    private var region: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let region {
                    DSChip("\(flag(region.countryCode)) \(region.nameZh)", tint: .dsSky, prominent: true)
                    Text("出门走走，也许会遇到有趣的人")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(region.activities) { activity in
                        activityCard(activity, region: region)
                    }
                    if let toast {
                        Label(toast, systemImage: "cloud.sun.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(DSSpacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.dsBubbleIncoming, in: RoundedRectangle(cornerRadius: DSRadius.inline))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle("城市活动")
        .task { profile = try? await deps.economyStore.profile() }
        .sheet(item: $encounterResult) { result in
            EncounterCardSheet(presentation: result, deps: deps, chatBuilder: chatBuilder) {
                encounterResult = nil
            }
        }
        .animation(DSAnimation.gentle, value: toast)
    }

    private func activityCard(_ activity: Region.Activity, region: Region) -> some View {
        Button {
            runActivity(activity, region: region)
        } label: {
            HStack(spacing: DSSpacing.md) {
                Text(activityEmoji(activity.id))
                    .font(.system(size: 34))
                    .frame(width: 58, height: 58)
                    .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: DSRadius.inline))
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.titleZh)
                        .font(.headline)
                    Text(activity.detailZh)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isRollingID == activity.id {
                    ProgressView().tint(.dsSky)
                } else {
                    Text("出发")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.dsSky)
                }
            }
            .dsCard()
        }
        .buttonStyle(.pressableCard)
        .disabled(isRollingID != nil)
    }

    private func runActivity(_ activity: Region.Activity, region: Region) {
        isRollingID = activity.id
        toast = nil
        Task {
            defer { isRollingID = nil }
            guard EncounterService.shouldEncounter(roll: .random(in: 0..<1)) else {
                toast = "\(activity.detailZh)，很惬意，但这次没遇到什么人。"
                return
            }
            let origin = EncounterService.rollOrigin(roll: .random(in: 0..<1))
            let currentProfile = try? await deps.economyStore.profile()
            let names = Set(((try? await deps.rosterStore.allCharacters()) ?? []).map(\.card.name))
            let encounter = await EncounterService(llm: deps.llm).generateEncounter(
                origin: origin,
                region: region,
                userLevel: currentProfile?.difficultyLevel ?? .junior3,
                existingNames: names
            )
            guard let characterID = try? await deps.rosterStore.addCharacter(
                card: encounter.card,
                difficulty: currentProfile?.difficultyLevel ?? .junior3,
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

    private func activityEmoji(_ id: String) -> String {
        switch id {
        case "stroll_market": "🛍️"
        case "cafe": "☕️"
        case "park": "🌳"
        default: "🚶"
        }
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}

private struct EncounterPresentation: Identifiable {
    let id = UUID()
    let character: CharacterDTO
    let openingLine: String
    let origin: EncounterService.Origin
}

private struct EncounterCardSheet: View {
    let presentation: EncounterPresentation
    let deps: HomeDependencies
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    let onDismiss: () -> Void

    @State private var showChat = false
    @State private var friendMessage: String?
    @State private var isFriend = false

    private var card: CharacterCard { presentation.character.card }

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 8)
            DSChip(originLabel, tint: .dsCyan)
            AvatarBadge(name: card.name, size: 88)
            Text(card.name).font(.title2.bold())
            Text("\(card.nationality) · \(card.age) 岁 · \(card.occupation)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("“\(presentation.openingLine)”")
                .font(.subheadline.italic())
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard(padding: DSSpacing.sm)
            HStack(spacing: DSSpacing.xs) {
                ForEach(card.hobbies.prefix(3), id: \.self) { DSChip($0, tint: .dsSky) }
            }
            if let friendMessage {
                Text(friendMessage)
                    .font(.footnote)
                    .foregroundStyle(isFriend ? Color.dsSuccess : Color.dsDanger)
            }
            HStack(spacing: DSSpacing.sm) {
                Button("聊聊") { showChat = true }
                    .buttonStyle(.duoPrimary)
                Button(isFriend ? "已加好友" : "加好友") { addFriend() }
                    .buttonStyle(.duo(.outline))
                    .disabled(isFriend)
            }
            Button("下次再见", role: .cancel) { leave() }
                .font(.footnote)
            Spacer(minLength: DSSpacing.xs)
        }
        .padding(.horizontal, DSSpacing.lg)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showChat) {
            NavigationStack {
                chatBuilder(presentation.character)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("返回") { showChat = false }
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
                Haptics.notify(.success)
                friendMessage = "已加入好友，以后随时可以在消息里找到 TA"
            } catch RosterStore.RosterError.friendSlotsFull {
                friendMessage = "好友位已满"
            } catch {
                friendMessage = "操作失败：\(error.localizedDescription)"
            }
        }
    }

    private func leave() {
        Task {
            if !isFriend {
                try? await deps.chatStore.archiveConversations(characterID: presentation.character.id)
            }
            onDismiss()
        }
    }
}
