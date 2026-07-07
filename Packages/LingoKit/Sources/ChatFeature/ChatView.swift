import CoreKit
import DesignSystem
import DictKit
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// 聊天页：消息列表 + 输入栏（文本/语音）+ 流式回复 + 点词查词。
public struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var wordSelection: TokenSelection?
    @State private var expandedCoachMessageIDs: Set<UUID> = []
    @State private var transcriptVisibleMessageIDs: Set<UUID> = []
    @State private var isVoiceMode = false
    @State private var recorder: VoiceRecorder
    @State private var voicePlayer: VoiceMessagePlayer
    @State private var showSimulatorInjection = false
    @State private var simulatorInjectionText = ""
    private let deps: ChatDependencies

    public init(character: CharacterDTO, deps: ChatDependencies) {
        _viewModel = State(initialValue: ChatViewModel(character: character, deps: deps))
        _recorder = State(initialValue: VoiceRecorder(audioSession: deps.audioSession))
        _voicePlayer = State(initialValue: VoiceMessagePlayer(audioSession: deps.audioSession))
        self.deps = deps
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .navigationTitle(viewModel.character.card.name)
        .navigationBarTitleDisplayMode(.inline)
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                let speech = deps.speech
                Task { await speech.speak(word, language: "en-US") }
            },
            aiFallback: aiWordFallback
        )
        .task {
            await viewModel.load()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    if let streaming = viewModel.streamingText {
                        MessageBubble(side: .incoming) {
                            if streaming.isEmpty {
                                TypingIndicator()
                            } else {
                                // 流式期间用普通 Text，定稿后换 TappableText（plan.md §3.1）
                                Text(streaming)
                            }
                        }
                        .id("streaming")
                    }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.streamingText) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: MessageDTO) -> some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                MessageBubble(side: .outgoing) {
                    tappableText(message, textColor: .white)
                }
                .contextMenu { bubbleMenu(message) }
                .overlay(alignment: .topLeading) {
                    coachBadge(message)
                }
                translationFootnote(message, alignment: .trailing)
                coachCard(message)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                MessageBubble(side: .incoming) {
                    tappableText(message, textColor: nil)
                }
                .contextMenu { bubbleMenu(message) }
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
                Text(message.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    /// 长按菜单四功能：复制/收藏/翻译/播放（plan.md 聊天模块）。
    @ViewBuilder
    private func bubbleMenu(_ message: MessageDTO) -> some View {
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        Button {
            Task { await viewModel.favorite(message: message) }
        } label: {
            Label("收藏", systemImage: "star")
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

    // MARK: - 教练纠错

    /// 用户气泡角落的小黄点：有纠错建议时出现，点击展开纠错卡。
    @ViewBuilder
    private func coachBadge(_ message: MessageDTO) -> some View {
        if CoachService.decode(fromJSON: message.coachReviewJSON)?.hasIssues == true {
            Button {
                withAnimation(.snappy) {
                    if expandedCoachMessageIDs.contains(message.id) {
                        expandedCoachMessageIDs.remove(message.id)
                    } else {
                        expandedCoachMessageIDs.insert(message.id)
                    }
                }
            } label: {
                Circle()
                    .fill(.yellow)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
            .offset(x: 42, y: -3)
            .accessibilityLabel("查看改进建议")
        }
    }

    /// 展开的纠错卡：错误片段 → 改法 + 中文讲解 + 采纳按钮（改不改随用户）。
    @ViewBuilder
    private func coachCard(_ message: MessageDTO) -> some View {
        if expandedCoachMessageIDs.contains(message.id),
           let review = CoachService.decode(fromJSON: message.coachReviewJSON),
           review.hasIssues {
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
                                .foregroundStyle(.green)
                        }
                        .font(.subheadline)
                        Text(issue.explanationZh)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("采纳") {
                            viewModel.draft = message.text.replacingOccurrences(
                                of: issue.quote,
                                with: issue.correction
                            )
                            withAnimation(.snappy) {
                                expandedCoachMessageIDs.remove(message.id)
                            }
                        }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
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
                    hasAudio: message.audioFileName != nil
                ),
                isPlaying: voicePlayer.playingFileName != nil && voicePlayer.playingFileName == message.audioFileName,
                showTranscript: transcriptVisibleMessageIDs.contains(message.id),
                textColor: textColor,
                onTogglePlay: {
                    guard let fileName = message.audioFileName else { return }
                    Task { await voicePlayer.togglePlay(fileName: fileName) }
                }
            )
        } else {
            TappableText(
                tokens: TokenCache.tokens(for: message.text, cacheKey: message.id.uuidString),
                contextID: message.id.uuidString,
                keywords: message.role == .assistant
                    ? KeywordAnnotator.decodeWords(fromJSON: message.keywordRangesJSON)
                    : [],
                textColor: textColor,
                selection: wordSelection,
                onSelect: { wordSelection = $0 }
            )
        }
    }

    /// 词典未收录时的 AI 简释兜底（fast 档）。
    private var aiWordFallback: @Sendable (String) async -> String? {
        let llm = deps.llm
        return { word in
            let request = LLMRequest(
                tier: .fast,
                system: "你是一个简明的英汉词典助手。用中文简要解释用户给出的英文词，格式：词性. 释义（不超过 3 条）；如是俚语/缩写/网络用语请注明。总长不超过 80 字。",
                messages: [.user(word)],
                maxTokens: 200,
                temperature: 0.2
            )
            return try? await llm.complete(request)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) {
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
                .disabled(viewModel.isStreaming)
                #if targetEnvironment(simulator)
                // 模拟器兜底：麦克风/识别不可用时注入文本验证全流程（plan.md §3.2）
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
                TextField("用英语说点什么…", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onSubmit {
                        Task { await viewModel.sendDraft() }
                    }

                Button {
                    Task { await viewModel.sendDraft() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
