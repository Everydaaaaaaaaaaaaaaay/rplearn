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
    @State private var viewportWidth: CGFloat = 390
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
    @State var bubbleMenuMessage: MessageDTO?
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
                bubbleMenuMessage: $bubbleMenuMessage, composerFocus: $composerFocus,
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
        withAnimation(inputDockAnimation) {
            showsChatFunctions = false
            inputDockHeight = 0
            composerFocus = nil
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func updateKeyboard(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        guard let window = chatWindow else { return }
        let localFrame = window.convert(frame, from: window.screen.coordinateSpace)
        // Floating and external keyboards do not reserve the bottom of the conversation.
        let height = localFrame.maxY >= window.bounds.maxY - 1 ? max(0, window.bounds.maxY - localFrame.minY) : 0
        if height > 0, composerFocus != nil {
            if window.bounds.width > window.bounds.height { landscapeKeyboardHeight = height }
            else { portraitKeyboardHeight = height }
        }
        guard height == 0 || composerFocus != nil else { return }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 7
        let animation: Animation
        switch curve {
        case 0: animation = .easeInOut(duration: duration)
        case 1: animation = .easeIn(duration: duration)
        case 2: animation = .easeOut(duration: duration)
        case 3: animation = .linear(duration: duration)
        default: animation = .interpolatingSpring(duration: max(0.2, duration), bounce: 0)
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : animation) {
            if !showsChatFunctions { inputDockHeight = height }
        }
        if height == 0 { bubbleMenuMessage = nil }
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
        }
        .ignoresSafeArea(learningSelected ? [] : [.keyboard, .container], edges: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            viewportWidth = $0
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
        }
        .onChange(of: learningSelected) { _, selected in
            bubbleMenuMessage = nil
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
            GeometryReader { viewport in
                // Share the gesture state rather than copying progress through onChange:
                // keyboard dismissal and gesture reset must resolve to the same final page.
                let reveal = (learningSelected ? 1 : 0) - learningTranslation / max(viewport.size.width, 1)
                ZStack {
                    Color.dsBackground
                    DSLearningSceneBackdrop(regionID: learningRegionID)
                        .opacity(min(1, max(0, reveal)))
                }
            }
            .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.28, extraBounce: 0), value: learningSelected)
        }
        .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { notification in
            guard notification.object as? UUID == viewModel.character.id else { return }
            Task { await viewModel.refreshMessages() }
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
        .toolbarBackground(learningSelected ? .hidden : .automatic, for: .navigationBar)
        .toolbarColorScheme(learningSelected ? .dark : nil, for: .navigationBar)
        .tint(learningSelected ? .white : .accentColor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            chatIdentityToolbar
            if learningSelected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { learningSelected = false } label: {
                        Image(systemName: "bubble.left.and.bubble.right").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回聊天")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { autoReadEnabled.toggle() } label: {
                        Image(systemName: autoReadEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(autoReadEnabled ? "关闭自动朗读" : "开启自动朗读")
                    .accessibilityValue(autoReadEnabled ? "开启" : "关闭")
                    .accessibilityIdentifier("chat.autoRead")
                }
                ToolbarItem(placement: .topBarTrailing) { chatSettingsAction }
            }
        }

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
        .task {
            // 整句翻译优先云端 LLM；离线、额度或供应商失败时回退 Apple 端上翻译。
            viewModel.translationFallback = { [appleTranslator] text in
                return await appleTranslator.translate(text)
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
        .dsTabBarHidden()
    }

    @ToolbarContentBuilder
    private var chatIdentityToolbar: some ToolbarContent {
        if !learningSelected {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .topBarLeading) { chatIdentity }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { chatIdentity }
            }
        }
    }

    private var chatIdentity: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let presence = viewModel.presence(at: context.date)
            Button(action: openChatSettings) {
                HStack(spacing: 9) {
                    AvatarBadge(name: viewModel.character.displayName, size: 34,
                        imageName: viewModel.character.card.avatarAssetName,
                        remoteURL: viewModel.character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                        usesPendingPlaceholder: true)
                    headerText(presence, at: context.date)
                }
            }
            .buttonStyle(.plain)
            .frame(width: max(44, viewportWidth - 188), alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(viewModel.character.displayName)，\(chatStatus(presence, at: context.date))，\(deps.regionName(viewModel.character.card.regionID))当地时间 \(ChatHeaderStatus.localTime(at: context.date, timeZoneIdentifier: presence.timeZoneIdentifier))")
            .accessibilityHint("打开聊天设置")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("chat.identity")
        }
    }

    private func headerText(_ presence: NPCPresenceSnapshot, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(viewModel.character.displayName).font(.subheadline.bold())
                .lineLimit(1).minimumScaleFactor(0.85)
            HStack(spacing: 5) {
                Circle().fill(presenceColor(presence)).frame(width: 7, height: 7)
                Text(chatStatus(presence, at: date))
                Text("·")
                Text("\(deps.regionName(viewModel.character.card.regionID)) \(ChatHeaderStatus.localTime(at: date, timeZoneIdentifier: presence.timeZoneIdentifier))")
                    .monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.secondary)
            .lineLimit(1).allowsTightening(true).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chatSettingsButton: some View {
        Button(action: openChatSettings) {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func presenceColor(_ presence: NPCPresenceSnapshot) -> Color {
        switch presence.state {
        case .online: Color.dsSuccess
        case .recentlyActive: Color.dsSunset
        case .offline: Color.secondary.opacity(0.55)
        }
    }

}
