import AuthenticationServices
import BackendKit
import DesignSystem
import SwiftUI

public struct AccountSecurityView: View {
    @Environment(\.dismiss) private var dismiss
    private let session: AuthSession

    @State private var identities: [AccountIdentity] = []
    @State private var deviceSessions: [AccountDeviceSession] = []
    @State private var challenge: AppleAuthChallenge?
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var pendingUnlink: AccountIdentity?
    @State private var showsDeleteConfirmation = false

    public init(session: AuthSession) {
        self.session = session
    }

    public var body: some View {
        List {
            Section {
                if identities.isEmpty && isBusy {
                    ProgressView("正在载入…")
                } else {
                    ForEach(identities) { identity in
                        identityRow(identity)
                    }
                }

                if !identities.contains(where: { $0.provider == "apple" }) {
                    appleLinkButton
                }
            } header: {
                Text("登录方式")
            } footer: {
                Text("同一个旅途账号可以绑定多种登录方式。系统不会仅凭相同邮箱自动合并两个账号。")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.dsDanger)
                }
            }

            Section {
                Button("永久删除账号", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .disabled(isBusy)
            } header: {
                Text("账号数据")
            } footer: {
                Text("删除会立即退出所有设备并清理账号数据；已有 App Store 订阅仍需在系统订阅管理中取消。")
            }

            Section("已登录设备") {
                ForEach(deviceSessions) { deviceSession in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(deviceSession.deviceName ?? platformName(deviceSession.platform))
                                .font(.body.weight(.semibold))
                            Text(deviceSession.current ? "当前设备" : platformName(deviceSession.platform))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !deviceSession.current {
                            Button("退出", role: .destructive) {
                                Task { await revoke(deviceSession) }
                            }
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
        .navigationTitle("账号与安全")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert(
            "解除\(providerName(pendingUnlink?.provider))登录？",
            isPresented: Binding(
                get: { pendingUnlink != nil },
                set: { if !$0 { pendingUnlink = nil } }
            ),
            presenting: pendingUnlink
        ) { identity in
            Button("解除绑定", role: .destructive) {
                Task { await unlink(identity) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("解除后不能再使用这种方式登录。为保护账号，登录超过 10 分钟时需要先退出并重新登录。")
        }
        .confirmationDialog(
            "永久删除账号？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久删除账号", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该操作不可撤销。旅程、角色关系、同步内容和登录身份都会进入删除流程。")
        }
    }

    private func identityRow(_ identity: AccountIdentity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: providerIcon(identity.provider))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(providerName(identity.provider))登录")
                    .font(.body.weight(.semibold))
                if let displayName = identity.displayName {
                    Text(displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let email = identity.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if identities.count > 1 {
                Button("解除", role: .destructive) {
                    pendingUnlink = identity
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isBusy)
            } else {
                Text("唯一方式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appleLinkButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.email, .fullName]
                request.nonce = challenge?.nonce
            } onCompletion: { result in
                handleAppleLink(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .disabled(challenge == nil || isBusy)

            if challenge == nil {
                Button("重新准备 Apple 绑定") {
                    Task { await prepareAppleLink() }
                }
                .font(.caption.weight(.semibold))
                .disabled(isBusy)
            }
        }
    }

    private func reload() async {
        isBusy = true
        defer { isBusy = false }
        do {
            async let loadedIdentities = session.accountIdentities()
            async let loadedSessions = session.accountDeviceSessions()
            identities = try await loadedIdentities
            deviceSessions = try await loadedSessions
            errorMessage = nil
            if !identities.contains(where: { $0.provider == "apple" }) {
                challenge = try await session.prepareAppleChallenge()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareAppleLink() async {
        isBusy = true
        defer { isBusy = false }
        do {
            challenge = try await session.prepareAppleChallenge()
            errorMessage = nil
        } catch {
            challenge = nil
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleLink(_ result: Result<ASAuthorization, any Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let challenge,
              let codeData = credential.authorizationCode,
              let tokenData = credential.identityToken,
              let authorizationCode = String(data: codeData, encoding: .utf8),
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            if case .failure(let error) = result,
               (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
            Task { await prepareAppleLink() }
            return
        }

        isBusy = true
        self.challenge = nil
        Task {
            defer { isBusy = false }
            do {
                try await session.linkWithApple(
                    authorizationCode: authorizationCode,
                    challengeID: challenge.challengeId,
                    identityToken: identityToken,
                    appleUserID: credential.user,
                    displayName: credential.fullName.flatMap {
                        let name = PersonNameComponentsFormatter()
                            .string(from: $0)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return name.isEmpty ? nil : name
                    }
                )
                identities = try await session.accountIdentities()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                await prepareAppleLink()
            }
        }
    }

    private func unlink(_ identity: AccountIdentity) async {
        isBusy = true
        pendingUnlink = nil
        defer { isBusy = false }
        do {
            try await session.unlinkIdentity(identity)
            identities = try await session.accountIdentities()
            errorMessage = nil
            if identity.provider == "apple" {
                await prepareAppleLink()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await session.deleteAccount()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ deviceSession: AccountDeviceSession) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await session.revokeDeviceSession(deviceSession)
            deviceSessions = try await session.accountDeviceSessions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func providerName(_ provider: String?) -> String {
        switch provider {
        case "apple": "Apple"
        case "google": "Google"
        case "email": "邮箱"
        default: "该"
        }
    }

    private func providerIcon(_ provider: String) -> String {
        switch provider {
        case "apple": "apple.logo"
        case "google": "g.circle.fill"
        case "email": "envelope.fill"
        default: "person.badge.key.fill"
        }
    }

    private func platformName(_ platform: String) -> String {
        switch platform {
        case "ios": "iPhone 或 iPad"
        case "android": "Android"
        case "web": "网页"
        case "macos": "Mac"
        default: "未知设备"
        }
    }
}
