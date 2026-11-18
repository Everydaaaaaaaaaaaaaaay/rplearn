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
    @Binding var bubbleMenuMessage: MessageDTO?
    @FocusState.Binding var composerFocus: ChatView.ComposerFocus?
    let showsChatFunctions: Bool
    let dismissChatInput: () -> Void
    @State private var messageScrollPosition = ScrollPosition()
    @State private var isNearConversationBottom = true
    @State private var followsConversationBottom = true
    @State private var unseenIncomingMessageCount = 0
    @State private var knownLatestMessageID: UUID?
    @State var transcriptVisibleMessageIDs: Set<UUID> = []
    @State var bubbleMenuFrame: CGRect = .zero
    @State var bubbleMenuSize = CGSize(width: 224, height: 200)
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
                            Button("查看会员订阅", action: deps.onShowAccess)
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
                    // Include the trailing gap in the lazy stack’s bottom edge.
                    Color.clear.frame(height: 10).accessibilityHidden(true)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background { keyboardDismissBackdrop }
                .anchorPreference(key: ChatTranscriptBoundsKey.self, value: .bounds) { $0 }
            }
            .accessibilityIdentifier("chat.messages")
            .scrollPosition($messageScrollPosition)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .defaultScrollAnchor(followsConversationBottom ? .bottom : .top, for: .sizeChanges)
            .scrollBounceBehavior(.always)
            // The bottom anchor follows dock resizing in the same layout pass.
            // Blank taps and downward drags share one dismissal transition.
            .scrollDismissesKeyboard(.never)
            .simultaneousGesture(messageListKeyboardDismissGesture)
            .background(Color.dsBackground)
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
            .onChange(of: viewModel.streamingText) {
                guard isNearConversationBottom else { return }
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
                if isNearConversationBottom || last.role == .user {
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

            if !isNearConversationBottom {
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
        .overlay { bubbleActionsOverlay }
    }

    /// Background-only hit target: word taps and bubble menus remain in the foreground.
    private var keyboardDismissBackdrop: some View {
        Color.dsBackground
            .contentShape(Rectangle())
            .onTapGesture { dismissChatInput() }
            .accessibilityHidden(true)
    }

    private var messageListKeyboardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard bubbleMenuMessage == nil,
                      showsChatFunctions || isTextInputFocused || isChineseInputFocused,
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
                    onMenuRequest: { presentBubbleMenu(message, frame: $0) },
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
            isReplying: viewModel.isStreaming,
            hasBeenRead: viewModel.hasRead(viewModel.messages[index].id)
        ) {
            Label(receipt.label, systemImage: receipt.systemImage)
                .font(.caption2.weight(.medium))
                .foregroundStyle(receipt == .delivered ? Color.secondary : Color.dsSkyDeep)
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
                bubbleMenuMessage = nil
                presentGrammarAnalysis(for: message)
            } label: {
                Label("语法解析", systemImage: "text.book.closed")
            }
        }
        Button {
            bubbleMenuMessage = nil
            UIPasteboard.general.string = message.text
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        Button {
            bubbleMenuMessage = nil
            Task { await viewModel.translate(message: message) }
        } label: {
            Label("翻译", systemImage: "character.book.closed.zh")
        }
        Button {
            bubbleMenuMessage = nil
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
                bubbleMenuMessage = nil
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
