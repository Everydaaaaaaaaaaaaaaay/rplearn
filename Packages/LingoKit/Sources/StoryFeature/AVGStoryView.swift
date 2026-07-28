import CoreKit
import DesignSystem
import DictKit
import DomainKit
import PersistenceKit
import SpeechKit
import StoryEngine
import SwiftUI

/// StoryFeature 依赖。
public struct StoryDependencies: Sendable {
    public let storyProgress: StoryProgressStore
    public let progression: any ProgressionRewardGateway
    public let rosterStore: RosterStore
    public let favorites: FavoritesStore
    public let dictionary: DictDatabase
    public let grammarPoints: GrammarPointStore
    public let speech: any SpeechService

    public init(
        storyProgress: StoryProgressStore,
        progression: any ProgressionRewardGateway,
        rosterStore: RosterStore,
        favorites: FavoritesStore,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService
    ) {
        self.storyProgress = storyProgress
        self.progression = progression
        self.rosterStore = rosterStore
        self.favorites = favorites
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
    }
}

/// 竖屏 AVG：背景 + 立绘 → 底部对话框（名牌 + 打字机台词）→
/// 顶部快进/自动/跳过 → 选项中上部垂直排列。台词定稿后接 TappableText 可查词。
public struct AVGStoryView: View {
    private let storyID: String
    private let scriptURL: URL
    private let deps: StoryDependencies

    @State private var player: StoryPlayer?
    @State private var typewriter = TypewriterState()
    @State private var isAuto = false
    @State private var wordSelection: TokenSelection?
    @State private var showSkipConfirm = false
    @State private var loadFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    public init(storyID: String, scriptURL: URL, deps: StoryDependencies) {
        self.storyID = storyID
        self.scriptURL = scriptURL
        self.deps = deps
    }

