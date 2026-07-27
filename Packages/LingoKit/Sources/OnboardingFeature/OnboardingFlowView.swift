import DesignSystem
import PersistenceKit
import StoryEngine
import SwiftUI

/// 首启引导依赖。
public struct OnboardingDependencies: Sendable {
    public let rosterStore: RosterStore
    public let scriptURL: URL

    public init(rosterStore: RosterStore, scriptURL: URL) {
        self.rosterStore = rosterStore
        self.scriptURL = scriptURL
    }
}

/// 首启流程：聊天皮肤剧情（中奖通知 + 三主角色介绍）→ 主角色资料浏览 → 选定出发。
public struct OnboardingFlowView: View {
    private enum Phase {
        case story
        case selection
    }

    private let deps: OnboardingDependencies
    private let onComplete: (CharacterDTO) -> Void

    @State private var phase: Phase = .story
    @State private var player: StoryPlayer?
    @State private var characters: [CharacterDTO] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(deps: OnboardingDependencies, onComplete: @escaping (CharacterDTO) -> Void) {
        self.deps = deps
        self.onComplete = onComplete
    }

    public var body: some View {
        Group {
            switch phase {
            case .story:
                if let player {
                    ChatStoryView(player: player, characters: characters) {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            phase = .selection
                        }
                    }
                } else {
                    ProgressView()
                }
            case .selection:
                CharacterSelectView(characters: characters, onSelect: onComplete)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .task {
            if player == nil, let script = try? StoryScript.load(from: deps.scriptURL) {
                let player = StoryPlayer(script: script)
                player.advance() // 显示第一条
                self.player = player
            }
            characters = (try? await deps.rosterStore.allCharacters().filter(\.isMainCharacter)) ?? []
            #if DEBUG
            await autoplayIfRequested()
            #endif
        }
    }

    #if DEBUG
    /// 冒烟验收用：SIMCTL_CHILD_ONBOARDING_AUTOPLAY=1 自动播完剧情停在选择页；=full 再自动选第一位。
    private func autoplayIfRequested() async {
        let mode = ProcessInfo.processInfo.environment["ONBOARDING_AUTOPLAY"]
        guard mode == "1" || mode == "full", let player else { return }
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
            onComplete(first)
        }
    }
    #endif
}

/// 聊天皮肤的剧情播放：复用剧情引擎，气泡逐条点击推进。
struct ChatStoryView: View {
    let player: StoryPlayer
    let characters: [CharacterDTO]
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(player.history.enumerated()), id: \.element.id) { index, line in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.speaker)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 6)
                                MessageBubble(side: .incoming) {
                                    Text(line.text)
                                }
                                if shouldShowCard(at: index, line: line),
                                   let character = character(for: line.sprite) {
                                    CharacterIntroCard(character: character)
                                        .padding(.leading, 6)
                                        .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
                                }
                            }
                            .id(line.id)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
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
        .contentShape(Rectangle())
        .onTapGesture {
            advanceOrFinish()
        }
        .accessibilityAction(named: player.isFinished ? "查看伙伴资料" : "继续") {
            advanceOrFinish()
        }
    }

    private var header: some View {
        HStack {
            AvatarBadge(name: "小雨", tint: .pink, size: 36)
            Text("小雨")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var footer: some View {
        if let choices = player.currentChoices {
            VStack(spacing: 8) {
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
            .background(.bar)
        } else {
            Text(player.isFinished ? "点击查看伙伴资料 →" : "点击继续")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
    let characters: [CharacterDTO]
    let onSelect: (CharacterDTO) -> Void

    private static let regionNames = ["london": "伦敦", "melbourne": "墨尔本", "newyork": "纽约"]
    private static let regionFlags = ["london": "🇬🇧", "melbourne": "🇦🇺", "newyork": "🇺🇸"]
    @State private var selectedID: UUID?
    @State private var celebrationTrigger = 0
    @State private var isConfirming = false
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
                            .foregroundStyle(step == 2 ? .white : Color.dsSky)
                            .frame(width: 26, height: 26)
                            .background(step == 2 ? Color.dsSky : Color.dsSurface, in: Circle())
                        if step < 3 {
                            Capsule()
                                .fill(step < 2 ? Color.dsSky : Color.dsBorder)
                                .frame(width: 22, height: 3)
                        }
                    }
                }
                .padding(.top, DSSpacing.sm)

                Text("选择你的旅伴")
                    .font(.largeTitle.bold())
                Text("左右滑动，认识来自不同城市的朋友")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DSSpacing.md) {
                        ForEach(characters) { character in
                            physicalCard(character)
                                .containerRelativeFrame(.horizontal, count: 10, span: 8, spacing: DSSpacing.md)
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
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID)
                .contentMargins(.horizontal, 28, for: .scrollContent)

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
                    Text(buttonTitle)
                }
                .buttonStyle(.dsActionPrimary)
                .disabled(selectedCharacter == nil || isConfirming)
                .celebration(true, tint: .dsSky, trigger: celebrationTrigger)
                .padding(.horizontal, DSSpacing.xl)
                .padding(.bottom, DSSpacing.md)
            }
        }
        .onAppear { selectedID = selectedID ?? characters.first?.id }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: selectedID)
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

            AvatarBadge(name: character.card.name, tint: .white, size: 112)
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
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 600))
            onSelect(character)
        }
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}
