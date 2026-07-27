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

    // MARK: - 语音音质

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
                Task { await speech.speak("Hello! This is how I sound. Nice to meet you.", language: "en-US") }
            } label: {
                Label("试听当前语音", systemImage: "play.circle")
            }
            if !voiceQuality.isNatural {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("前往系统设置下载", systemImage: "arrow.down.circle")
                }
            }
        } header: {
            Text("语音音质")
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
