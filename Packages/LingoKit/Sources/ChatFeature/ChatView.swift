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

public extension Notification.Name {
    /// 用户在本次聊天中实际播放过 TTS，并已退出聊天页。
    static let chatDidExitAfterSpeechPlayback = Notification.Name(
        "LingoTripChatDidExitAfterSpeechPlayback"
    )
}

/// 聊天页：消息列表 + 输入栏（文本/语音）+ 流式回复 + 点词查词。
public struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var wordSelection: TokenSelection?
    @State private var grammarAnalysis: GrammarAnalysisRequest?
    @State private var grammarAICache: [UUID: AIGrammarAnalysis] = [:]
    @State private var expandedCoachMessageIDs: Set<UUID> = []
    @State private var transcriptVisibleMessageIDs: Set<UUID> = []
    @State private var isVoiceMode = false
    @State private var recorder: VoiceRecorder
    @State private var voicePlayer: VoiceMessagePlayer
    @State private var showSimulatorInjection = false
    @State private var simulatorInjectionText = ""
    @State private var appleTranslator = AppleTranslator()
    @State private var quizCelebrationTrigger = 0
    @State private var shakingMessageID: UUID?
    @State private var shakePhase = false
    @State private var isMascotPromptDismissed = false
    @State private var didBeginSpeechPlayback = false
    @State private var showsRealtimeConversation = false
    @State private var isNearConversationBottom = true
    @State private var unseenIncomingMessageCount = 0
    @State private var knownLatestMessageID: UUID?
    @FocusState private var isTextInputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let deps: ChatDependencies

    public init(character: CharacterDTO, deps: ChatDependencies) {
        _viewModel = State(initialValue: ChatViewModel(character: character, deps: deps))
        _recorder = State(initialValue: VoiceRecorder(audioSession: deps.audioSession))
        _voicePlayer = State(initialValue: VoiceMessagePlayer(audioSession: deps.audioSession))
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarBadge(name: viewModel.character.card.name, size: 32)
                        Circle()
                            .fill(viewModel.isStreaming ? Color.dsSunset : Color.dsSuccess)
                            .frame(width: 9, height: 9)
                            .overlay { Circle().stroke(Color.dsSurface, lineWidth: 1.5) }
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewModel.character.card.name)
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
            #if DEBUG && targetEnvironment(simulator)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.debugInjectQuiz() }
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("调试：注入小测")
            }
            #endif
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
            aiFallback: aiWordFallback
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
                onSpeechPlayback: { didBeginSpeechPlayback = true }
            )
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
        .onReceive(NotificationCenter.default.publisher(for: .speechPlaybackDidBegin)) { _ in
            didBeginSpeechPlayback = true
        }
        .onDisappear {
            markVisibleConversationRead()
            guard didBeginSpeechPlayback else { return }
            didBeginSpeechPlayback = false
            NotificationCenter.default.post(name: .chatDidExitAfterSpeechPlayback, object: nil)
        }
        .dsTabBarHidden()
    }

    private func markVisibleConversationRead() {
        guard let conversation = viewModel.conversation else { return }
        ConversationReadState.markRead(
            conversationID: conversation.id,
            at: viewModel.messages.last?.createdAt ?? .now
        )
    }

    private var chatStatus: String {
        if viewModel.isStreaming {
            return "正在输入…"
        }
        if viewModel.conversation?.isEncounterSession == true {
            return "在线 · 偶遇中 · \(viewModel.learnerDifficulty.displayName)"
        }
        return "在线 · \(chatCityDisplayName) · \(viewModel.learnerDifficulty.displayName)"
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
                    }
                ) {
                    tappableText(message, textColor: nil)
                }
                .contextMenu { bubbleMenu(message) }
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
            AvatarBadge(name: viewModel.character.card.name, size: 30)
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
    private func bubbleMenu(_ message: MessageDTO) -> some View {
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
        Divider()
        Button {} label: {
            Label(
                ChatTimelinePolicy.exactTimeText(for: message.createdAt),
                systemImage: "clock"
            )
        }
        .disabled(true)
    }

    // MARK: - 教练纠错

    @ViewBuilder
    private func userMessageBubble(
        _ message: MessageDTO,
        groupPosition: MessageBubbleGroupPosition
    ) -> some View {
        if CoachService.decode(fromJSON: message.coachReviewJSON)?.hasIssues == true {
            MessageBubble(
                side: .outgoing,
                groupPosition: groupPosition,
                leadingAccessory: { coachButton(message) }
            ) {
                tappableText(message, textColor: .white)
            }
            .contextMenu { bubbleMenu(message) }
        } else {
            MessageBubble(side: .outgoing, groupPosition: groupPosition) {
                tappableText(message, textColor: .white)
            }
            .contextMenu { bubbleMenu(message) }
        }
    }

    /// 紧贴用户气泡中线的纠错入口；可见尺寸克制，触控区域保持 44pt。
    private func coachButton(_ message: MessageDTO) -> some View {
        let isExpanded = expandedCoachMessageIDs.contains(message.id)
        return Button {
            Haptics.selection()
            withAnimation(DSAnimation.snappy) {
                if isExpanded {
                    expandedCoachMessageIDs.remove(message.id)
                } else {
                    expandedCoachMessageIDs.insert(message.id)
                }
            }
        } label: {
            BrandMascotView(pose: .coach, size: 28, showsShadow: false)
                .scaleEffect(isExpanded ? 1.06 : 1)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(isExpanded ? Color.dsBrandCream : Color.dsSurface)
                        .shadow(color: Color.dsCoach.opacity(0.18), radius: 4, y: 2)
                }
                .overlay {
                    Circle()
                        .stroke(Color.dsCoach.opacity(isExpanded ? 0.55 : 0.3), lineWidth: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .animation(DSAnimation.snappy, value: isExpanded)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(isExpanded ? "收起改进建议" : "查看改进建议")
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }

    /// 展开的纠错卡：错误片段 → 改法 + 中文讲解。
    @ViewBuilder
    private func coachCard(_ message: MessageDTO) -> some View {
        if expandedCoachMessageIDs.contains(message.id),
           let review = CoachService.decode(fromJSON: message.coachReviewJSON),
           review.hasIssues {
            CalloutCard(kind: .coach) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(issue.quote)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(issue.correction)
                                    .foregroundStyle(Color.dsSuccess)
                            }
                            .font(.subheadline)
                            Text(issue.explanationZh)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - 口语点评

    /// 语音消息的口语点评卡：自然度星级 + 中文点评 + 更自然说法建议。
    @ViewBuilder
    private func speechReviewCard(_ message: MessageDTO) -> some View {
        if message.kind == .voice, let review = CoachService.decodeSpeech(fromJSON: message.speechReviewJSON) {
            CalloutCard(kind: .speech, trailing: {
                    Text(String(repeating: "★", count: review.clampedRating)
                        + String(repeating: "☆", count: 5 - review.clampedRating))
                        .font(.caption)
                        .foregroundStyle(Color.dsSpeech)
                }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(review.commentZh)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    ForEach(Array(review.tips.enumerated()), id: \.offset) { _, tip in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tip.quote)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                Text(tip.better).foregroundStyle(Color.dsSpeech)
                            }
                            .font(.subheadline)
                            Text(tip.explanationZh)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 语境出题

    /// 角色回复附带的小测：选项气泡 + 作答反馈 + 「不再弹题」。
    @ViewBuilder
    private func quizCard(_ message: MessageDTO) -> some View {
        if let quiz = QuizService.decode(fromJSON: message.quizJSON) {
            let chosen = message.quizChosenIndex
            CalloutCard(kind: .quiz) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(quiz.question)
                        .font(.subheadline.weight(.medium))
                    VStack(spacing: 6) {
                        ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                            quizOption(message: message, quiz: quiz, index: index, option: option, chosen: chosen)
                        }
                    }
                    if let chosen {
                        let correct = chosen == quiz.answer
                        VStack(alignment: .leading, spacing: 4) {
                            Text(correct
                                ? "🎉 答对了！+\(QuizService.correctReward) 金币"
                                : "正确答案：\(QuizService.optionLabel(quiz.answer)). \(quiz.options[quiz.answer])")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(correct ? Color.dsSuccess : Color.dsWarning)
                            Text(quiz.explanationZh)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                    Button {
                        Task { await viewModel.setQuizOptOut(!viewModel.conversationOptedOut) }
                    } label: {
                        Label(
                            "不再弹题",
                            systemImage: viewModel.conversationOptedOut ? "checkmark.square.fill" : "square"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.snappy, value: chosen)
            .offset(x: shakingMessageID == message.id ? (shakePhase ? 7 : -7) : 0)
            .celebration(chosen == quiz.answer, tint: .dsSuccess, trigger: quizCelebrationTrigger)
        }
    }

    private func quizOption(
        message: MessageDTO,
        quiz: Quiz,
        index: Int,
        option: String,
        chosen: Int?
    ) -> some View {
        let isAnswered = chosen != nil
        let isCorrect = index == quiz.answer
        let isChosen = index == chosen
        return Button {
            Task {
                await viewModel.answerQuiz(message: message, chosenIndex: index)
                if index == quiz.answer {
                    quizCelebrationTrigger += 1
                } else if !reduceMotion {
                    shakingMessageID = message.id
                    withAnimation(.linear(duration: 0.07).repeatCount(5, autoreverses: true)) {
                        shakePhase.toggle()
                    }
                    try? await Task.sleep(for: .milliseconds(420))
                    shakingMessageID = nil
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(QuizService.optionLabel(index))
                    .font(.subheadline.weight(.bold))
                    .monospaced()
                Text(option)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isAnswered, isCorrect {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if isChosen {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(quizOptionColor(isAnswered: isAnswered, isCorrect: isCorrect, isChosen: isChosen),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isAnswered)
    }

    private func quizOptionColor(isAnswered: Bool, isCorrect: Bool, isChosen: Bool) -> Color {
        if isAnswered, isCorrect { return .dsSuccess.opacity(0.22) }
        if isChosen { return .dsDanger.opacity(0.16) }
        return .dsSurface
    }

    @ViewBuilder
    private func translationFootnote(_ message: MessageDTO, alignment: HorizontalAlignment) -> some View {
        if viewModel.translatingMessageIDs.contains(message.id) {
            ProgressView()
                .controlSize(.small)
        } else if let translation = message.translationZh {
            Text(translation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
                .padding(alignment == .trailing ? .leading : .trailing, 48)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func tappableText(_ message: MessageDTO, textColor: Color?) -> some View {
        if message.kind == .voice {
            VoiceBubbleContent(
                message: .init(
                    duration: message.audioDuration ?? 0,
                    transcript: message.text,
                    hasAudio: message.audioFileName != nil || message.audioAssetID != nil
                ),
                isPlaying: voicePlayer.playingFileName != nil && voicePlayer.playingFileName == message.audioFileName,
                showTranscript: transcriptVisibleMessageIDs.contains(message.id),
                textColor: textColor,
                onTogglePlay: {
                    Task {
                        guard let fileName = await viewModel.localVoiceFile(for: message) else {
                            return
                        }
                        await voicePlayer.togglePlay(fileName: fileName)
                    }
                }
            )
        } else {
            let displayText = message.role == .assistant
                ? RoleplayReplyFormatter.streamingPreview(from: message.text)
                : message.text
            let tokens = TokenCache.tokens(
                for: displayText,
                cacheKey: message.id.uuidString
            )
            TappableText(
                tokens: tokens,
                contextID: message.id.uuidString,
                keywords: message.role == .assistant
                    ? KeywordAnnotator.decodeWords(fromJSON: message.keywordRangesJSON)
                    : [],
                textColor: textColor,
                selection: wordSelection,
                onSelect: selectWord
            )
        }
    }

    private func selectWord(_ selection: TokenSelection) {
        isTextInputFocused = false
        wordSelection = selection
    }

    private func presentGrammarAnalysis(for message: MessageDTO) {
        let sentence = RoleplayReplyFormatter.streamingPreview(from: message.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        let tokens = TokenCache.tokens(
            for: sentence,
            cacheKey: "grammar-\(message.id.uuidString)"
        )
        let localItems: [LocalGrammarAnalysisItem] = deps.grammarPoints.matches(in: tokens).compactMap { match -> LocalGrammarAnalysisItem? in
            guard let point = deps.grammarPoints.point(id: match.pointID) else { return nil }
            let matchedText = match.spanTokenIDs
                .compactMap { tokens.indices.contains($0) ? tokens[$0].display : nil }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LocalGrammarAnalysisItem(
                id: "\(point.id)-\(match.spanTokenIDs.map { String($0) }.joined(separator: "-"))",
                point: point,
                matchedText: matchedText
            )
        }
        isTextInputFocused = false
        Haptics.selection()
        grammarAnalysis = GrammarAnalysisRequest(
            id: message.id,
            sentence: sentence,
            learnerLevel: viewModel.learnerDifficulty.displayName,
            localItems: localItems
        )
    }

    /// 词典未收录时的 AI 简释兜底（fast 档）。
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

    private var inputBar: some View {
        VStack(spacing: 0) {
            if shouldShowMascotPrompt {
                mascotConversationPrompt
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) {
                        isTextInputFocused = false
                        isVoiceMode.toggle()
                        recorder.resetFailure()
                    }
                } label: {
                    Image(systemName: isVoiceMode ? "keyboard" : "mic")
                        .font(.system(size: 22))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(isVoiceMode ? "切换到键盘" : "切换到语音")

                if isVoiceMode {
                    VoiceInputBar(recorder: recorder) { capture in
                        Task { await viewModel.sendVoice(capture: capture) }
                    }
                    #if targetEnvironment(simulator)
                    // 模拟器兜底：麦克风/识别不可用时注入文本验证全流程
                    Button {
                        showSimulatorInjection = true
                    } label: {
                        Image(systemName: "hammer")
                    }
                    .alert("模拟语音注入", isPresented: $showSimulatorInjection) {
                        TextField("转写文本", text: $simulatorInjectionText)
                        Button("发送") {
                            let text = simulatorInjectionText
                            simulatorInjectionText = ""
                            guard !text.isEmpty else { return }
                            Task {
                                await viewModel.sendVoice(
                                    capture: .init(fileName: nil, duration: 3, transcript: text)
                                )
                            }
                        }
                        Button("取消", role: .cancel) {}
                    }
                    #endif
                } else {
                    TextField(
                        viewModel.isStreaming
                            ? "\(viewModel.character.card.name)正在输入，你也可以继续说…"
                            : "用英语说点什么…",
                        text: $viewModel.draft,
                        axis: .vertical
                    )
                        .lineLimit(1...4)
                        .focused($isTextInputFocused)
                        .submitLabel(.send)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Color.dsBubbleIncoming,
                            in: RoundedRectangle(
                                cornerRadius: DSRadius.bubble,
                                style: .continuous
                            )
                        )
                        .onSubmit {
                            Task { await viewModel.sendDraft() }
                        }

                    Button {
                        Task { await viewModel.sendDraft() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.dsSky)
                    }
                    .disabled(
                        viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityLabel("发送消息")
                    .accessibilityHint("发送输入框中的英文消息；对方正在输入时也可以继续发送")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .dsMaterial(.ultraThinMaterial, in: Rectangle())
    }

    private var shouldShowMascotPrompt: Bool {
        !isVoiceMode
            && !isMascotPromptDismissed
            && viewModel.draft.isEmpty
            && !viewModel.isStreaming
            && viewModel.messages.count <= 3
    }

    private var mascotConversationPrompt: some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            BrandMascotView(pose: .coach, size: 30, showsShadow: false)
                .padding(.top, 1)

            Button {
                withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                    viewModel.draft = conversationStarter
                    isMascotPromptDismissed = true
                    isTextInputFocused = true
                }
            } label: {
                Text("咕咕：试试 “\(conversationStarter)”")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)

            Button {
                withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                    isMascotPromptDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭咕咕建议")
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var conversationStarter: String {
        "What do you love most about \(chatCityEnglishName)?"
    }

    private var chatCityDisplayName: String {
        let regions = ["london": "伦敦", "melbourne": "墨尔本", "newyork": "纽约"]
        return regions[viewModel.character.card.regionID] ?? viewModel.character.card.regionID
    }

    private var chatCityEnglishName: String {
        let regions = [
            "london": "London",
            "melbourne": "Melbourne",
            "newyork": "New York",
        ]
        return regions[viewModel.character.card.regionID]
            ?? viewModel.character.card.regionID.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
