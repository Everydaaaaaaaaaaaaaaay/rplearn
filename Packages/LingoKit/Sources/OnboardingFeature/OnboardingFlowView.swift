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

    public init(deps: OnboardingDependencies, onComplete: @escaping (CharacterDTO) -> Void) {
        self.deps = deps
        self.onComplete = onComplete
    }

    public var body: some View {
        Group {
            switch phase {
            case .story:
                if let player {
                    ChatStoryView(player: player) {
                        withAnimation(.snappy) {
                            phase = .selection
                        }
                    }
                } else {
                    ProgressView()
                }
            case .selection:
                CharacterSelectView(characters: characters, onSelect: onComplete)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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

/// 聊天皮肤的剧情播放：气泡逐条点击推进（plan.md §3.6 首启剧情复用引擎、换渲染皮肤）。
struct ChatStoryView: View {
    let player: StoryPlayer
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(player.history) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.speaker)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 6)
                                MessageBubble(side: .incoming) {
                                    Text(line.text)
                                }
                            }
                            .id(line.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(12)
                }
                .onChange(of: player.history.count) {
                    if let last = player.history.last {
                        withAnimation(.snappy) {
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
    }

    private var header: some View {
        HStack {
            ZStack {
                Circle().fill(Color.pink.opacity(0.2))
                Text("雨").foregroundStyle(.pink).font(.headline)
            }
            .frame(width: 36, height: 36)
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
                        withAnimation(.snappy) {
                            player.choose(index)
                            player.advance()
                        }
                    } label: {
                        Text(option.text)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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
            withAnimation(.snappy) {
                player.advance()
            }
        }
    }
}

/// 主角色资料浏览与选择。
struct CharacterSelectView: View {
    let characters: [CharacterDTO]
    let onSelect: (CharacterDTO) -> Void

    private static let regionNames = ["london": "伦敦", "melbourne": "墨尔本", "newyork": "纽约"]
    private static let regionFlags = ["london": "🇬🇧", "melbourne": "🇦🇺", "newyork": "🇺🇸"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("选择你的出发城市")
                    .font(.title2.bold())
                    .padding(.top, 24)
                Text("每个城市都有一位伙伴在等你")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(characters) { character in
                    card(character)
                }
            }
            .padding(16)
        }
    }

    private func card(_ character: CharacterDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15))
                    Text(String(character.card.name.prefix(1)))
                        .font(.title2.bold())
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.card.name)
                        .font(.headline)
                    Text("\(Self.regionFlags[character.card.regionID] ?? "🌍") \(Self.regionNames[character.card.regionID] ?? character.card.regionID) · \(character.card.age) 岁")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(character.card.occupation)
                .font(.subheadline)
            Text(character.card.personality)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack(spacing: 6) {
                ForEach(character.card.hobbies.prefix(3), id: \.self) { hobby in
                    Text(hobby)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
            }
            Button {
                onSelect(character)
            } label: {
                Text("去\(Self.regionNames[character.card.regionID] ?? "这里")找 TA")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
