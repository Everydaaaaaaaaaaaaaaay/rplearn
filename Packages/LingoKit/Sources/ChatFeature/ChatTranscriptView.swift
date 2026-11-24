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

private struct ChatTranscriptBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private let chatMessageInset: CGFloat = 12

/// 记住已经播过弹出动画的消息，懒加载行滚回视野时不再重播。只在主线程读写，不触发界面刷新。
@MainActor
private final class ChatArrivalLedger {
    private var ids: Set<UUID> = []

    func contains(_ id: UUID) -> Bool { ids.contains(id) }
    func insert(_ id: UUID) { ids.insert(id) }
}

/// Owns conversation scrolling and bubble interaction independently of draft editing.
struct ChatTranscriptView: View {
    let viewModel: ChatViewModel
    let deps: ChatDependencies
    let voicePlayer: VoiceMessagePlayer
    let autoReadQueue: ChatAutoReadQueue
    @Binding var wordSelection: TokenSelection?
    @Binding var grammarTermSelection: GrammarTermSelection?
    @Binding var grammarAnalysis: GrammarAnalysisRequest?
    @Binding var expandedCoachMessageIDs: Set<UUID>
    @Binding var highlightedMessageID: UUID?
    @FocusState.Binding var composerFocus: ChatView.ComposerFocus?
    let showsChatFunctions: Bool
    let dismissChatInput: () -> Void
    @State private var messageScrollPosition = ScrollPosition()
    @State private var isNearConversationBottom = true
    /// 最新一条消息在视野里。懒加载列表对未渲染行用估算高度，大字号下内容总高常常估大，
    /// 只看几何会在已经停在底部时误判“不在底部”，所以两者满足其一就算到底。
    @State private var isLatestMessageVisible = false
    private var isAtLatest: Bool { isNearConversationBottom || isLatestMessageVisible }
    @State private var followsConversationBottom = true
    @State private var unseenIncomingMessageCount = 0
    @State private var knownLatestMessageID: UUID?
    /// 打开会话之后才产生的消息会从发送方一侧弹出来；历史消息原样显示。
    @State private var openedAt = Date.now
    @State private var arrivals = ChatArrivalLedger()
    @State var transcriptVisibleMessageIDs: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var isTextInputFocused: Bool {
        get { composerFocus == .english }
        nonmutating set {
            if newValue { composerFocus = .english }
            else if composerFocus == .english { composerFocus = nil }
        }
    }
    var isChineseInputFocused: Bool {
        get { composerFocus == .chinese }
        nonmutating set {
            if newValue { composerFocus = .chinese }
            else if composerFocus == .chinese { composerFocus = nil }
        }
    }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 10).accessibilityHidden(true)
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        if ChatTimelinePolicy.shouldShowTimeMarker(
                            in: viewModel.messages,
                            at: index
                        ) {
                            timeMarker(for: message.createdAt)
                                .padding(.top, index == 0 ? 2 : 12)
                                .padding(.bottom, 6)
                                .padding(.horizontal, chatMessageInset)
                        }
                        messageRow(message, at: index)
                            .puffArrival(
                                isNew: message.createdAt > openedAt && !arrivals.contains(message.id),
                                anchor: message.role == .user ? .bottomTrailing : .bottomLeading,
                                onArrive: { arrivals.insert(message.id) }
                            )
                            .id(message.id)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(message.id == viewModel.messages.last?.id ? "chat.message.latest" : "chat.message.\(message.id)")
                            .padding(.top, messageTopSpacing(at: index))
                            .background(
                                highlightedMessageID == message.id
                                    ? PuffCandy.sky.wash
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: Puff.Radius.medium, style: .continuous)
                            )
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.2),
                                value: highlightedMessageID
                            )
                            .padding(.horizontal, chatMessageInset)
                        #if DEBUG
                        if deps.showsTimelineEventPreview, let event = ChatTimelineEventPreview.event(after: message) {
                            event
                        }
                        #endif
                        if let event = viewModel.timelineEvents[message.id] {
                            ChatTimelineEvent(event, name: viewModel.character.card.name)
                        }
                        if let appointments = viewModel.appointmentTimeline[message.id] {
                            ForEach(appointments) { row in
                                ChatTimelineEvent(row.event, name: viewModel.character.card.name,
                                                  action: deps.onOpenAppointment.map { open in { open(row.appointmentID) } })
                            }
                        }
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
                        .puffArrival(isNew: true, anchor: .bottomLeading)
                        .id("streaming")
                        .padding(.top, streamingTopSpacing)
                        .padding(.horizontal, chatMessageInset)
                        .transition(.opacity)
                    }
                    if let error = viewModel.errorMessage {
                        if error.contains("额度") || error.contains("登录") || error.contains("语音体验") {
                            Button("查看会员订阅", action: deps.onShowAccess)
                                .font(.puff(.footnote, Puff.Weight.emphasis))
                                .foregroundStyle(PuffCandy.sky.deep)
                                .padding(.horizontal, chatMessageInset)
                        }
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.puff(.footnote, Puff.Weight.label))
                            .foregroundStyle(Puff.Palette.cherry)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PuffCandy.bubblegum.wash, in: Capsule())
                            .padding(.top, 8)
                            .padding(.horizontal, chatMessageInset)
                    }
                    if viewModel.canRetryUnansweredReply {
                        Button("重试回复", systemImage: "arrow.clockwise") {
                            viewModel.retryUnansweredReply()
                        }
                        .font(.puff(.footnote, Puff.Weight.emphasis))
                        .foregroundStyle(PuffCandy.sky.deep)
                        .padding(.vertical, 8)
                        .padding(.horizontal, chatMessageInset)
                    }
                    // Include the trailing gap in the lazy stack’s bottom edge.
                    Color.clear.frame(height: 10).accessibilityHidden(true)
                }
                .scrollTargetLayout()
                // Keep the gutter inside the lazy rows so a scroll anchor adjustment
                // cannot move them between the padded and unpadded content origins.
                .frame(maxWidth: .infinity)
                .background { keyboardDismissBackdrop }
                .anchorPreference(key: ChatTranscriptBoundsKey.self, value: .bounds) { $0 }
            }
            // 消息就绪时重建滚动视图，让“初始停在底部”作用于真实内容；
            // 否则初始锚点会耗在空列表上，消息到达后先停错位置再跳到底部。
            .id(viewModel.hasLoadedMessages)
            // 顶栏下沿柔和淡出：聊天页外层分页会裁切内容，消息到不了顶栏下面，不淡出就是一刀切的硬边。
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                    Color.black
                }
            }
            .accessibilityIdentifier("chat.messages")
            // 本地消息就绪前保持透明，就绪后轻轻淡入，不出现“空白 → 整屏消息跳出”。
            .opacity(viewModel.hasLoadedMessages ? 1 : 0)
            .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18), value: viewModel.hasLoadedMessages)
            .overlay(alignment: .top) {
                if let notice = viewModel.syncNotice {
                    Label(notice, systemImage: "icloud.slash")
                        .font(.puff(.caption, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.inkSoft)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Puff.Palette.card, in: Capsule())
                        .overlay { Capsule().strokeBorder(Puff.Palette.line, lineWidth: 1) }
                        .padding(.top, 8)
                        .transition(.puffDrop)
                        .allowsHitTesting(false)
                }
            }
            .animation(Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion), value: viewModel.syncNotice)
            .modifier(ChatTimelineUpdates(viewModel: viewModel))
            .scrollPosition($messageScrollPosition)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .defaultScrollAnchor(followsConversationBottom ? .bottom : .top, for: .sizeChanges)
            .scrollBounceBehavior(.always)
            // The bottom anchor follows dock resizing in the same layout pass.
            // Blank taps and downward drags share one dismissal transition.
            .scrollDismissesKeyboard(.never)
            .simultaneousGesture(messageListKeyboardDismissGesture)
            .overlayPreferenceValue(ChatTranscriptBoundsKey.self, alignment: .top) { bounds in
                if composerFocus != nil || showsChatFunctions {
                    // A bottom-aligned short transcript leaves blank space outside its content.
                    GeometryReader { proxy in
                        let blankHeight = bounds.map { max(0, min(proxy[$0].minY, proxy.size.height)) } ?? proxy.size.height
                        if blankHeight > 0 {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: dismissChatInput)
                                .frame(height: blankHeight)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                guard newPhase == .idle,
                      oldPhase == .interacting || oldPhase == .decelerating else { return }
                followsConversationBottom = context.geometry.contentSize.height - context.geometry.visibleRect.maxY < 96
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY < 96
            } action: { _, isNearBottom in
                isNearConversationBottom = isNearBottom
                if isNearBottom {
                    unseenIncomingMessageCount = 0
                }
            }
            .onScrollTargetVisibilityChange(idType: UUID.self, threshold: 0.6) { visibleIDs in
                let visible = viewModel.messages.last.map { visibleIDs.contains($0.id) } ?? false
                guard visible != isLatestMessageVisible else { return }
                isLatestMessageVisible = visible
                if visible { unseenIncomingMessageCount = 0 }
            }
            .onChange(of: viewModel.streamingText) {
                guard isAtLatest else { return }
                withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                    messageScrollPosition.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.id, initial: true) {
                guard let last = viewModel.messages.last else {
                    knownLatestMessageID = nil
                    return
                }
                guard knownLatestMessageID != last.id else { return }
                let isInitialHistory = knownLatestMessageID == nil
                knownLatestMessageID = last.id
                if isInitialHistory {
                    followsConversationBottom = true
                    messageScrollPosition.scrollTo(edge: .bottom)
                    return
                }
                if isAtLatest || last.role == .user {
                    followsConversationBottom = true
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        messageScrollPosition.scrollTo(edge: .bottom)
                    }
                } else if last.role == .assistant {
                    unseenIncomingMessageCount += 1
                }
            }
            .onChange(of: composerFocus != nil) { _, isFocused in
                viewModel.composerFocusChanged(isFocused)
            }
            .onChange(of: highlightedMessageID) { _, messageID in
                guard let messageID else { return }
                followsConversationBottom = false
                withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                    messageScrollPosition.scrollTo(id: messageID, anchor: .center)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard highlightedMessageID == messageID else { return }
                    highlightedMessageID = nil
                }
            }

            if viewModel.hasLoadedMessages && !isAtLatest {
                Button {
                    followsConversationBottom = true
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        messageScrollPosition.scrollTo(edge: .bottom)
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
                    .font(.puff(.footnote, Puff.Weight.emphasis))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                }
                .buttonStyle(PuffCardButtonStyle(radius: 19, face: PuffCandy.sky.base, border: .clear, lip: PuffCandy.sky.lip, lipHeight: 3))
                .transition(.puffPop)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .accessibilityHint("跳转到会话中的最新消息")
            }
        }
    }

    /// Background-only hit target: word taps and bubble long-presses remain in the foreground.
    private var keyboardDismissBackdrop: some View {
        // 透明：露出聊天壁纸，只负责接住空白处的点按。
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { dismissChatInput() }
            .accessibilityHidden(true)
    }

    private var messageListKeyboardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard showsChatFunctions || isTextInputFocused || isChineseInputFocused,
                      value.translation.height > 20,
                      value.translation.height > abs(value.translation.width) else { return }
                dismissChatInput()
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
                    .font(.puff(.footnote, Puff.Weight.label))
                    .foregroundStyle(PuffCandy.grape.deep)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PuffCandy.grape.wash, in: Capsule())
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
            .font(.puff(.caption2, Puff.Weight.emphasis))
            .foregroundStyle(Puff.Palette.inkFaint)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Puff.Palette.card, in: Capsule())
            .overlay { Capsule().strokeBorder(Puff.Palette.line, lineWidth: 1) }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("会话时间，\(ChatTimelinePolicy.exactTimeText(for: date))")
    }

    @ViewBuilder
    private func incomingAvatar(isVisible: Bool) -> some View {
        if isVisible {
            PuffAvatar(
                name: viewModel.character.displayName,
                size: 30,
                imageName: viewModel.character.card.avatarAssetName,
                remoteURL: viewModel.character.card.avatarRemoteURL.flatMap(URL.init(string:))
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
            isReplying: viewModel.isStreaming,
            hasBeenRead: viewModel.hasRead(viewModel.messages[index].id)
        ) {
            Label(receipt.label, systemImage: receipt.systemImage)
                .font(.caption2.weight(.medium))
                .foregroundStyle(receipt == .delivered ? Puff.Palette.inkFaint : PuffCandy.sky.deep)
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
            if message.kind == .voice {
                toggleVoicePlayback(message)
            } else {
                voicePlayer.stop()
                let stopped = autoReadQueue.interrupt()
                Task { await stopped?.value; await viewModel.speak(message: message) }
            }
        } label: {
            Label(message.kind == .voice ? "播放原音" : "播放", systemImage: "speaker.wave.2")
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

private struct ChatTimelineUpdates: ViewModifier {
    let viewModel: ChatViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .chatTimelineDidChange)) { event in
                guard event.object as? UUID == viewModel.conversation?.id else { return }
                Task { await viewModel.reloadMessages() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatAppointmentsDidChange)) { event in
                guard event.object as? UUID == viewModel.character.id else { return }
                Task { await viewModel.refreshAppointments() }
            }
    }
}
