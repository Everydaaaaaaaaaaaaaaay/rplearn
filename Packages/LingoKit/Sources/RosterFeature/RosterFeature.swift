import BackendKit
import DesignSystem
import DomainKit
import Foundation
import PersistenceKit
import SwiftUI

public struct RosterDependencies: Sendable {
    public let rosterStore: RosterStore
    public let economyStore: EconomyStore
    public let regionName: @Sendable (String) -> String
    public let npcRegistry: (any PublicNPCRegistry)?

    public init(
        rosterStore: RosterStore,
        economyStore: EconomyStore,
        npcRegistry: (any PublicNPCRegistry)? = nil,
        regionName: @escaping @Sendable (String) -> String = {
            $0.replacingOccurrences(of: "_", with: " ").capitalized
        }
    ) {
        self.rosterStore = rosterStore
        self.economyStore = economyStore
        self.npcRegistry = npcRegistry
        self.regionName = regionName
    }
}

enum RosterPresentationPolicy {
    static func sorted(_ contacts: [CharacterDTO]) -> [CharacterDTO] {
        contacts.sorted {
            $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending
        }
    }

    static func filtered(
        _ contacts: [CharacterDTO],
        query: String,
        regionName: (String) -> String
    ) -> [CharacterDTO] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return sorted(contacts) }
        return sorted(
            contacts.filter { character in
                [
                    character.displayName,
                    character.card.name,
                    character.card.nationality,
                    character.card.occupation,
                    character.card.regionID,
                    character.card.signature ?? "",
                    character.travelerID,
                    regionName(character.card.regionID),
                ].contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
            }
        )
    }

    static func favoriteContacts(
        in contacts: [CharacterDTO],
        isSearching: Bool
    ) -> [CharacterDTO] {
        guard !isSearching else { return [] }
        return sorted(contacts.filter(\.isFavorite))
    }

    static func friendGroupContacts(in contacts: [CharacterDTO]) -> [CharacterDTO] {
        sorted(contacts.filter { !$0.isFavorite })
    }

    static func isCapacityNearLimit(occupied: Int, limit: Int) -> Bool {
        guard limit > 0 else { return true }
        return Double(occupied) / Double(limit) >= 0.8
    }
}

public struct CharacterProfileView: View {
    @State private var character: CharacterDTO
    private let regionName: String
    private let rosterStore: RosterStore
    private let onFavoriteChanged: @MainActor (Bool) -> Void
    private let slotLimit: Int
    private let onContactRestored: @MainActor (CharacterDTO) -> Void
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var isFavorite: Bool
    @State private var relationship: PersistenceKit.RelationshipSnapshot
    @State private var isUpdatingFavorite = false
    @State private var isRestoringContact = false
    @State private var failedFavoriteTarget: Bool?
    @State private var restoreFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    public init(
        character: CharacterDTO,
        regionName: String,
        rosterStore: RosterStore,
        onFavoriteChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        slotLimit: Int = 10,
        onContactRestored: @escaping @MainActor (CharacterDTO) -> Void = { _ in },
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        callBuilder: (@MainActor (CharacterDTO) -> AnyView)? = nil
    ) {
        _character = State(initialValue: character)
        self.regionName = regionName
        self.rosterStore = rosterStore
        self.onFavoriteChanged = onFavoriteChanged
        self.slotLimit = slotLimit
        self.onContactRestored = onContactRestored
        self.chatBuilder = chatBuilder
        self.callBuilder = callBuilder
        _isFavorite = State(initialValue: character.isFavorite)
        _relationship = State(initialValue: character.relationship)
    }

    private var card: CharacterCard { character.card }

