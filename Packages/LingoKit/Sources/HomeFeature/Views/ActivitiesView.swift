import BackendKit
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
    @State private var localCompanion: CharacterDTO?
    @State private var selectedCategory: Region.ActivityCategory?
    @State private var isRollingID: String?
    @State private var explorationProgress: ActivityExplorationPresentation?
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
        .task { await loadContext() }
        .onAppear { Task { await loadContext() } }
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
        .overlay {
            if let explorationProgress {
                ActivityExplorationOverlay(presentation: explorationProgress)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }
        }
        .animation(DSAnimation.snappy, value: explorationProgress?.id)
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
                    detail: localCompanion.map {
                        "与 \(firstName($0.card.name)) 同行"
                    } ?? "每天轮换一条在地路线"
                )

                Button {
                    runActivity(activity, region: region)
                } label: {
                    featuredCard(activity, region: region)
                }
                .buttonStyle(.pressableCard)
                .disabled(isRollingID != nil)
                .accessibilityLabel(
                    activityAccessibilityLabel(activity, prefix: "今日推荐，")
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
                    activityAccessibilityLabel(activity)
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
        explorationProgress = ActivityExplorationPresentation(activity: activity, region: region)

        Task {
            defer { isRollingID = nil }
            let minimumJourney = Task {
                try? await Task.sleep(for: minimumExplorationDuration)
            }
            let companion = localCompanion
            await recordSharedActivity(activity, companion: companion)
            guard EncounterService.shouldEncounter(
                roll: .random(in: 0..<1),
                probability: activity.encounterProbability
            ) else {
                await minimumJourney.value
                await hideExplorationProgress()
                Haptics.notify(.success)
                activityMoment = ActivityMomentPresentation(
                    activity: activity,
                    region: region,
                    companionName: companion?.card.name
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
                existingNames: names,
                activityContext: "\(activity.category.rawValue): \(activity.titleZh). \(activity.detailZh)"
            )
            let generatedCharacterID = UUID()
            var publicCard = encounter.card
            var publicTravelerID: String?
            if let registry = deps.npcRegistry {
                do {
                    let registered = try await registry.registerPublicNPC(
                        id: generatedCharacterID,
                        card: PublicNPCAdapter.backendCard(from: encounter.card)
                    )
                    publicCard = PublicNPCAdapter.characterCard(from: registered)
                    publicTravelerID = registered.travelerId
                } catch {
                    // 游客或离线时继续使用同一 UUID 的端侧稳定旅伴号；登录联网后不阻断偶遇。
                    Log.app.info("公共 NPC 登记暂不可用，使用端侧身份：\(String(describing: type(of: error)))")
                }
            }
            guard let characterID = try? await deps.rosterStore.addCharacter(
                characterID: generatedCharacterID,
                travelerID: publicTravelerID,
                card: publicCard,
                difficulty: currentProfile?.difficultyLevel ?? .junior3,
                isFriend: false
            ) else {
                await minimumJourney.value
                await hideExplorationProgress()
                activityMoment = ActivityMomentPresentation(
                    activity: activity,
                    region: region,
                    companionName: companion?.card.name
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
            guard let character = try? await deps.rosterStore.character(id: characterID) else {
                await minimumJourney.value
                await hideExplorationProgress()
                activityMoment = ActivityMomentPresentation(
                    activity: activity,
                    region: region,
                    companionName: companion?.card.name
                )
                return
            }
            await minimumJourney.value
            await hideExplorationProgress()
            Haptics.notify(.success)
            encounterResult = EncounterPresentation(
                character: character,
                openingLine: encounter.openingLine,
                origin: encounter.origin,
                activity: activity,
                region: region,
                companionName: companion?.card.name
            )
        }
    }

    private var minimumExplorationDuration: Duration {
        #if DEBUG
        if ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("UI_TEST_") }) {
            return .milliseconds(300)
        }
        #endif
        return .seconds(8)
    }

    @MainActor
    private func hideExplorationProgress() async {
        explorationProgress = nil
        try? await Task.sleep(for: .milliseconds(180))
    }

    private func loadContext() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCharacters = try? deps.rosterStore.allCharacters()
        let profile = await loadedProfile
        let characters = await loadedCharacters ?? []
        self.profile = profile
        self.localCompanion = profile.flatMap {
            RelationshipContextEvent.preferredCompanion(
                in: $0.currentRegionID,
                characters: characters
            )
        }
    }

    private func recordSharedActivity(
        _ activity: Region.Activity,
        companion: CharacterDTO?
    ) async {
        guard let companion else { return }
        do {
            _ = try await RelationshipContextEventService(rosterStore: deps.rosterStore).apply(
                characterID: companion.id,
                signal: RelationshipContextEvent.sharedActivity(
                    title: activity.titleZh,
                    companionName: companion.card.name
                ),
                source: .sharedActivity,
                eventID: UUID()
            )
        } catch {
            Log.app.warning("共同活动关系结算失败：\(error.localizedDescription)")
        }
    }

    private func activityAccessibilityLabel(
        _ activity: Region.Activity,
        prefix: String = ""
    ) -> String {
        let companion = localCompanion.map { "，与 \(firstName($0.card.name)) 同行" } ?? ""
        return "\(prefix)\(activity.titleZh)，\(activity.category.titleZh)，约 \(activity.durationMinutes) 分钟，邂逅率 \(Int((activity.encounterProbability * 100).rounded()))%\(companion)"
    }

    private func firstName(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? value
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

private struct ActivityExplorationPresentation: Identifiable, Equatable {
    let id = UUID()
    let activity: Region.Activity
    let region: Region
    let startedAt = Date.now

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

private struct ActivityExplorationOverlay: View {
    let presentation: ActivityExplorationPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let statusMessages = [
        "沿着路线探索城市",
        "留意身边发生的小事",
        "这一程的结果还没有揭晓",
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: DSSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(presentation.activity.category.tint.opacity(0.14))
                        .frame(width: 92, height: 92)
                    Image(systemName: presentation.activity.category.icon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(presentation.activity.category.tint)
                    ProgressView()
                        .controlSize(.large)
                        .tint(presentation.activity.category.tint)
                        .offset(y: 64)
                }

                VStack(spacing: DSSpacing.xs) {
                    Text(presentation.activity.titleZh)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("\(presentation.region.nameZh) · 城市活动进行中")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if reduceMotion {
                    Text(statusMessages[0])
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    TimelineView(.periodic(from: presentation.startedAt, by: 2)) { timeline in
                        Text(statusMessage(at: timeline.date))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }

                Text("是否遇见新的旅伴，会在活动结束后一起揭晓")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(DSSpacing.xl)
            .frame(maxWidth: 340)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
                    .stroke(Color.dsBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .padding(DSSpacing.lg)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.activity.titleZh)进行中，结果尚未揭晓")
    }

    private func statusMessage(at date: Date) -> String {
        let elapsed = max(0, date.timeIntervalSince(presentation.startedAt))
        return statusMessages[Int(elapsed / 2) % statusMessages.count]
    }
}
