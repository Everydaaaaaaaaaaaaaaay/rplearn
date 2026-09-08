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

}
