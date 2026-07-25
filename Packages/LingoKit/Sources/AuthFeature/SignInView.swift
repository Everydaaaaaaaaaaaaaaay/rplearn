import AuthenticationServices
import BackendKit
import DesignSystem
import SwiftUI

public struct SignInView: View {
    private enum Mode: Hashable {
        case login
        case register
    }

    @Bindable private var session: AuthSession
    @State private var appleChallenge: AppleAuthChallenge?
    @State private var email = ""
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var mode: Mode = .login
    @State private var password = ""
    @State private var registrationAccepted = false

    public init(session: AuthSession) {
        self.session = session
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                if registrationAccepted {
                    verificationNotice
                } else {
                    credentials
                    primaryAction
                    divider
                    appleAction
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [
                    Color.dsSky.opacity(0.18),
                    Color.dsBackground,
                    Color.dsBackground,
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .task { await reloadAppleChallenge() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 68))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.dsSky)
                .shadow(color: Color.dsSky.opacity(0.2), radius: 14, y: 7)
            Text("继续你的语言之旅")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("登录后，城市、机票、学习进度与订阅会安全同步到你的所有设备。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var credentials: some View {
        VStack(spacing: 14) {
            Picker("账号操作", selection: $mode) {
                Text("登录").tag(Mode.login)
                Text("注册").tag(Mode.register)
            }
            .pickerStyle(.segmented)

            TextField("邮箱", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))

            SecureField(mode == .login ? "密码" : "密码（至少 12 位）", text: $password)
                .textContentType(mode == .login ? .password : .newPassword)
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var primaryAction: some View {
        Button {
            submitCredentials()
        } label: {
            HStack {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(mode == .login ? "登录" : "创建账号")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.duoPrimary)
        .disabled(isBusy || !isFormValid)
    }

    private var divider: some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text("或")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
    }

    private var appleAction: some View {
        VStack(spacing: 8) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.email, .fullName]
                request.nonce = appleChallenge?.nonce
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .allowsHitTesting(appleChallenge != nil && !isBusy)
            .opacity(appleChallenge == nil ? 0.55 : 1)

            if appleChallenge == nil {
                Text("正在准备安全登录…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var verificationNotice: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.dsSky)
            Text("验证邮件已发送")
                .font(.title2.bold())
            Text("请打开发送到 \(email) 的链接完成验证，然后返回这里登录。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("我已验证，去登录") {
                registrationAccepted = false
                mode = .login
                password = ""
            }
            .buttonStyle(.duoPrimary)
            Button("重新发送验证邮件") {
                Task {
                    do {
                        try await session.resendVerification(email: normalizedEmail)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isFormValid: Bool {
        normalizedEmail.contains("@") && password.count >= 12
    }

    private func submitCredentials() {
        guard isFormValid else { return }
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                switch mode {
                case .login:
                    try await session.login(email: normalizedEmail, password: password)
                case .register:
                    try await session.register(email: normalizedEmail, password: password)
                    registrationAccepted = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reloadAppleChallenge() async {
        do {
            appleChallenge = try await session.prepareAppleChallenge()
        } catch {
            appleChallenge = nil
        }
    }

    private func handleAppleCompletion(
        _ result: Result<ASAuthorization, any Error>
    ) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let challenge = appleChallenge,
              let codeData = credential.authorizationCode,
              let tokenData = credential.identityToken,
              let authorizationCode = String(data: codeData, encoding: .utf8),
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            if case .failure(let error) = result {
                let authorizationError = error as? ASAuthorizationError
                if authorizationError?.code != .canceled {
                    errorMessage = error.localizedDescription
                }
            }
            Task { await reloadAppleChallenge() }
            return
        }

        isBusy = true
        errorMessage = nil
        appleChallenge = nil
        Task {
            defer { isBusy = false }
            do {
                try await session.loginWithApple(
                    authorizationCode: authorizationCode,
                    challengeID: challenge.challengeId,
                    identityToken: identityToken
                )
            } catch {
                errorMessage = error.localizedDescription
                await reloadAppleChallenge()
            }
        }
    }
}
