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
    @State private var showsAccountPanel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleContent
            } else {
                modernTravelDesk
            }
        }
        .background(Color.dsBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: reloadToken) { await reload() }
        .sheet(isPresented: $showsAccountPanel) {
            accountPanel
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
    }

    private var accessibleContent: some View {
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
        .refreshable { await reload() }
    }

    /// 现代旅行者工作台：插画只提供空间语境，所有数据和交互仍由原生控件承载。
    private var modernTravelDesk: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let sceneHeight = max(proxy.size.height, width * 1906 / 825)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    Image("profile_modern_travel_desk", bundle: .main)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: sceneHeight)
                        .clipped()
                        .overlay {
                            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.02)
                        }
                        .accessibilityHidden(true)

                    profileHotspot
                        .frame(width: min(width * 0.60, 236))
                        .position(x: width * 0.31, y: sceneHeight * 0.145)

                    coinHotspot
                        .position(x: width * 0.81, y: sceneHeight * 0.215)

                    learningHotspot
                        .frame(width: min(width * 0.64, 270))
                        .position(x: width * 0.51, y: sceneHeight * 0.445)

                    favoritesHotspot
                        .frame(width: min(width * 0.42, 172))
                        .position(x: width * 0.22, y: sceneHeight * 0.635)

                    settingsHotspot
                        .frame(width: min(width * 0.42, 172))
                        .position(x: width * 0.78, y: sceneHeight * 0.635)

                    accountHotspot
                        .frame(width: min(width * 0.56, 226))
                        .position(x: width * 0.52, y: sceneHeight * 0.735)

                    #if DEBUG
                    memoryDebugHotspot
                        .position(x: width * 0.53, y: sceneHeight * 0.075)
                    #endif
                }
                .frame(width: width, height: sceneHeight)
            }
            .scrollIndicators(.hidden)
            .refreshable { await reload() }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var profileHotspot: some View {
        Button {
            if isSignedIn {
                showsAccountPanel = true
            } else {
                onSignIn()
            }
        } label: {
            deskPanel {
                HStack(spacing: 10) {
                    AvatarBadge(name: displayName, tint: .dsSky, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(displayName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(accountBadgeTitle)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accountBadgeTint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(accountBadgeTint.opacity(0.12), in: Capsule())
                        }
                        Text(accountIdentifier)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label("已认识 \(occupiedFriendSlots) 位旅途朋友", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(DeskHotspotButtonStyle())
        .accessibilityLabel("个人资料，\(displayName)，\(accountBadgeTitle)，已认识 \(occupiedFriendSlots) 位旅途朋友")
        .accessibilityHint(isSignedIn ? "打开账号与订阅" : "登录或创建账号")
    }

    @ViewBuilder
    private var coinHotspot: some View {
        #if DEBUG
        Button {
            Task {
                await economyService.grantDebugCoins()
                await reload()
            }
        } label: {
            coinLabel(showsDebugAction: true)
        }
        .buttonStyle(DeskHotspotButtonStyle())
        .accessibilityHint("调试构建中轻点增加 500 金币")
        #else
        coinLabel(showsDebugAction: false)
        #endif
    }

    private func coinLabel(showsDebugAction: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.grid.2x1.fill")
                .foregroundStyle(Color.dsSunset)
            Text("\(profile?.coins ?? 0)")
                .font(.subheadline.bold().monospacedDigit())
            if showsDebugAction {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.dsSuccess)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(deskMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(profile?.coins ?? 0) 金币")
    }

    private var learningHotspot: some View {
        Button(action: onCalibrateLevel) {
            deskPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("英语旅程", systemImage: "map.fill")
                            .font(.headline)
                            .foregroundStyle(Color.dsSkyDeep)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 14) {
                        deskMetric(
                            title: "当前水平",
                            value: profile?.difficultyLevel.displayName ?? "载入中"
                        )
                        deskMetric(
                            title: "学习目标",
                            value: profile?.learningGoal.displayName ?? "载入中"
                        )
                    }
                    HStack {
                        if let score = profile?.placementScore {
                            Label("最近校准 \(score) / 100", systemImage: "checkmark.seal.fill")
                        } else {
                            Label("校准英语水平", systemImage: "scope")
                        }
                        Spacer()
                        Text("重新校准")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSkyDeep)
                }
            }
        }
        .buttonStyle(DeskHotspotButtonStyle())
        .accessibilityLabel("英语旅程，当前水平 \(profile?.difficultyLevel.displayName ?? "载入中")，学习目标 \(profile?.learningGoal.displayName ?? "载入中")")
        .accessibilityHint("重新校准英语水平")
    }

    private func deskMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favoritesHotspot: some View {
        NavigationLink {
            favoritesBuilder()
        } label: {
            deskEntryLabel(
                "收藏夹",
                subtitle: "单词与语法点",
                icon: "star.fill",
                tint: .dsSunset
            )
        }
        .buttonStyle(DeskHotspotButtonStyle())
        .accessibilityHint("查看收藏的单词与语法点")
    }

    private var settingsHotspot: some View {
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
            deskEntryLabel(
                "设置",
                subtitle: "AI、语音与偏好",
                icon: "gearshape.fill",
                tint: .dsSky
            )
        }
        .buttonStyle(DeskHotspotButtonStyle())
        .accessibilityHint("打开设置")
    }

    private var accountHotspot: some View {
        Button {
            if isSignedIn {
                showsAccountPanel = true
            } else {
                onSignIn()
            }
        } label: {
            deskEntryLabel(
                isSignedIn ? "账号与订阅" : "登录或创建账号",
                subtitle: isSignedIn ? "同步旅程与管理方案" : "跨设备同步与订阅恢复",
                icon: isSignedIn ? "icloud.fill" : "person.crop.circle.badge.plus",
                tint: .dsSkyDeep
            )
        }
        .buttonStyle(DeskHotspotButtonStyle())
    }

    #if DEBUG
    private var memoryDebugHotspot: some View {
        NavigationLink {
            MemoryDebugView(
                memoryStore: memoryStore,
                rosterStore: rosterStore,
                economyStore: economyStore,
                memoryService: memoryService
            )
        } label: {
            Image(systemName: "brain.head.profile.fill")
                .font(.headline)
                .foregroundStyle(Color.dsQuiz)
                .frame(width: 46, height: 46)
                .background(deskMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        }
        .buttonStyle(DeskHotspotButtonStyle())
        .accessibilityLabel("记忆调试面板")
        .accessibilityHint("查看角色长期与近期记忆")
    }
    #endif

    private func deskEntryLabel(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        deskPanel {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func deskPanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(11)
            .background(deskMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.58), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.11), radius: 10, y: 4)
    }

    private var deskMaterial: AnyShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(Color.dsSurface.opacity(0.96))
        } else {
            AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var accountPanel: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.md) {
                    profileCard
                    subscriptionCard
                    if isSignedIn {
                        Button(role: .destructive) {
                            Task {
                                await authSession.logout()
                                showsAccountPanel = false
                            }
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsAction(.secondary, fullWidth: true))
                    }
                }
                .padding(DSSpacing.md)
            }
            .background(Color.dsBackground)
            .navigationTitle("账号与版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsAccountPanel = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                            : "当前使用自选水平"
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
                entryRow("收藏夹", subtitle: "收集旅途中遇到的单词与语法点", icon: "star.fill", tint: .dsSunset)
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

    private var accountIdentifier: String {
        guard case .signedIn(let identity) = authSession.phase else {
            return "本地旅客"
        }
        return "ID \(identity.userID.uuidString.prefix(8).uppercased())"
    }

    private func reload() async {
        async let loadedProfile = try? economyStore.profile()
        async let loadedSlots = try? rosterStore.occupiedFriendSlots()
        profile = await loadedProfile
        occupiedFriendSlots = await loadedSlots ?? 0
    }
}

private struct DeskHotspotButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0),
                value: configuration.isPressed
            )
            .contentShape(Rectangle())
    }
}
