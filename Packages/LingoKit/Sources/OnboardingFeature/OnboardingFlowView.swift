import CoreKit
import DesignSystem
import DomainKit
import PersistenceKit
import StoryEngine
import SwiftUI

/// 首启引导依赖。
public struct OnboardingDependencies: Sendable {
    public let economyStore: EconomyStore
    public let profileCommands: any ProfileCommandGateway
    public let rosterStore: RosterStore
    public let scriptURL: URL

    public init(
        economyStore: EconomyStore,
        profileCommands: any ProfileCommandGateway,
        rosterStore: RosterStore,
        scriptURL: URL
    ) {
        self.economyStore = economyStore
        self.profileCommands = profileCommands
        self.rosterStore = rosterStore
        self.scriptURL = scriptURL
    }
}

/// 登录后的账号首启流程：建立学习档案 → 咕咕带来旅行邀请 → 主角色资料浏览 → 选定出发。
public struct OnboardingFlowView: View {
    private enum Phase {
        case loading
        case profile
        case calibration
        case story
        case selection
    }

    private let deps: OnboardingDependencies
    private let placementCompletionRevision: Int
    private let onRequestPlacement: () -> Void
    private let onComplete: (CharacterDTO) async -> Bool

    @State private var phase: Phase = .loading
    @State private var profile: UserProfileDTO?
    @State private var player: StoryPlayer?
    @State private var characters: [CharacterDTO] = []
    @AppStorage private var placementOfferDismissed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        accountID: UUID,
        deps: OnboardingDependencies,
        placementCompletionRevision: Int = 0,
        onRequestPlacement: @escaping () -> Void = {},
        onComplete: @escaping (CharacterDTO) async -> Bool
    ) {
        self.deps = deps
        self.placementCompletionRevision = placementCompletionRevision
        self.onRequestPlacement = onRequestPlacement
        self.onComplete = onComplete
        _placementOfferDismissed = AppStorage(
            wrappedValue: false,
            "onboarding.placement-offer.dismissed.v2.\(accountID.uuidString.lowercased())"
        )
    }

    public var body: some View {
        Group {
            switch phase {
            case .loading:
                onboardingLoading
            case .profile:
                if let profile {
                    LearnerProfileSetupView(
                        initialProfile: profile,
                        profileCommands: deps.profileCommands
                    ) { updated in
                        self.profile = updated
                        withAnimation(reduceMotion ? nil : .snappy) {
                            phase = .calibration
                        }
                    }
                } else {
                    onboardingLoading
                }
            case .calibration:
                PlacementCalibrationChoiceView(
                    onStart: onRequestPlacement,
                    onSkip: continueWithSelfAssessment
                )
            case .story:
                if let player {
                    ChatStoryView(player: player, characters: characters) {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            phase = .selection
                        }
                    }
                } else {
                    onboardingLoading
                }
            case .selection:
                CharacterSelectView(characters: characters, onSelect: onComplete)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .task {
            if profile == nil {
                profile = try? await deps.economyStore.profile()
            }
            if player == nil, let script = try? StoryScript.load(from: deps.scriptURL) {
                let player = StoryPlayer(script: script)
                player.advance() // 显示第一条
                self.player = player
            }
            characters = (try? await deps.rosterStore.allCharacters().filter(\.isMainCharacter)) ?? []
            if phase == .loading, let profile {
                phase = destination(for: profile)
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_SELECTION"] == "1" {
                phase = .selection
                return
            }
            if ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_STORY"] == "1",
               let player {
                phase = .story
                while player.history.count < 5, !player.isFinished {
                    if player.currentChoices != nil {
                        player.choose(0)
                    }
                    player.advance()
                }
                return
            }
            await autoplayIfRequested()
            #endif
        }
        .onChange(of: placementCompletionRevision) { oldValue, newValue in
            guard oldValue != newValue else { return }
            placementOfferDismissed = true
            Task {
                profile = try? await deps.economyStore.profile()
                withAnimation(reduceMotion ? nil : .snappy) {
                    phase = .story
                }
            }
        }
    }

    private var onboardingLoading: some View {
        ZStack {
            Color.dsBackground
            .ignoresSafeArea()

            VStack(spacing: DSSpacing.sm) {
                BrandMascotView(pose: .greeting, size: 112, showsShadow: false)
                ProgressView()
                    .tint(.dsSky)
                Text("\(AppBrand.mascotName)正在飞来…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func continueWithSelfAssessment() {
        placementOfferDismissed = true
        withAnimation(reduceMotion ? nil : .snappy) {
            phase = .story
        }
    }

    private func destination(for profile: UserProfileDTO) -> Phase {
        if !profile.hasCompletedProfileSetup { return .profile }
        if profile.proficiencySource == .placement || placementOfferDismissed { return .story }
        return .calibration
    }

    #if DEBUG
    /// 冒烟验收用：SIMCTL_CHILD_ONBOARDING_AUTOPLAY=1 自动播完剧情停在选择页；=full 再自动选第一位。
    private func autoplayIfRequested() async {
        let mode = ProcessInfo.processInfo.environment["ONBOARDING_AUTOPLAY"]
        guard mode == "1" || mode == "full",
              phase == .story,
              let player
        else { return }
        while !player.isFinished {
            try? await Task.sleep(for: .milliseconds(120))
            if player.currentChoices != nil {
                player.choose(0)
            }
            player.advance()
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.snappy) {
            phase = .selection
        }
        if mode == "full", let first = characters.first {
            try? await Task.sleep(for: .milliseconds(500))
            _ = await onComplete(first)
        }
    }
    #endif
}

/// 建档与剧情之间只出现一次的可选校准，不把测评包装成强制门槛。
private struct PlacementCalibrationChoiceView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.dsSky.opacity(0.1), Color.dsBackground],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.xl) {
                    HStack(alignment: .top, spacing: DSSpacing.md) {
                        BrandMascotView(pose: .guide, size: 104, showsShadow: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("要不要再校准一下？")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text("这是可选项，自评结果已经可以直接开始。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(spacing: 0) {
                        calibrationRow(
                            icon: "slider.horizontal.3",
                            title: "题目会动态调整",
                            detail: "答对会变难，答错会回到更合适的位置"
                        )
                        Divider().padding(.leading, 52)
                        calibrationRow(
                            icon: "clock",
                            title: "约 3–5 分钟",
                            detail: "通常 8–12 题，可随时退出"
                        )
                        Divider().padding(.leading, 52)
                        calibrationRow(
                            icon: "person.2",
                            title: "马上影响角色对话",
                            detail: "问题长度、词汇和引导方式会随结果调整"
                        )
                    }
                    .dsSurface(.grouped, padding: 0)

                    VStack(spacing: DSSpacing.sm) {
                        Button("答几题，更准确") {
                            onStart()
                        }
                        .buttonStyle(.dsActionPrimary)

                        Button("先按自评结果开始") {
                            onSkip()
                        }
                        .buttonStyle(.dsAction(.secondary))
                    }
                }
                .frame(maxWidth: 560)
                .padding(DSSpacing.lg)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func calibrationRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.dsSkyDeep)
                .frame(width: 36, height: 36)
                .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DSSpacing.sm)
    }
}

