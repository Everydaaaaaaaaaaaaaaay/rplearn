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

    /// 现代旅行者工作台：双层功能牌以统一透视贴合场景中的真实物件。
    private var modernTravelDesk: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let sceneHeight = max(proxy.size.height, width * 1906 / 825)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    travelDeskBackground(width: width, height: sceneHeight)

                    profileHotspot
                        .frame(width: min(width * 0.45, 180), height: 104)
                        .position(x: width * 0.22, y: sceneHeight * 0.135)

                    coinHotspot
                        .frame(width: 112, height: 76)
                        .position(x: width * 0.82, y: sceneHeight * 0.145)

                    learningHotspot
                        .frame(width: min(width * 0.35, 140), height: 112)
                        .position(x: width * 0.515, y: sceneHeight * 0.452)

                    favoritesHotspot
                        .frame(width: 106, height: 76)
                        .position(x: width * 0.17, y: sceneHeight * 0.51)

                    settingsHotspot
                        .frame(width: 104, height: 74)
                        .position(x: width * 0.73, y: sceneHeight * 0.625)

                    accountHotspot
                        .frame(width: 112, height: 78)
                        .position(x: width * 0.50, y: sceneHeight * 0.695)

                    #if DEBUG
                    memoryDebugHotspot
                        .frame(width: 80, height: 68)
                        .position(x: width * 0.515, y: sceneHeight * 0.085)
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
            SceneLayeredControl(
                panelSize: CGSize(width: 154, height: 70),
                rotation: -6.5,
                tilt: 3.2,
                floatDelay: 0.05
            ) {
                HStack(spacing: 10) {
                    MinimalSceneGlyph(kind: .profile)
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text("\(accountIdentifier) · \(accountBadgeTitle)")
                            .font(.system(size: 8, weight: .medium))
                            .lineLimit(1)
                        Text("\(occupiedFriendSlots) 位旅途朋友")
                            .font(.system(size: 8, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
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
            coinLabel
        }
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityHint("调试构建中轻点增加 500 金币")
        #else
        coinLabel
        #endif
    }

    private var coinLabel: some View {
        SceneLayeredControl(
            panelSize: CGSize(width: 94, height: 50),
            rotation: 8,
            tilt: 3,
            floatDelay: 0.18
        ) {
            HStack(spacing: 7) {
                MinimalSceneGlyph(kind: .coins)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(profile?.coins ?? 0)")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .layoutPriority(1)
                    Text("金币")
                        .font(.system(size: 8, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(profile?.coins ?? 0) 金币")
    }

    private var learningHotspot: some View {
        Button(action: onCalibrateLevel) {
            SceneLayeredControl(
                panelSize: CGSize(width: 126, height: 78),
                rotation: 1.4,
                tilt: 2.8,
                floatDelay: 0.32
            ) {
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        MinimalSceneGlyph(kind: .journey)
                            .frame(width: 25, height: 25)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("英语旅程")
                                .font(.system(size: 11, weight: .bold))
                            if let score = profile?.placementScore {
                                Text("校准 \(score) / 100")
                                    .font(.system(size: 7, weight: .medium).monospacedDigit())
                            } else {
                                Text("轻点重新校准")
                                    .font(.system(size: 7, weight: .medium))
                            }
                        }
                    }

                    HStack(alignment: .center, spacing: 4) {
                        sceneMetric(
                            title: "当前",
                            value: profile?.difficultyLevel.displayName ?? "载入中"
                        )
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7, weight: .bold))
                        sceneMetric(
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

    private func sceneMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 7, weight: .medium))
            Text(value)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favoritesHotspot: some View {
        NavigationLink {
            favoritesBuilder()
        } label: {
            sceneLayeredMark(
                title: "收藏",
                glyph: .favorites,
                rotation: -10.5,
                floatDelay: 0.46
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
            sceneLayeredMark(
                title: "设置",
                glyph: .settings,
                rotation: 4.5,
                compact: true,
                floatDelay: 0.60
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
            sceneLayeredMark(
                title: isSignedIn ? "账号" : "登录",
                glyph: .account,
                rotation: 1.8,
                floatDelay: 0.74
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
            sceneLayeredMark(
                title: "记忆",
                glyph: .memory,
                rotation: 0.8,
                compact: true,
                floatDelay: 0.88
            )
        }
        .buttonStyle(SceneHotspotButtonStyle())
        .accessibilityLabel("记忆调试面板")
        .accessibilityHint("查看角色长期与近期记忆")
    }
    #endif

    private func sceneLayeredMark(
        title: String,
        glyph: MinimalSceneGlyph.Kind,
        rotation: Double,
        compact: Bool = false,
        floatDelay: Double
    ) -> some View {
        SceneLayeredControl(
            panelSize: CGSize(
                width: compact ? 78 : 88,
                height: compact ? 44 : 52
            ),
            rotation: rotation,
            tilt: compact ? 2.2 : 2.8,
            floatDelay: floatDelay
        ) {
            HStack(spacing: compact ? 5 : 7) {
                MinimalSceneGlyph(kind: glyph)
                    .frame(
                        width: compact ? 21 : 25,
                        height: compact ? 21 : 25
                    )

                Text(title)
                    .font(
                        .system(
                            size: compact ? 9 : 11,
                            weight: .semibold,
                            design: .default
                        )
                    )
                    .lineLimit(1)
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

private struct SceneLayeredControl<Content: View>: View {
    let panelSize: CGSize
    let rotation: Double
    let tilt: Double
    let floatDelay: Double
    @ViewBuilder let content: () -> Content

    @State private var isContentLifted = false
    @Environment(\.sceneControlIsPressed) private var isPressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            underPlate
                .offset(x: 5.5, y: 7)

            facePlate
                .offset(
                    x: isPressed && !reduceMotion ? 2.8 : 0,
                    y: isPressed && !reduceMotion ? 3.8 : -1.5
                )
        }
        .frame(
            width: max(panelSize.width + 14, 64),
            height: panelSize.height + 16
        )
        .rotationEffect(.degrees(rotation))
        .rotation3DEffect(
            .degrees(tilt),
            axis: (x: 1, y: 0.08, z: 0),
            anchor: .center,
            perspective: 0.42
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.90),
            value: isPressed
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 2.8)
                    .repeatForever(autoreverses: true)
                    .delay(floatDelay)
            ) {
                isContentLifted = true
            }
        }
    }

    private var underPlate: some View {
        let shape = ScenePanelShape(chamfer: min(panelSize.height * 0.15, 8))

        return shape
            .fill(
                LinearGradient(
                    colors: [
                        SceneControlPalette.graphite.opacity(reduceTransparency ? 0.98 : 0.88),
                        SceneControlPalette.graphiteDeep.opacity(reduceTransparency ? 1 : 0.90),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: panelSize.width, height: panelSize.height)
            .overlay {
                shape.stroke(.black.opacity(0.34), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.30), radius: 5, x: 1, y: 5)
            .accessibilityHidden(true)
    }

    private var facePlate: some View {
        let shape = ScenePanelShape(chamfer: min(panelSize.height * 0.15, 8))
        let faceOpacity = reduceTransparency ? 1.0 : (contrast == .increased ? 0.98 : 0.92)

        return ZStack(alignment: .topLeading) {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            SceneControlPalette.faceTop.opacity(faceOpacity),
                            SceneControlPalette.faceBottom.opacity(faceOpacity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Capsule()
                .fill(SceneControlPalette.accent.opacity(contrast == .increased ? 0.90 : 0.66))
                .frame(width: 17, height: 1.5)
                .padding(.leading, 9)
                .padding(.top, 7)

            content()
                .foregroundStyle(SceneControlPalette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: isContentLifted && !isPressed && !reduceMotion ? -1.2 : 0)
                .shadow(color: .white.opacity(0.38), radius: 0.5, y: -0.4)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .overlay {
            shape.stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(0.90),
                        SceneControlPalette.edge.opacity(0.64),
                        SceneControlPalette.graphite.opacity(0.20),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: contrast == .increased ? 1.2 : 0.75
            )
        }
        .shadow(color: SceneControlPalette.accent.opacity(reduceTransparency ? 0 : 0.10), radius: 4)
        .shadow(color: .white.opacity(0.20), radius: 1.5, x: -0.5, y: -1)
        .shadow(color: .black.opacity(0.16), radius: 2.5, x: 0.5, y: 2)
        .compositingGroup()
    }
}

private enum SceneControlPalette {
    static let ink = Color(red: 0.105, green: 0.125, blue: 0.135)
    static let graphite = Color(red: 0.20, green: 0.23, blue: 0.24)
    static let graphiteDeep = Color(red: 0.105, green: 0.125, blue: 0.13)
    static let faceTop = Color(red: 0.965, green: 0.963, blue: 0.935)
    static let faceBottom = Color(red: 0.845, green: 0.855, blue: 0.825)
    static let accent = Color(red: 0.43, green: 0.52, blue: 0.50)
    static let edge = Color(red: 0.57, green: 0.62, blue: 0.59)
}

private struct ScenePanelShape: Shape {
    let chamfer: CGFloat

    func path(in rect: CGRect) -> Path {
        let cut = min(chamfer, min(rect.width, rect.height) * 0.22)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut * 0.55))
        path.addLine(to: CGPoint(x: rect.maxX - cut * 0.55, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut * 0.55))
        path.closeSubpath()
        return path
    }
}

private struct SceneControlPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var sceneControlIsPressed: Bool {
        get { self[SceneControlPressedKey.self] }
        set { self[SceneControlPressedKey.self] = newValue }
    }
}

private struct MinimalSceneGlyph: View {
    enum Kind {
        case profile
        case coins
        case journey
        case favorites
        case settings
        case account
        case memory
    }

    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let stroke = StrokeStyle(
                lineWidth: max(side * 0.065, 1.15),
                lineCap: .square,
                lineJoin: .miter
            )

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + side * x, y: origin.y + side * y)
            }

            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(
                    x: origin.x + side * x,
                    y: origin.y + side * y,
                    width: side * width,
                    height: side * height
                )
            }

            func drawStroke(_ path: Path) {
                context.stroke(path, with: .color(SceneControlPalette.ink), style: stroke)
            }

            func drawFill(_ path: Path) {
                context.fill(path, with: .color(SceneControlPalette.ink))
            }

            switch kind {
            case .profile:
                var head = Path()
                head.addEllipse(in: rect(0.38, 0.16, 0.24, 0.24))
                drawFill(head)

                var shoulders = Path()
                shoulders.move(to: point(0.20, 0.79))
                shoulders.addCurve(
                    to: point(0.80, 0.79),
                    control1: point(0.25, 0.50),
                    control2: point(0.75, 0.50)
                )
                shoulders.addLine(to: point(0.80, 0.86))
                shoulders.addLine(to: point(0.20, 0.86))
                shoulders.closeSubpath()
                drawFill(shoulders)

            case .coins:
                var top = Path()
                top.addEllipse(in: rect(0.17, 0.18, 0.66, 0.26))
                drawStroke(top)

                var body = Path()
                body.move(to: point(0.17, 0.31))
                body.addLine(to: point(0.17, 0.66))
                body.addCurve(
                    to: point(0.83, 0.66),
                    control1: point(0.23, 0.86),
                    control2: point(0.77, 0.86)
                )
                body.addLine(to: point(0.83, 0.31))
                body.move(to: point(0.17, 0.48))
                body.addCurve(
                    to: point(0.83, 0.48),
                    control1: point(0.27, 0.66),
                    control2: point(0.73, 0.66)
                )
                drawStroke(body)

            case .journey:
                var map = Path()
                map.move(to: point(0.12, 0.24))
                map.addLine(to: point(0.38, 0.14))
                map.addLine(to: point(0.62, 0.24))
                map.addLine(to: point(0.88, 0.14))
                map.addLine(to: point(0.88, 0.76))
                map.addLine(to: point(0.62, 0.86))
                map.addLine(to: point(0.38, 0.76))
                map.addLine(to: point(0.12, 0.86))
                map.closeSubpath()
                map.move(to: point(0.38, 0.14))
                map.addLine(to: point(0.38, 0.76))
                map.move(to: point(0.62, 0.24))
                map.addLine(to: point(0.62, 0.86))
                drawStroke(map)

                var route = Path()
                route.move(to: point(0.21, 0.62))
                route.addCurve(
                    to: point(0.77, 0.43),
                    control1: point(0.40, 0.38),
                    control2: point(0.56, 0.70)
                )
                drawStroke(route)

            case .favorites:
                var star = Path()
                star.move(to: point(0.50, 0.10))
                star.addLine(to: point(0.60, 0.40))
                star.addLine(to: point(0.90, 0.50))
                star.addLine(to: point(0.60, 0.60))
                star.addLine(to: point(0.50, 0.90))
                star.addLine(to: point(0.40, 0.60))
                star.addLine(to: point(0.10, 0.50))
                star.addLine(to: point(0.40, 0.40))
                star.closeSubpath()
                drawFill(star)

            case .settings:
                let rows: [(CGFloat, CGFloat)] = [(0.28, 0.64), (0.50, 0.36), (0.72, 0.70)]
                for (y, knobX) in rows {
                    var line = Path()
                    line.move(to: point(0.14, y))
                    line.addLine(to: point(0.86, y))
                    drawStroke(line)

                    var knob = Path()
                    knob.addRect(rect(knobX - 0.07, y - 0.07, 0.14, 0.14))
                    drawFill(knob)
                }

            case .account:
                var card = Path()
                card.addRoundedRect(
                    in: rect(0.10, 0.20, 0.80, 0.60),
                    cornerSize: CGSize(width: side * 0.05, height: side * 0.05)
                )
                drawStroke(card)

                var head = Path()
                head.addEllipse(in: rect(0.22, 0.33, 0.18, 0.18))
                drawFill(head)

                var bust = Path()
                bust.move(to: point(0.17, 0.68))
                bust.addCurve(
                    to: point(0.45, 0.68),
                    control1: point(0.21, 0.50),
                    control2: point(0.41, 0.50)
                )
                bust.closeSubpath()
                drawFill(bust)

                var details = Path()
                details.move(to: point(0.54, 0.39))
                details.addLine(to: point(0.78, 0.39))
                details.move(to: point(0.54, 0.57))
                details.addLine(to: point(0.72, 0.57))
                drawStroke(details)

            case .memory:
                let nodes = [
                    point(0.23, 0.28), point(0.70, 0.20),
                    point(0.80, 0.67), point(0.34, 0.77), point(0.50, 0.48),
                ]
                var links = Path()
                for node in nodes.dropLast() {
                    links.move(to: node)
                    links.addLine(to: nodes[4])
                }
                drawStroke(links)

                for (index, node) in nodes.enumerated() {
                    let radius = side * (index == 4 ? 0.095 : 0.075)
                    var square = Path()
                    square.addRect(
                        CGRect(
                            x: node.x - radius,
                            y: node.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                    )
                    drawFill(square)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SceneHotspotButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.sceneControlIsPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.24, dampingFraction: 0.90),
                value: configuration.isPressed
            )
            .contentShape(Rectangle())
    }
}
