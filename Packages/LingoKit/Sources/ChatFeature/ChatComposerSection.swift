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
                        speakEnglishDraft()
                        return
                    }
                    dismissChatInput()
                    withAnimation(.snappy) {
                        isVoiceMode.toggle()
                        recorder.resetFailure()
                    }
                } label: {
                    Image(systemName: composerTranslation.isOpen ? "speaker.wave.2.fill" : (isVoiceMode ? "keyboard" : "mic.fill"))
                        .font(.system(size: 18, weight: Puff.Weight.icon, design: .rounded))
                        .foregroundStyle(composerTint)
                        .frame(width: 38, height: 38)
                        .background(composerWash, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.puffSquish)
                .disabled(composerTranslation.isOpen && viewModel.draft.isEmpty)
                .accessibilityLabel(composerTranslation.isOpen ? "朗读英文译文" : (isVoiceMode ? "切换到键盘" : "切换到语音"))

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
                            : (composerTranslation.isOpen ? "英文译文" : "用英语说点什么…"),
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
                        .font(.puff(.body, Puff.Weight.body))
                        .foregroundStyle(Puff.Palette.ink)
                        .padding(.leading, composerTranslation.isOpen ? 36 : 14)
                        .padding(.trailing, 14)
                        .padding(.vertical, 9)
                        .background(
                            Puff.Palette.cloud,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(composerFocus == .english ? composerTint : .clear, lineWidth: 2)
                        }
                        .overlay(alignment: .leading) {
                            if composerTranslation.isOpen { languageTag("英").padding(.leading, 9) }
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
        // 与键盘同节奏（平滑、不回弹）：打开翻译器时面板展开和键盘升起一起完成，输入框不错位。
        .animation(reduceMotion ? .linear(duration: 0.15) : Self.translatorAnimation, value: composerTranslation.isOpen)
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
        .onChange(of: composerAppleTranslator.availability) { _, availability in
            // 语言包刚下载好：把已经写下的中文补翻一次。
            if availability == .installed, composerTranslation.isOpen, composerTranslation.mode == .instant {
                translateComposer()
            }
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
                .font(.system(size: 18, weight: Puff.Weight.icon, design: .rounded))
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
                .font(.puff(.caption, Puff.Weight.emphasis))
                .foregroundStyle(Puff.Palette.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .contentShape(Rectangle())
    }

    private static let translatorAnimation = Animation.smooth(duration: 0.28)

    private var composerTint: Color { composerTranslation.isOpen ? PuffCandy.grape.base : PuffCandy.sky.base }
    private var composerWash: Color { composerTranslation.isOpen ? PuffCandy.grape.wash : PuffCandy.sky.wash }

    private var translatorToggle: some View {
        Button(action: toggleComposerTranslator) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 15, weight: Puff.Weight.icon, design: .rounded))
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
        if composerTranslation.isOpen, composerFocus != nil { composerFocus = .english }
        composerTranslation.cancel()
        composerAppleTranslator.cancelAll()
        chineseRecordingTask?.cancel()
        Task {
            await chineseRecorder.cancelRecording()
            await recorder.cancelRecording()
        }
        withAnimation(reduceMotion ? nil : Self.translatorAnimation) {
            composerTranslation.isOpen.toggle()
            isVoiceMode = false
        }
        guard composerTranslation.isOpen else { return }
        Task { await composerAppleTranslator.refreshAvailability() }
        // 打开翻译器就把光标放进中文框：一眼知道从哪里开始写。中文框插入后的下一帧聚焦，
        // 键盘与面板展开同时开始。
        Task { @MainActor in
            await Task.yield()
            if composerTranslation.isOpen { composerFocus = .chinese }
        }
        if composerTranslation.mode == .instant { translateComposer() }
    }

    /// 翻译器：上面是要写的中文（主输入框），下面的英文框接收译文，改好再发送。
    private var translatorControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ComposerModeSwitch(mode: $composerTranslation.mode)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            chineseSourceField
            translatorStatus
        }
        .padding(.horizontal, 12)
    }

    private var chineseSourceField: some View {
        let focused = composerFocus == .chinese
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(spacing: 4) {
            TextField(isChineseRecording ? "正在听，请说中文…" : "想说的中文",
                      text: $composerTranslation.source, axis: .vertical)
                .font(.puff(.body, Puff.Weight.body)).foregroundStyle(Puff.Palette.ink)
                .focused($composerFocus, equals: .chinese)
                .submitLabel(.done)
                .onSubmit { isChineseInputFocused = false }
                .lineLimit(1...3)
                .padding(.vertical, 9)
                .accessibilityIdentifier("chat.translator.source")
            if composerTranslation.isWorking {
                ProgressView().controlSize(.small)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("正在翻译")
            } else if composerTranslation.mode == .ai {
                Button("翻译") { translateComposer() }
                    .font(.puff(.subheadline, Puff.Weight.emphasis))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(composerTint, in: Capsule())
                    .buttonStyle(.puffSquish)
                    .disabled(composerTranslation.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button(action: toggleChineseRecording) {
                Image(systemName: isChineseRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: Puff.Weight.icon, design: .rounded))
                    .foregroundStyle(isChineseRecording ? Color.white : composerTint)
                    .frame(width: 32, height: 32)
                    .background(isChineseRecording ? composerTint : composerWash, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.puffSquish)
            .accessibilityLabel(isChineseRecording ? "停止说中文" : "说中文")
            .accessibilityIdentifier("chat.translator.voice")
        }
        .padding(.leading, 36)
        .padding(.trailing, 2)
        .background(Puff.Palette.card, in: shape)
        .overlay {
            shape.strokeBorder(focused ? composerTint : composerTint.opacity(0.3), lineWidth: focused ? 2 : 1.2)
        }
        .overlay(alignment: .leading) { languageTag("中").padding(.leading, 9) }
        .contentShape(shape)
        .onTapGesture { composerFocus = .chinese }
        .animation(Puff.Motion.press, value: focused)
    }

    /// 输入框里的小语言标签：中文框标“中”，英文框标“英”，看得出是中译英。
    private func languageTag(_ text: String) -> some View {
        Text(text)
            .font(.puff(.caption, Puff.Weight.emphasis))
            .foregroundStyle(PuffCandy.grape.deep)
            .frame(width: 22, height: 22)
            .background(PuffCandy.grape.wash, in: Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var translatorStatus: some View {
        if let recordingError = chineseRecordingError {
            Text(recordingError).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).padding(.horizontal, 4)
        }
        if composerTranslation.mode == .instant {
            instantAvailabilityNotice
        }
        if let error = composerTranslation.error {
            Button(error) { translateComposer() }
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .padding(.horizontal, 4)
        }
    }

    /// 即时翻译用本机语言包。没装时在这里给出选择，只有点了“下载”才由系统弹出下载确认。
    @ViewBuilder
    private var instantAvailabilityNotice: some View {
        switch composerAppleTranslator.availability {
        case .downloadable:
            HStack(spacing: 8) {
                Label("即时翻译需先下载中英语言包", systemImage: "arrow.down.circle")
                    .font(.puff(.caption, Puff.Weight.label)).foregroundStyle(Puff.Palette.inkSoft)
                    .lineLimit(2)
                Spacer(minLength: 4)
                noticeButton("下载", filled: true) { composerAppleTranslator.requestDownload() }
                    .accessibilityIdentifier("chat.translator.download")
                noticeButton("用 AI", filled: false) { composerTranslation.mode = .ai }
            }
            .padding(.horizontal, 4)
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在下载语言包…")
                    .font(.puff(.caption, Puff.Weight.label)).foregroundStyle(Puff.Palette.inkSoft)
            }
            .padding(.horizontal, 4).frame(minHeight: 36)
        case .unsupported:
            HStack(spacing: 8) {
                Label("本机暂不支持即时翻译", systemImage: "exclamationmark.circle")
                    .font(.puff(.caption, Puff.Weight.label)).foregroundStyle(Puff.Palette.inkSoft)
                    .lineLimit(2)
                Spacer(minLength: 4)
                noticeButton("用 AI", filled: true) { composerTranslation.mode = .ai }
            }
            .padding(.horizontal, 4)
        case .checking, .installed:
            EmptyView()
        }
    }

    private func noticeButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.puff(.caption, Puff.Weight.emphasis))
            .foregroundStyle(filled ? Color.white : composerTint)
            .padding(.horizontal, 12).frame(height: 30)
            .background(filled ? composerTint : composerWash, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.puffSquish)
    }

    private func speakEnglishDraft() {
        let text = viewModel.draft
        guard !text.isEmpty else { return }
        Task {
            await autoReadQueue.interrupt()?.value
            await deps.speech.speak(viewModel.speechRequest(for:
                MessageDTO(id: UUID(), role: .user, kind: .text, text: text, orderIndex: 0)))
        }
    }

    private func translateComposer() {
        let mode = composerTranslation.mode
        // 本机语言包没装或不支持时，即时模式不发起翻译，由上方提示让用户选择下载或改用 AI。
        if mode == .instant, ![.installed, .checking].contains(composerAppleTranslator.availability) {
            composerTranslation.cancel()
            return
        }
        composerTranslation.translate(automatic: mode == .instant,
            readDraft: { viewModel.draft }, writeDraft: { viewModel.draft = $0 },
            isComposing: { composerFocus == .chinese && InputMethodComposition.isComposing },
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
