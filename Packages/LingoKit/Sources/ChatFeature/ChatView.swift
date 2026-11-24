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

/// 聊天页：消息列表 + 输入栏（文本/语音）+ 流式回复 + 点词查词。
public struct ChatView: View {
    @State private var learningRegionID: String?
    @State var viewModel: ChatViewModel
    @State var learningSelected = false
    @GestureState(resetTransaction: Transaction(animation: .interactiveSpring(duration: 0.28, extraBounce: 0)))
    private var learningTranslation: CGFloat = 0
    #if DEBUG
    @State private var fillingLearning = false
    @State private var learningDebugError: String?
    #endif
    @AppStorage("chat.autoReadEnabled") private var autoReadEnabled = true
    @State var showsChatFunctions = false
    @State private var opensAppointmentsAfterSettings = false
    @State private var appointmentAfterSettings: UUID?
    @State var inputDockHeight: CGFloat = 0
    @AppStorage("chat.keyboardHeight.portrait") private var portraitKeyboardHeight = 346.0
    @AppStorage("chat.keyboardHeight.landscape") private var landscapeKeyboardHeight = 216.0
    @State private var autoReadReady = false
    @State var autoReadQueue: ChatAutoReadQueue
    @Environment(\.scenePhase) private var scenePhase
    @State var wordSelection: TokenSelection?
    @State var grammarTermSelection: GrammarTermSelection?
    @State var grammarAnalysis: GrammarAnalysisRequest?
    @State var grammarAICache: [UUID: AIGrammarAnalysis] = [:]
    @State var expandedCoachMessageIDs: Set<UUID> = []
    @State var composerTranslation = ComposerTranslationModel()
    @State var composerAppleTranslator = AppleTranslator(sourceLanguage: "zh-Hans", targetLanguage: "en", requestTimeout: .seconds(20))
    @State var chineseRecorder: VoiceRecorder
    @State var isVoiceMode = false
    @State var recorder: VoiceRecorder
    @State var voicePlayer: VoiceMessagePlayer
    @State var appleTranslator = AppleTranslator()
    @State var showsRealtimeConversation = false
    @State private var accessAfterVoice = false
    @State var showsContactDetails = false
    @State var highlightedMessageID: UUID?
    /// 键盘已在屏幕上（贴底、占满宽度）。
    @State private var keyboardShown = false
    /// 键盘通知先于 SwiftUI 焦点更新到达时暂存的高度，焦点到位后再抬起输入栏。
    @State private var pendingKeyboardHeight: CGFloat?
    enum ComposerFocus: Hashable { case english, chinese }
    @FocusState var composerFocus: ComposerFocus?
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
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) var dismiss
    let deps: ChatDependencies

    public init(
        character: CharacterDTO,
        deps: ChatDependencies,
        startsInRealtimeConversation: Bool = false
    ) {
        _viewModel = State(initialValue: ChatViewModel(character: character, deps: deps))
        _chineseRecorder = State(initialValue: VoiceRecorder(audioSession: deps.audioSession, localeIdentifier: "zh_CN"))
        _recorder = State(initialValue: VoiceRecorder(audioSession: deps.audioSession))
        _voicePlayer = State(initialValue: VoiceMessagePlayer(audioSession: deps.audioSession))
        _showsRealtimeConversation = State(initialValue: startsInRealtimeConversation)
        _autoReadQueue = State(initialValue: ChatAutoReadQueue(speech: deps.speech))
        self.deps = deps
    }

    var inputDockAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .interactiveSpring(response: 0.28, dampingFraction: 1)
    }

    private var chatWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    var preferredKeyboardHeight: CGFloat {
        let landscape = chatWindow.map { $0.bounds.width > $0.bounds.height } ?? false
        return CGFloat(landscape ? landscapeKeyboardHeight : portraitKeyboardHeight)
    }

    private func chatPage(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            ChatTranscriptView(viewModel: viewModel, deps: deps, voicePlayer: voicePlayer,
                autoReadQueue: autoReadQueue, wordSelection: $wordSelection,
                grammarTermSelection: $grammarTermSelection, grammarAnalysis: $grammarAnalysis,
                expandedCoachMessageIDs: $expandedCoachMessageIDs, highlightedMessageID: $highlightedMessageID,
                composerFocus: $composerFocus,
                showsChatFunctions: showsChatFunctions, dismissChatInput: dismissChatInput)
            ChatComposerView(viewModel: viewModel, composerTranslation: composerTranslation,
                deps: deps, bottomInset: bottomInset, autoReadQueue: autoReadQueue,
                recorder: recorder, chineseRecorder: chineseRecorder, voicePlayer: voicePlayer,
                composerAppleTranslator: composerAppleTranslator, composerFocus: $composerFocus,
                showsChatFunctions: $showsChatFunctions, inputDockHeight: $inputDockHeight,
                isVoiceMode: $isVoiceMode, showsRealtimeConversation: $showsRealtimeConversation,
                learningSelected: $learningSelected, preferredKeyboardHeight: preferredKeyboardHeight,
                inputDockAnimation: inputDockAnimation, dismissChatInput: dismissChatInput)
                .disabled(learningSelected)
                .layoutPriority(1)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    func dismissChatInput() {
        guard showsChatFunctions || inputDockHeight > 0 || composerFocus != nil else { return }
        withAnimation(inputDockAnimation) {
            showsChatFunctions = false
            inputDockHeight = 0
            composerFocus = nil
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func updateKeyboard(_ notification: Notification) {
        // The function panel owns the dock until it hands that space to the keyboard.
        guard !showsChatFunctions else { return }
        let animation = keyboardAnimation(notification)
        var height: CGFloat = 0
        var window: UIWindow?
        if notification.name != UIResponder.keyboardWillHideNotification {
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let chatWindow else { return }
            let localFrame = chatWindow.convert(frame, from: chatWindow.screen.coordinateSpace)
            let overlap = localFrame.intersection(chatWindow.bounds)
            // Floating and external keyboards do not reserve the bottom of the conversation.
            height = !overlap.isEmpty && localFrame.maxY >= chatWindow.bounds.maxY - 1
                && overlap.width >= chatWindow.bounds.width - 1 ? (overlap.height.rounded()) : 0
            window = chatWindow
        }
        keyboardShown = height > 0
        guard height > 0 else {
            pendingKeyboardHeight = nil
            // 输入框仍持有焦点时键盘被临时收起（例如长按气泡弹出系统菜单）：输入栏留在原位，
            // 菜单关闭、键盘回来时对话不跳动。焦点真正离开后再落下（见 composerFocus 的 onChange）。
            guard composerFocus == nil else { return }
            setInputDock(0, animation: animation)
            return
        }
        guard composerFocus != nil else {
            // 键盘通知有时先于焦点更新到达：先记下，焦点到位后再抬起输入栏。
            pendingKeyboardHeight = height
            return
        }
        if let window { rememberKeyboardHeight(height, in: window) }
        setInputDock(height, animation: animation)
    }

    private func rememberKeyboardHeight(_ height: CGFloat, in window: UIWindow) {
        if window.bounds.width > window.bounds.height {
            if landscapeKeyboardHeight != height { landscapeKeyboardHeight = height }
        } else if portraitKeyboardHeight != height {
            portraitKeyboardHeight = height
        }
    }

    private func keyboardAnimation(_ notification: Notification) -> Animation {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 7
        switch curve {
        case 0: return .easeInOut(duration: duration)
        case 1: return .easeIn(duration: duration)
        case 2: return .easeOut(duration: duration)
        case 3: return .linear(duration: duration)
        default: return .interpolatingSpring(duration: max(0.2, duration), bounce: 0)
        }
    }

    private func setInputDock(_ height: CGFloat, animation: Animation) {
        guard height != inputDockHeight else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : animation) {
            inputDockHeight = height
        }
    }

    /// 焦点变化收尾键盘留下的状态：补上先到的键盘高度，或在焦点离开且键盘已收起后放下输入栏。
    private func composerFocusChanged(to focus: ComposerFocus?) {
        if focus != nil, let height = pendingKeyboardHeight {
            pendingKeyboardHeight = nil
            if let window = chatWindow { rememberKeyboardHeight(height, in: window) }
            setInputDock(height, animation: inputDockAnimation)
        } else if focus == nil, !keyboardShown, !showsChatFunctions {
            setInputDock(0, animation: inputDockAnimation)
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            // Reserve the keyboard and function panel through one layout height.
            // Native keyboard avoidance would apply the same movement a second time.
            let bottomInset = chatWindow?.safeAreaInsets.bottom ?? proxy.safeAreaInsets.bottom
            Group {
                if let learningPage = deps.learningPage {
                    ChatLearningPager(learningSelected: $learningSelected, translation: $learningTranslation,
                                      enabled: recorder.state == .idle && chineseRecorder.state == .idle && wordSelection == nil && grammarTermSelection == nil && !showsRealtimeConversation) {
                        chatPage(bottomInset: bottomInset)
                    } learning: {
                        learningPage(viewModel.character, learningSelected, openChatSettings)
                            .environment(\.dsLearningBackdropProvided, true)
                    }
                } else {
                    chatPage(bottomInset: bottomInset)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboard(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboard(notification)
            }
            .onChange(of: composerFocus) { _, focus in composerFocusChanged(to: focus) }
        }
        .ignoresSafeArea(learningSelected ? [] : [.keyboard, .container], edges: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
            if showsChatFunctions { inputDockHeight = preferredKeyboardHeight }
        }
        .onChange(of: recorder.state) { _, state in
            if case .recording = state { voicePlayer.stop() }
            switch state {
            case .recording, .transcribing: viewModel.composerRecordingChanged(true)
            default: viewModel.composerRecordingChanged(false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voicePlayer.stop() }
            // 用户可能刚在系统设置里下载或删除了语言包。
            if phase == .active {
                Task {
                    await appleTranslator.refreshAvailability()
                    await composerAppleTranslator.refreshAvailability()
                }
            }
        }
        .onChange(of: learningSelected) { _, selected in
            dismissChatInput()
            if selected {
                voicePlayer.stop()
            } else {
                Task { await deps.learningChat?.refresh(characterID: viewModel.character.id) }
            }
        }
        .task(id: learningSelected) {
            // 分页提交后再清理一次 UIKit 焦点，避免恢复可交互性时还原旧 responder。
            await Task.yield()
            guard !Task.isCancelled else { return }
            isTextInputFocused = false; isChineseInputFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if let region = try? await deps.economyStore.profile().currentRegionID, !Task.isCancelled {
                learningRegionID = region
            }
        }
        .dsQuickNotice($viewModel.quickNotice)
        .background {
            ChatLearningBackdrop(regionID: learningRegionID, learningSelected: learningSelected,
                translation: $learningTranslation,
                candy: PuffCandy.stable(for: viewModel.character.displayName))
        }
        .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { notification in
            guard notification.object as? UUID == viewModel.character.id else { return }
            Task { await viewModel.refreshMessages(resumeSharedObservation: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { notification in
            guard notification.object as? UUID == viewModel.character.id else { return }
            Task { await viewModel.refreshCharacter() }
        }
        #if DEBUG
        .alert("无法填满挑战进度", isPresented: Binding(get: { learningDebugError != nil }, set: { if !$0 { learningDebugError = nil } })) {
            Button("知道了", role: .cancel) { learningDebugError = nil }
        } message: { Text(learningDebugError ?? "") }
        #endif
        .tint(learningSelected ? .white : PuffCandy.sky.deep)
        // 顶栏画在页面里，不用系统导航栏：信息列表等蓬蓬页隐藏了系统栏，聊天页若用系统栏，
        // 左缘滑动返回时系统会边滑边隐藏导航栏，返回按钮和头像会脱离页面单独漂移。
        .toolbar(.hidden, for: .navigationBar)
        .chatTopBar { chatTopBar }
        .dsInteractivePopGesture()

        .accessibilityAction(named: "聊天设置", openChatSettings)
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                deps.speakLookupWord(word)
            },
            favoriteActions: wordFavoriteActions,
            aiFallback: aiWordFallback)
        .onChange(of: wordSelection) { _, selection in
            if selection != nil { deps.tutorial?.onEvent("word") }
        }
        .grammarTermLookupOverlay(
            selection: $grammarTermSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints)
        .sheet(item: $grammarAnalysis) { request in
            GrammarAnalysisSheet(
                request: request,
                service: GrammarAnalysisService(llm: deps.llm, sharedAnalysis: deps.sharedGrammarAnalysis),
                initialAIAnalysis: grammarAICache[request.id],
                dictionary: deps.dictionary,
                grammar: deps.grammarPoints,
                favorites: deps.favorites,
                onSpeak: { word in
                    let speech = deps.speech
                    Task {
                        await speech.speak(
                            SpeechRequest(text: word, language: "en-US", purpose: .pronunciation)
                        )
                    }
                },
                favoriteActions: wordFavoriteActions,
                aiFallback: aiWordFallback,
                onAIAnalysis: { analysis in
                    grammarAICache[request.id] = analysis
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsRealtimeConversation, onDismiss: {
            Task { await viewModel.refreshMessages() }
            if accessAfterVoice { accessAfterVoice = false; deps.onShowAccess() }
        }) {
            RealtimeConversationView(
                chat: viewModel,
                deps: deps,
                onSpeechPlayback: {},
                onRequestAccess: { accessAfterVoice = true }
            )
        }
        .sheet(isPresented: $showsContactDetails, onDismiss: {
            guard opensAppointmentsAfterSettings else { return }
            opensAppointmentsAfterSettings = false
            let appointmentID = appointmentAfterSettings
            appointmentAfterSettings = nil
            deps.onOpenAppointment?(appointmentID)
        }) {
            NavigationStack {
                ChatContactDetailsView(
                    viewModel: viewModel,
                    deps: deps,
                    onOpenAppointment: { appointmentID in
                        appointmentAfterSettings = appointmentID
                        opensAppointmentsAfterSettings = true
                        showsContactDetails = false
                    },
                    onSelectMessage: { messageID in
                        learningSelected = false
                        highlightedMessageID = messageID
                        showsContactDetails = false
                    },
                    onRemoved: {
                        showsContactDetails = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            dismiss()
                        }
                    }
                )
            }
        }
        .background {
            ZStack {
                AppleTranslationHost(translator: appleTranslator)
                AppleTranslationHost(translator: composerAppleTranslator)
            }
        }
        .task { await loadConversation() }
        .onChange(of: viewModel.messages.last?.id) {
            markVisibleConversationRead()
        }
        .onChange(of: showsRealtimeConversation || showsContactDetails || wordSelection != nil || grammarTermSelection != nil || grammarAnalysis != nil || isTextInputFocused) { _, presented in
            deps.tutorial?.onEvent(presented ? "presented" : "dismissed")
        }
        .onChange(of: viewModel.messages.contains(where: { $0.role == .assistant })) { _, hasBubble in
            deps.tutorial?.onEvent(hasBubble ? "hasBubble" : "noBubble")
        }
        .onChange(of: autoReadSnapshot) { previous, current in
            autoReadQueue.synchronize(from: previous, to: current)
        }
        .onDisappear {
            voicePlayer.stop()
            viewModel.stopSharedObservation()
            autoReadReady = false
            autoReadQueue.configure(enabled: false, existingIDs: viewModel.messages.map(\.id))
            appleTranslator.cancelAll()
            isChineseInputFocused = false
            composerTranslation.cancel()
            composerAppleTranslator.cancelAll()
            Task { await chineseRecorder.cancelRecording() }
            markVisibleConversationRead()
        }
        .dsInteractiveContentPopGesture(enabled: !learningSelected
            && recorder.state == .idle && chineseRecorder.state == .idle)
        .dsTabBarHidden()
    }

    private func loadConversation() async {
        // 整句翻译优先云端 LLM；离线、额度或供应商失败时回退 Apple 端上翻译。
        viewModel.translationFallback = { [appleTranslator] text in
            return await appleTranslator.translate(text)
        }
        Task {
            await appleTranslator.refreshAvailability()
            await composerAppleTranslator.refreshAvailability()
        }
        await viewModel.load()
        guard !Task.isCancelled else { return }
        autoReadReady = true
        autoReadQueue.configure(enabled: shouldAutoRead, existingIDs: viewModel.messages.map(\.id))
        #if DEBUG
        // Screenshot-only presentation of seeded reviews in the isolated marketing workspace.
        if ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "chat",
           ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1",
           ProcessInfo.processInfo.environment["UI_TEST_MARKETING_CAPTURE"] == "1",
           ProcessInfo.processInfo.environment["UI_TEST_CAPTURE_COACHES"] == "1" {
            expandedCoachMessageIDs = Set(viewModel.messages.filter {
                CoachService.decode(fromJSON: $0.coachReviewJSON)?.hasIssues == true
            }.map(\.id))
        }
        if ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "chat",
           ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1",
           ProcessInfo.processInfo.environment["UI_TEST_CAPTURE_DICTIONARY"] == "1",
           let message = viewModel.messages.first(where: { $0.text.contains("cosy") }),
           let token = TokenCache.tokens(for: message.text, cacheKey: message.id.uuidString).first(where: { $0.word == "cosy" }) {
            try? await Task.sleep(for: .seconds(1))
            wordSelection = TokenSelection(contextID: message.id.uuidString, tokenID: token.id, word: "cosy")
        }
        #endif
        markVisibleConversationRead()
        #if DEBUG
        await viewModel.playMarketingCaptureReply()
        #endif
    }

    /// 聊天页顶栏：返回、旅伴身份、自动朗读与设置；学习页时换成“返回聊天”。随页面整体滑动。
    private var chatTopBar: some View {
        HStack(spacing: 10) {
            ChatTopBarChip {
                Button { dismiss() } label: { ChatTopBarIcon(systemImage: "chevron.left") }
                    .buttonStyle(.puffSquish)
                    .accessibilityLabel("返回")
                    .accessibilityIdentifier("chat.back")
            }
            if learningSelected {
                Spacer(minLength: 0)
                ChatTopBarChip {
                    Button { learningSelected = false } label: { ChatTopBarIcon(systemImage: "bubble.left.and.bubble.right") }
                        .buttonStyle(.puffSquish)
                        .accessibilityLabel("返回聊天")
                }
            } else {
                chatIdentity
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChatTopBarChip {
                    HStack(spacing: 0) {
                        Button { autoReadEnabled.toggle() } label: {
                            ChatTopBarIcon(systemImage: autoReadEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        }
                        .buttonStyle(.puffSquish)
                        .accessibilityLabel(autoReadEnabled ? "关闭自动朗读" : "开启自动朗读")
                        .accessibilityValue(autoReadEnabled ? "开启" : "关闭")
                        .accessibilityIdentifier("chat.autoRead")
                        chatSettingsAction
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.header")
    }

    private var chatIdentity: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let presence = viewModel.presence(at: context.date)
            let status = chatStatus(presence, at: context.date)
            let shortStatus = presence.state == .offline && !viewModel.isStreaming ? "离线" : status
            let city = deps.regionName(viewModel.character.card.regionID)
            let localTime = ChatHeaderStatus.localTime(at: context.date, timeZoneIdentifier: presence.timeZoneIdentifier)
            Button(action: openChatSettings) {
                HStack(spacing: 9) {
                    PuffAvatar(name: viewModel.character.displayName, size: 36,
                        imageName: viewModel.character.card.avatarAssetName,
                        remoteURL: viewModel.character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                        presence: puffPresence(presence))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.character.displayName).font(.puff(.subheadline, Puff.Weight.emphasis))
                            .foregroundStyle(Puff.Palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        ViewThatFits(in: .horizontal) {
                            Text("\(status) · \(city) \(localTime)").fixedSize()
                            Text("\(shortStatus) · \(city) \(localTime)").fixedSize()
                            Text("\(shortStatus) · \(localTime)")
                        }
                        .font(.puff(.caption2, Puff.Weight.label)).foregroundStyle(Puff.Palette.inkSoft)
                        .monospacedDigit()
                        .lineLimit(1).allowsTightening(true).minimumScaleFactor(0.7)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(viewModel.character.displayName)，\(status)，\(city)当地时间 \(localTime)")
            .accessibilityHint("打开聊天设置")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("chat.identity")
        }
    }

    private var chatSettingsButton: some View {
        Button(action: openChatSettings) {
            ChatTopBarIcon(systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel("聊天设置")
        .accessibilityIdentifier("chat.settings")
    }

    @ViewBuilder
    private var chatSettingsAction: some View {
        #if DEBUG
        if let fill = deps.debugFillLearning {
            chatSettingsButton.contextMenu {
                Button {
                    fillingLearning = true
                    Task {
                        defer { fillingLearning = false }
                        do {
                            try await fill(viewModel.character.id)
                            learningSelected = true
                            NotificationCenter.default.post(name: .roleplayConversationDidChange, object: viewModel.character.id)
                        } catch { learningDebugError = error.localizedDescription }
                    }
                } label: { Label("填满挑战进度（开发者）", systemImage: "hammer") }
                .disabled(fillingLearning || recorder.state != .idle || chineseRecorder.state != .idle)
                .accessibilityIdentifier("chat.debugFillLearning")
            }
        } else { chatSettingsButton }
        #else
        chatSettingsButton
        #endif
    }

    func openChatSettings() {
        dismissChatInput()
        voicePlayer.stop()
        showsContactDetails = true
    }

    private var autoReadSnapshot: ChatAutoReadQueue.Snapshot {
        .init(enabled: shouldAutoRead, items: viewModel.messages.sorted {
            $0.orderIndex < $1.orderIndex
        }.compactMap { message in
            guard message.role == .user || message.role == .assistant,
                  message.kind == .text else { return nil }
            return .init(id: message.id, request: viewModel.speechRequest(for: message))
        })
    }

    private var shouldAutoRead: Bool {
        let recording: Bool
        switch recorder.state {
        case .recording, .transcribing: recording = true
        default: recording = false
        }
        return autoReadReady && autoReadEnabled && !learningSelected && scenePhase == .active
            && !showsRealtimeConversation && !showsContactDetails && !showsChatFunctions && !recording
            && wordSelection == nil && grammarTermSelection == nil && grammarAnalysis == nil
            && voicePlayer.playingFileName == nil
            && voicePlayer.loadingMessageID == nil
    }

    private func markVisibleConversationRead() {
        Task {
            await viewModel.markConversationRead(at: viewModel.messages.last?.createdAt ?? .now)
        }
    }

    private func chatStatus(_ presence: NPCPresenceSnapshot, at date: Date) -> String {
        ChatHeaderStatus.text(
            presence: presence,
            at: date,
            isStreaming: viewModel.isStreaming
        )
    }

    private func puffPresence(_ presence: NPCPresenceSnapshot) -> PuffPresence {
        switch presence.state {
        case .online: .online
        case .recentlyActive: .recentlyActive
        case .offline: .offline
        }
    }

}
