import CoreKit
import DesignSystem
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI
import UIKit

/// 设置页：学习、语音与后端 AI 服务状态。
public struct SettingsView: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    private let router: LLMRouter
    private let economyStore: EconomyStore
    private let profileCommands: any ProfileCommandGateway
    private let memoryStore: MemoryStore
    private let rosterStore: RosterStore
    private let chatStore: ChatStore
    private let speech: any SpeechService
    private let onProactiveMessagesChanged: @MainActor (Bool) -> Void
    @State private var testState: TestState = .idle
    @State private var profile: UserProfileDTO?
    @State private var voiceReports: [VoiceReport] = []
    @State private var voiceQuality: VoiceReport.Quality = .standard
    @State private var synthesisEngineStatus = SpeechSynthesisEngineStatus(
        phase: .resourceMissing,
        selectedEngine: .pocketTTS
    )
    @AppStorage(ProactiveMessagePreferences.enabledKey) private var proactiveMessagesEnabled = true
    @Environment(\.openURL) private var openURL

    public init(
        router: LLMRouter,
        economyStore: EconomyStore,
        profileCommands: any ProfileCommandGateway,
        memoryStore: MemoryStore,
        rosterStore: RosterStore,
        chatStore: ChatStore,
        speech: any SpeechService,
        onProactiveMessagesChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.router = router
        self.economyStore = economyStore
        self.profileCommands = profileCommands
        self.memoryStore = memoryStore
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.speech = speech
        self.onProactiveMessagesChanged = onProactiveMessagesChanged
    }

    public var body: some View {
        ZStack {
            DSWorkbenchBackdrop(focus: .settings)

            ScrollView {
                DSWorkbenchPaperSheet(radius: 28, padding: 0) {
                    VStack(spacing: 0) {
                        journeySummary
                        paperSectionDivider
                        learningAndReminderPanel
                        paperSectionDivider
                        offlineVoicePanel
                        paperSectionDivider
                        systemVoicePanel
                        paperSectionDivider
                        servicePanel
                        paperSectionDivider
                        creditsPanel
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .animation(DSAnimation.snappy, value: testState)
        .task {
            await reloadProfile()
        }
        .task {
            reloadVoiceInfo()
        }
        .task {
            await observeOfflineVoiceStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // 从系统设置下载语音回来后，刷新音源并让新音质立即生效。
            reloadVoiceInfo()
            Task { await speech.refreshVoices() }
        }
        .onChange(of: proactiveMessagesEnabled) { _, enabled in
            onProactiveMessagesChanged(enabled)
        }
    }

    private var journeySummary: some View {
        HStack(spacing: DSSpacing.lg) {
            DSObsidianMedallion(systemImage: "bell", size: 72)

            VStack(alignment: .leading, spacing: 7) {
                Text("旅程设置")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.dsPaperInk)
                Label(reminderSummary, systemImage: reminderSummaryIcon)
                Label("Pocket TTS · \(offlineVoicePhaseLabel)", systemImage: "waveform.circle.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.dsPaperInkSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, 26)
    }

    private var reminderSummary: String {
        let quizEnabled = profile?.quizGloballyEnabled == true
        let activeCount = (quizEnabled ? 1 : 0) + (proactiveMessagesEnabled ? 1 : 0)
        return switch activeCount {
        case 0: "学习提醒已暂停"
        case 1: "1 项学习提醒已开启"
        default: "2 项学习提醒已开启"
        }
    }

    private var reminderSummaryIcon: String {
        reminderSummary == "学习提醒已暂停" ? "pause.circle.fill" : "checkmark.circle.fill"
    }

    private var learningAndReminderPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelTitle("学习与提醒", systemImage: "bell.and.waves.left.and.right")

            if profile != nil {
                settingsToggle(
                    "聊天中随机出题",
                    detail: "在对话中偶尔加入一道轻量练习",
                    isOn: quizEnabledBinding
                )
                panelDivider
            }

            settingsToggle(
                "角色主动联系",
                detail: "好友只会在白天偶尔发起适合练习的话题",
                isOn: $proactiveMessagesEnabled
            )

            panelDivider

            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            } label: {
                settingsLinkLabel("系统通知设置", systemImage: "bell.badge")
            }
            .buttonStyle(.plain)
        }
        .padding(DSSpacing.lg)
    }

    // MARK: - 语音引擎

    @ViewBuilder
    private var offlineVoicePanel: some View {
        if let manager = speech as? any SpeechSynthesisEngineManaging {
            VStack(alignment: .leading, spacing: 0) {
                    panelTitle("语音工作室", systemImage: "waveform")

                    settingsValueRow("语音识别", value: "Apple 系统识别")
                    panelDivider

                    Picker(
                        "语音合成",
                        selection: Binding(
                            get: { synthesisEngineStatus.selectedEngine },
                            set: { engine in
                                Task { await manager.selectSynthesisEngine(engine) }
                            }
                        )
                    ) {
                        ForEach(SpeechSynthesisEngine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.dsSkyDeep)
                    .frame(minHeight: 52)
                    .disabled(
                        synthesisEngineStatus.isBusy
                            || !synthesisEngineStatus.isBundledModelAvailable
                    )

                    panelDivider

                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                        Text("内置 TTS")
                            .font(.body.weight(.medium))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Pocket TTS · \(formattedBytes(synthesisEngineStatus.bundledModelBytes))")
                                .font(.subheadline)
                                .foregroundStyle(Color.dsPaperInkSecondary)
                            Text(offlineVoicePhaseLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(offlineVoicePhaseTint)
                        }
                    }
                    .frame(minHeight: 52)

                    if synthesisEngineStatus.phase == .loading {
                        Label("正在预热离线语音模型…", systemImage: "hourglass")
                            .font(.footnote)
                            .foregroundStyle(Color.dsPaperInkSecondary)
                            .padding(.bottom, DSSpacing.sm)
                    }

                    if let message = synthesisEngineStatus.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.dsWarning)
                            .padding(.bottom, DSSpacing.sm)
                    }

                    panelDivider

                    VStack(spacing: 0) {
                        voicePreviewButton("试听系统语音", systemImage: "waveform") {
                            Task {
                                await speech.speak(
                                    SpeechRequest(
                                        text: "Hey! It's lovely to meet you. Fancy exploring the city together?",
                                        language: "en-GB",
                                        purpose: .characterDialogue,
                                        voiceHint: previewVoiceHint,
                                        engine: .system
                                    )
                                )
                            }
                        }

                        panelDivider

                        voicePreviewButton("试听 Pocket TTS", systemImage: "waveform") {
                            Task {
                                await speech.speak(
                                    SpeechRequest(
                                        text: "Hey! It's lovely to meet you. Fancy exploring the city together?",
                                        language: "en-GB",
                                        purpose: .characterDialogue,
                                        voiceHint: previewVoiceHint,
                                        engine: .pocketTTS
                                    )
                                )
                            }
                        }
                        .disabled(
                            !synthesisEngineStatus.isBundledModelAvailable
                                || synthesisEngineStatus.isBusy
                        )
                    }

                    panelDivider

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text("实时语音使用 Apple 系统识别。Pocket TTS 完全离线；系统识别会优先端侧处理，当前语言模型不可用时可能使用网络。")
                                .font(.footnote)
                                .foregroundStyle(Color.dsPaperInkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Link(
                                "Pocket TTS 与开源许可",
                                destination: URL(string: "https://github.com/kyutai-labs/pocket-tts")!
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, DSSpacing.sm)
                    } label: {
                        Text("语音隐私与许可")
                            .font(.body.weight(.medium))
                    }
                    .tint(Color.dsSkyDeep)
            }
            .foregroundStyle(Color.dsPaperInk)
            .padding(DSSpacing.lg)
        }
    }

    private var systemVoicePanel: some View {
        DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    settingsValueRow("当前英语语音", value: voiceQuality.label)
                    panelDivider

                    ForEach(voiceReports) { report in
                        settingsValueRow(
                            report.accentLabel,
                            value: [report.voiceName, report.quality.label]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                        )
                    }

                    Button {
                        Task {
                            await speech.speak(
                                SpeechRequest(
                                    text: "Hello! This is how I sound. Nice to meet you.",
                                    language: "en-US",
                                    engine: .system
                                )
                            )
                        }
                    } label: {
                        settingsLinkLabel("试听当前语音", systemImage: "play.circle")
                    }
                    .buttonStyle(.plain)

                    if !voiceQuality.isNatural {
                        panelDivider
                        Button {
                            if let url = VoiceSettingsNavigation.prepareToOpenSettings() {
                                openURL(url)
                            }
                        } label: {
                            settingsLinkLabel("下载更自然的系统语音", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.plain)
                    }

                    Text(
                        voiceQuality.isNatural
                            ? "已启用增强或高级音质。"
                            : "可在系统设置的辅助功能中下载增强或高级英语语音。"
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.dsPaperInkSecondary)
                    .padding(.top, DSSpacing.sm)
                }
                .padding(.top, DSSpacing.sm)
            } label: {
                panelTitle("Apple 系统语音详情", systemImage: "slider.horizontal.3")
            }
            .tint(Color.dsSkyDeep)
            .foregroundStyle(Color.dsPaperInk)
            .padding(DSSpacing.lg)
    }

    private var servicePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
                panelTitle("AI 服务", systemImage: "network")
                settingsValueRow("连接方式", value: "安全后端中转")
                panelDivider
                settingsValueRow("模型策略", value: "服务端按任务配置")
                panelDivider

                Button {
                    runConnectionTest()
                } label: {
                    HStack {
                        Label("测试 AI 服务", systemImage: "bolt.horizontal.circle")
                        Spacer()
                        if testState == .testing { ProgressView() }
                    }
                    .frame(minHeight: 48)
                    .foregroundStyle(Color.dsSkyDeep)
                }
                .buttonStyle(.plain)
                .disabled(testState == .testing)

                switch testState {
                case .idle, .testing:
                    EmptyView()
                case .success(let reply):
                    Label("服务可用：\(reply)", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.dsSuccess)
                case .failure(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.dsDanger)
                }

                Text("供应商密钥、模型和配额只保存在服务端，不会下发到设备。")
                    .font(.footnote)
                    .foregroundStyle(Color.dsPaperInkSecondary)
                    .padding(.top, DSSpacing.sm)
        }
        .foregroundStyle(Color.dsPaperInk)
        .padding(DSSpacing.lg)
    }

    private var creditsPanel: some View {
        NavigationLink {
            CityScenePhotoCreditsView()
        } label: {
            settingsLinkLabel("背景照片与开源许可", systemImage: "photo.on.rectangle.angled")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
    }

    private func panelTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.dsPaperInk)
            .padding(.bottom, DSSpacing.sm)
    }

    private var panelDivider: some View {
        Divider().overlay(Color.dsPaperInk.opacity(0.12))
    }

    private var paperSectionDivider: some View {
        Divider()
            .overlay(Color.dsPaperInk.opacity(0.16))
            .padding(.horizontal, DSSpacing.lg)
    }

    private func settingsToggle(
        _ title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.dsPaperInk)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.dsPaperInkSecondary)
            }
        }
        .tint(Color.dsSkyDeep)
        .frame(minHeight: 64)
    }

    private func settingsValueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.dsPaperInk)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.dsPaperInkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 52)
    }

    private func settingsLinkLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
        }
        .font(.body.weight(.medium))
        .foregroundStyle(Color.dsSkyDeep)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func voicePreviewButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "play.circle")
                    .font(.title3)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dsTravelNavy)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reloadVoiceInfo() {
        voiceReports = AppleTTSService.voiceReports()
        voiceQuality = AppleTTSService.bestAvailableEnglishQuality()
    }

    private func observeOfflineVoiceStatus() async {
        guard let manager = speech as? any SpeechSynthesisEngineManaging else { return }
        synthesisEngineStatus = await manager.synthesisEngineStatus()
        let updates = await manager.synthesisEngineStatusUpdates()
        for await update in updates {
            if Task.isCancelled { return }
            synthesisEngineStatus = update
        }
    }

    private var previewVoiceHint: SpeechVoiceHint {
        SpeechVoiceHint(
            stableID: "settings-voice-preview",
            gender: "female",
            nationality: "British"
        )
    }

    private var offlineVoicePhaseLabel: String {
        switch synthesisEngineStatus.phase {
        case .resourceMissing: "资源缺失"
        case .available:
            synthesisEngineStatus.selectedEngine == .pocketTTS ? "待预热" : "已打包"
        case .loading: "预热中"
        case .ready: "可用"
        case .failed: "加载失败"
        }
    }

    private var offlineVoicePhaseTint: Color {
        switch synthesisEngineStatus.phase {
        case .ready: .green
        case .failed: .orange
        default: .secondary
        }
    }

    private func formattedBytes(_ count: Int64) -> String {
        guard count > 0 else { return "331 MB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
    }

    private var quizEnabledBinding: Binding<Bool> {
        Binding(
            get: { profile?.quizGloballyEnabled ?? true },
            set: { newValue in
                Task {
                    profile = try? await profileCommands.updateProfile {
                        $0.quizGloballyEnabled = newValue
                    }
                }
            }
        )
    }

    private func reloadProfile() async {
        profile = try? await economyStore.profile()
    }

    private func runConnectionTest() {
        testState = .testing
        Task {
            do {
                let reply = try await router.testConnection()
                testState = .success(String(reply.prefix(40)))
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}
