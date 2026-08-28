import DesignSystem
import Foundation
import PersistenceKit
import SwiftUI

public struct RosterDependencies: Sendable {
    public let rosterStore: RosterStore
    public let economyStore: EconomyStore
    public let regionName: @Sendable (String) -> String

    public init(
        rosterStore: RosterStore,
        economyStore: EconomyStore,
        regionName: @escaping @Sendable (String) -> String = {
            $0.replacingOccurrences(of: "_", with: " ").capitalized
        }
    ) {
        self.rosterStore = rosterStore
        self.economyStore = economyStore
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
                    character.card.name,
                    character.card.nationality,
                    character.card.occupation,
                    character.card.regionID,
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

    static func isCapacityNearLimit(occupied: Int, limit: Int) -> Bool {
        guard limit > 0 else { return true }
        return Double(occupied) / Double(limit) >= 0.8
    }
}

public struct RosterView: View {
    private let deps: RosterDependencies
    private let reloadToken: Int
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var friends: [CharacterDTO] = []
    @State private var profile: UserProfileDTO?
    @State private var occupiedSlots = 0
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var favoriteSaveFailure: FavoriteSaveFailure?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        deps: RosterDependencies,
        reloadToken: Int = 0,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        callBuilder: (@MainActor (CharacterDTO) -> AnyView)? = nil
    ) {
        self.deps = deps
        self.reloadToken = reloadToken
        self.chatBuilder = chatBuilder
        self.callBuilder = callBuilder
    }

    private var slotLimit: Int { max(profile?.friendSlotLimit ?? 10, 1) }
    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isSearching: Bool { !normalizedSearchText.isEmpty }
    private var allContacts: [CharacterDTO] {
        RosterPresentationPolicy.sorted(friends)
    }
    private var visibleContacts: [CharacterDTO] {
        RosterPresentationPolicy.filtered(
            friends,
            query: normalizedSearchText,
            regionName: deps.regionName
        )
    }
    private var favoriteContacts: [CharacterDTO] {
        RosterPresentationPolicy.favoriteContacts(in: friends, isSearching: isSearching)
    }
    private var isCapacityNearLimit: Bool {
        RosterPresentationPolicy.isCapacityNearLimit(occupied: occupiedSlots, limit: slotLimit)
    }

    private var preferredDirectoryHeight: CGFloat {
        if isLoading && friends.isEmpty { return 320 }
        if loadErrorMessage != nil && friends.isEmpty { return 390 }
        if friends.isEmpty { return 390 }
        if isSearching && visibleContacts.isEmpty { return 360 }

        let usesAccessibilityLayout = dynamicTypeSize.isAccessibilitySize
        let contactRowHeight: CGFloat = usesAccessibilityLayout ? 118 : 66
        // List 会为 Section 的首尾保留系统间距；把它纳入面板高度，
        // 避免联系人很少时 footer 被迫滚动后才出现。
        let contentMargin: CGFloat = usesAccessibilityLayout ? 80 : 64

        if isSearching {
            return max(
                contactRowHeight + contentMargin,
                CGFloat(visibleContacts.count) * contactRowHeight + contentMargin
            )
        }

        let favoritesHeight: CGFloat = favoriteContacts.isEmpty
            ? 0
            : (usesAccessibilityLayout ? 190 : 132)
        let allContactsHeaderHeight: CGFloat = favoriteContacts.isEmpty
            ? 0
            : (usesAccessibilityLayout ? 52 : 38)
        let footerHeight: CGFloat = usesAccessibilityLayout ? 96 : 54
        let refreshErrorHeight: CGFloat = loadErrorMessage == nil ? 0 : 48

        return favoritesHeight
            + allContactsHeaderHeight
            + CGFloat(allContacts.count) * contactRowHeight
            + footerHeight
            + refreshErrorHeight
            + contentMargin
    }

