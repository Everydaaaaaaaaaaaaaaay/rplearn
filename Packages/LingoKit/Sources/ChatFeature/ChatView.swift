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
import UIKit

/// 聊天页：消息列表 + 输入栏（文本/语音）+ 流式回复 + 点词查词。
public struct ChatView: View {
    @State var viewModel: ChatViewModel
    @State private var learningSelected = false
    @State private var autoReadEnabled = false
    @State private var autoReadReady = false
    @State var autoReadQueue: ChatAutoReadQueue
    @Environment(\.scenePhase) private var scenePhase
    @State var wordSelection: TokenSelection?
    @State var grammarTermSelection: GrammarTermSelection?
    @State var grammarAnalysis: GrammarAnalysisRequest?
    @State var grammarAICache: [UUID: AIGrammarAnalysis] = [:]
    @State var expandedCoachMessageIDs: Set<UUID> = []
    @State var transcriptVisibleMessageIDs: Set<UUID> = []
    @State var composerTranslation = ComposerTranslationModel()
    @State var composerAppleTranslator = AppleTranslator(sourceLanguage: "zh-Hans", targetLanguage: "en", requestTimeout: .seconds(20))
    @State var chineseRecorder: VoiceRecorder
    @State var chineseRecordingTask: Task<Void, Never>?
    @State var isVoiceMode = false
    @State var recorder: VoiceRecorder
    @State var voicePlayer: VoiceMessagePlayer
    @State var showSimulatorInjection = false
    @State var simulatorInjectionText = ""
    @State var appleTranslator = AppleTranslator()
    @State var showsRealtimeConversation = false
    @State private var accessAfterVoice = false
    @State var isNearConversationBottom = true
    @State private var followsComposerResize = true
    @State private var isUserScrollingMessages = false
    @State var unseenIncomingMessageCount = 0
    @State var knownLatestMessageID: UUID?
    @State var showsContactDetails = false
    @State var highlightedMessageID: UUID?
    /// 软件键盘是否占据屏幕底部；键盘占据时输入栏不再补底部安全区。
    @State private var isKeyboardVisible = false
    @FocusState var isTextInputFocused: Bool
    @FocusState var isChineseInputFocused: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) var dismiss
    let deps: ChatDependencies

    public init(
        character: CharacterDTO,
        deps: ChatDependencies,
        startsInRealtimeConversation: Bool = false
    ) {
        _viewModel = State(initialValue: ChatViewModel(character: character, deps: deps))
        _chineseRecorder = State(initialValue: VoiceRecorder(audioSession: deps.audioSession, localeIdentifier: "zh_CN"))
        _recorder = State(initialValue: VoiceRecorder(audioSession: deps.audioSession))
        _voicePlayer = State(initialValue: VoiceMessagePlayer(audioSession: deps.audioSession))
        _showsRealtimeConversation = State(initialValue: startsInRealtimeConversation)
        _autoReadQueue = State(initialValue: ChatAutoReadQueue(speech: deps.speech))
        self.deps = deps
    }

    private func chatPage(bottomInset: CGFloat) -> some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar(bottomInset: isKeyboardVisible ? 0 : bottomInset)
                    .disabled(learningSelected)
            }
            .ignoresSafeArea(.container, edges: .bottom)
    }

    public var body: some View {
        GeometryReader { proxy in
            if let learningPage = deps.learningPage {
                ChatLearningPager(learningSelected: $learningSelected,
                                  enabled: recorder.state == .idle && chineseRecorder.state == .idle && wordSelection == nil && grammarTermSelection == nil && !showsRealtimeConversation) {
                    chatPage(bottomInset: proxy.safeAreaInsets.bottom)
                } learning: {
                    learningPage(viewModel.character, learningSelected)
                }
            } else {
                chatPage(bottomInset: proxy.safeAreaInsets.bottom)
            }
        }
        .onChange(of: learningSelected) { _, selected in
            isTextInputFocused = false; isChineseInputFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if selected {
                voicePlayer.stop()
            } else {
                Task { await deps.learningChat?.refresh(characterID: viewModel.character.id) }
            }
        }
        .task(id: learningSelected) {
            // 分页提交后再清理一次 UIKit 焦点，避免恢复可交互性时还原旧 responder。
            await Task.yield()
            guard !Task.isCancelled else { return }
            isTextInputFocused = false; isChineseInputFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .dsQuickNotice($viewModel.quickNotice)
        .background(Color.dsBackground)
        .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { notification in
            guard notification.object as? UUID == viewModel.character.id else { return }
            Task { await viewModel.refreshMessages() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { notification in
            guard notification.object as? UUID == viewModel.character.id else { return }
            Task { await viewModel.refreshCharacter() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let presence = viewModel.presence(at: context.date)
                    ChatTitleView(
                        title: learningSelected ? "角色学习" : viewModel.character.displayName,
                        subtitle: chatStatus(presence, at: context.date)
                    ) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarBadge(
                                name: viewModel.character.displayName,
                                size: 32,
                                imageName: viewModel.character.card.avatarAssetName,
                                remoteURL: viewModel.character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                                usesPendingPlaceholder: true
                            )
                            Circle()
                                .fill(presenceColor(presence))
                                .frame(width: 9, height: 9)
                                .overlay { Circle().stroke(Color.dsSurface, lineWidth: 1.5) }
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if deps.learningPage != nil {
                        Button { learningSelected.toggle() } label: {
                            Image(systemName: learningSelected ? "bubble.left.and.bubble.right" : "book.closed")
                                .font(.system(size: 18, weight: .medium)).frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(learningSelected ? "返回聊天" : "角色学习")
                        .disabled(recorder.state != .idle || chineseRecorder.state != .idle)
                        .accessibilityIdentifier("chat.learning")
                    }
                    if !learningSelected {
                        Button {
                            isTextInputFocused = false
                            voicePlayer.stop()
                            showsRealtimeConversation = true
                        } label: {
                            Image(systemName: "phone.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("与\(viewModel.character.card.name)实时语音对话")
                        Menu {
                            Button {
                                autoReadEnabled.toggle()
                            } label: {
                                Label(autoReadEnabled ? "关闭自动朗读" : "开启自动朗读", systemImage: autoReadEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            }
                            .accessibilityValue(autoReadEnabled ? "开启" : "关闭")
                            .accessibilityIdentifier("chat.autoRead")
                            Button {
                                isTextInputFocused = false
                                voicePlayer.stop()
                                showsContactDetails = true
                            } label: { Label("聊天设置", systemImage: "person.crop.circle") }
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("更多聊天操作").accessibilityIdentifier("chat.more")
                    }
                }
                .buttonStyle(.plain)
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
                deps.speakLookupWord(word)
            },
            favoriteActions: wordFavoriteActions,
            aiFallback: aiWordFallback)
        .onChange(of: wordSelection) { _, selection in
            if selection != nil { deps.tutorial?.onEvent("word") }
        }
        .grammarTermLookupOverlay(
            selection: $grammarTermSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints)
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
                onAIAnalysis: { analysis in
                    grammarAICache[request.id] = analysis
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsRealtimeConversation, onDismiss: {
            Task { await viewModel.refreshMessages() }
            if accessAfterVoice { accessAfterVoice = false; deps.onShowAccess() }
        }) {
            RealtimeConversationView(
                chat: viewModel,
                deps: deps,
                onSpeechPlayback: {},
                onRequestAccess: { accessAfterVoice = true }
            )
        }
        .sheet(isPresented: $showsContactDetails) {
            NavigationStack {
                ChatContactDetailsView(
                    viewModel: viewModel,
                    deps: deps,
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
        .background {
            ZStack {
                AppleTranslationHost(translator: appleTranslator)
                AppleTranslationHost(translator: composerAppleTranslator)
            }
        }
        .task {
            // 整句翻译优先云端 LLM；离线、额度或供应商失败时回退 Apple 端上翻译。
            viewModel.translationFallback = { [appleTranslator] text in
                return await appleTranslator.translate(text)
            }
            await viewModel.load()
            guard !Task.isCancelled else { return }
            autoReadReady = true
            autoReadQueue.configure(enabled: shouldAutoRead, existingIDs: viewModel.messages.map(\.id))
            #if DEBUG
            // Screenshot-only presentation of seeded reviews in the isolated marketing workspace.
            if ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "chat",
               ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1",
               ProcessInfo.processInfo.environment["UI_TEST_MARKETING_CAPTURE"] == "1",
               ProcessInfo.processInfo.environment["UI_TEST_CAPTURE_COACHES"] == "1" {
                expandedCoachMessageIDs = Set(viewModel.messages.filter {
                    CoachService.decode(fromJSON: $0.coachReviewJSON)?.hasIssues == true
                }.map(\.id))
            }
            if ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "chat",
               ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1",
               ProcessInfo.processInfo.environment["UI_TEST_CAPTURE_DICTIONARY"] == "1",
               let message = viewModel.messages.first(where: { $0.text.contains("cosy") }),
               let token = TokenCache.tokens(for: message.text, cacheKey: message.id.uuidString).first(where: { $0.word == "cosy" }) {
                try? await Task.sleep(for: .seconds(1))
                wordSelection = TokenSelection(contextID: message.id.uuidString, tokenID: token.id, word: "cosy")
            }
            #endif
            knownLatestMessageID = viewModel.messages.last?.id
            markVisibleConversationRead()
            #if DEBUG
            await viewModel.playMarketingCaptureReply()
            #endif
        }
        .onChange(of: viewModel.messages.last?.id) {
            markVisibleConversationRead()
        }
        .onChange(of: showsRealtimeConversation || showsContactDetails || wordSelection != nil || grammarTermSelection != nil || grammarAnalysis != nil || isTextInputFocused) { _, presented in
            deps.tutorial?.onEvent(presented ? "presented" : "dismissed")
        }
        .onChange(of: viewModel.messages.contains(where: { $0.role == .assistant })) { _, hasBubble in
            deps.tutorial?.onEvent(hasBubble ? "hasBubble" : "noBubble")
        }
        .onChange(of: autoReadSnapshot) { previous, current in
            autoReadQueue.synchronize(from: previous, to: current)
        }
        .onDisappear {
            autoReadReady = false
            autoReadQueue.configure(enabled: false, existingIDs: viewModel.messages.map(\.id))
            appleTranslator.cancelAll()
            isChineseInputFocused = false
            composerTranslation.cancel()
            composerAppleTranslator.cancelAll()
            chineseRecordingTask?.cancel()
            Task { await chineseRecorder.cancelRecording() }
            markVisibleConversationRead()
        }
        .dsTabBarHidden()
    }

    private var autoReadSnapshot: ChatAutoReadQueue.Snapshot {
        .init(enabled: shouldAutoRead, items: viewModel.messages.sorted {
            $0.orderIndex < $1.orderIndex
        }.compactMap { message in
            guard message.role == .user || message.role == .assistant,
                  message.kind == .text else { return nil }
            return .init(id: message.id, request: viewModel.speechRequest(for: message))
        })
    }

    private var shouldAutoRead: Bool {
        let recording: Bool
        switch recorder.state {
        case .recording, .transcribing: recording = true
        default: recording = false
        }
        return autoReadReady && autoReadEnabled && !learningSelected && scenePhase == .active
            && !showsRealtimeConversation && !showsContactDetails && !recording
            && wordSelection == nil && grammarTermSelection == nil && grammarAnalysis == nil
            && voicePlayer.playingFileName == nil
    }

    private func markVisibleConversationRead() {
        Task {
            await viewModel.markConversationRead(at: viewModel.messages.last?.createdAt ?? .now)
        }
    }

    private func chatStatus(_ presence: NPCPresenceSnapshot, at date: Date) -> String {
        ChatHeaderStatus.text(
            presence: presence,
            at: date,
            regionName: deps.regionName(viewModel.character.card.regionID),
            isStreaming: viewModel.isStreaming
        )
    }

    private func presenceColor(_ presence: NPCPresenceSnapshot) -> Color {
        switch presence.state {
        case .online: Color.dsSuccess
        case .recentlyActive: Color.dsSunset
        case .offline: Color.secondary.opacity(0.55)
        }
    }

    private var messageList: some View {
        GeometryReader { viewport in
            messageList(viewportHeight: viewport.size.height)
        }
    }

    private func messageList(viewportHeight: CGFloat) -> some View {
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
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier(message.id == viewModel.messages.last?.id ? "chat.message.latest" : "chat.message.\(message.id)")
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
                            if error.contains("额度") || error.contains("登录") || error.contains("语音体验") {
                                Button("查看用量与权益", action: deps.onShowAccess)
                                    .font(.footnote.weight(.semibold))
                            }
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.dsDanger)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.top, 8)
                        }
                        if viewModel.canRetryUnansweredReply {
                            Button("重试回复", systemImage: "arrow.clockwise") {
                                viewModel.retryUnansweredReply()
                            }
                            .font(.footnote.weight(.semibold))
                            .padding(.vertical, 8)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("conversation-bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    // Fill short/empty conversations so blank taps land inside scroll content.
                    .frame(minHeight: max(0, viewportHeight), alignment: .bottom)
                    .background {
                        keyboardDismissBackdrop
                    }
                }
                .accessibilityIdentifier("chat.messages")
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
                    if isUserScrollingMessages { followsComposerResize = isNearBottom }
                    if isNearBottom {
                        unseenIncomingMessageCount = 0
                    }
                }
                // Follow the actual laid-out viewport, not the mode toggle before layout.
                // Keep this intent separate from proximity: shrinking the viewport can
                // temporarily move the bottom outside the visible rect.
                .onScrollGeometryChange(for: CGSize.self) { geometry in
                    CGSize(width: geometry.containerSize.width,
                           height: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom)
                } action: { old, new in
                    guard old != new, followsComposerResize else { return }
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
                .onScrollPhaseChange { _, phase in
                    isUserScrollingMessages = phase == .tracking || phase == .interacting || phase == .decelerating
                    if isUserScrollingMessages { followsComposerResize = isNearConversationBottom }
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
                        followsComposerResize = true
                        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                    } else if last.role == .assistant {
                        unseenIncomingMessageCount += 1
                    }
                }
                .onChange(of: isTextInputFocused || isChineseInputFocused) {
                    viewModel.composerFocusChanged(isTextInputFocused || isChineseInputFocused)
                    guard isTextInputFocused || isChineseInputFocused else { return }
                    followsComposerResize = true
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: composerTranslation.isOpen) {
                    guard followsComposerResize else { return }
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: highlightedMessageID) { _, messageID in
                    guard let messageID else { return }
                    followsComposerResize = false
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
                        followsComposerResize = true
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

    /// Background-only hit target: word taps and bubble menus remain in the foreground.
    private var keyboardDismissBackdrop: some View {
        Color.dsBackground
            .contentShape(Rectangle())
            .onTapGesture {
                isTextInputFocused = false
                isChineseInputFocused = false
            }
            .accessibilityHidden(true)
    }

    private var messageListKeyboardDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isTextInputFocused || isChineseInputFocused, value.translation.height > 0 else { return }
                isTextInputFocused = false
                isChineseInputFocused = false
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
                .environment(\.tutorialBubbleFocused, deps.tutorial?.focus == "chat.bubble"
                    && message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id)
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
            UserAvatar(size: 30)
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
            deps.tutorial?.onEvent("manualPlayback")
            let stopped = autoReadQueue.interrupt()
            Task { await stopped?.value; await viewModel.speak(message: message) }
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
