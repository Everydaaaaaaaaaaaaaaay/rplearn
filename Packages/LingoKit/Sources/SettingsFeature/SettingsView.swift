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
    @AppStorage(VoiceEnginePreferences.recognitionEngineKey)
    private var recognitionEngineRaw = SpeechRecognitionEngine.enhancedOnDevice.rawValue
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
        Form {
            learningSection
            proactiveMessagesSection
            offlineVoiceSection
            voiceSection
            Section {
                LabeledContent("连接方式", value: "安全后端中转")
                LabeledContent("模型策略", value: "服务端按任务配置")
                Button {
                    runConnectionTest()
                } label: {
                    HStack {
                        Text("测试 AI 服务")
                        Spacer()
                        if testState == .testing {
                            ProgressView()
                        }
                    }
                }
                .disabled(testState == .testing)

                switch testState {
                case .idle, .testing:
                    EmptyView()
                case .success(let reply):
                    Label("服务可用：\(reply)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("AI 服务")
            } footer: {
                Text("供应商密钥、模型和配额只保存在服务端，不会下发到设备。")
            }
        }
        .navigationTitle("设置")
        .animation(.default, value: testState)
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

    private var proactiveMessagesSection: some View {
        Section {
            Toggle("角色主动联系", isOn: $proactiveMessagesEnabled)
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("系统通知设置", systemImage: "bell.badge")
            }
        } header: {
            Text("消息提醒")
        } footer: {
            Text("好友会偶尔主动聊起适合练习英语的话题。通常间隔数天，只在白天提醒；关闭后会取消尚未发送的消息。")
        }
    }

    // MARK: - 语音引擎

    @ViewBuilder
    private var offlineVoiceSection: some View {
        if let manager = speech as? any SpeechSynthesisEngineManaging {
            Section {
                Picker("语音识别（ASR）", selection: recognitionEngineBinding) {
                    ForEach(SpeechRecognitionEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }

                Picker(
                    "语音合成（TTS）",
                    selection: Binding(
                        get: {
                            synthesisEngineStatus.selectedEngine
                        },
                        set: { engine in
                            Task {
                                await manager.selectSynthesisEngine(engine)
                            }
                        }
                    )
                ) {
                    ForEach(SpeechSynthesisEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                .disabled(
                    synthesisEngineStatus.isBusy
                        || !synthesisEngineStatus.isBundledModelAvailable
                )

                LabeledContent("内置 ASR", value: "Parakeet + SenseVoice · 464 MB")
                LabeledContent("内置 TTS") {
                    HStack(spacing: 6) {
                        Text("Pocket TTS · \(formattedBytes(synthesisEngineStatus.bundledModelBytes))")
                            .foregroundStyle(.secondary)
                        Text(offlineVoicePhaseLabel)
                            .foregroundStyle(offlineVoicePhaseTint)
                            .font(.caption)
                    }
                }

                if synthesisEngineStatus.phase == .loading {
                    HStack {
                        ProgressView()
                        Text("正在预热 Pocket TTS Core ML 模型…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = synthesisEngineStatus.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button {
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
                } label: {
                    Label("试听 Apple 系统语音", systemImage: "play.circle")
                }

                Button {
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
                } label: {
                    Label("试听 Pocket TTS", systemImage: "waveform.circle")
                }
                .disabled(
                    !synthesisEngineStatus.isBundledModelAvailable
                        || synthesisEngineStatus.isBusy
                )

                Link(
                    "Pocket TTS 与开源许可",
                    destination: URL(string: "https://github.com/kyutai-labs/pocket-tts")!
                )
            } header: {
                Text("语音引擎对比")
            } footer: {
                Text("两套外置模型均已随 App 安装，不会再下载。ASR 选择从下一次实时语音会话生效；TTS 选择立即生效，也可用上方按钮在不改设置的情况下试听。内置模型完全离线；Apple 系统识别会优先端侧处理，但在当前语言模型不可用时可能使用网络。")
            }
        }
    }

    private var voiceSection: some View {
        Section {
            LabeledContent("当前英语语音") {
                Text(voiceQuality.label)
                    .foregroundStyle(voiceQuality.isNatural ? .green : .orange)
                    .fontWeight(.medium)
            }
            ForEach(voiceReports) { report in
                LabeledContent(report.accentLabel) {
                    HStack(spacing: 6) {
                        if let name = report.voiceName {
                            Text(name).foregroundStyle(.secondary)
                        }
                        Text(report.quality.label)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (report.quality.isNatural ? Color.green : Color.orange).opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(report.quality.isNatural ? .green : .orange)
                    }
                }
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
                Label("试听当前语音", systemImage: "play.circle")
            }
            if !voiceQuality.isNatural {
                Button {
                    if let url = VoiceSettingsNavigation.prepareToOpenSettings() {
                        openURL(url)
                    }
                } label: {
                    Label(
                        "复制“\(VoiceSettingsNavigation.searchTerm)”并打开设置",
                        systemImage: "arrow.down.circle"
                    )
                }
            }
        } header: {
            Text("Apple 系统语音详情")
        } footer: {
            if voiceQuality.isNatural {
                Text("已启用增强/高级音质，听感更自然。想为更多口音提升音质，可在「设置 › 辅助功能 › 朗读内容 › 声音 › 英语」继续下载。")
            } else {
                Text("系统自带的标准语音偏机械。前往「设置 › 辅助功能 › 朗读内容 › 声音 › 英语」，下载带「增强」或「高级」标记的语音（如 Ava、Zoe、Serena），下载后回到 App 即自动生效、明显更像真人。")
            }
        }
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

    private var recognitionEngineBinding: Binding<SpeechRecognitionEngine> {
        Binding(
            get: {
                SpeechRecognitionEngine(rawValue: recognitionEngineRaw) ?? .enhancedOnDevice
            },
            set: { engine in
                recognitionEngineRaw = engine.rawValue
            }
        )
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

    // MARK: - 学习

    @ViewBuilder
    private var learningSection: some View {
        Section {
            if profile != nil {
                Toggle("聊天中随机出题", isOn: quizEnabledBinding)
            }
        } header: {
            Text("学习")
        } footer: {
            Text("开启后，与朋友聊到一定轮次会随手出一道小测；每个对话里也能单独关闭。")
        }
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
