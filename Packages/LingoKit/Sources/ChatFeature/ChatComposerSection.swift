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

extension ChatView {
var inputBar: some View {
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
                        // 保留学习者实际输入，避免系统把语法/拼写错误改成另一个词后再送去点评。
                        .autocorrectionDisabled(true)
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

    var shouldShowMascotPrompt: Bool {
        !isVoiceMode
            && !isMascotPromptDismissed
            && viewModel.draft.isEmpty
            && !viewModel.isStreaming
            && viewModel.messages.count <= 3
    }

    var mascotConversationPrompt: some View {
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

    var conversationStarter: String {
        "What do you love most about \(chatCityEnglishName)?"
    }

    var chatCityDisplayName: String {
        let regions = ["london": "伦敦", "melbourne": "墨尔本", "newyork": "纽约"]
        return regions[viewModel.character.card.regionID] ?? viewModel.character.card.regionID
    }

    var chatCityEnglishName: String {
        let regions = [
            "london": "London",
            "melbourne": "Melbourne",
            "newyork": "New York",
        ]
        return regions[viewModel.character.card.regionID]
            ?? viewModel.character.card.regionID.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