    public var body: some View {
        ZStack {
            DSSceneBackdrop(imageName: "contacts_london_glass", tone: .warm)
            navigationReadabilityWash
            contactList
        }
        .navigationTitle("联系人")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "搜索姓名、职业或地区"
        )
        .dsCompactSearchToolbar()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: reloadToken) { await reload() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let failure = favoriteSaveFailure {
                saveErrorBanner(failure)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: favoriteSaveFailure?.id)
    }

    private var contactList: some View {
        GeometryReader { proxy in
            directoryList
                .frame(
                    height: min(
                        preferredDirectoryHeight,
                        max(proxy.size.height - DSSpacing.md, 160)
                    )
                )
                .padding(.horizontal, DSSpacing.sm)
                .padding(.top, DSSpacing.xs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var directoryList: some View {
        List {
            directoryContent
        }
        .listStyle(.plain)
        .listSectionSpacing(DSSpacing.xs)
        .scrollContentBackground(.hidden)
        .background { RosterDirectorySurface() }
        .clipShape(
            RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
        )
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var directoryContent: some View {
        if isLoading && friends.isEmpty {
            loadingRow
        } else if let loadErrorMessage, friends.isEmpty {
            loadErrorRow(loadErrorMessage)
        } else if isSearching {
            searchContent
        } else if friends.isEmpty {
            emptyState
        } else {
            if let loadErrorMessage {
                compactLoadErrorRow(loadErrorMessage)
            }
            if !favoriteContacts.isEmpty {
                favoriteSection
            }
            allContactsSection
        }
    }

    private var navigationReadabilityWash: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.28), location: 0),
                .init(color: .black.opacity(0.1), location: 0.12),
                .init(color: .clear, location: 0.28),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var loadingRow: some View {
        HStack(spacing: DSSpacing.sm) {
            ProgressView()
            Text("正在载入联系人…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private func loadErrorRow(_ message: String) -> some View {
        ContentUnavailableView {
            Label("无法载入联系人", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task { await reload() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func compactLoadErrorRow(_ message: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Label("刷新失败", systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
            Spacer(minLength: DSSpacing.xs)
            Button("重试") {
                Task { await reload() }
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(Color.dsDanger)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("刷新联系人失败，\(message)，重试")
        .listRowBackground(Color.dsDanger.opacity(0.08))
    }

    @ViewBuilder
    private var searchContent: some View {
        if visibleContacts.isEmpty {
            ContentUnavailableView.search(text: normalizedSearchText)
                .frame(maxWidth: .infinity, minHeight: 360)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(visibleContacts) { character in
                contactLink(character)
            }
        }
    }

    private var favoriteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("特别关心")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: DSSpacing.md) {
                        ForEach(favoriteContacts) { character in
                            favoriteLink(character)
                        }
                    }
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 132 : 88)
                .scrollIndicators(.hidden)
            }
            .padding(.vertical, DSSpacing.xs)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func favoriteLink(_ character: CharacterDTO) -> some View {
        NavigationLink {
            friendDestination(character)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarBadge(name: character.card.name, size: 54)
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.dsSunset, in: Circle())
                        .overlay { Circle().stroke(Color.dsSurface, lineWidth: 2) }
                        .accessibilityHidden(true)
                }
                Text(character.card.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 92)
            .frame(minHeight: 78)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(character.card.name)，特别关心")
            .accessibilityHint("打开联系人详情")
        }
        .buttonStyle(.plain)
        .contextMenu {
            favoriteMenuButton(for: character)
        }
    }

    private var allContactsSection: some View {
        Section {
            if !favoriteContacts.isEmpty {
                Text("全部联系人")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(allContacts) { character in
                contactLink(character)
            }
        } footer: {
            capacityFooter
        }
    }

    private func contactLink(_ character: CharacterDTO) -> some View {
        NavigationLink {
            friendDestination(character)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                AvatarBadge(name: character.card.name, size: 50)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(character.card.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(friendStatus(character))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: DSSpacing.xs)

                if character.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsSunset)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contactAccessibilityLabel(character))
            .accessibilityHint("打开联系人详情")
        }
        .listRowInsets(
            EdgeInsets(
                top: 7,
                leading: DSSpacing.md,
                bottom: 7,
                trailing: DSSpacing.md
            )
        )
        .listRowBackground(Color.clear)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + 50 + DSSpacing.sm
        }
        .contextMenu {
            favoriteMenuButton(for: character)
        }
    }

    private func friendDestination(_ character: CharacterDTO) -> some View {
        CharacterProfileView(
            character: character,
            regionName: deps.regionName(character.card.regionID),
            rosterStore: deps.rosterStore,
            onFavoriteChanged: { isFavorite in
                applyFavoriteState(characterID: character.id, isFavorite: isFavorite)
            },
            chatBuilder: chatBuilder,
            callBuilder: callBuilder
        )
    }

    private func favoriteMenuButton(for character: CharacterDTO) -> some View {
        Button {
            updateFavorite(character, isFavorite: !character.isFavorite)
        } label: {
            Label(
                character.isFavorite ? "取消特别关心" : "设为特别关心",
                systemImage: character.isFavorite ? "star.slash" : "star"
            )
        }
    }

    private func friendStatus(_ character: CharacterDTO) -> String {
        if character.isMainCharacter {
            return "剧情旅伴 · \(compactOccupation(character.card.occupation))"
        }
        return "\(character.card.nationality) · \(compactOccupation(character.card.occupation))"
    }

    private func compactOccupation(_ occupation: String) -> String {
        occupation.components(separatedBy: CharacterSet(charactersIn: "，,\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? occupation
    }

    private func contactAccessibilityLabel(_ character: CharacterDTO) -> String {
        var components = [character.card.name]
        components.append(character.isMainCharacter ? "剧情旅伴" : character.card.nationality)
        components.append(compactOccupation(character.card.occupation))
        if character.isFavorite {
            components.append("已特别关心")
        }
        return components.joined(separator: "，")
    }

    private var capacityFooter: some View {
        Text("好友位 \(occupiedSlots)/\(slotLimit) · 剧情旅伴不占好友位")
            .font(.footnote)
            .fontWeight(isCapacityNearLimit ? .semibold : .regular)
            .foregroundStyle(isCapacityNearLimit ? .primary : .secondary)
            .monospacedDigit()
            .accessibilityLabel(
                "好友位已使用 \(occupiedSlots) 个，共 \(slotLimit) 个。剧情旅伴不占好友位"
            )
            .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有联系人",
            systemImage: "person.2",
            description: Text("继续旅行，认识的新朋友会出现在这里")
        )
        .frame(maxWidth: .infinity, minHeight: 360)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func saveErrorBanner(_ failure: FavoriteSaveFailure) -> some View {
        SaveErrorBanner(
            message: "特别关心没有保存成功",
            retry: {
                guard let character = friends.first(where: { $0.id == failure.characterID }) else {
                    favoriteSaveFailure = nil
                    return
                }
                updateFavorite(character, isFavorite: failure.targetValue)
            },
            dismiss: { favoriteSaveFailure = nil }
        )
    }

    private func reload() async {
        if friends.isEmpty { isLoading = true }
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedSlots = try? deps.rosterStore.occupiedFriendSlots()

        do {
            friends = try await deps.rosterStore.friends()
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = "请检查网络或稍后重试。"
        }

        profile = await loadedProfile
        occupiedSlots = await loadedSlots ?? occupiedSlots
        isLoading = false
    }

    private func updateFavorite(_ character: CharacterDTO, isFavorite: Bool) {
        let previousValue = character.isFavorite
        favoriteSaveFailure = nil
        applyFavoriteState(characterID: character.id, isFavorite: isFavorite, animated: true)

        Task {
            do {
                try await deps.rosterStore.setFavorite(
                    characterID: character.id,
                    isFavorite: isFavorite
                )
                Haptics.selection()
            } catch {
                applyFavoriteState(
                    characterID: character.id,
                    isFavorite: previousValue,
                    animated: true
                )
                favoriteSaveFailure = FavoriteSaveFailure(
                    characterID: character.id,
                    targetValue: isFavorite
                )
            }
        }
    }

    private func applyFavoriteState(
        characterID: UUID,
        isFavorite: Bool,
        animated: Bool = false
    ) {
        guard let index = friends.firstIndex(where: { $0.id == characterID }) else { return }
        withAnimation(animated && !reduceMotion ? DSAnimation.snappy : nil) {
            friends[index].isFavorite = isFavorite
        }
    }
}

public struct CharacterProfileView: View {
    private let character: CharacterDTO
    private let regionName: String
    private let rosterStore: RosterStore
    private let onFavoriteChanged: @MainActor (Bool) -> Void
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var isFavorite: Bool
    @State private var isUpdatingFavorite = false
    @State private var failedFavoriteTarget: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        character: CharacterDTO,
        regionName: String,
        rosterStore: RosterStore,
        onFavoriteChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        callBuilder: (@MainActor (CharacterDTO) -> AnyView)? = nil
    ) {
        self.character = character
        self.regionName = regionName
        self.rosterStore = rosterStore
        self.onFavoriteChanged = onFavoriteChanged
        self.chatBuilder = chatBuilder
        self.callBuilder = callBuilder
        _isFavorite = State(initialValue: character.isFavorite)
    }

    private var card: CharacterCard { character.card }

    public var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileHero
                contactActions
                infoCard("性格", text: card.personality, icon: "sparkles")
                hobbiesCard
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
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: failedFavoriteTarget)
    }

    private var profileHero: some View {
        VStack(spacing: DSSpacing.sm) {
            AvatarBadge(name: card.name, size: 96)
            Text(card.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
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

private struct FavoriteSaveFailure: Identifiable {
    let id = UUID()
    let characterID: UUID
    let targetValue: Bool
}

private struct RosterDirectorySurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                Color.dsBackground.opacity(reduceTransparency ? 1 : 0.985)
            } else {
                Color.dsSurface.opacity(colorScheme == .dark ? 0.9 : 0.84)
            }
        }
        .overlay {
            LinearGradient(
                colors: [Color.dsSky.opacity(0.025), Color.dsSunset.opacity(0.018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.white.opacity(0.62),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.2 : 0.1),
            radius: 16,
            y: 6
        )
        .accessibilityHidden(true)
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