    public var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let choices = player?.currentChoices {
                    choiceStack(choices)
                    Spacer()
                }
                dialogBox
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .tabBar)
        .dsTabBarHidden()
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .accessibilityAction(named: player?.isFinished == true ? "退出本章" : "继续") {
            handleTap()
        }
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                let speech = deps.speech
                Task { await speech.speak(word, language: "en-US") }
            },
            favoriteActions: wordFavoriteActions
        )
        .task {
            await loadPlayerIfNeeded()
        }
        .task(id: isAuto) {
            await autoLoopIfNeeded()
        }
        .dsModalDialog(
            isPresented: $showSkipConfirm,
            configuration: .init(
                eyebrow: "剧情抉择",
                title: "跳过本章剧情？",
                message: "将直接推进到本章结尾，并按默认选项处理尚未做出的选择。之后仍可从剧情列表重温。",
                icon: "forward.end.fill",
                tone: .warning,
                primaryTitle: "确认跳过",
                primaryIcon: "forward.end.fill",
                primaryRole: .destructive,
                secondaryTitle: "继续剧情",
                secondaryIcon: "play.fill"
            ),
            onPrimary: skipAll
        )
        .dsModalDialog(
            isPresented: $loadFailed,
            configuration: .init(
                eyebrow: "剧情中断",
                title: "暂时无法载入剧情",
                message: "剧情资源未能读取，请返回剧情列表后重试。",
                icon: "exclamationmark.triangle.fill",
                tone: .danger,
                primaryTitle: "返回剧情列表",
                primaryIcon: "arrow.backward",
                secondaryTitle: nil,
                allowsInteractiveDismiss: false
            ),
            onPrimary: { dismiss() }
        )
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

    // MARK: - 背景与立绘

    private var currentLine: StoryPlayer.Line? {
        player?.history.last
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: DSScenePalette.story(currentLine?.bg),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            if let emoji = BackgroundPalette.emoji(for: currentLine?.bg) {
                Text(emoji)
                    .font(.system(size: 120))
                    .opacity(0.25)
                    .offset(y: -140)
            }
            // 立绘占位：说话人首字母大圆徽章（美术素材接入前的形象锚点）
            if let line = currentLine, line.speaker != "旁白" {
                VStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.25))
                        Text(String(line.speaker.prefix(1)))
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 140, height: 140)
                    .padding(.bottom, 210)
                    .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, phase in
                        content.offset(y: phase ? -7 : 5)
                    } animation: { _ in
                        .easeInOut(duration: 1.8)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentLine?.bg)
    }

    // MARK: - 顶部控制条

    private var topBar: some View {
        HStack(spacing: 18) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
            }
            Spacer()
            Button {
                player?.skipToNextChoiceOrEnd()
                typewriter.showFull(currentLine?.text ?? "")
            } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel("快进")
            Button {
                isAuto.toggle()
            } label: {
                Image(systemName: isAuto ? "pause.circle" : "play.circle")
            }
            .accessibilityLabel("自动播放")
            Button {
                showSkipConfirm = true
            } label: {
                Image(systemName: "chevron.forward.2")
            }
            .accessibilityLabel("跳过")
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - 对话框

    @ViewBuilder
    private var dialogBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = currentLine {
                Text(line.speaker)
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.dsSky, in: Capsule())
                    .foregroundStyle(.white)

                let tokens = TokenCache.tokens(
                    for: line.text,
                    cacheKey: "avg-\(storyID)-\(line.id)"
                )
                Group {
                    if typewriter.isTyping {
                        StableTypewriterText(
                            tokens: tokens,
                            visibleCharacterCount: typewriter.visibleText.count
                        )
                    } else {
                        TappableText(
                            tokens: tokens,
                            contextID: "avg-\(line.id)",
                            selection: wordSelection,
                            onSelect: { wordSelection = $0 }
                        )
                    }
                }
                .font(.body)
                .frame(minHeight: 76, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(player?.isFinished == true ? "本章完 · 点击退出" : "点击继续")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding(14)
        .dsMaterial(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    // MARK: - 选项

    private func choiceStack(_ choices: [StoryChoiceOption]) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, option in
                Button {
                    player?.choose(index)
                    advanceWithTyping()
                } label: {
                    Text(option.text)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.dsAction(.glass))
            }
        }
        .padding(.horizontal, 32)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - 行为

    private func handleTap() {
        guard let player else { return }
        if player.isFinished {
            dismiss()
            return
        }
        guard player.currentChoices == nil else { return }
        if typewriter.isTyping {
            typewriter.showFull(currentLine?.text ?? "")
        } else {
            advanceWithTyping()
        }
    }

    private func advanceWithTyping() {
        guard let player, !player.isFinished else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            player.advance()
        }
        if let text = currentLine?.text {
            typewriter.start(text: text)
        }
    }

    private func autoLoopIfNeeded() async {
        guard isAuto else { return }
        while isAuto, let player, !player.isFinished {
            try? await Task.sleep(for: .milliseconds(300))
            if typewriter.isTyping || player.currentChoices != nil {
                continue
            }
            try? await Task.sleep(for: .seconds(1.2))
            if isAuto, player.currentChoices == nil, !player.isFinished {
                advanceWithTyping()
            }
        }
    }

    private func skipAll() {
        guard let player else { return }
        while !player.isFinished {
            if player.currentChoices != nil {
                player.choose(0)
            }
            player.skipToNextChoiceOrEnd()
        }
        typewriter.showFull(currentLine?.text ?? "")
    }

    private func loadPlayerIfNeeded() async {
        guard player == nil else { return }
        guard let script = try? StoryScript.load(from: scriptURL) else {
            loadFailed = true
            return
        }
        let progress = try? await deps.storyProgress.progress(storyID: storyID)
        let resumeNode = (progress?.isCompleted == true) ? nil : progress?.currentNodeID
        let player = StoryPlayer(script: script, resumeFrom: resumeNode, flags: progress?.flags ?? [:])

        let storyID = self.storyID
        let progressStore = deps.storyProgress
        let progression = deps.progression
        let rosterStore = deps.rosterStore

        player.onStateChange = { nodeID, flags in
            Task {
                try? await progressStore.saveCheckpoint(storyID: storyID, nodeID: nodeID, flags: flags)
            }
        }
        player.onReward = { reward in
            // 客户端脚本只负责演出；奖励值由服务端白名单与账本决定。
            _ = reward
        }
        player.onCompleted = { unlocks in
            Task {
                do {
                    _ = try await progression.completeStory(storyID)
                    for unlock in unlocks {
                        guard unlock.hasPrefix("character:") else { continue }
                        let regionID = String(unlock.dropFirst("character:".count))
                        try await rosterStore.unlockMainCharacter(regionID: regionID)
                    }
                    try await progressStore.markCompleted(storyID: storyID)
                } catch {
                    Log.app.warning("剧情完成同步失败：\(error)")
                }
            }
        }

        self.player = player
        advanceWithTyping()
    }
}