    public var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileHero
                contactActions
                identityCard
                infoCard("性格", text: card.personality, icon: "sparkles")
                hobbiesCard
                growthCard
                relationshipCard
                infoCard("外貌", text: card.appearance, icon: "person.crop.rectangle")
                if let speechStyle = card.speechStyle {
                    infoCard("说话风格", text: speechStyle, icon: "quote.bubble")
                }
                if let background = card.background {
                    infoCard("背景故事", text: background, icon: "book.closed")
                }
                infoCard(
                    "相识于",
                    text: character.metAt.formatted(date: .abbreviated, time: .omitted),
                    icon: "mappin.and.ellipse"
                )
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let failedFavoriteTarget {
                SaveErrorBanner(
                    message: "特别关心没有保存成功",
                    retry: { setFavorite(failedFavoriteTarget) },
                    dismiss: { self.failedFavoriteTarget = nil }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else if restoreFailed {
                SaveErrorBanner(
                    message: "重新添加没有成功",
                    retry: restoreContact,
                    dismiss: { restoreFailed = false }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: failedFavoriteTarget)
        .task {
            await reloadRelationship()
        }
        .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { note in
            guard note.object as? UUID == character.id else { return }
            Task { await reloadRelationship() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rosterRelationshipDidChange)) { note in
            guard let characterID = note.object as? UUID, characterID == character.id else { return }
            Task { await reloadRelationship() }
        }
    }

    private var profileHero: some View {
        VStack(spacing: DSSpacing.sm) {
            AvatarBadge(
                name: character.displayName,
                size: 96,
                imageName: card.avatarAssetName,
                remoteURL: card.avatarRemoteURL.flatMap(URL.init(string:)),
                usesPendingPlaceholder: true
            )
            Text(character.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Label("AI 旅伴 · 虚构角色", systemImage: "sparkles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.dsSkyDeep)
            if let signature = card.signature, !signature.isEmpty {
                Text(signature)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(
                [
                    character.isMainCharacter ? "剧情旅伴" : "旅行朋友",
                    card.occupation,
                    regionName,
                ].joined(separator: " · ")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Text("\(card.nationality) · \(card.age) 岁")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .dsSurface(.grouped)
        .accessibilityElement(children: .combine)
    }

    private var contactActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DSSpacing.sm))
            : AnyLayout(HStackLayout(spacing: DSSpacing.sm))

        return layout {
            if !character.isFriend {
                Button {
                    restoreContact()
                } label: {
                    contactActionLabel(
                        character.contactStatus == .removed ? "重新添加" : "添加好友",
                        systemImage: "person.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsSky)
                .disabled(isRestoringContact)
            } else {
                NavigationLink {
                    chatBuilder(character)
                } label: {
                    contactActionLabel("发消息", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsSky)

                if let callBuilder {
                    NavigationLink {
                        callBuilder(character)
                    } label: {
                        contactActionLabel("打电话", systemImage: "phone.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.dsSkyDeep)
                }

                Button {
                    setFavorite(!isFavorite)
                } label: {
                    contactActionLabel(
                        isFavorite ? "已特别关心" : "特别关心",
                        systemImage: isFavorite ? "star.fill" : "star"
                    )
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .tint(isFavorite ? Color.dsSunset : Color.dsSkyDeep)
                .disabled(isUpdatingFavorite)
                .accessibilityValue(isFavorite ? "已开启" : "未开启")
                .accessibilityHint(isFavorite ? "双击取消特别关心" : "双击设为特别关心")
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("旅伴资料", systemImage: "person.text.rectangle")
                .font(.headline)
                .foregroundStyle(Color.dsSky)
            profileValue("旅伴号", value: character.travelerID)
            profileValue("性别", value: genderName)
            profileValue("生日", value: card.birthday)
            profileValue("家乡", value: card.hometown)
            profileValue("语言", value: card.languages?.joined(separator: "、"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    @ViewBuilder
    private func profileValue(_ title: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .font(.subheadline)
        }
    }

    private var genderName: String {
        switch card.gender {
        case .male: "男"
        case .female: "女"
        case .other: "未设定"
        }
    }

    private func contactActionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
    }

    private var relationshipCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label("你们的关系", systemImage: "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(Color.dsSunset)
                Spacer(minLength: DSSpacing.sm)
                Text("共同互动 \(relationship.meaningfulInteractionCount) 次")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Text("了解、信任和默契来自你们实际发生过的对话与经历，不由英语水平决定。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let event = relationship.latestEvent {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.dsSky)
                    Text(event.reasonZh)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("最近的关系变化，\(event.reasonZh)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    @MainActor
    private func reloadRelationship() async {
        guard let latest = try? await rosterStore.character(id: character.id) else { return }
        character = latest
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            relationship = latest.relationship
        }
    }

    private func setFavorite(_ newValue: Bool) {
        guard !isUpdatingFavorite else { return }
        let previousValue = isFavorite
        failedFavoriteTarget = nil
        isUpdatingFavorite = true
        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
            isFavorite = newValue
        }
        onFavoriteChanged(newValue)

        Task {
            do {
                try await rosterStore.setFavorite(
                    characterID: character.id,
                    isFavorite: newValue
                )
                Haptics.selection()
            } catch {
                withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                    isFavorite = previousValue
                }
                onFavoriteChanged(previousValue)
                failedFavoriteTarget = newValue
            }
            isUpdatingFavorite = false
        }
    }

    private func restoreContact() {
        guard !isRestoringContact else { return }
        isRestoringContact = true
        restoreFailed = false
        Task {
            do {
                try await rosterStore.makeFriend(characterID: character.id, slotLimit: slotLimit)
                guard let restored = try await rosterStore.character(id: character.id) else {
                    throw RosterStore.RosterError.characterNotFound
                }
                onContactRestored(restored)
                Haptics.notify(.success)
                dismiss()
            } catch {
                restoreFailed = true
                isRestoringContact = false
            }
        }
    }

    private var hobbiesCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("爱好", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(Color.dsSunset)
            FlowLayout(spacing: 6, lineSpacing: 7) {
                ForEach(card.localizedHobbies, id: \.self) { DSChip($0, tint: .dsSky) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    @ViewBuilder
    private var growthCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("与你相处后的成长", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Color.dsSuccess)

            if character.growth.arcs.isEmpty {
                Text("还没有形成稳定变化。一次建议只会种下想法，持续的经历与行动才会慢慢留下改变。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(character.growth.arcs.sorted { $0.updatedAt > $1.updatedAt }) { arc in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(growthTitle(arc))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(arc.stage.titleZh)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.dsSkyDeep)
                        }
                        Text(arc.reasonZh)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ProgressView(value: min(max(arc.progress, 0), 1))
                            .tint(Color.dsSuccess)
                    }
                    if arc.id != character.growth.arcs.sorted(by: { $0.updatedAt > $1.updatedAt }).last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    private func growthTitle(_ arc: CharacterGrowthArc) -> String {
        switch arc.direction {
        case .increase: "更有\(arc.trait.titleZh)"
        case .decrease: "减少\(arc.trait.titleZh)"
        }
    }

    private func infoCard(_ title: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.dsSky)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dsSurface(.grouped)
    }
}

private struct SaveErrorBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsDanger)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("重试", action: retry)
                .font(.footnote.weight(.semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("关闭错误提示")
        }
        .padding(.leading, DSSpacing.md)
        .padding(.trailing, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(.thickMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.dsBorder, lineWidth: 1) }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.xs)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
