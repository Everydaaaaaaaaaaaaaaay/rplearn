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
    @State private var showsEmailForm = false

    public init(session: AuthSession) {
        self.session = session
    }

    public var body: some View {
        ZStack {
            DSWorkbenchBackdrop(focus: .account)

            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    header

                    if registrationAccepted {
                        verificationNotice
                    } else {
                        signInPanel
                    }
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, 68)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .task { await reloadAppleChallenge() }
    }

    private var header: some View {
        VStack(spacing: DSSpacing.sm) {
            DSObsidianMedallion(systemImage: "wallet.pass", size: 72)

            Text("继续你的语言之旅")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.dsPaperInk)
                .multilineTextAlignment(.center)

            Text("城市、学习进度与订阅会安全同步到你的所有设备。")
                .font(.subheadline)
                .foregroundStyle(Color.dsPaperInkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .shadow(
            color: Color(red: 0.985, green: 0.970, blue: 0.925).opacity(0.94),
            radius: 8
        )
    }

    private var signInPanel: some View {
        DSWorkbenchPaperSheet(radius: 28) {
            VStack(spacing: DSSpacing.md) {
                appleAction

                HStack(spacing: DSSpacing.sm) {
                    syncItem("map.fill", text: "城市")
                    syncItem("chart.line.uptrend.xyaxis", text: "进度")
                    syncItem("checkmark.shield.fill", text: "订阅")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("同步城市、学习进度与订阅")

                divider

                DisclosureGroup(isExpanded: $showsEmailForm) {
                    VStack(spacing: DSSpacing.md) {
                        credentials
                        primaryAction
                    }
                    .padding(.top, DSSpacing.md)
                } label: {
                    Label("使用邮箱登录或注册", systemImage: "envelope")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.dsPaperInk)
                }
                .tint(Color.dsSkyDeep)
            }
        }
    }

    private var divider: some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(Color.dsPaperInk.opacity(0.12))
            Text("或")
                .font(.caption)
                .foregroundStyle(Color.dsPaperInkSecondary)
            Rectangle().frame(height: 1).foregroundStyle(Color.dsPaperInk.opacity(0.12))
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
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous))
            .allowsHitTesting(appleChallenge != nil && !isBusy)
            .opacity(appleChallenge == nil ? 0.55 : 1)

            if appleChallenge == nil {
                Text("正在准备安全登录…")
                    .font(.caption)
                    .foregroundStyle(Color.dsPaperInkSecondary)
            }
        }
    }

    private var credentials: some View {
        VStack(spacing: DSSpacing.sm) {
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
                .foregroundStyle(Color.dsPaperInk)
                .background(
                    Color.white.opacity(0.56),
                    in: RoundedRectangle(cornerRadius: DSRadius.inline)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.inline)
                        .stroke(Color.dsPaperInk.opacity(0.10), lineWidth: 0.8)
                }

            SecureField(mode == .login ? "密码" : "密码（至少 12 位）", text: $password)
                .textContentType(mode == .login ? .password : .newPassword)
                .padding(14)
                .foregroundStyle(Color.dsPaperInk)
                .background(
                    Color.white.opacity(0.56),
                    in: RoundedRectangle(cornerRadius: DSRadius.inline)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.inline)
                        .stroke(Color.dsPaperInk.opacity(0.10), lineWidth: 0.8)
                }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.dsDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var primaryAction: some View {
        Button {
            submitCredentials()
        } label: {
            HStack {
                if isBusy { ProgressView().tint(.white) }
                Text(mode == .login ? "登录" : "创建账号")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.dsWorkbenchAction)
        .disabled(isBusy || !isFormValid)
    }

    private func syncItem(_ systemImage: String, text: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsSkyDeep)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.dsPaperInkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var verificationNotice: some View {
        DSWorkbenchPaperSheet(radius: 28) {
            VStack(spacing: DSSpacing.md) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.dsSkyDeep)
                Text("验证邮件已发送")
                    .font(.title2.bold())
                    .foregroundStyle(Color.dsPaperInk)
                Text("请打开发送到 \(email) 的链接完成验证，然后返回这里登录。")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsPaperInkSecondary)
                    .multilineTextAlignment(.center)
                Button("我已验证，去登录") {
                    registrationAccepted = false
                    mode = .login
                    password = ""
                    showsEmailForm = true
                }
                .buttonStyle(.dsWorkbenchAction)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsSkyDeep)
            }
        }
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