// MARK: - 打字机

/// 让完整 token 从第一帧就参与排版，仅隐藏尚未播放的字符。
///
/// 如果直接渲染持续增长的字符串，行尾单词会先留在上一行，字符增加后再整体跳到下一行。
/// 这里与定稿后的 `TappableText` 共用 token 级流式布局，使换行和对话框高度保持稳定。
private struct StableTypewriterText: View {
    let tokens: [TextToken]
    let visibleCharacterCount: Int

    var body: some View {
        FlowLayout {
            ForEach(revealedTokens) { token in
                (
                    Text(token.visible)
                        + Text(token.pending).foregroundColor(.clear)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(visibleText)
    }

    private var revealedTokens: [RevealedToken] {
        var remaining = max(0, visibleCharacterCount)
        return tokens.map { token in
            let visibleCount = min(remaining, token.display.count)
            remaining -= visibleCount
            return RevealedToken(
                id: token.id,
                visible: String(token.display.prefix(visibleCount)),
                pending: String(token.display.dropFirst(visibleCount))
            )
        }
    }

    private var visibleText: String {
        let fullText = tokens.map(\.display).joined()
        return String(fullText.prefix(max(0, visibleCharacterCount)))
    }

    private struct RevealedToken: Identifiable {
        let id: Int
        let visible: String
        let pending: String
    }
}

/// 打字机台词状态：点击先跳完打字、再推进。
@MainActor
@Observable
final class TypewriterState {
    private(set) var visibleText = ""
    private(set) var isTyping = false
    private var task: Task<Void, Never>?

    func start(text: String) {
        task?.cancel()
        visibleText = ""
        isTyping = true
        task = Task { @MainActor in
            for character in text {
                guard !Task.isCancelled else { return }
                visibleText.append(character)
                try? await Task.sleep(for: .milliseconds(28))
            }
            isTyping = false
        }
    }

    func showFull(_ text: String) {
        task?.cancel()
        visibleText = text
        isTyping = false
    }
}

// MARK: - 背景符号（配色由 DesignSystem.DSScenePalette 统一提供）

enum BackgroundPalette {
    static func emoji(for key: String?) -> String? {
        switch key {
        case "london_bookshop": "📚"
        case "london_street": "🌧️"
        case "melbourne_beach": "🌅"
        case "melbourne_cafe": "☕️"
        case "newyork_subway": "🚇"
        case "newyork_street": "🌆"
        case "capetown_signal_hill": "📻"
        case "singapore_rain": "🌦️"
        case "singapore_supertree": "🌿"
        case "capetown_bokaap": "🎨"
        case "singapore_hawker": "🍜"
        case "dublin_library": "📖"
        case "edinburgh_royal_mile": "🎭"
        case "vancouver_seawall": "📷"
        case "auckland_harbour": "⛵️"
        case "nairobi_karura": "🌧️"
        case "toronto_path": "🧭"
        case "sydney_harbour": "⛴️"
        case "neworleans_jazz": "🎺"
        case "manchester_record": "💿"
        case "kingston_studio": "🎙️"
        default: nil
        }
    }
}
