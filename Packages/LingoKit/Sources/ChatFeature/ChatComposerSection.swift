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
    /// 输入栏。`bottomInset` 是屏幕底部安全区（home indicator）——iOS 26 的 `safeAreaInset`
    /// 会把安全区算进输入栏自身，iOS 27 不会；为了让输入栏在所有系统上都贴住屏幕底边，
    /// 这里由输入栏自己带上这段高度（材质一起铺下去，内容仍留在 indicator 之上）。
    func inputBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            translatorControls
                .frame(height: composerTranslation.isOpen ? nil : 0)
                .opacity(composerTranslation.isOpen ? 1 : 0)
                .clipped()
                .allowsHitTesting(composerTranslation.isOpen)
                .disabled(!composerTranslation.isOpen)
                .accessibilityHidden(!composerTranslation.isOpen)
            HStack(spacing: 8) {
                Button {
                    if composerTranslation.isOpen {
                        toggleChineseRecording()
                        return
                    }
                    withAnimation(.snappy) {
                        isTextInputFocused = false
                        isVoiceMode.toggle()
                        recorder.resetFailure()
                    }
                } label: {
                    Image(systemName: composerTranslation.isOpen ? (isChineseRecording ? "stop.fill" : "mic") : (isVoiceMode ? "keyboard" : "mic"))
                        .font(.system(size: 22))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(isVoiceMode ? "切换到键盘" : "切换到语音")

                if isVoiceMode && !composerTranslation.isOpen {
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
                        .foregroundStyle(Color.primary)
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
                            Task { await sendComposerDraft() }
                        }

                    if isTextInputFocused && !composerTranslation.isOpen {
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

                    translatorToggle

                    Button {
                        Task { await sendComposerDraft() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(composerTint, in: Circle())
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
        .padding(.bottom, max(0, bottomInset))
        .tint(composerTint)
        .background(ComposerWaterSurface(expanded: composerTranslation.isOpen, bottomInset: max(0, bottomInset)))
        .animation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.94), value: composerTranslation.isOpen)
        .onChange(of: composerTranslation.source) { old, new in
            if composerTranslation.isOpen { viewModel.composerSourceEdited(from: old, to: new) }
            composerTranslation.cancel()
            if composerTranslation.isOpen && composerTranslation.mode == .instant { translateComposer() }
        }
        .onChange(of: composerTranslation.mode) { _, _ in
            composerTranslation.cancel()
            composerAppleTranslator.cancelAll()
            if composerTranslation.mode == .instant { translateComposer() }
        }
        .translationTask(composerAppleTranslator.configuration) { @Sendable session in
            let id = await composerAppleTranslator.sessionID
            var failed = false
            do {
                try await session.prepareTranslation()
                while !Task.isCancelled {
                    let batch = await composerAppleTranslator.takeBatch(sessionID: id)
                    if batch.isEmpty { break }
                    for item in batch {
                        let result = try? await session.translate(item.text).targetText
                        await composerAppleTranslator.complete(item.id, with: result)
                    }
                }
            } catch { failed = true }
            await composerAppleTranslator.finishSession(id, failed: failed || Task.isCancelled)
        }
        .onChange(of: chineseRecorder.pendingAutoCapture?.transcript) { _, transcript in
            guard let transcript, composerTranslation.isOpen else { return }
            composerTranslation.source = transcript
            if let file = chineseRecorder.pendingAutoCapture?.fileName { VoiceMessageStorage.delete(fileName: file) }
        }
        .onDisappear {
            isChineseInputFocused = false
            composerTranslation.cancel()
            composerAppleTranslator.cancelAll()
            chineseRecordingTask?.cancel()
            Task { await chineseRecorder.cancelRecording() }
        }
    }

    private var composerTint: Color { composerTranslation.isOpen ? Color(red: 0.49, green: 0.35, blue: 0.91) : .dsSky }

    private var translatorToggle: some View {
        Button {
            isChineseInputFocused = false
            composerTranslation.cancel()
            composerAppleTranslator.cancelAll()
            chineseRecordingTask?.cancel()
            Task {
                await chineseRecorder.cancelRecording()
                await recorder.cancelRecording()
            }
            withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.94)) {
                composerTranslation.isOpen.toggle()
                isVoiceMode = false
            }
            if composerTranslation.isOpen && composerTranslation.mode == .instant { translateComposer() }
        } label: {
            ZStack {
                Circle().fill(composerTint.opacity(0.12))
                BrandMascotView(pose: composerTranslation.isOpen ? .achievement : .greeting, size: 49)
                    .offset(y: 9)
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(composerTint.opacity(0.45), lineWidth: 2))
            .overlay(Circle().inset(by: 2).strokeBorder(.white.opacity(0.75), lineWidth: 1))
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(composerTranslation.isOpen ? "收起翻译器" : "打开翻译器")
        .accessibilityIdentifier("chat.translator.toggle")
    }

    private var translatorControls: some View {
        VStack(spacing: 4) {
            ComposerModeSwitch(mode: $composerTranslation.mode)
                .padding(.top, 10)
            HStack(spacing: 8) {
                Button {
                    let text = viewModel.draft
                    guard !text.isEmpty else { return }
                    Task {
                        await autoReadQueue.interrupt()?.value
                        await deps.speech.speak(viewModel.speechRequest(for:
                            MessageDTO(id: UUID(), role: .user, kind: .text, text: text, orderIndex: 0)))
                    }
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 22)).frame(width: 32, height: 44)
                }
                .disabled(viewModel.draft.isEmpty)
                .accessibilityLabel("朗读英文草稿")
                TextField(isChineseRecording ? "正在听，请说中文…" : "输入中文，或者说中文…",
                          text: $composerTranslation.source, axis: .vertical)
                    .font(.body).foregroundStyle(Color.primary)
                    .focused($isChineseInputFocused)
                    .submitLabel(.done)
                    .onSubmit { isChineseInputFocused = false }
                    .lineLimit(1...2)
                    .accessibilityIdentifier("chat.translator.source")
                if composerTranslation.isWorking {
                    ProgressView().controlSize(.small).accessibilityLabel("正在翻译")
                } else if composerTranslation.mode == .ai {
                    Button("翻译") { translateComposer() }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(composerTint.opacity(0.10), in: Capsule())
                        .disabled(composerTranslation.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            if let recordingError = chineseRecordingError {
                Text(recordingError).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).padding(.horizontal, 16)
            }
            if let error = composerTranslation.error {
                Button(error) { translateComposer() }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func translateComposer() {
        let mode = composerTranslation.mode
        composerTranslation.translate(automatic: mode == .instant,
            readDraft: { viewModel.draft }, writeDraft: { viewModel.draft = $0 },
            perform: { text in
                if mode == .ai { return try await deps.translator.translateToEnglish(text) }
                guard let result = await composerAppleTranslator.translate(text) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return result
            })
    }

    private func sendComposerDraft() async {
        composerTranslation.cancel()
        composerAppleTranslator.cancelAll()
        await viewModel.sendDraft()
        if viewModel.draft.isEmpty { composerTranslation.source = "" }
    }

    private var chineseRecordingError: String? {
        switch chineseRecorder.state {
        case .denied: "请在系统设置中允许麦克风与语音识别"
        case .failed(let message): message
        case .transcribing: "正在识别中文…"
        default: nil
        }
    }

    private var isChineseRecording: Bool {
        if case .recording = chineseRecorder.state { return true }
        return false
    }

    private func toggleChineseRecording() {
        chineseRecordingTask?.cancel()
        chineseRecordingTask = Task {
            if isChineseRecording {
                if let capture = await chineseRecorder.finishRecording() {
                    if let file = capture.fileName { VoiceMessageStorage.delete(fileName: file) }
                    guard composerTranslation.isOpen, !Task.isCancelled else { return }
                    composerTranslation.source = capture.transcript
                }
            } else {
                await autoReadQueue.interrupt()?.value
                await chineseRecorder.startRecording()
            }
        }
    }

}
