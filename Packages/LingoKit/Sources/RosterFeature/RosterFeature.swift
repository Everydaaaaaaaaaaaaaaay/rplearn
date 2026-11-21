import BackendKit
import DesignSystem
import DomainKit
import Foundation
import PersistenceKit
import SwiftUI

public struct RosterDependencies: Sendable {
    public let rosterStore: RosterStore
    public let economyStore: EconomyStore
    public let chatStore: ChatStore?
    public let regionName: @Sendable (String) -> String
    public let npcRegistry: (any PublicNPCRegistry)?

    public init(
        rosterStore: RosterStore,
        economyStore: EconomyStore,
        npcRegistry: (any PublicNPCRegistry)? = nil,
        chatStore: ChatStore? = nil,
        regionName: @escaping @Sendable (String) -> String = {
            $0.replacingOccurrences(of: "_", with: " ").capitalized
        }
    ) {
        self.chatStore = chatStore
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
    @State private var hasEntered = false
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
            VStack(spacing: Puff.Space.m) {
                profileHero
                    .puffEntrance(index: 0, isShown: hasEntered)
                contactActions
                    .puffEntrance(index: 1, isShown: hasEntered)
                identityCard
                    .puffEntrance(index: 2, isShown: hasEntered)
                infoCard("性格", text: card.personality, icon: "sparkles", candy: .grape)
                    .puffEntrance(index: 3, isShown: hasEntered)
                hobbiesCard
                    .puffEntrance(index: 4, isShown: hasEntered)
                growthCard
                    .puffEntrance(index: 5, isShown: hasEntered)
                relationshipCard
                    .puffEntrance(index: 6, isShown: hasEntered)
                infoCard("外貌", text: card.appearance, icon: "person.crop.rectangle", candy: .sky)
                if let speechStyle = card.speechStyle {
                    infoCard("说话风格", text: speechStyle, icon: "quote.bubble.fill", candy: .tangerine)
                }
                if let background = card.background {
                    infoCard("背景故事", text: background, icon: "book.closed.fill", candy: .mint)
                }
                infoCard(
                    "相识于",
                    text: character.metAt.formatted(date: .abbreviated, time: .omitted),
                    icon: "mappin.and.ellipse",
                    candy: .bubblegum
                )
            }
            .padding(.horizontal, Puff.Space.m)
            .padding(.top, Puff.Space.xs)
            .padding(.bottom, Puff.Space.xl)
        }
        .background(Puff.Palette.page.ignoresSafeArea())
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
        .animation(Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion), value: failedFavoriteTarget)
        .animation(Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion), value: restoreFailed)
        .task {
            if !hasEntered {
                try? await Task.sleep(for: .milliseconds(40))
                hasEntered = true
            }
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

    /// 角色所在城市的卡通街景上，探出一个大头像。
    private var profileHero: some View {
        VStack(spacing: 0) {
            PuffCityScene(regionID: card.regionID, viewport: .west)
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.large, style: .continuous))
                .padding([.horizontal, .top], 6)

            PuffAvatar(
                name: character.displayName,
                size: 104,
                imageName: card.avatarAssetName,
                remoteURL: card.avatarRemoteURL.flatMap(URL.init(string:))
            )
            .padding(6)
            .background(Puff.Palette.card, in: Circle())
            .offset(y: -50)
            .padding(.bottom, -50)

            VStack(spacing: 6) {
                Text(character.displayName)
                    .font(.puff(.title, .heavy))
                    .foregroundStyle(Puff.Palette.ink)
                    .multilineTextAlignment(.center)
                PuffTag("AI 旅伴 · 虚构角色", systemImage: "sparkles", candy: .grape)
                if let signature = card.signature, !signature.isEmpty {
                    Text("“\(signature)”")
                        .font(.puff(.body, .semibold))
                        .foregroundStyle(Puff.Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                Text(
                    [
                        character.isMainCharacter ? "剧情旅伴" : "旅行朋友",
                        card.occupation,
                        regionName,
                    ].joined(separator: " · ")
                )
                .font(.puff(.subheadline, .semibold))
                .foregroundStyle(Puff.Palette.inkSoft)
                .multilineTextAlignment(.center)
                Text("\(card.nationality) · \(card.age) 岁")
                    .font(.puff(.footnote, .medium))
                    .foregroundStyle(Puff.Palette.inkFaint)
            }
            .padding(.horizontal, Puff.Space.l)
            .padding(.top, Puff.Space.xs)
            .padding(.bottom, Puff.Space.l)
        }
        .frame(maxWidth: .infinity)
        .puffCard(radius: Puff.Radius.huge)
        .accessibilityElement(children: .combine)
    }

    private var contactActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Puff.Space.s))
            : AnyLayout(HStackLayout(spacing: Puff.Space.s))

        return layout {
            if !character.isFriend {
                Button {
                    restoreContact()
                } label: {
                    contactActionLabel(
                        character.contactStatus == .removed ? "重新添加" : "添加好友",
                        systemImage: "person.badge.plus"
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(actionStyle(.sky))
                .disabled(isRestoringContact)
            } else {
                NavigationLink {
                    chatBuilder(character)
                } label: {
                    contactActionLabel("发消息", systemImage: "bubble.left.fill")
                        .foregroundStyle(.white)
                }
                .buttonStyle(actionStyle(.sky))

                if let callBuilder {
                    NavigationLink {
                        callBuilder(character)
                    } label: {
                        contactActionLabel("打电话", systemImage: "phone.fill")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(actionStyle(.mint))
                }

                Button {
                    setFavorite(!isFavorite)
                } label: {
                    contactActionLabel(
                        isFavorite ? "已特别关心" : "特别关心",
                        systemImage: isFavorite ? "star.fill" : "star"
                    )
                    .foregroundStyle(isFavorite ? .white : PuffCandy.sunny.deep)
                    .symbolEffect(.bounce, value: isFavorite)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                }
                .buttonStyle(isFavorite ? actionStyle(.sunny) : PuffCardButtonStyle(radius: Puff.Radius.medium))
                .disabled(isUpdatingFavorite)
                .accessibilityValue(isFavorite ? "已开启" : "未开启")
                .accessibilityHint(isFavorite ? "双击取消特别关心" : "双击设为特别关心")
            }
        }
    }

    /// 实心糖果色的厚按钮。
    private func actionStyle(_ candy: PuffCandy) -> PuffCardButtonStyle {
        PuffCardButtonStyle(radius: Puff.Radius.medium, face: candy.base, border: .clear, lip: candy.lip)
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: Puff.Space.s) {
            cardTitle("旅伴资料", icon: "person.text.rectangle.fill", candy: .sky)
            VStack(spacing: Puff.Space.xs) {
                profileValue("旅伴号", value: character.travelerID)
                profileValue("性别", value: genderName)
                profileValue("生日", value: card.birthday)
                profileValue("家乡", value: card.hometown)
                profileValue("语言", value: card.languages?.joined(separator: "、"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Puff.Space.m)
        .puffCard()
    }

    private func cardTitle(_ title: String, icon: String, candy: PuffCandy) -> some View {
        HStack(spacing: 10) {
            PuffIconBubble(icon, candy: candy, size: 32)
            Text(title)
                .font(.puff(.headline, .heavy))
                .foregroundStyle(Puff.Palette.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func profileValue(_ title: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.puff(.subheadline, .bold))
                    .foregroundStyle(Puff.Palette.inkSoft)
                Spacer(minLength: Puff.Space.s)
                Text(value)
                    .font(.puff(.subheadline, .semibold))
                    .foregroundStyle(Puff.Palette.ink)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, Puff.Space.s)
            .padding(.vertical, 10)
            .background(Puff.Palette.cloud, in: RoundedRectangle(cornerRadius: Puff.Radius.small, style: .continuous))
            .accessibilityElement(children: .combine)
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
                .font(.system(size: 20, weight: .heavy, design: .rounded))
            Text(title)
                .font(.puff(.caption, .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
    }

    private var relationshipCard: some View {
        VStack(alignment: .leading, spacing: Puff.Space.s) {
            HStack(alignment: .center) {
                cardTitle("你们的关系", icon: "heart.fill", candy: .bubblegum)
                Spacer(minLength: Puff.Space.s)
                Text("共同互动 \(relationship.meaningfulInteractionCount) 次")
                    .font(.puff(.caption, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(PuffCandy.bubblegum.deep)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(PuffCandy.bubblegum.wash, in: Capsule())
            }

            if let event = relationship.latestEvent {
                HStack(alignment: .top, spacing: Puff.Space.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(PuffCandy.bubblegum.deep)
                    Text(event.reasonZh)
                        .font(.puff(.footnote, .semibold))
                        .foregroundStyle(Puff.Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Puff.Space.s)
                .background(PuffCandy.bubblegum.wash.opacity(0.7), in: RoundedRectangle(cornerRadius: Puff.Radius.small, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("最近的关系变化，\(event.reasonZh)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Puff.Space.m)
        .puffCard()
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
        withAnimation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion)) {
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
                withAnimation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion)) {
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
        VStack(alignment: .leading, spacing: Puff.Space.s) {
            cardTitle("爱好", icon: "heart.text.square.fill", candy: .tangerine)
            FlowLayout(spacing: 6, lineSpacing: 7) {
                ForEach(Array(card.localizedHobbies.enumerated()), id: \.offset) { index, hobby in
                    let candy = PuffCandy.all[index % PuffCandy.all.count]
                    Text(hobby)
                        .font(.puff(.subheadline, .bold))
                        .foregroundStyle(candy.deep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(candy.wash, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Puff.Space.m)
        .puffCard()
    }

    @ViewBuilder
    private var growthCard: some View {
        let arcs = character.growth.arcs.sorted { $0.updatedAt > $1.updatedAt }
        VStack(alignment: .leading, spacing: Puff.Space.s) {
            cardTitle("与你相处后的成长", icon: "leaf.fill", candy: .mint)

            if arcs.isEmpty {
                Text("还没有明显变化")
                    .font(.puff(.subheadline, .medium))
                    .foregroundStyle(Puff.Palette.inkSoft)
            } else {
                ForEach(arcs) { arc in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(growthTitle(arc))
                                .font(.puff(.subheadline, .heavy))
                                .foregroundStyle(Puff.Palette.ink)
                            Spacer()
                            PuffTag(arc.stage.titleZh, candy: .mint)
                        }
                        Text(arc.reasonZh)
                            .font(.puff(.footnote, .medium))
                            .foregroundStyle(Puff.Palette.inkSoft)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Puff.Palette.cloud)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(PuffCandy.mint.base)
                                        .frame(width: max(proxy.size.width * min(max(arc.progress, 0), 1), 10))
                                }
                        }
                        .frame(height: 10)
                        .accessibilityElement()
                        .accessibilityLabel("进度")
                        .accessibilityValue("\(Int(min(max(arc.progress, 0), 1) * 100))%")
                    }
                    .padding(Puff.Space.s)
                    .background(Puff.Palette.cloud.opacity(0.6), in: RoundedRectangle(cornerRadius: Puff.Radius.medium, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Puff.Space.m)
        .puffCard()
    }

    private func growthTitle(_ arc: CharacterGrowthArc) -> String {
        switch arc.direction {
        case .increase: "更有\(arc.trait.titleZh)"
        case .decrease: "减少\(arc.trait.titleZh)"
        }
    }

    private func infoCard(_ title: String, text: String, icon: String, candy: PuffCandy) -> some View {
        VStack(alignment: .leading, spacing: Puff.Space.s) {
            cardTitle(title, icon: icon, candy: candy)
            Text(text)
                .font(.puff(.subheadline, .medium))
                .foregroundStyle(Puff.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Puff.Space.m)
        .puffCard()
    }
}

private struct SaveErrorBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Puff.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Puff.Palette.cherry)
                .accessibilityHidden(true)
            Text(message)
                .font(.puff(.footnote, .heavy))
                .foregroundStyle(Puff.Palette.ink)
            Spacer(minLength: 0)
            Button("重试", action: retry)
                .font(.puff(.footnote, .heavy))
                .foregroundStyle(PuffCandy.sky.deep)
                .buttonStyle(.puffSquish)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .frame(width: 32, height: 32)
                    .background(Puff.Palette.cloud, in: Circle())
            }
            .buttonStyle(.puffSquish)
            .accessibilityLabel("关闭错误提示")
        }
        .padding(.leading, Puff.Space.m)
        .padding(.trailing, Puff.Space.xs)
        .padding(.vertical, Puff.Space.xs)
        .puffCard(radius: Puff.Radius.large)
        .padding(.horizontal, Puff.Space.m)
        .padding(.bottom, Puff.Space.xs)
    }
}