/// 聊天皮肤的剧情播放：复用剧情引擎，气泡逐条点击推进。
struct ChatStoryView: View {
    let player: StoryPlayer
    let characters: [CharacterDTO]
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.dsSky.opacity(0.035),
                    Color.dsBackground,
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(player.history.enumerated()), id: \.element.id) { index, line in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.speaker)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.dsSkyDeep)
                                        .padding(.leading, 6)
                                    MessageBubble(side: .incoming) {
                                        Text(line.text)
                                    }
                                    if shouldShowCard(at: index, line: line),
                                       let character = character(for: line.sprite) {
                                        CharacterIntroCard(character: character)
                                            .padding(.leading, 6)
                                            .transition(
                                                reduceMotion
                                                    ? .opacity
                                                    : .scale(scale: 0.94).combined(with: .opacity)
                                            )
                                    }
                                }
                                .id(line.id)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .move(edge: .bottom))
                                )
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: player.history.count) {
                        if let last = player.history.last {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                footer
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            advanceOrFinish()
        }
        .accessibilityAction(named: player.isFinished ? "查看伙伴资料" : "继续") {
            advanceOrFinish()
        }
    }

    private var header: some View {
        HStack(spacing: DSSpacing.xs) {
            BrandMascotView(pose: .greeting, size: 38, showsShadow: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(AppBrand.mascotName)
                    .font(.headline.weight(.bold))
                Text(AppBrand.mascotRole)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("开始旅程 2 / 3")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var footer: some View {
        if let choices = player.currentChoices {
            VStack(spacing: 8) {
                Text("你想怎么回答\(AppBrand.mascotName)？")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(choices.enumerated()), id: \.offset) { index, option in
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            player.choose(index)
                            player.advance()
                        }
                    } label: {
                        Text(option.text)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsAction(.secondary))
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
        } else {
            Label(
                player.isFinished ? "查看伙伴资料" : "轻点继续",
                systemImage: player.isFinished ? "person.2.crop.square.stack.fill" : "hand.tap.fill"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(player.isFinished ? Color.dsSkyDeep : .secondary)
            .padding(.vertical, 10)
        }
    }

    private func advanceOrFinish() {
        if player.isFinished {
            onFinished()
        } else if player.currentChoices == nil {
            withAnimation(reduceMotion ? nil : .snappy) {
                player.advance()
            }
        }
    }

    private func shouldShowCard(at index: Int, line: StoryPlayer.Line) -> Bool {
        guard line.sprite?.hasPrefix("card:") == true else { return false }
        guard index > 0 else { return true }
        return player.history[index - 1].sprite != line.sprite
    }

    private func character(for sprite: String?) -> CharacterDTO? {
        guard let regionID = sprite?.split(separator: ":").last.map(String.init) else { return nil }
        return characters.first { $0.card.regionID == regionID && $0.isMainCharacter }
    }
}

/// 主角色资料浏览与选择。
struct CharacterSelectView: View {
    private static let confirmationDelay = Duration.milliseconds(260)

    let characters: [CharacterDTO]
    let onSelect: (CharacterDTO) async -> Bool

    private static let regionNames = ["london": "伦敦", "melbourne": "墨尔本", "newyork": "纽约"]
    private static let regionFlags = ["london": "🇬🇧", "melbourne": "🇦🇺", "newyork": "🇺🇸"]
    @State private var selectedID: UUID?
    @State private var celebrationTrigger = 0
    @State private var isConfirming = false
    @State private var selectionError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shouldReduceMotion = reduceMotion
        ZStack {
            LinearGradient(
                colors: [Color.dsSky.opacity(0.22), Color.dsBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: DSSpacing.sm) {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { step in
                        Text("\(step)")
                            .font(.caption.bold())
                            .foregroundStyle(step == 3 ? .white : Color.dsSky)
                            .frame(width: 26, height: 26)
                            .background(step == 3 ? Color.dsSky : Color.dsSurface, in: Circle())
                        if step < 3 {
                            Capsule()
                                .fill(Color.dsSky)
                                .frame(width: 22, height: 3)
                        }
                    }
                }
                .padding(.top, DSSpacing.sm)

                HStack(spacing: DSSpacing.xs) {
                    BrandMascotView(pose: .guide, size: 88, showsShadow: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("选择你的第一位旅伴")
                            .font(.system(.title2, design: .rounded, weight: .black))
                        Text("\(AppBrand.mascotName)会陪你一起出发")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(characters) { character in
                            physicalCard(character)
                                .padding(.horizontal, 28)
                                .containerRelativeFrame(.horizontal)
                                .id(character.id)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.92)
                                        .rotation3DEffect(
                                            .degrees(shouldReduceMotion ? 0 : Double(phase.value) * -9),
                                            axis: (x: 0, y: 1, z: 0),
                                            perspective: 0.65
                                        )
                                        .opacity(shouldReduceMotion || phase.isIdentity ? 1 : 0.74)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedID)

                HStack(spacing: 7) {
                    ForEach(characters) { character in
                        Circle()
                            .fill(selectedID == character.id ? Color.dsSky : Color.dsBorder)
                            .frame(width: selectedID == character.id ? 18 : 7, height: 7)
                            .animation(reduceMotion ? nil : DSAnimation.snappy, value: selectedID)
                    }
                }

                Button {
                    confirmSelection()
                } label: {
                    HStack(spacing: DSSpacing.xs) {
                        if isConfirming {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isConfirming ? "正在准备旅程…" : buttonTitle)
                    }
                }
                .buttonStyle(.dsActionPrimary)
                .disabled(selectedCharacter == nil || isConfirming)
                .celebration(true, tint: .dsSky, trigger: celebrationTrigger)
                .accessibilityIdentifier("onboarding.selection.confirm")
                .padding(.horizontal, DSSpacing.xl)
                .padding(.bottom, DSSpacing.md)
            }
        }
        .onAppear { selectedID = selectedID ?? characters.first?.id }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: selectedID)
        .alert(
            "暂时无法出发",
            isPresented: Binding(
                get: { selectionError != nil },
                set: { if !$0 { selectionError = nil } }
            )
        ) {
            Button("再试一次") { selectionError = nil }
        } message: {
            Text(selectionError ?? "请稍后重试。")
        }
    }

    private var selectedCharacter: CharacterDTO? {
        selectedID.flatMap { id in characters.first { $0.id == id } }
    }

    private var buttonTitle: String {
        guard let character = selectedCharacter else { return "选择一位旅伴" }
        return "去\(Self.regionNames[character.card.regionID] ?? "这座城市")找 \(firstName(character.card.name))"
    }

    private func physicalCard(_ character: CharacterDTO) -> some View {
        let palette = DSScenePalette.city(character.card.regionID)
        return VStack(spacing: DSSpacing.md) {
            HStack {
                Text(firstName(character.card.name))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                Spacer()
                Text(Self.regionFlags[character.card.regionID] ?? "🌍")
                    .font(.system(size: 32))
                    .padding(7)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                    .rotationEffect(.degrees(3))
            }

            AvatarBadge(
                name: character.card.name,
                tint: .white,
                size: 112,
                imageName: character.card.avatarAssetName,
                remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:))
            )
                .accessibilityIdentifier("onboarding.character.avatar.\(character.card.regionID)")
                .background(.white.opacity(0.16), in: Circle())

            VStack(spacing: 4) {
                Text("\(character.card.age) 岁 · \(Self.regionNames[character.card.regionID] ?? character.card.regionID) · \(character.card.occupation)")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(character.card.personality)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .opacity(0.88)
            }

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(character.card.localizedHobbies.prefix(3), id: \.self) { hobby in
                    DSChip(hobby, tint: .white)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(DSSpacing.lg)
        .frame(maxHeight: 520)
        .background(
            LinearGradient(
                colors: [palette.skyTop, palette.accent, palette.silhouetteNear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 7)
        }
        .shadow(color: palette.silhouetteNear.opacity(0.35), radius: 18, y: 12)
        .scaleEffect(!reduceMotion && isConfirming && selectedID == character.id ? 1.04 : 1)
        .animation(reduceMotion ? nil : DSAnimation.celebration, value: isConfirming)
        .padding(.vertical, 18)
    }

    private func confirmSelection() {
        guard let character = selectedCharacter else { return }
        isConfirming = true
        celebrationTrigger += 1
        Task {
            if !reduceMotion {
                do {
                    try await Task.sleep(for: Self.confirmationDelay)
                } catch {
                    isConfirming = false
                    return
                }
            }
            guard await onSelect(character) else {
                isConfirming = false
                selectionError = "旅程没有保存成功，请稍后再试一次。"
                return
            }
        }
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}
