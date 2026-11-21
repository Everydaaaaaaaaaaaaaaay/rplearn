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

/// Draft and translation edits are observed within the composer, outside the transcript.
struct ChatComposerView: View {
    @Bindable var viewModel: ChatViewModel
    @Bindable var composerTranslation: ComposerTranslationModel
    let deps: ChatDependencies
    let bottomInset: CGFloat
    let autoReadQueue: ChatAutoReadQueue
    let recorder: VoiceRecorder
    let chineseRecorder: VoiceRecorder
    let voicePlayer: VoiceMessagePlayer
    let composerAppleTranslator: AppleTranslator
    @FocusState.Binding var composerFocus: ChatView.ComposerFocus?
    @Binding var showsChatFunctions: Bool
    @Binding var inputDockHeight: CGFloat
    @Binding var isVoiceMode: Bool
    @Binding var showsRealtimeConversation: Bool
    @Binding var learningSelected: Bool
    let preferredKeyboardHeight: CGFloat
    let inputDockAnimation: Animation
    let dismissChatInput: () -> Void
    @State private var chineseRecordingTask: Task<Void, Never>?
    @State private var showSimulatorInjection = false
    @State private var simulatorInjectionText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isChineseInputFocused: Bool {
        get { composerFocus == .chinese }
        nonmutating set {
            if newValue { composerFocus = .chinese }
            else if composerFocus == .chinese { composerFocus = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if composerTranslation.isOpen {
                translatorControls.transition(.opacity)
            }
            HStack(spacing: 8) {
                Button {
                    if composerTranslation.isOpen {
                        toggleChineseRecording()
                        return
                    }
                    dismissChatInput()
                    withAnimation(.snappy) {
                        isVoiceMode.toggle()
                        recorder.resetFailure()
                    }
                } label: {
                    Image(systemName: composerTranslation.isOpen ? (isChineseRecording ? "stop.fill" : "mic.fill") : (isVoiceMode ? "keyboard" : "mic.fill"))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(composerTint)
                        .frame(width: 38, height: 38)
                        .background(composerWash, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.puffSquish)
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
                        .focused($composerFocus, equals: .english)
                        .accessibilityIdentifier("chat.composer")
                        // 保留学习者实际输入，避免系统把语法/拼写错误改成另一个词后再送去点评。
                        .autocorrectionDisabled(true)
                        .submitLabel(.send)
                        .textFieldStyle(.plain)
                        .font(.puff(.body, .medium))
                        .foregroundStyle(Puff.Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Puff.Palette.cloud,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(composerFocus == .english ? composerTint : .clear, lineWidth: 2)
                        }
                        .animation(Puff.Motion.press, value: composerFocus == .english)
                        .onSubmit {
                            Task { await sendComposerDraft() }
                        }

                    translatorToggle
                }
                composerAction
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            ZStack(alignment: .top) {
                if showsChatFunctions { chatFunctionPanel.transition(.opacity) }
            }
            .frame(height: max(0, inputDockHeight - bottomInset), alignment: .top)
            .clipped()
        }
        .padding(.bottom, max(0, bottomInset))
        .tint(composerTint)
        .background(ComposerPanelSurface(expanded: composerTranslation.isOpen))
        .animation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.94), value: composerTranslation.isOpen)
        .onChange(of: composerFocus) { _, focus in
            if focus != nil { showsChatFunctions = false }
        }
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
        .onDisappear { chineseRecordingTask?.cancel() }
        .onChange(of: chineseRecorder.pendingAutoCapture?.transcript) { _, transcript in
            guard let transcript, composerTranslation.isOpen else { return }
            composerTranslation.source = transcript
            if let file = chineseRecorder.pendingAutoCapture?.fileName { VoiceMessageStorage.delete(fileName: file) }
        }
    }

