import CoreKit
import DesignSystem
import DictKit
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

public struct ActivitiesView: View {
    private let deps: HomeDependencies
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var profile: UserProfileDTO?
    @State private var selectedCategory: Region.ActivityCategory?
    @State private var isRollingID: String?
    @State private var activityMoment: ActivityMomentPresentation?
    @State private var encounterResult: EncounterPresentation?

    public init(
        deps: HomeDependencies,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView
    ) {
        self.deps = deps
        self.chatBuilder = chatBuilder
    }

    private var region: Region? {
        #if DEBUG
        if let requestedRegionID = ProcessInfo.processInfo.environment["UI_TEST_REGION"],
           let requestedRegion = deps.regionCatalog.region(id: requestedRegionID)
        {
            return requestedRegion
        }
        #endif
        return profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    private var heroHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 286 : 224
    }

    private var featuredHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 238 : 178
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.lg) {
                if let region {
                    cityHero(region)
                    featuredSection(region)
                    routeSection(region)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.xl)
        }
        .background(Color.dsBackground)
        .navigationTitle("城市活动")
        .navigationBarTitleDisplayMode(.inline)
        .task { profile = try? await deps.economyStore.profile() }
        .onAppear { Task { profile = try? await deps.economyStore.profile() } }
        .sheet(item: $activityMoment) { result in
            ActivityMomentSheet(presentation: result) {
                activityMoment = nil
            }
        }
        .sheet(item: $encounterResult) { result in
            EncounterCardSheet(presentation: result, deps: deps, chatBuilder: chatBuilder) {
                encounterResult = nil
            }
        }
    }

    private func cityHero(_ region: Region) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image("home_activity_\(region.id)")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: heroHeight)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.04), location: 0),
                        .init(color: .black.opacity(0.2), location: 0.45),
                        .init(color: .black.opacity(0.84), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(spacing: 7) {
                        Text(flag(region.countryCode))
                        Text("城市探索局")
                            .font(.caption.weight(.black))
                            .tracking(1.1)
                        Spacer()
                        Text(region.nameEn.uppercased())
                            .font(.caption2.monospaced().weight(.bold))
                            .opacity(0.78)
                    }

                    Text(region.nameZh)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Text(region.taglineZh)
                        .font(.subheadline)
                        .lineLimit(2)
                        .opacity(0.88)

                    HStack(spacing: DSSpacing.xs) {
                        heroStat(
                            icon: "point.3.connected.trianglepath.dotted",
                            value: "\(region.activities.count) 条路线"
                        )
                        heroStat(
                            icon: "person.crop.circle.badge.questionmark",
                            value: "\(encounterRange(region)) 邂逅"
                        )
                        heroStat(
                            icon: "textformat.abc",
                            value: profile?.difficultyLevel.displayName ?? "载入中"
                        )
                    }
                }
                .foregroundStyle(.white)
                .padding(DSSpacing.md)
            }
            .frame(width: proxy.size.width, height: heroHeight)
        }
        .frame(height: heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: DSScenePalette.city(region.id).accent.opacity(0.22), radius: 14, y: 7)
        .padding(.top, DSSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func heroStat(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.24), in: Capsule())
    }

    @ViewBuilder
    private func featuredSection(_ region: Region) -> some View {
        if let activity = featuredActivity(in: region) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                sectionTitle(
                    eyebrow: "今日推荐",
                    title: "从这里开始",
                    detail: "每天轮换一条在地路线"
                )

                Button {
                    runActivity(activity, region: region)
                } label: {
                    featuredCard(activity, region: region)
                }
                .buttonStyle(.pressableCard)
                .disabled(isRollingID != nil)
                .accessibilityLabel(
                    "今日推荐，\(activity.titleZh)，约 \(activity.durationMinutes) 分钟，出发"
                )
            }
        }
    }

    private func featuredCard(_ activity: Region.Activity, region: Region) -> some View {
        let tint = activity.category.tint
        return ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Image("home_activity_\(region.id)")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: featuredHeight)
                    .clipped()
            }

            LinearGradient(
                stops: [
                    .init(color: tint.opacity(0.08), location: 0),
                    .init(color: tint.opacity(0.56), location: 0.45),
                    .init(color: .black.opacity(0.88), location: 1),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label(activity.category.titleZh, systemImage: activity.category.icon)
                    Text("·")
                    Label("\(activity.durationMinutes) 分钟", systemImage: "clock.fill")
                    Text("·")
                    Label(
                        "\(Int((activity.encounterProbability * 100).rounded()))%",
                        systemImage: "sparkles"
                    )
                }
                .font(.caption2.weight(.bold))
                .opacity(0.84)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                Text(activity.titleZh)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(activity.detailZh)
                    .font(.footnote)
                    .lineLimit(2)
                    .opacity(0.9)

                HStack {
                    Text(isRollingID == activity.id ? "正在探索…" : "立即出发")
                        .font(.subheadline.weight(.black))
                    Spacer()
                    if isRollingID == activity.id {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                    }
                }
                .padding(.top, 3)
            }
            .foregroundStyle(.white)
            .padding(DSSpacing.md)
        }
        .frame(height: featuredHeight)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private func routeSection(_ region: Region) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle(
                eyebrow: "自由探索",
                title: "选择一条路线",
                detail: "\(filteredActivities(in: region).count) 项可选"
            )

            categoryPicker(region)

            ForEach(filteredActivities(in: region)) { activity in
                Button {
                    runActivity(activity, region: region)
                } label: {
                    activityCard(activity)
                }
                .buttonStyle(.pressableCard)
                .disabled(isRollingID != nil)
                .accessibilityLabel(
                    "\(activity.titleZh)，\(activity.category.titleZh)，约 \(activity.durationMinutes) 分钟，邂逅率 \(Int((activity.encounterProbability * 100).rounded()))%"
                )
            }
        }
    }

    private func sectionTitle(eyebrow: String, title: String, detail: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(Color.dsSky)
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func categoryPicker(_ region: Region) -> some View {
        let available = Region.ActivityCategory.allCases.filter { category in
            filteredActivities(in: region).contains { $0.category == category }
        }
        return ScrollView(.horizontal) {
            HStack(spacing: DSSpacing.xs) {
                categoryButton(title: "全部", icon: "square.grid.2x2.fill", category: nil)
                ForEach(available, id: \.self) { category in
                    categoryButton(
                        title: category.titleZh,
                        icon: category.icon,
                        category: category
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func categoryButton(
        title: String,
        icon: String,
        category: Region.ActivityCategory?
    ) -> some View {
        let selected = selectedCategory == category
        let tint = category?.tint ?? Color.dsSky
        return Button {
            Haptics.selection()
            withAnimation(DSAnimation.snappy) {
                selectedCategory = category
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? .white : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? tint : tint.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(tint.opacity(selected ? 0 : 0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func activityCard(_ activity: Region.Activity) -> some View {
        let tint = activity.category.tint
        let isRolling = isRollingID == activity.id
        return HStack(spacing: DSSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: activity.category.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 58, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(activity.titleZh)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer()
                    Text(activity.category.titleZh)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(tint)
                }

                Text(activity.detailZh)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                HStack(spacing: DSSpacing.sm) {
                    Label("\(activity.durationMinutes) 分钟", systemImage: "clock")
                    Label(
                        "邂逅 \(Int((activity.encounterProbability * 100).rounded()))%",
                        systemImage: "sparkles"
                    )
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            if isRolling {
                ProgressView()
                    .tint(tint)
                    .padding(.leading, 2)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
            }
        }
        .padding(DSSpacing.sm)
        .background(Color.dsSurface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 46)
                .padding(.leading, 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(isRolling ? tint.opacity(0.42) : Color.dsBorder, lineWidth: 1)
        }
    }

    private func runActivity(_ activity: Region.Activity, region: Region) {
        guard isRollingID == nil else { return }
        Haptics.impact(.light)
        isRollingID = activity.id

        Task {
            defer { isRollingID = nil }
            guard EncounterService.shouldEncounter(
                roll: .random(in: 0..<1),
                probability: activity.encounterProbability
            ) else {
                Haptics.notify(.success)
                activityMoment = ActivityMomentPresentation(
                    activity: activity,
                    region: region
                )
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
            ) else {
                activityMoment = ActivityMomentPresentation(
                    activity: activity,
                    region: region
                )
                return
            }
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
                Haptics.notify(.success)
                encounterResult = EncounterPresentation(
                    character: character,
                    openingLine: encounter.openingLine,
                    origin: encounter.origin,
                    activity: activity,
                    region: region
                )
            }
        }
    }

    private func featuredActivity(in region: Region) -> Region.Activity? {
        guard !region.activities.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let citySeed = region.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return region.activities[(day + citySeed) % region.activities.count]
    }

    private func filteredActivities(in region: Region) -> [Region.Activity] {
        let featuredID = featuredActivity(in: region)?.id
        return region.activities.filter { activity in
            activity.id != featuredID
                && (selectedCategory == nil || activity.category == selectedCategory)
        }
    }

    private func encounterRange(_ region: Region) -> String {
        let values = region.activities.map {
            Int(($0.encounterProbability * 100).rounded())
        }
        guard let minimum = values.min(), let maximum = values.max() else { return "35%" }
        return minimum == maximum ? "\(minimum)%" : "\(minimum)–\(maximum)%"
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}

private struct ActivityMomentPresentation: Identifiable {
    let id = UUID()
    let activity: Region.Activity
    let region: Region
}

private struct EncounterPresentation: Identifiable {
    let id = UUID()
    let character: CharacterDTO
    let openingLine: String
    let origin: EncounterService.Origin
    let activity: Region.Activity
    let region: Region
}

private struct ActivityMomentSheet: View {
    let presentation: ActivityMomentPresentation
    let onDismiss: () -> Void

    private var activity: Region.Activity { presentation.activity }
    private var region: Region { presentation.region }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.lg) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 36, height: 5)

                ZStack(alignment: .bottomLeading) {
                    GeometryReader { proxy in
                        Image("home_activity_\(region.id)")
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: 190)
                            .clipped()
                    }
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Label("探索完成", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(activity.category.tint)
                        Text(activity.titleZh)
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .foregroundStyle(.white)
                    .padding(DSSpacing.md)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous))

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("本次见闻")
                        .font(.caption.weight(.black))
                        .foregroundStyle(activity.category.tint)
                    Text(activity.outcomeZh)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Label(region.nameZh, systemImage: "mappin.and.ellipse")
                        Spacer()
                        Label("\(activity.durationMinutes) 分钟", systemImage: "clock")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .dsSurface(.elevated)

                Label(
                    "这次没有遇见新角色，但城市依然留下了一段只属于你的片刻。",
                    systemImage: "sparkles"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("收下这段见闻") {
                    onDismiss()
                }
                .buttonStyle(.dsAction(.tinted(activity.category.tint)))
            }
            .padding(DSSpacing.md)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}

private struct EncounterCardSheet: View {
    let presentation: EncounterPresentation
    let deps: HomeDependencies
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showChat = false
    @State private var friendMessage: String?
    @State private var isFriend = false
    @State private var hasRevealed = false
    @State private var wordSelection: TokenSelection?

    private var card: CharacterCard { presentation.character.card }
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

                HStack(spacing: DSSpacing.sm) {
                    Button("开始聊天") { showChat = true }
                        .buttonStyle(.dsAction(.tinted(tint)))
                    Button(isFriend ? "已加好友" : "加为好友") { addFriend() }
                        .buttonStyle(.dsAction(.secondary))
                        .disabled(isFriend)
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
            aiFallback: aiWordFallback,
            exampleTranslationActions: deps.exampleTranslationActions
        )
        .onAppear {
            withAnimation(reduceMotion ? DSAnimation.feedback : DSAnimation.scene) {
                hasRevealed = true
            }
        }
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

    private var encounterHeader: some View {
        VStack(spacing: DSSpacing.xs) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 108, height: 108)
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 1)
                    .frame(width: 94, height: 94)
                AvatarBadge(name: card.name, size: 82)
            }

            Label(rarityLabel, systemImage: rarityIcon)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12), in: Capsule())

            Text("在「\(presentation.activity.titleZh)」途中")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                    characterID: presentation.character.id
                )
            }
            onDismiss()
        }
    }
}

private extension Region.ActivityCategory {
    var titleZh: String {
        switch self {
        case .culture: "人文"
        case .food: "美食"
        case .outdoors: "户外"
        case .social: "社交"
        case .night: "夜游"
        }
    }

    var icon: String {
        switch self {
        case .culture: "building.columns.fill"
        case .food: "fork.knife"
        case .outdoors: "figure.hiking"
        case .social: "person.2.fill"
        case .night: "moon.stars.fill"
        }
    }

    var tint: Color {
        switch self {
        case .culture: .dsQuiz
        case .food: .dsSunset
        case .outdoors: .dsSuccess
        case .social: .dsSky
        case .night: .dsSpeech
        }
    }
}
