import CoreKit
import DesignSystem
import DictKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI
import Translation

/// 聊天页：消息列表 + 输入栏（文本/语音）+ 流式回复 + 点词查词。
public struct ChatView: View {
    @State var viewModel: ChatViewModel
    @State var wordSelection: TokenSelection?
    @State var grammarAnalysis: GrammarAnalysisRequest?
    @State var grammarAICache: [UUID: AIGrammarAnalysis] = [:]
    @State var expandedCoachMessageIDs: Set<UUID> = []
    @State var transcriptVisibleMessageIDs: Set<UUID> = []
    @State var isVoiceMode = false
    @State var recorder: VoiceRecorder
    @State var voicePlayer: VoiceMessagePlayer
    @State var showSimulatorInjection = false
    @State var simulatorInjectionText = ""
    @State var appleTranslator = AppleTranslator()
    @State var quizCelebrationTrigger = 0
    @State var shakingMessageID: UUID?
    @State var shakePhase = false
    @State var isMascotPromptDismissed = false
    @State var showsRealtimeConversation = false
    @State var isNearConversationBottom = true
    @State var unseenIncomingMessageCount = 0
    @State var knownLatestMessageID: UUID?
    @State var showsContactDetails = false
    @State var highlightedMessageID: UUID?
    @FocusState var isTextInputFocused: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) var dismiss
    let deps: ChatDependencies

    public init(
        character: CharacterDTO,
        deps: ChatDependencies,
        startsInRealtimeConversation: Bool = false
    ) {
        _viewModel = State(initialValue: ChatViewModel(character: character, deps: deps))
        _recorder = State(initialValue: VoiceRecorder(audioSession: deps.audioSession))
        _voicePlayer = State(initialValue: VoiceMessagePlayer(audioSession: deps.audioSession))
        _showsRealtimeConversation = State(initialValue: startsInRealtimeConversation)
        self.deps = deps
    }

    public var body: some View {
        messageList
        // 输入栏参与系统安全区布局；键盘出现时会缩小消息视口，
        // 而不是覆盖输入栏或当前可见消息。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .background(Color.dsBackground)
        .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { notification in
            guard notification.object as? UUID == viewModel.character.id else { return }
            Task { await viewModel.refreshCharacter() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarBadge(
                            name: viewModel.character.displayName,
                            size: 32,
                            imageName: viewModel.character.card.avatarAssetName,
                            remoteURL: viewModel.character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                            usesPendingPlaceholder: true
                        )
                        Circle()
                            .fill(viewModel.isStreaming ? Color.dsSunset : Color.dsSuccess)
                            .frame(width: 9, height: 9)
                            .overlay { Circle().stroke(Color.dsSurface, lineWidth: 1.5) }
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewModel.character.displayName)
                            .font(.subheadline.bold())
                        Text(chatStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isTextInputFocused = false
                    voicePlayer.stop()
                    // 先展示页面，让点击立即得到反馈；旧 TTS 在实时页启动阶段有序停止。
                    showsRealtimeConversation = true
                } label: {
                    Image(systemName: "phone.fill")
                }
                .accessibilityLabel("与\(viewModel.character.card.name)实时语音对话")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isTextInputFocused = false
                    voicePlayer.stop()
                    showsContactDetails = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("聊天设置")
            }
        }
        .accessibilityAction(named: "聊天设置") {
            isTextInputFocused = false
            voicePlayer.stop()
            showsContactDetails = true
        }
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
        .sheet(item: $grammarAnalysis) { request in
            GrammarAnalysisSheet(
                request: request,
                service: GrammarAnalysisService(llm: deps.llm),
                initialAIAnalysis: grammarAICache[request.id],
                dictionary: deps.dictionary,
                grammar: deps.grammarPoints,
                favorites: deps.favorites,
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
                exampleTranslationActions: deps.exampleTranslationActions,
                onAIAnalysis: { analysis in
                    grammarAICache[request.id] = analysis
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsRealtimeConversation, onDismiss: {
            Task { await viewModel.refreshMessages() }
        }) {
            RealtimeConversationView(
                chat: viewModel,
                deps: deps,
                onSpeechPlayback: {}
            )
        }
        .sheet(isPresented: $showsContactDetails) {
            NavigationStack {
                ChatContactDetailsView(
                    viewModel: viewModel,
                    onSelectMessage: { messageID in
                        highlightedMessageID = messageID
                        showsContactDetails = false
                    },
                    onRemoved: {
                        showsContactDetails = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            dismiss()
                        }
                    }
                )
            }
        }
        .translationTask(appleTranslator.configuration) { @Sendable session in
            // session 非 Sendable，只能在本闭包内内联使用；仅与协调器交换纯数据。
            try? await session.prepareTranslation()
            for item in await appleTranslator.takeBatch() {
                let zh = try? await session.translate(item.text).targetText
                await appleTranslator.complete(item.id, with: zh)
            }
        }
        .task {
            // 注入 Apple 端上翻译作为云端翻译失败/离线时的兜底。
            viewModel.translationFallback = { [appleTranslator] text in
                await appleTranslator.translate(text)
            }
            await viewModel.load()
            knownLatestMessageID = viewModel.messages.last?.id
            markVisibleConversationRead()
        }
        .onChange(of: viewModel.messages.last?.id) {
            markVisibleConversationRead()
        }
        .onChange(of: viewModel.draft) {
            viewModel.noteDraftActivity()
        }
        .onDisappear {
            markVisibleConversationRead()
        }
        .dsTabBarHidden()
    }

    private func markVisibleConversationRead() {
        Task {
            await viewModel.markConversationRead(at: viewModel.messages.last?.createdAt ?? .now)
        }
    }

    private var chatStatus: String {
        if viewModel.isStreaming {
            return "AI 旅伴 · 正在生成回复"
        }
        if viewModel.conversation?.isEncounterSession == true {
            return "AI 旅伴 · 偶遇中"
        }
        return "AI 旅伴 · 可对话"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            if ChatTimelinePolicy.shouldShowTimeMarker(
                                in: viewModel.messages,
                                at: index
                            ) {
                                timeMarker(for: message.createdAt)
                                    .padding(.top, index == 0 ? 2 : 12)
                                    .padding(.bottom, 6)
                            }
                            messageRow(message, at: index)
                                .id(message.id)
                                .padding(.top, messageTopSpacing(at: index))
                                .background(
                                    highlightedMessageID == message.id
                                        ? Color.dsSky.opacity(0.14)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: DSRadius.card)
                                )
                                .animation(
                                    reduceMotion ? nil : .easeInOut(duration: 0.2),
                                    value: highlightedMessageID
                                )
                        }
                        if viewModel.streamingText != nil {
                            MessageBubble(
                                side: .incoming,
                                groupPosition: streamingGroupPosition,
                                leadingAccessory: {
                                    incomingAvatar(isVisible: true)
                                }
                            ) {
                                TypingIndicator()
                            }
                            .id("streaming")
                            .padding(.top, streamingTopSpacing)
                            .transition(.opacity)
                        }
                        if let error = viewModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.dsDanger)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.top, 8)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("conversation-bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .scrollBounceBehavior(.always)
                .scrollDismissesKeyboard(.interactively)
                // 短会话没有足够滚动范围时，系统的交互式收起不会开始；
                // 兜底手势仅挂在消息区，避免与输入框争抢首触。
                .simultaneousGesture(messageListKeyboardDismissGesture)
                .background(Color.dsBackground)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.visibleRect.maxY < 96
                } action: { _, isNearBottom in
                    isNearConversationBottom = isNearBottom
                    if isNearBottom {
                        unseenIncomingMessageCount = 0
                    }
                }
                .onChange(of: viewModel.streamingText) {
                    guard isNearConversationBottom else { return }
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.last?.id) {
                    guard let last = viewModel.messages.last else {
                        knownLatestMessageID = nil
                        return
                    }
                    guard knownLatestMessageID != last.id else { return }
                    let isInitialHistory = knownLatestMessageID == nil
                    knownLatestMessageID = last.id
                    if isInitialHistory {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        return
                    }
                    if isNearConversationBottom || last.role == .user {
                        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                    } else if last.role == .assistant {
                        unseenIncomingMessageCount += 1
                    }
                }
                .onChange(of: isTextInputFocused) {
                    guard isTextInputFocused else { return }
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: highlightedMessageID) { _, messageID in
                    guard let messageID else { return }
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        proxy.scrollTo(messageID, anchor: .center)
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        guard highlightedMessageID == messageID else { return }
                        highlightedMessageID = nil
                    }
                }

                if !isNearConversationBottom {
                    Button {
                        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                        isNearConversationBottom = true
                        unseenIncomingMessageCount = 0
                    } label: {
                        Label(
                            unseenIncomingMessageCount > 0
                                ? "\(unseenIncomingMessageCount) 条新消息"
                                : "回到底部",
                            systemImage: "arrow.down"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.dsSkyDeep)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().stroke(Color.dsBorder, lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .accessibilityHint("跳转到会话中的最新消息")
                }
            }
        }
    }

    private var messageListKeyboardDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isTextInputFocused, value.translation.height > 0 else { return }
                isTextInputFocused = false
            }
    }

    private func messageTopSpacing(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if ChatTimelinePolicy.shouldShowTimeMarker(in: viewModel.messages, at: index) {
            return 0
        }
        let previous = viewModel.messages[index - 1]
        let current = viewModel.messages[index]
        guard previous.role != .coach, current.role != .coach else { return 10 }
        return ChatTimelinePolicy.canGroup(previous, current) ? 3 : 12
    }

    private var streamingTopSpacing: CGFloat {
        viewModel.messages.last?.role == .assistant ? 3 : 12
    }

    @ViewBuilder
    private func messageRow(_ message: MessageDTO, at index: Int) -> some View {
        let groupPosition = displayedGroupPosition(at: index)
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .bottom, spacing: 6) {
                    userMessageBubble(message, groupPosition: groupPosition)
                    outgoingAvatar(
                        isVisible: ChatTimelinePolicy.showsOutgoingAvatar(
                            in: viewModel.messages,
                            at: index
                        )
                    )
                }
                translationFootnote(message, alignment: .trailing)
                deliveryReceipt(at: index)
                coachCard(message)
                speechReviewCard(message)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                MessageBubble(
                    side: .incoming,
                    groupPosition: groupPosition,
                    leadingAccessory: {
                        incomingAvatar(
                            isVisible: ChatTimelinePolicy.showsIncomingAvatar(
                                in: viewModel.messages,
                                at: index,
                                hasTypingContinuation: viewModel.isStreaming
                            )
                        )
                    },
                    contextMenu: {
                        bubbleMenu(message)
                    }
                ) {
                    tappableText(message, textColor: nil)
                }
                .accessibilityAction(named: "语法解析") {
                    presentGrammarAnalysis(for: message)
                }
                translationFootnote(message, alignment: .leading)
                if message.isInterrupted {
                    Button {
                        Task { await viewModel.retryInterrupted(messageID: message.id) }
                    } label: {
                        Label("回复中断，点击重试", systemImage: "arrow.clockwise")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                }
                quizCard(message)
            }
        case .coach:
            // storyLine：剧情/系统通知（居中提示）；纯教练消息不占位
            if message.kind == .storyLine {
                Label(message.text, systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityHint("系统消息，\(ChatTimelinePolicy.exactTimeText(for: message.createdAt))")
            }
        }
    }

    private func displayedGroupPosition(at index: Int) -> MessageBubbleGroupPosition {
        let position = ChatTimelinePolicy.groupPosition(in: viewModel.messages, at: index)
        guard viewModel.isStreaming,
              index == viewModel.messages.indices.last,
              viewModel.messages[index].role == .assistant
        else { return position }

        return switch position {
        case .single: .first
        case .last: .middle
        case .first, .middle: position
        }
    }

    private var streamingGroupPosition: MessageBubbleGroupPosition {
        guard viewModel.messages.last?.role == .assistant else { return .single }
        return .last
    }

    private func timeMarker(for date: Date) -> some View {
        Text(ChatTimelinePolicy.timeMarkerText(for: date))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityLabel("会话时间，\(ChatTimelinePolicy.exactTimeText(for: date))")
    }

    @ViewBuilder
    private func incomingAvatar(isVisible: Bool) -> some View {
        if isVisible {
            AvatarBadge(
                name: viewModel.character.displayName,
                size: 30,
                imageName: viewModel.character.card.avatarAssetName,
                remoteURL: viewModel.character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                usesPendingPlaceholder: true
            )
        } else {
            Color.clear
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func outgoingAvatar(isVisible: Bool) -> some View {
        if isVisible {
            AvatarBadge(name: "我", tint: Color.dsSkyDeep, size: 30)
        } else {
            Color.clear
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func deliveryReceipt(at index: Int) -> some View {
        if let receipt = ChatTimelinePolicy.deliveryReceipt(
            in: viewModel.messages,
            at: index,
            isReplying: viewModel.isStreaming
        ) {
            Label(receipt.label, systemImage: receipt.systemImage)
                .font(.caption2.weight(.medium))
                .foregroundStyle(receipt == .read ? Color.dsSkyDeep : Color.secondary)
                .padding(.trailing, 4)
                .transition(.opacity)
                .accessibilityLabel("消息\(receipt.label)")
        }
    }

    /// 长按菜单仅保留消息级操作；单词收藏统一收敛到释义弹窗。
    @ViewBuilder
    func bubbleMenu(_ message: MessageDTO) -> some View {
        if message.role == .assistant, !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                presentGrammarAnalysis(for: message)
            } label: {
                Label("语法解析", systemImage: "text.book.closed")
            }
        }
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        Button {
            Task { await viewModel.translate(message: message) }
        } label: {
            Label("翻译", systemImage: "character.book.closed.zh")
        }
        Button {
            Task { await viewModel.speak(message: message) }
        } label: {
            Label("播放", systemImage: "speaker.wave.2")
        }
        if message.kind == .voice {
            Button {
                if transcriptVisibleMessageIDs.contains(message.id) {
                    transcriptVisibleMessageIDs.remove(message.id)
                } else {
                    transcriptVisibleMessageIDs.insert(message.id)
                }
            } label: {
                Label(
                    transcriptVisibleMessageIDs.contains(message.id) ? "隐藏文字" : "查看文字",
                    systemImage: "text.bubble"
                )
            }
        }
    }
}
