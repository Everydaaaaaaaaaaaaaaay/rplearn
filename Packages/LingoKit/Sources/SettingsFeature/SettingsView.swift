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
    private let onOpenPhotoCredits: (@MainActor () -> Void)?
    private let onOpenTutorial: (@MainActor () -> Void)?
    private let onOpenIntroduction: (@MainActor () -> Void)?
    private let onTestInitialPlacement: (@MainActor () -> Void)?
    private let onTestFirstLoginFlow: (@MainActor () -> Void)?
    private let onTestAppointments: (@MainActor () -> Void)?
    private let onOpenLearningTrial: (@MainActor () -> Void)?
    @State private var testState: TestState = .idle
    @State private var profile: UserProfileDTO?
    @State private var voiceReports: [VoiceReport] = []
    @State private var voiceQuality: VoiceReport.Quality = .standard
    @State private var synthesisEngineStatus = SpeechSynthesisEngineStatus(
        phase: .resourceMissing,
        selectedEngine: .supertonic3
    )
    @AppStorage private var proactiveMessagesEnabled: Bool
    @Environment(\.openURL) private var openURL

    public init(
        accountID: UUID,
        router: LLMRouter,
        economyStore: EconomyStore,
        profileCommands: any ProfileCommandGateway,
        memoryStore: MemoryStore,
        rosterStore: RosterStore,
        chatStore: ChatStore,
        speech: any SpeechService,
        onProactiveMessagesChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onOpenPhotoCredits: (@MainActor () -> Void)? = nil,
        onOpenIntroduction: (@MainActor () -> Void)? = nil,
        onOpenTutorial: (@MainActor () -> Void)? = nil,
        onTestInitialPlacement: (@MainActor () -> Void)? = nil,
        onTestFirstLoginFlow: (@MainActor () -> Void)? = nil,
        onTestAppointments: (@MainActor () -> Void)? = nil,
        onOpenLearningTrial: (@MainActor () -> Void)? = nil
    ) {
        _proactiveMessagesEnabled = AppStorage(
            wrappedValue: true,
            ProactiveMessagePreferences.enabledKey(for: accountID)
        )
        self.router = router
        self.economyStore = economyStore
        self.profileCommands = profileCommands
        self.memoryStore = memoryStore
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.speech = speech
        self.onProactiveMessagesChanged = onProactiveMessagesChanged
        self.onOpenPhotoCredits = onOpenPhotoCredits
        self.onOpenIntroduction = onOpenIntroduction
        self.onOpenTutorial = onOpenTutorial
        self.onTestInitialPlacement = onTestInitialPlacement
        self.onTestFirstLoginFlow = onTestFirstLoginFlow
        self.onTestAppointments = onTestAppointments
        self.onOpenLearningTrial = onOpenLearningTrial
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Puff.Space.m) {
                journeySummary
                learningAndReminderPanel
                offlineVoicePanel
                systemVoicePanel
                servicePanel
                extraLinksPanel
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, Puff.Space.m)
            .padding(.top, Puff.Space.xs)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Puff.Palette.page.ignoresSafeArea())
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .tint(PuffCandy.sky.base)
        .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: false), value: testState)
        .task {
            await reloadProfile()
        }
        .task {
            await reloadVoiceInfo()
        }
        .task {
            await observeOfflineVoiceStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // 从系统设置下载语音回来后，刷新音源并让新音质立即生效。
            Task {
                await reloadVoiceInfo()
                await speech.refreshVoices()
            }
        }
        .onChange(of: proactiveMessagesEnabled) { _, enabled in
            onProactiveMessagesChanged(enabled)
        }
    }

    private var journeySummary: some View {
        HStack(spacing: Puff.Space.m) {
            PuffIconBubble("slider.horizontal.3", candy: .sky, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text("旅程设置")
                    .font(.puff(.title2, Puff.Weight.display))
                    .foregroundStyle(Puff.Palette.ink)
                PuffTag(reminderSummary, systemImage: reminderSummaryIcon,
                        candy: proactiveMessagesEnabled ? .mint : .grape)
                PuffTag("Supertonic-3 · \(offlineVoicePhaseLabel)", systemImage: "waveform", candy: .sky)
            }
            Spacer(minLength: 0)
        }
        .padding(Puff.Space.m)
        .puffCard(radius: Puff.Radius.huge)
    }

    private var reminderSummary: String {
        proactiveMessagesEnabled ? "角色主动联系已开启" : "角色主动联系已暂停"
    }

    private var reminderSummaryIcon: String {
        !proactiveMessagesEnabled ? "pause.circle.fill" : "checkmark.circle.fill"
    }

    private var learningAndReminderPanel: some View {
        settingsCard {
            panelTitle("消息提醒", systemImage: "bell.fill", candy: .bubblegum)

            settingsToggle("角色主动联系", isOn: $proactiveMessagesEnabled)

            panelDivider

            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            } label: {
                settingsLinkLabel("系统通知设置", systemImage: "bell.badge.fill", external: true)
            }
            .buttonStyle(.puffRow)
        }
    }

    // MARK: - 语音引擎

    @ViewBuilder
    private var offlineVoicePanel: some View {
        if let manager = speech as? any SpeechSynthesisEngineManaging {
            settingsCard {
                panelTitle("语音工作室", systemImage: "waveform", candy: .grape)

                settingsValueRow("语音识别", value: "Apple 系统识别")
                panelDivider

                HStack {
                    Text("语音合成")
                        .font(.puff(.body, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.ink)
                    Spacer()
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
                    .tint(PuffCandy.grape.deep)
                    .labelsHidden()
                }
                .frame(minHeight: 52)
                .disabled(
                    synthesisEngineStatus.isBusy
                        || !synthesisEngineStatus.isBundledModelAvailable
                )

                panelDivider

                HStack(alignment: .center, spacing: Puff.Space.s) {
                    Text("内置 TTS")
                        .font(.puff(.body, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.ink)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Supertonic-3 · \(formattedBytes(synthesisEngineStatus.bundledModelBytes))")
                            .font(.puff(.subheadline, Puff.Weight.label))
                            .foregroundStyle(Puff.Palette.inkSoft)
                        Text(offlineVoicePhaseLabel)
                            .font(.puff(.caption, Puff.Weight.emphasis))
                            .foregroundStyle(offlineVoicePhaseTint)
                    }
                }
                .frame(minHeight: 52)

                if synthesisEngineStatus.phase == .loading {
                    PuffTag("正在预热离线语音模型", systemImage: "hourglass", candy: .sunny)
                        .padding(.bottom, Puff.Space.s)
                }

                if let message = synthesisEngineStatus.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.puff(.footnote, Puff.Weight.label))
                        .foregroundStyle(PuffCandy.tangerine.deep)
                        .padding(.bottom, Puff.Space.s)
                }

                panelDivider

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

                voicePreviewButton("试听 Supertonic-3 整句", systemImage: "waveform") {
                    Task {
                        await speech.speak(
                            SpeechRequest(
                                text: "Hey! It's lovely to meet you. Fancy exploring the city together?",
                                language: "en-US",
                                purpose: .characterDialogue,
                                voiceHint: previewVoiceHint,
                                engine: .supertonic3
                            )
                        )
                    }
                }
                .disabled(
                    !synthesisEngineStatus.isBundledModelAvailable
                        || synthesisEngineStatus.isBusy
                )

                panelDivider

                voicePreviewButton("试听 Supertonic-3 单词", systemImage: "textformat.abc") {
                    Task {
                        await speech.speak(
                            SpeechRequest(
                                text: "extraordinary",
                                language: "en-US",
                                purpose: .pronunciation,
                                engine: .supertonic3
                            )
                        )
                    }
                }
                .disabled(
                    !synthesisEngineStatus.isBundledModelAvailable
                        || synthesisEngineStatus.isBusy
                )

                panelDivider

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Puff.Space.s) {
                        Text("Supertonic-3 完全离线，生成内容属于机器合成语音；实时识别仍使用 Apple 系统能力，当前语言模型不可用时可能使用网络。")
                            .font(.puff(.footnote, Puff.Weight.body))
                            .foregroundStyle(Puff.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Link(
                            "Supertonic-3 模型与 OpenRAIL-M 许可",
                            destination: URL(string: "https://huggingface.co/Supertone/supertonic-3")!
                        )
                        .font(.puff(.subheadline, Puff.Weight.emphasis))
                        .foregroundStyle(PuffCandy.sky.deep)
                    }
                    .padding(.top, Puff.Space.xs)
                    .padding(.bottom, Puff.Space.s)
                } label: {
                    settingsDisclosureLabel("语音隐私与许可", systemImage: "lock.shield.fill")
                }
                .tint(Puff.Palette.inkSoft)
            }
        }
    }

    private var systemVoicePanel: some View {
        settingsCard {
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
                        settingsLinkLabel("试听当前语音", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.puffRow)

                    if !voiceQuality.isNatural {
                        panelDivider
                        Button {
                            if let url = VoiceSettingsNavigation.prepareToOpenSettings() {
                                openURL(url)
                            }
                        } label: {
                            settingsLinkLabel("下载更自然的系统语音", systemImage: "arrow.down.circle.fill", external: true)
                        }
                        .buttonStyle(.puffRow)
                    }
                }
                .padding(.top, Puff.Space.xs)
            } label: {
                panelTitle("Apple 系统语音", systemImage: "slider.horizontal.3", candy: .tangerine)
                    .padding(.bottom, -Puff.Space.s)
            }
            .tint(Puff.Palette.inkSoft)
        }
    }

    private var servicePanel: some View {
        settingsCard {
            panelTitle("AI 服务", systemImage: "network", candy: .mint)
            settingsValueRow("连接方式", value: "安全后端中转")
            panelDivider
            settingsValueRow("模型策略", value: "服务端按任务配置")
            panelDivider

            Button {
                runConnectionTest()
            } label: {
                HStack {
                    Label("测试 AI 服务", systemImage: "bolt.horizontal.circle.fill")
                    Spacer()
                    if testState == .testing {
                        PuffLoadingDots().scaleEffect(0.6).frame(width: 40, height: 20)
                    }
                }
                .font(.puff(.body, Puff.Weight.emphasis))
                .foregroundStyle(PuffCandy.sky.deep)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.puffRow)
            .disabled(testState == .testing)

            switch testState {
            case .idle, .testing:
                EmptyView()
            case .success(let reply):
                Label("服务可用：\(reply)", systemImage: "checkmark.circle.fill")
                    .font(.puff(.footnote, Puff.Weight.label))
                    .foregroundStyle(PuffCandy.mint.deep)
                    .padding(.bottom, Puff.Space.s)
                    .transition(.puffPop)
            case .failure(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.puff(.footnote, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.cherry)
                    .padding(.bottom, Puff.Space.s)
                    .transition(.puffPop)
            }
        }
    }

    /// 调试入口、教程与许可。
    private var extraLinksPanel: some View {
        settingsCard {
            if let onOpenLearningTrial {
                Button(action: onOpenLearningTrial) {
                    settingsLinkLabel("学习实测 · 切换档位做题", systemImage: "book.pages.fill")
                }
                .buttonStyle(.puffRow)
                .accessibilityIdentifier("me.learning-trial")
                panelDivider
            }
            if let onTestInitialPlacement {
                Button(action: onTestInitialPlacement) {
                    settingsLinkLabel("测试初次水平测评", systemImage: "checklist")
                }
                .buttonStyle(.puffRow)
                .accessibilityIdentifier("settings.test-initial-placement")
                panelDivider
            }
            if let onTestFirstLoginFlow {
                Button(action: onTestFirstLoginFlow) {
                    settingsLinkLabel("测试首次登录完整流程", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .buttonStyle(.puffRow)
                .accessibilityIdentifier("settings.test-first-login")
                panelDivider
            }
            if let onTestAppointments {
                Button(action: onTestAppointments) {
                    settingsLinkLabel("测试原生赴约", systemImage: "calendar.badge.checkmark")
                }
                .buttonStyle(.puffRow)
                .accessibilityIdentifier("settings.test-appointments")
                panelDivider
            }
            if let onOpenTutorial {
                Button(action: onOpenTutorial) {
                    settingsLinkLabel("上手练习", systemImage: "hand.tap.fill")
                }
                .buttonStyle(.puffRow)
                .accessibilityIdentifier("settings.tutorial")
                panelDivider
            }
            if let onOpenIntroduction {
                Button(action: onOpenIntroduction) {
                    settingsLinkLabel("重看旅程介绍", systemImage: "book.fill")
                }
                .buttonStyle(.puffRow)
                .accessibilityIdentifier("settings.introduction")
                panelDivider
            }
            creditsPanel
        }
    }

    @ViewBuilder
    private var creditsPanel: some View {
        if let onOpenPhotoCredits {
            Button(action: onOpenPhotoCredits) {
                settingsLinkLabel("背景照片与开源许可", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.puffRow)
        } else {
            NavigationLink {
                CityScenePhotoCreditsView()
            } label: {
                settingsLinkLabel("背景照片与开源许可", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.puffRow)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, Puff.Space.m)
        .padding(.vertical, Puff.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .puffCard(radius: Puff.Radius.huge)
    }

    private func panelTitle(_ title: String, systemImage: String, candy: PuffCandy) -> some View {
        HStack(spacing: 10) {
            PuffIconBubble(systemImage, candy: candy, size: 34)
            Text(title)
                .font(.puff(.headline, Puff.Weight.title))
                .foregroundStyle(Puff.Palette.ink)
        }
        .padding(.vertical, Puff.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var panelDivider: some View {
        Rectangle().fill(Puff.Palette.line).frame(height: 1)
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.puff(.body, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.ink)
        }
        .tint(PuffCandy.mint.base)
        .frame(minHeight: 56)
    }

    private func settingsValueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Puff.Space.s) {
            Text(title)
                .font(.puff(.body, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.ink)
            Spacer()
            Text(value)
                .font(.puff(.subheadline, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.inkSoft)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 52)
    }

    private func settingsLinkLabel(_ title: String, systemImage: String, external: Bool = false) -> some View {
        HStack(spacing: Puff.Space.s) {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 13, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(Puff.Palette.inkFaint)
        }
        .font(.puff(.body, Puff.Weight.emphasis))
        .foregroundStyle(PuffCandy.sky.deep)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func settingsDisclosureLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.puff(.body, Puff.Weight.emphasis))
            .foregroundStyle(PuffCandy.sky.deep)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func voicePreviewButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Puff.Space.s) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(Puff.Palette.ink)
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: Puff.Weight.icon))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(PuffCandy.grape.base, in: Circle())
            }
            .font(.puff(.subheadline, Puff.Weight.emphasis))
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.puffRow)
    }

    private func reloadVoiceInfo() async {
        let snapshot = await Task.detached(priority: .userInitiated) {
            AppleTTSService.voiceCatalogSnapshot()
        }.value
        guard !Task.isCancelled else { return }
        voiceReports = snapshot.reports
        voiceQuality = snapshot.bestQuality
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
            synthesisEngineStatus.selectedEngine == .system ? "已打包" : "待预热"
        case .loading: "预热中"
        case .ready: "可用"
        case .failed: "加载失败"
        }
    }

    private var offlineVoicePhaseTint: Color {
        switch synthesisEngineStatus.phase {
        case .ready: PuffCandy.mint.deep
        case .failed: PuffCandy.tangerine.deep
        default: Puff.Palette.inkSoft
        }
    }

    private func formattedBytes(_ count: Int64) -> String {
        guard count > 0 else { return "约 172 MB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
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
