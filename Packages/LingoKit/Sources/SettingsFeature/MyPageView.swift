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

    /// 现代旅行者工作台：动态内容像印刷物与实物标记一样落在场景锚点上。
    private var modernTravelDesk: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let sceneHeight = max(proxy.size.height, width * 1906 / 825)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    travelDeskBackground(width: width, height: sceneHeight)

                    profileHotspot
                        .frame(width: min(width * 0.45, 180), height: 150)
                        .position(x: width * 0.22, y: sceneHeight * 0.16)

                    coinHotspot
                        .frame(width: 112, height: 90)
                        .position(x: width * 0.82, y: sceneHeight * 0.17)

                    learningHotspot
                        .frame(width: min(width * 0.35, 140), height: 164)
                        .position(x: width * 0.515, y: sceneHeight * 0.478)

                    favoritesHotspot
                        .frame(width: 110, height: 100)
                        .position(x: width * 0.17, y: sceneHeight * 0.535)

                    settingsHotspot
                        .frame(width: 108, height: 100)
                        .position(x: width * 0.73, y: sceneHeight * 0.65)

                    accountHotspot
                        .frame(width: 124, height: 118)
                        .position(x: width * 0.50, y: sceneHeight * 0.72)

                    #if DEBUG
                    memoryDebugHotspot
                        .frame(width: 76, height: 82)
                        .position(x: width * 0.515, y: sceneHeight * 0.11)
                    #endif
                }
                .frame(width: width, height: sceneHeight)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            .coordinateSpace(name: "travelDeskScroll")
            .scrollIndicators(.hidden)
            .refreshable { await reload() }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func travelDeskBackground(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { sceneProxy in
            let pullDistance = max(
                sceneProxy.frame(in: .named("travelDeskScroll")).minY,
                0
            )

            ZStack {
                Image("profile_modern_travel_desk", bundle: .main)
                    .resizable()
                    .frame(width: width, height: height + pullDistance)

                Color.black.opacity(colorScheme == .dark ? 0.28 : 0.02)
            }
            .frame(width: width, height: height + pullDistance)
            .offset(y: -pullDistance)
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var profileHotspot: some View {
        Button {
            if isSignedIn {
                showsAccountPanel = true
            } else {
                onSignIn()
            }
        } label: {
            SceneHologramProjection(
                accent: .dsCyan,
                panelSize: CGSize(width: 150, height: 70),
                rotation: -6.5,
                tilt: 4.5,
                emitterOffset: -17,
                activationDelay: 0.02
            ) {
                HStack(spacing: 8) {
                    HologramAvatarBadge(name: displayName, accent: .dsCyan)
                        .offset(y: -3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .hologramInk(.dsCyan)
                        Text(accountIdentifier)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .hologramInk(.dsCyan)
                        Text("\(accountBadgeTitle) · \(occupiedFriendSlots) 位朋友")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .hologramInk(.dsCyan)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(SceneHotspotButtonStyle())
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
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityHint("调试构建中轻点增加 500 金币")
        #else
        coinLabel(showsDebugAction: false)
        #endif
    }

    private func coinLabel(showsDebugAction: Bool) -> some View {
        let accent = Color(red: 1, green: 0.66, blue: 0.20)

        return SceneHologramProjection(
            accent: accent,
            panelSize: CGSize(width: 96, height: 52),
            rotation: 8,
            tilt: 4,
            emitterOffset: 0,
            activationDelay: 0.06
        ) {
            HStack(spacing: 5) {
                HologramSymbolBadge(systemName: "circle.grid.2x1.fill", accent: accent, size: 11)
                    .offset(y: -2)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        Text("\(profile?.coins ?? 0)")
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .layoutPriority(1)
                        if showsDebugAction {
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .hologramInk(accent)
                    Text("金币")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .hologramInk(accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(profile?.coins ?? 0) 金币")
    }

    private var learningHotspot: some View {
        Button(action: onCalibrateLevel) {
            SceneHologramProjection(
                accent: .dsSky,
                panelSize: CGSize(width: 118, height: 84),
                rotation: 1.4,
                tilt: 3.5,
                emitterOffset: 0,
                activationDelay: 0.10
            ) {
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        HologramSymbolBadge(systemName: "map.fill", accent: .dsSky, size: 11)
                            .offset(y: -2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("英语旅程")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            if let score = profile?.placementScore {
                                Text("校准 \(score) / 100")
                                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                            } else {
                                Text("轻点重新校准")
                                    .font(.system(size: 7, weight: .medium, design: .rounded))
                            }
                        }
                        .hologramInk(.dsSky)
                    }

                    HStack(alignment: .center, spacing: 4) {
                        hologramMetric(
                            title: "当前",
                            value: profile?.difficultyLevel.displayName ?? "载入中"
                        )
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7, weight: .bold))
                            .hologramInk(.dsSky)
                        hologramMetric(
                            title: "目标",
                            value: profile?.learningGoal.displayName ?? "载入中"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityLabel("英语旅程，当前水平 \(profile?.difficultyLevel.displayName ?? "载入中")，学习目标 \(profile?.learningGoal.displayName ?? "载入中")")
        .accessibilityHint("重新校准英语水平")
    }

    private func hologramMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 7, weight: .medium, design: .rounded))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hologramInk(.dsSky)
    }

    private var favoritesHotspot: some View {
        NavigationLink {
            favoritesBuilder()
        } label: {
            sceneHologramMark(
                title: "收藏",
                icon: "star.fill",
                accent: Color(red: 1, green: 0.70, blue: 0.22),
                rotation: -10.5,
                activationDelay: 0.14
            )
        }
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityLabel("收藏夹，单词与语法点")
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
            sceneHologramMark(
                title: "设置",
                icon: "gearshape.fill",
                accent: .dsCyan,
                rotation: 4.5,
                compact: true,
                activationDelay: 0.18
            )
        }
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityLabel("设置，AI、语音与偏好")
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
            sceneHologramMark(
                title: isSignedIn ? "账号" : "登录",
                icon: isSignedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus",
                accent: Color(red: 0.34, green: 0.78, blue: 1),
                rotation: 1.8,
                activationDelay: 0.22
            )
        }
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityLabel(isSignedIn ? "账号与订阅" : "登录或创建账号")
        .accessibilityHint(isSignedIn ? "同步旅程与管理方案" : "跨设备同步与订阅恢复")
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
            sceneHologramMark(
                title: "记忆",
                icon: "brain.head.profile.fill",
                accent: .dsQuiz,
                rotation: 0.8,
                compact: true,
                activationDelay: 0.26
            )
        }
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityLabel("记忆调试面板")
        .accessibilityHint("查看角色长期与近期记忆")
    }
    #endif

    private func sceneHologramMark(
        title: String,
        icon: String,
        accent: Color,
        rotation: Double,
        compact: Bool = false,
        activationDelay: Double
    ) -> some View {
        SceneHologramProjection(
            accent: accent,
            panelSize: CGSize(
                width: compact ? 74 : 84,
                height: compact ? 44 : 50
            ),
            rotation: rotation,
            tilt: compact ? 3 : 4,
            emitterOffset: 0,
            activationDelay: activationDelay
        ) {
            HStack(spacing: compact ? 5 : 7) {
                HologramSymbolBadge(
                    systemName: icon,
                    accent: accent,
                    size: compact ? 11 : 14
                )
                .offset(y: -2)

                Text(title)
                    .font(
                        .system(
                            size: compact ? 9 : 11,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .lineLimit(1)
                    .hologramInk(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct SceneHologramProjection<Content: View>: View {
    let accent: Color
    let panelSize: CGSize
    let rotation: Double
    let tilt: Double
    let emitterOffset: CGFloat
    let activationDelay: Double
    @ViewBuilder let content: () -> Content

    @State private var isMaterialized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .bottom) {
            HologramBeamShape()
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.03),
                            accent.opacity(reduceTransparency ? 0.08 : 0.20),
                            .white.opacity(reduceTransparency ? 0.04 : 0.13),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: panelSize.width * 0.72, height: 30)
                .blur(radius: reduceTransparency ? 0 : 1.8)
                .offset(x: emitterOffset, y: -8)
                .accessibilityHidden(true)

            hologramEmitter
                .offset(x: emitterOffset)

            hologramPanel
                .offset(y: -25)
        }
        .frame(
            width: max(panelSize.width + 18, 64),
            height: panelSize.height + 44,
            alignment: .bottom
        )
        .rotationEffect(.degrees(rotation))
        .rotation3DEffect(
            .degrees(tilt),
            axis: (x: 1, y: 0.12, z: 0),
            anchor: .bottom,
            perspective: 0.52
        )
        .opacity(isMaterialized ? 1 : 0.22)
        .scaleEffect(
            isMaterialized || reduceMotion ? 1 : 0.96,
            anchor: .bottom
        )
        .offset(y: isMaterialized || reduceMotion ? 0 : 4)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.16)
                : .spring(response: 0.38, dampingFraction: 1, blendDuration: 0.08)
                    .delay(activationDelay),
            value: isMaterialized
        )
        .onAppear { isMaterialized = true }
    }

    private var hologramPanel: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let panelOpacity = reduceTransparency ? 0.88 : (contrast == .increased ? 0.72 : 0.48)

        return ZStack {
            shape
                .fill(Color.black.opacity(reduceTransparency ? 0.24 : 0.18))
                .offset(x: 2.4, y: 3.4)

            shape
                .stroke(accent.opacity(reduceTransparency ? 0.18 : 0.34), lineWidth: 0.7)
                .offset(x: 2.4, y: 3.4)

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.025, green: 0.08, blue: 0.14).opacity(panelOpacity),
                            accent.opacity(reduceTransparency ? 0.22 : 0.13),
                            Color(red: 0.05, green: 0.025, blue: 0.13).opacity(panelOpacity * 0.88),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HologramGridShape()
                .stroke(accent.opacity(reduceTransparency ? 0.05 : 0.12), lineWidth: 0.45)
                .clipShape(shape)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.68), accent.opacity(0.32), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.8)
                .offset(y: -panelSize.height * 0.22)
                .blur(radius: reduceTransparency ? 0 : 0.35)

            content()
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .overlay {
            shape.stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(0.88),
                        accent.opacity(0.92),
                        Color(red: 0.62, green: 0.42, blue: 1).opacity(0.74),
                        accent.opacity(0.42),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: contrast == .increased ? 1.25 : 0.85
            )
        }
        .overlay {
            HologramCornerShape()
                .stroke(.white.opacity(0.72), style: StrokeStyle(lineWidth: 1.15, lineCap: .round))
                .padding(3)
        }
        .background {
            shape
                .fill(accent.opacity(reduceTransparency ? 0.06 : 0.22))
                .blur(radius: reduceTransparency ? 0 : 8)
        }
        .shadow(color: accent.opacity(reduceTransparency ? 0.12 : 0.58), radius: 9)
        .shadow(color: Color(red: 0.49, green: 0.35, blue: 1).opacity(0.24), radius: 14)
        .shadow(color: .black.opacity(0.38), radius: 5, x: 1.5, y: 7)
        .compositingGroup()
    }

    private var hologramEmitter: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.34))
                .frame(width: panelSize.width * 0.48, height: 10)
                .blur(radius: 3)
                .offset(y: 2)

            Ellipse()
                .fill(accent.opacity(reduceTransparency ? 0.16 : 0.30))
                .frame(width: panelSize.width * 0.44, height: 9)
                .blur(radius: reduceTransparency ? 0 : 4)

            Ellipse()
                .stroke(accent.opacity(0.95), lineWidth: 1.1)
                .frame(width: panelSize.width * 0.44, height: 9)
                .shadow(color: accent.opacity(0.72), radius: 4)

            Ellipse()
                .stroke(.white.opacity(0.74), lineWidth: 0.6)
                .frame(width: panelSize.width * 0.31, height: 5.5)
        }
        .frame(height: 15)
        .accessibilityHidden(true)
    }
}

