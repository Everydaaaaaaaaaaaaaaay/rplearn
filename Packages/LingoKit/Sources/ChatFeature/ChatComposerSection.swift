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
                        guard deps.tutorial == nil else { return }
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
                        .accessibilityIdentifier("chat.composer")
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

                    if isTextInputFocused {
                        Button {
                            isTextInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 20))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("收起键盘")
                        .accessibilityIdentifier("chat.dismissKeyboard")
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
        .background(alignment: .bottom) {
            // 部分真机在隐藏标签栏或收起键盘后会保留底部安全区，输入栏会浮在屏幕底边之上，
            // 下方露出还留在屏幕里的消息内容（iPhone 13 实机反馈）。这里用同一材质向屏幕底边
            // 再铺一段：输入栏正常贴底时它落在屏幕外，看不到任何变化；真的被顶起来时刚好补住缝隙。
            Rectangle()
                .fill(Color.clear)
                .dsMaterial(.ultraThinMaterial, in: Rectangle())
                .frame(height: Self.composerBottomBleed)
                .offset(y: Self.composerBottomBleed)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 输入栏材质向下补铺的高度，覆盖标签栏残留安全区等系统差异。
    private static let composerBottomBleed: CGFloat = 160

}