    private var composerAction: some View {
        let sends = composerFocus != nil
        return Button {
            if sends {
                Task { await sendComposerDraft() }
            } else if showsChatFunctions {
                // Keep the same reserved height while the system keyboard takes over.
                showsChatFunctions = false
                isVoiceMode = false
                composerFocus = .english
            } else {
                withAnimation(inputDockAnimation) {
                    showsChatFunctions = true
                    inputDockHeight = preferredKeyboardHeight
                }
            }
        } label: {
            Image(systemName: sends ? "arrow.up" : (showsChatFunctions ? "keyboard" : "plus"))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(sends ? Color.white : composerTint)
                .frame(width: 38, height: 38)
                .background(sends ? composerTint : composerWash, in: Circle())
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.puffSquish)
        .disabled(sends && viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(sends ? "发送消息" : (showsChatFunctions ? "切换到键盘" : "聊天功能"))
        .accessibilityIdentifier(sends ? "chat.send" : "chat.functions")
        .accessibilityValue(sends ? "" : (showsChatFunctions ? "展开" : "收起"))
    }

    private var chatFunctionPanel: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            Button {
                dismissChatInput()
                voicePlayer.stop()
                showsRealtimeConversation = true
            } label: { chatFunctionLabel("打电话", symbol: "phone.fill", candy: .mint) }
            .accessibilityIdentifier("chat.call")

            if deps.learningPage != nil {
                Button {
                    dismissChatInput()
                    learningSelected = true
                } label: { chatFunctionLabel("学习模式", symbol: "book.closed.fill", candy: .grape) }
                .accessibilityIdentifier("chat.learningMode")
            }

            Button {
                dismissChatInput()
                toggleComposerTranslator()
            } label: { chatFunctionLabel("翻译器", symbol: "character.bubble.fill", candy: .tangerine) }
            .accessibilityIdentifier("chat.translationMode")
        }
        .buttonStyle(.puffSquish)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .accessibilityIdentifier("chat.functions.panel")
    }

    private func chatFunctionLabel(_ title: String, symbol: String, candy: PuffCandy) -> some View {
        VStack(spacing: 7) {
            PuffIconBubble(symbol, candy: candy, size: 56)
            Text(title)
                .font(.puff(.caption, .heavy))
                .foregroundStyle(Puff.Palette.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .contentShape(Rectangle())
    }

    private var composerTint: Color { composerTranslation.isOpen ? PuffCandy.grape.base : PuffCandy.sky.base }
    private var composerWash: Color { composerTranslation.isOpen ? PuffCandy.grape.wash : PuffCandy.sky.wash }

    private var translatorToggle: some View {
        Button(action: toggleComposerTranslator) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(composerTranslation.isOpen ? .white : PuffCandy.tangerine.deep)
                .frame(width: 34, height: 34)
                .background(composerTranslation.isOpen ? PuffCandy.grape.base : PuffCandy.tangerine.wash, in: Circle())
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel(composerTranslation.isOpen ? "收起翻译器" : "打开翻译器")
        .accessibilityIdentifier("chat.translator.toggle")
    }

    private func toggleComposerTranslator() {
        // Transfer focus before hiding the source field. Closing the translator
        // must not resign the keyboard that the learner is already using.
        if composerTranslation.isOpen {
            if composerFocus != nil { composerFocus = .english }
        } else if composerFocus == .chinese {
            composerFocus = nil
        }
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
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .heavy)).foregroundStyle(composerTint)
                        .frame(width: 32, height: 44)
                }
                .disabled(viewModel.draft.isEmpty)
                .accessibilityLabel("朗读英文草稿")
                TextField(isChineseRecording ? "正在听，请说中文…" : "输入中文，或者说中文…",
                          text: $composerTranslation.source, axis: .vertical)
                    .font(.puff(.body, .medium)).foregroundStyle(Puff.Palette.ink)
                    .focused($composerFocus, equals: .chinese)
                    .submitLabel(.done)
                    .onSubmit { isChineseInputFocused = false }
                    .lineLimit(1...2)
                    .accessibilityIdentifier("chat.translator.source")
                if composerTranslation.isWorking {
                    ProgressView().controlSize(.small).accessibilityLabel("正在翻译")
                } else if composerTranslation.mode == .ai {
                    Button("翻译") { translateComposer() }
                        .font(.puff(.subheadline, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(composerTint, in: Capsule())
                        .buttonStyle(.puffSquish)
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
