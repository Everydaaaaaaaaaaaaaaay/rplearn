import LLMKit
import SwiftUI

/// 设置页：LLM 供应商、API Key、模型与连接测试。
/// 出题开关、订阅调试面板等在后续单元加入。
public struct SettingsView: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    @Bindable private var settings: LLMSettingsStore
    private let router: LLMRouter
    @State private var testState: TestState = .idle

    public init(settings: LLMSettingsStore, router: LLMRouter) {
        self.settings = settings
        self.router = router
    }

    public var body: some View {
        Form {
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

#Preview {
    NavigationStack {
        SettingsView(
            settings: LLMSettingsStore(),
            router: LLMRouter { LLMProviderConfig(kind: .anthropic, apiKey: "", baseURL: URL(string: "https://api.anthropic.com")!, models: [:]) }
        )
    }
}
