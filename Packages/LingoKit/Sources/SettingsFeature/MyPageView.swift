import BackendKit
import BillingKit
import CoreKit
import DesignSystem
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import StoreKit
import SwiftUI

/// “我的”聚合页：资料、订阅、金币与二级入口。
public struct MyPageView: View {
    private let router: LLMRouter
    private let economyStore: EconomyStore
    private let economyService: EconomyService
    private let profileCommands: any ProfileCommandGateway
    private let memoryStore: MemoryStore
    private let rosterStore: RosterStore
    private let chatStore: ChatStore
    private let speech: any SpeechService
    private let authSession: AuthSession
    private let billing: BillingController
    private let reloadToken: Int
    private let isSignedIn: Bool
    private let onSignIn: @MainActor () -> Void
    private let onCalibrateLevel: @MainActor () -> Void
    private let onProactiveMessagesChanged: @MainActor (Bool) -> Void
    private let favoritesBuilder: @MainActor () -> AnyView

    @State private var profile: UserProfileDTO?
    @State private var occupiedFriendSlots = 0
    @State private var showsTierPicker = false
    @State private var showsManageSubscriptions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        router: LLMRouter,
        economyStore: EconomyStore,
        economyService: EconomyService,
        profileCommands: any ProfileCommandGateway,
        memoryStore: MemoryStore,
        rosterStore: RosterStore,
        chatStore: ChatStore,
        speech: any SpeechService,
        authSession: AuthSession,
        billing: BillingController,
        reloadToken: Int = 0,
        isSignedIn: Bool,
        onSignIn: @escaping @MainActor () -> Void,
        onCalibrateLevel: @escaping @MainActor () -> Void,
        onProactiveMessagesChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        favoritesBuilder: @escaping @MainActor () -> AnyView
    ) {
        self.router = router
        self.economyStore = economyStore
        self.economyService = economyService
        self.profileCommands = profileCommands
        self.memoryStore = memoryStore
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.speech = speech
        self.authSession = authSession
        self.billing = billing
        self.reloadToken = reloadToken
        self.isSignedIn = isSignedIn
        self.onSignIn = onSignIn
        self.onCalibrateLevel = onCalibrateLevel
        self.onProactiveMessagesChanged = onProactiveMessagesChanged
        self.favoritesBuilder = favoritesBuilder
    }

    private var memoryService: MemoryService {
        MemoryService(
            llm: router,
            chatStore: chatStore,
            memoryStore: memoryStore,
            economyStore: economyStore
        )
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileCard
                learningProfileCard
                subscriptionCard
                entryList
                #if DEBUG
                debugCard
                #endif
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: reloadToken) { await reload() }
        .refreshable { await reload() }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
    }

    private var profileCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(spacing: DSSpacing.sm) {
                        AvatarBadge(name: displayName, tint: .dsSky, size: 60)
                        Text(displayName)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DSChip(
                        accountBadgeTitle,
                        tint: accountBadgeTint,
                        prominent: isSignedIn && billing.tier != .free
                    )
                    Label("已认识 \(occupiedFriendSlots) 位旅途朋友", systemImage: "person.2.fill")
                        .foregroundStyle(.secondary)
                    Label("\(profile?.coins ?? 0) 金币", systemImage: "circle.grid.2x1.fill")
                        .foregroundStyle(Color.dsSunset)
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: DSSpacing.md) {
                    AvatarBadge(name: displayName, tint: .dsSky, size: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayName)
                            .font(.title2.bold())
                        DSChip(
                            accountBadgeTitle,
                            tint: accountBadgeTint,
                            prominent: isSignedIn && billing.tier != .free
                        )
                        Text("已认识 \(occupiedFriendSlots) 位旅途朋友")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "circle.grid.2x1.fill")
                            .foregroundStyle(Color.dsSunset)
                        Text("\(profile?.coins ?? 0)")
                            .font(.title3.bold().monospacedDigit())
                        Text("金币")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dsSurface(.elevated)
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if isSignedIn {
                subscriptionHeader

                HStack {
                    Button {
                        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                            showsTierPicker.toggle()
                        }
                    } label: {
                        Label(showsTierPicker ? "收起方案" : "查看订阅方案", systemImage: "sparkles")
                    }
                    .buttonStyle(.dsAction(.glass, fullWidth: false, compact: true))
                    .tint(.white)

                    if billing.tier != .free {
                        Button("管理") {
                            showsManageSubscriptions = true
                        }
                        .buttonStyle(.dsAction(.glass, fullWidth: false, compact: true))
                        .tint(.white)
                    }
                }

                if showsTierPicker {
                    VStack(spacing: DSSpacing.xs) {
                        if billing.operation == .loading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else if billing.products.isEmpty {
                            Text("当前 App Store 账户暂无可购买方案。")
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(billing.products) { product in
                                Button {
                                    Task {
                                        await billing.purchase(product)
                                        await reload()
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(product.tier.displayName)
                                                .fontWeight(.bold)
                                            if let period = product.periodDescription {
                                                Text(period)
                                                    .font(.caption)
                                                    .opacity(0.76)
                                            }
                                        }
                                        Spacer()
                                        Text(product.displayPrice)
                                            .fontWeight(.bold)
                                            .monospacedDigit()
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.dsAction(.glass, fullWidth: true, compact: true))
                                .tint(.white)
                                .disabled(billing.operation != .idle)
                            }
                        }

                        Button("恢复购买") {
                            Task {
                                await billing.restorePurchases()
                                await reload()
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .disabled(billing.operation != .idle)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                if let validity = billing.currentValidityDescription {
                    Text(validity)
                        .font(.caption2)
                        .opacity(0.76)
                }
                if let message = billing.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                if let error = billing.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            } else {
                guestAccountPrompt
            }
        }
        .foregroundStyle(.white)
        .padding(DSSpacing.md)
        .background(
            LinearGradient(
                colors: [Color.dsSkyDeep, Color.dsSky, Color.dsCyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
        )
        .shadow(color: Color.dsSky.opacity(0.24), radius: 12, y: 5)
    }

    private var learningProfileCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("英语学习档案")
                        .font(.headline)
                    Text(
                        profile?.proficiencySource == .placement
                            ? "已通过答题校准"
                            : "当前使用自评水平"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("校准水平", action: onCalibrateLevel)
                    .buttonStyle(.dsAction(.secondary, fullWidth: false, compact: true))
            }

            HStack(spacing: DSSpacing.sm) {
                learningMetric(
                    title: "当前水平",
                    value: profile?.difficultyLevel.displayName ?? "载入中",
                    icon: "gauge.with.dots.needle.33percent"
                )
                learningMetric(
                    title: "学习目标",
                    value: profile?.learningGoal.displayName ?? "载入中",
                    icon: "scope"
                )
            }

            if let score = profile?.placementScore {
                HStack {
                    Label("最近校准 \(score) / 100", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.dsSkyDeep)
                    Spacer()
                    if let date = profile?.placementCompletedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .dsSurface(.grouped)
    }

    private func learningMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color.dsSurfaceMuted, in: RoundedRectangle(cornerRadius: DSRadius.inline))
    }

    private var guestAccountPrompt: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开发期完整体验")
                        .font(.title3.bold())
                    Text("AI 对话、城市探索、剧情和学习功能均可使用")
                        .font(.footnote)
                        .opacity(0.86)
                }
                Spacer()
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.largeTitle)
            }

            Button(action: onSignIn) {
                Label("登录或创建账号", systemImage: "icloud.and.arrow.up")
            }
            .buttonStyle(.dsAction(.glass, fullWidth: false, compact: true))
            .tint(.white)

            Text("登录仅用于跨设备同步和订阅恢复；未登录时功能不受限。")
                .font(.caption2)
                .opacity(0.76)
        }
    }

    @ViewBuilder
    private var subscriptionHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title)
                Text("\(AppBrand.englishName) \(billing.tier.displayName)")
                    .font(.headline.bold())
                Text("更长的角色记忆，让每段友谊都有延续")
                    .font(.body)
                    .opacity(0.86)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppBrand.englishName) \(billing.tier.displayName)")
                        .font(.title3.bold())
                    Text("更长的角色记忆，让每段友谊都有延续")
                        .font(.footnote)
                        .opacity(0.86)
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.largeTitle)
            }
        }
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            NavigationLink {
                favoritesBuilder()
            } label: {
                entryRow("收藏夹", subtitle: "收集旅途中遇到的单词", icon: "star.fill", tint: .dsSunset)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            NavigationLink {
                SettingsView(
                    router: router,
                    economyStore: economyStore,
                    profileCommands: profileCommands,
                    memoryStore: memoryStore,
                    rosterStore: rosterStore,
                    chatStore: chatStore,
                    speech: speech,
                    onProactiveMessagesChanged: onProactiveMessagesChanged
                )
            } label: {
                entryRow("设置", subtitle: "AI、语音与学习偏好", icon: "gearshape.fill", tint: .dsSky)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            if isSignedIn {
                Button(role: .destructive) {
                    Task { await authSession.logout() }
                } label: {
                    entryRow(
                        "退出登录",
                        subtitle: "退出账号并回到本地游客空间",
                        icon: "rectangle.portrait.and.arrow.right",
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSignIn) {
                    entryRow(
                        "登录或创建账号",
                        subtitle: "用于跨设备同步与订阅恢复",
                        icon: "person.crop.circle.badge.plus",
                        tint: .dsSky
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .dsSurface(.grouped, padding: 0)
    }

    #if DEBUG
    private var debugCard: some View {
        VStack(spacing: 0) {
            Button {
                Task {
                    await economyService.grantDebugCoins()
                    await reload()
                }
            } label: {
                entryRow("调试：+500 金币", subtitle: "仅 Debug 构建可见", icon: "plus.circle.fill", tint: .dsSuccess)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            NavigationLink {
                MemoryDebugView(
                    memoryStore: memoryStore,
                    rosterStore: rosterStore,
                    economyStore: economyStore,
                    memoryService: memoryService
                )
            } label: {
                entryRow("记忆调试面板", subtitle: "查看角色长期与近期记忆", icon: "brain.head.profile", tint: .dsQuiz)
            }
            .buttonStyle(.plain)
        }
        .dsSurface(.grouped, padding: 0)
    }
    #endif

    private func entryRow(_ title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(DSSpacing.sm)
        .contentShape(Rectangle())
    }

    private var displayName: String {
        let value = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "旅行者" : value
    }

    private var accountBadgeTitle: String {
        isSignedIn ? billing.tier.displayName : "完整游客"
    }

    private var accountBadgeTint: Color {
        guard isSignedIn else { return .secondary }
        return billing.tier == .free ? .secondary : .dsSky
    }

    private func reload() async {
        async let loadedProfile = try? economyStore.profile()
        async let loadedSlots = try? rosterStore.occupiedFriendSlots()
        profile = await loadedProfile
        occupiedFriendSlots = await loadedSlots ?? 0
    }
}
