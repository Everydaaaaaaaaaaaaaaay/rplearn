import CoreKit
import DesignSystem
import DictKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

struct EncounterCardSheet: View {
    let presentation: EncounterPresentation
    let deps: HomeDependencies
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshedCharacter: CharacterDTO?
    @State private var showChat = false
    @State private var friendMessage: String?
    @State private var isFriend = false
    @State private var hasRevealed = false
    @State private var wordSelection: TokenSelection?
    @State private var friendSlotsOccupied: Int?
    @State private var friendSlotLimit: Int?

    private var character: CharacterDTO { refreshedCharacter ?? presentation.character }
    private var card: CharacterCard { character.card }
    private var tint: Color { presentation.activity.category.tint }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 36, height: 5)
                    .padding(.top, 2)

                encounterHeader
                characterCard
                if isFriendSlotFull, deps.access.isGuest {
                    Button("登录，解锁 5 个好友位") {
                        onDismiss()
                        deps.access.requestSignIn("登录即可将普通好友位从 3 个提升到 5 个，剧情旅伴不占位。")
                    }.buttonStyle(.dsActionPrimary)
                }

                if let friendMessage {
                    Label(
                        friendMessage,
                        systemImage: isFriend ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isFriend ? Color.dsSuccess : Color.dsDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.sm)
                    .background(
                        (isFriend ? Color.dsSuccess : Color.dsDanger).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: DSRadius.inline)
                    )
                }

                if let friendCapacityText {
                    Label(friendCapacityText, systemImage: "person.2")
                        .font(.footnote)
                        .fontWeight(isFriendSlotNearLimit ? .semibold : .regular)
                        .foregroundStyle(isFriendSlotFull ? Color.dsDanger : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .monospacedDigit()
                        .accessibilityLabel(friendCapacityAccessibilityLabel)
                }

                HStack(spacing: DSSpacing.sm) {
                    Button("开始聊天") { showChat = true }
                        .buttonStyle(.dsAction(.tinted(tint)))
                    Button(friendButtonTitle) { addFriend() }
                        .buttonStyle(.dsAction(.secondary))
                        .disabled(isFriend || isFriendSlotFull)
                }

                Button("先告别", role: .cancel) { leave() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DSSpacing.xs)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.md)
            .opacity(hasRevealed ? 1 : 0)
            .offset(y: reduceMotion || hasRevealed ? 0 : 12)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                let speech = deps.speech
                Task {
                    await speech.speak(
                        SpeechRequest(text: word, language: "en-US", purpose: .pronunciation)
                    )
                }
            },
            favoriteActions: wordFavoriteActions,
            aiFallback: aiWordFallback)
        .onAppear {
            withAnimation(reduceMotion ? DSAnimation.feedback : DSAnimation.scene) {
                hasRevealed = true
            }
        }
        .task {
            refreshedCharacter = try? await deps.rosterStore.character(id: character.id)
            await loadFriendCapacity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { notification in
            guard notification.object as? UUID == character.id else { return }
            Task { refreshedCharacter = try? await deps.rosterStore.character(id: character.id) }
        }
        .fullScreenCover(isPresented: $showChat) {
            NavigationStack {
                chatBuilder(character)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("返回") { showChat = false }
                        }
                    }
            }
        }
    }

    private var encounterHeader: some View {
        VStack(spacing: DSSpacing.xs) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 108, height: 108)
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 1)
                    .frame(width: 94, height: 94)
                AvatarBadge(
                    name: card.name,
                    size: 82,
                    imageName: card.avatarAssetName,
                    remoteURL: card.avatarRemoteURL.flatMap(URL.init(string:)),
                    usesPendingPlaceholder: true
                )
            }

            Label(rarityLabel, systemImage: rarityIcon)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12), in: Capsule())

            Text(encounterContext)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var encounterContext: String {
        if let companionName = presentation.companionName {
            let name = companionName.split(whereSeparator: \.isWhitespace).first.map(String.init)
                ?? companionName
            return "与 \(name) 在「\(presentation.activity.titleZh)」途中"
        }
        return "在「\(presentation.activity.titleZh)」途中"
    }

    private var characterCard: some View {
        VStack(spacing: DSSpacing.sm) {
            VStack(spacing: 3) {
                Text(card.name)
                    .font(.system(.title2, design: .rounded, weight: .black))
                Text("\(card.nationality) · \(card.age) 岁 · \(card.occupation)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TappableText(
                tokens: TokenCache.tokens(
                    for: "“\(presentation.openingLine)”",
                    cacheKey: "encounter-\(presentation.id.uuidString)"
                ),
                contextID: "encounter-\(presentation.id.uuidString)",
                selection: wordSelection,
                onSelect: { wordSelection = $0 }
            )
                .font(.body)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: DSRadius.inline))

            ScrollView(.horizontal) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(card.localizedHobbies.prefix(4), id: \.self) {
                        DSChip($0, tint: tint)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .dsSurface(.grouped)
    }

    private var wordFavoriteActions: WordFavoriteActions {
        let favorites = deps.favorites
        return WordFavoriteActions(
            contains: { word in
                (try? await favorites.isWordFavorited(word)) ?? false
            },
            toggle: { word, translationZh in
                (try? await favorites.toggleWord(word, translationZh: translationZh)) ?? false
            }
        )
    }

    private var aiWordFallback: @Sendable (String) async -> String? {
        let llm = deps.llm
        return { word in
            let request = LLMRequest(
                task: .dictionaryExplain,
                tier: .fast,
                system: "你是一个简明的英汉词典助手。用中文简要解释用户给出的英文词，格式：词性. 释义（不超过 3 条）；如是俚语/缩写/网络用语请注明。总长不超过 80 字。",
                messages: [.user(word)],
                maxTokens: 200,
                temperature: 0.2
            )
            return try? await llm.complete(request)
        }
    }

    private var rarityLabel: String {
        switch presentation.origin {
        case .local: "城市邂逅 · 当地人"
        case .domestic: "特别邂逅 · 国内旅人"
        case .foreigner: "稀有邂逅 · 异国旅人"
        }
    }

    private var rarityIcon: String {
        switch presentation.origin {
        case .local: "person.crop.circle.fill"
        case .domestic: "person.2.fill"
        case .foreigner: "sparkles"
        }
    }

    private var isFriendSlotFull: Bool {
        guard let friendSlotsOccupied, let friendSlotLimit else { return false }
        return friendSlotsOccupied >= friendSlotLimit
    }

    private var isFriendSlotNearLimit: Bool {
        guard let friendSlotsOccupied, let friendSlotLimit, friendSlotLimit > 0 else {
            return false
        }
        return Double(friendSlotsOccupied) / Double(friendSlotLimit) >= 0.8
    }

    private var friendButtonTitle: String {
        if isFriend { return "已加好友" }
        return isFriendSlotFull ? "好友位已满" : "加为好友"
    }

    private var friendCapacityText: String? {
        guard let friendSlotsOccupied, let friendSlotLimit else { return nil }
        if isFriend {
            return "好友位 \(friendSlotsOccupied)/\(friendSlotLimit)"
        }
        let remainingAfterAdding = max(friendSlotLimit - friendSlotsOccupied - 1, 0)
        return isFriendSlotFull
            ? "好友位 \(friendSlotsOccupied)/\(friendSlotLimit) · 已满"
            : "好友位 \(friendSlotsOccupied)/\(friendSlotLimit) · 添加后剩余 \(remainingAfterAdding) 个"
    }

    private var friendCapacityAccessibilityLabel: String {
        guard let friendSlotsOccupied, let friendSlotLimit else { return "" }
        let remaining = max(friendSlotLimit - friendSlotsOccupied, 0)
        return "好友位已使用 \(friendSlotsOccupied) 个，共 \(friendSlotLimit) 个，还可添加 \(remaining) 位好友"
    }

    private func loadFriendCapacity() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedSlots = try? deps.rosterStore.occupiedFriendSlots()
        let profile = await loadedProfile
        friendSlotLimit = profile?.friendSlotLimit
        friendSlotsOccupied = await loadedSlots
    }

    private func addFriend() {
        Task {
            do {
                let profile = try await deps.economyStore.profile()
                try await deps.rosterStore.makeFriend(
                    characterID: character.id,
                    slotLimit: profile.friendSlotLimit
                )
                isFriend = true
                friendSlotLimit = profile.friendSlotLimit
                friendSlotsOccupied = min(
                    (friendSlotsOccupied ?? 0) + 1,
                    profile.friendSlotLimit
                )
                Haptics.notify(.success)
                friendMessage = "已加入好友，以后随时可以在消息里找到 TA"
                if let registry = deps.npcRegistry {
                    if character.publicIdentityRegistered {
                        try? await registry.linkPublicNPC(
                            npcID: character.id,
                            localCharacterID: character.id,
                            status: .friend
                        )
                    } else if let registered = try? await registry.registerPublicNPC(
                        id: character.id,
                        card: PublicNPCAdapter.backendCard(from: character.card)
                    ) {
                        do {
                            try await registry.linkPublicNPC(
                                npcID: registered.id,
                                localCharacterID: character.id,
                                status: .friend
                            )
                            try await deps.rosterStore.applyPublicIdentity(
                                characterID: character.id,
                                travelerID: registered.travelerId,
                                card: PublicNPCAdapter.characterCard(from: registered)
                            )
                        } catch {
                            // Keep registration pending locally so the foreground coordinator retries the link.
                        }
                    }
                }
            } catch RosterStore.RosterError.friendSlotsFull {
                if let friendSlotLimit {
                    friendSlotsOccupied = friendSlotLimit
                }
                Haptics.notify(.warning)
                friendMessage = "好友位已满"
            } catch {
                Haptics.notify(.error)
                friendMessage = "操作失败：\(error.localizedDescription)"
            }
        }
    }

    private func leave() {
        Task {
            if !isFriend {
                try? await deps.chatStore.archiveConversations(
                    characterID: character.id
                )
            }
            onDismiss()
        }
    }
}
