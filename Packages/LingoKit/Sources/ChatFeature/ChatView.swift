import CoreKit
import DesignSystem
import DictKit
import DomainKit
import LLMKit
import PersistenceKit
import SwiftUI

/// 聊天页：消息列表 + 输入栏 + 流式回复 + 点词查词。
public struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var wordSelection: TokenSelection?
    private let deps: ChatDependencies

    public init(character: CharacterDTO, deps: ChatDependencies) {
        _viewModel = State(initialValue: ChatViewModel(character: character, deps: deps))
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
                translationFootnote(message, alignment: .trailing)
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
            EmptyView()
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

    private func tappableText(_ message: MessageDTO, textColor: Color?) -> some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