private struct HologramBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.08, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.92, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.59, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.41, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct HologramGridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizontalFractions: [CGFloat] = [0.25, 0.5, 0.75]
        for fraction in horizontalFractions {
            path.move(to: CGPoint(x: 0, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        let verticalFractions: [CGFloat] = [0.33, 0.66]
        for fraction in verticalFractions {
            path.move(to: CGPoint(x: rect.width * fraction, y: 0))
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
        }
        return path
    }
}

private struct HologramCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.16
        var path = Path()

        path.move(to: CGPoint(x: 0, y: length))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: length, y: 0))

        path.move(to: CGPoint(x: rect.maxX - length, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: length, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY - length))
        return path
    }
}

private extension View {
    func hologramInk(_ accent: Color) -> some View {
        modifier(HologramInkModifier(accent: accent))
    }
}

private struct HologramInkModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        ZStack {
            content
                .foregroundStyle(accent.opacity(0.94))
                .blur(radius: 4.5)
            content
                .foregroundStyle(Color(red: 0.66, green: 0.45, blue: 1).opacity(0.72))
                .offset(x: 0.8, y: 0.5)
                .blur(radius: 0.45)
            content
                .foregroundStyle(.white.opacity(0.97))
        }
        .compositingGroup()
    }
}

