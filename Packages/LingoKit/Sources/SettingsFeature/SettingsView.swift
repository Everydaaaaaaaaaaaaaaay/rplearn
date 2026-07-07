import DomainKit
import LLMKit
import PersistenceKit
import SwiftUI

/// 设置页：LLM 供应商、API Key、模型、连接测试、账户（订阅/金币）与调试面板。
public struct SettingsView: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    @Bindable private var settings: LLMSettingsStore
    private let router: LLMRouter
    private let economyStore: EconomyStore
    private let economyService: EconomyService
    private let memoryStore: MemoryStore
    private let rosterStore: RosterStore
    private let chatStore: ChatStore
    @State private var testState: TestState = .idle
    @State private var profile: UserProfileDTO?

    public init(
        settings: LLMSettingsStore,
        router: LLMRouter,
        economyStore: EconomyStore,
        economyService: EconomyService,
        memoryStore: MemoryStore,
        rosterStore: RosterStore,
        chatStore: ChatStore
    ) {
        self.settings = settings
        self.router = router
        self.economyStore = economyStore
        self.economyService = economyService
        self.memoryStore = memoryStore
        self.rosterStore = rosterStore
        self.chatStore = chatStore
    }

    private var memoryService: MemoryService {
        MemoryService(llm: router, chatStore: chatStore, memoryStore: memoryStore, economyStore: economyStore)
    }

    public var body: some View {
        Form {
            accountSection
            learningSection
            Section {
                Picker("供应商", selection: $settings.providerKind) {
                    ForEach(LLMProviderKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                SecureField("API Key", text: apiKeyBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if settings.providerKind == .custom {
                    TextField("服务地址（如 https://example.com/v1）", text: $settings.customBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("AI 服务")
            } footer: {
                Text("API Key 只保存在本机钥匙串中。")
            }

            Section {
                ForEach(LLMTier.allCases, id: \.rawValue) { tier in
                    LabeledContent(tierLabel(tier)) {
                        TextField(
                            settings.providerKind.defaultModelID(for: tier),
                            text: modelBinding(tier)
                        )
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("模型")
            } footer: {
                Text("留空使用默认模型。fast 用于纠错/翻译等轻任务，balanced 用于角色对话，deep 用于最高质量任务。")
            }

            Section {
                Button {
                    runConnectionTest()
                } label: {
                    HStack {
                        Text("测试连接")
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
                    Label("连接成功：\(reply)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("设置")
        .animation(.default, value: testState)
        .task {
            await reloadProfile()
        }
    }

    // MARK: - 账户

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let profile {
                LabeledContent("金币") {
                    Label("\(profile.coins)", systemImage: "circle.grid.2x1.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline.monospacedDigit())
                }
                Picker("订阅", selection: subscriptionBinding) {
                    ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
            } else {
                ProgressView()
            }
            #if DEBUG
            Button("调试：+500 金币") {
                Task {
                    await economyService.grantDebugCoins()
                    await reloadProfile()
                }
            }
            NavigationLink("调试：记忆面板") {
                MemoryDebugView(
                    memoryStore: memoryStore,
                    rosterStore: rosterStore,
                    economyStore: economyStore,
                    memoryService: memoryService
                )
            }
            #endif
        } header: {
            Text("账户")
        } footer: {
            Text("订阅为本地模拟，未接入真实支付。订阅等级影响角色记忆容量。")
        }
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
                    profile = try? await economyStore.updateProfile { $0.quizGloballyEnabled = newValue }
                }
            }
        )
    }

    private var subscriptionBinding: Binding<SubscriptionTier> {
        Binding(
            get: { profile?.subscriptionTier ?? .free },
            set: { newTier in
                Task {
                    profile = try? await economyService.subscribe(to: newTier)
                }
            }
        )
    }

    private func reloadProfile() async {
        profile = try? await economyStore.profile()
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { settings.apiKey(for: settings.providerKind) },
            set: { settings.setAPIKey($0, for: settings.providerKind) }
        )
    }

    private func modelBinding(_ tier: LLMTier) -> Binding<String> {
        Binding(
            get: { settings.modelID(for: tier) },
            set: { settings.setModelID($0, for: tier) }
        )
    }

    private func tierLabel(_ tier: LLMTier) -> String {
        switch tier {
        case .fast: "fast"
        case .balanced: "balanced"
        case .deep: "deep"
        }
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

