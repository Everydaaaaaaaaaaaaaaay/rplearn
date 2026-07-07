import DesignSystem
import PersistenceKit
import SwiftUI

/// 聊天页：消息列表 + 输入栏 + 流式回复。
public struct ChatView: View {
    @State private var viewModel: ChatViewModel

    public init(character: CharacterDTO, deps: ChatDependencies) {
        _viewModel = State(initialValue: ChatViewModel(character: character, deps: deps))
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .navigationTitle(viewModel.character.card.name)
        .navigationBarTitleDisplayMode(.inline)
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
            MessageBubble(side: .outgoing) {
                Text(message.text)
                    .foregroundStyle(.white)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                MessageBubble(side: .incoming) {
                    Text(message.text)
                }
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