private struct HologramSymbolBadge: View {
    let systemName: String
    let accent: Color
    var size: CGFloat = 17

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.34))
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.white, accent, Color(red: 0.64, green: 0.42, blue: 1), accent],
                        center: .center
                    ),
                    lineWidth: 0.8
                )
            Circle()
                .stroke(accent.opacity(0.48), lineWidth: 3)
                .blur(radius: 4)
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .hologramInk(accent)
        }
        .frame(width: size + 17, height: size + 17)
        .shadow(color: accent.opacity(0.58), radius: 6, y: 1)
    }
}

private struct HologramAvatarBadge: View {
    let name: String
    let accent: Color

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.30))
            Circle()
                .stroke(accent.opacity(0.96), lineWidth: 1)
            Circle()
                .stroke(.white.opacity(0.62), style: StrokeStyle(lineWidth: 0.55, dash: [2, 2]))
                .padding(4)
            Text(initial)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .hologramInk(accent)
        }
        .frame(width: 39, height: 39)
        .background(Circle().fill(accent.opacity(0.22)).blur(radius: 7))
        .shadow(color: accent.opacity(0.66), radius: 7)
    }
}

private struct SceneHotspotButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1, anchor: .bottom)
            .offset(y: configuration.isPressed && !reduceMotion ? 3 : 0)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .brightness(configuration.isPressed ? -0.055 : 0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.08)
                    : .snappy(duration: 0.16, extraBounce: 0),
                value: configuration.isPressed
            )
            .contentShape(Rectangle())
    }
}
