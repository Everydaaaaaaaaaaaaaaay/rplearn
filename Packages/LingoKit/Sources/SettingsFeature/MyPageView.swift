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

    /// 现代旅行者工作台：背景只承载实物，全部入口由统一的实时全息组件绘制。
    private var modernTravelDesk: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let sceneHeight = max(proxy.size.height, width * 1906 / 825)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    travelDeskBackground(width: width, height: sceneHeight)

                    profileHotspot
                        .frame(width: min(width * 0.48, 190), height: 190)
                        .position(x: width * 0.20, y: sceneHeight * 0.195)

                    coinHotspot
                        .frame(width: 118, height: 110)
                        .position(x: width * 0.81, y: sceneHeight * 0.19)

                    learningHotspot
                        .frame(width: min(width * 0.44, 176), height: 210)
                        .position(x: width * 0.515, y: sceneHeight * 0.48)

                    favoritesHotspot
                        .frame(width: 112, height: 120)
                        .position(x: width * 0.16, y: sceneHeight * 0.59)

                    settingsHotspot
                        .frame(width: 106, height: 118)
                        .position(x: width * 0.75, y: sceneHeight * 0.625)

                    accountHotspot
                        .frame(width: 112, height: 120)
                        .position(x: width * 0.49, y: sceneHeight * 0.66)

                    #if DEBUG
                    memoryDebugHotspot
                        .frame(width: 108, height: 120)
                        .position(x: width * 0.52, y: sceneHeight * 0.18)
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
                Image("profile_modern_travel_desk_interactive_scene", bundle: .main)
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
            profileSceneEntry
        }
        .buttonStyle(SceneHologramButtonStyle())
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
            coinSceneEntry
        }
        .buttonStyle(SceneHologramButtonStyle())
        .accessibilityHint("调试构建中轻点增加 500 金币")
        #else
        coinLabel
        #endif
    }

    private var coinLabel: some View {
        coinSceneEntry
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(profile?.coins ?? 0) 金币")
    }

    private var learningHotspot: some View {
        Button(action: onCalibrateLevel) {
            learningSceneEntry
        }
        .buttonStyle(SceneHologramButtonStyle())
        .accessibilityLabel("英语旅程，当前水平 \(profile?.difficultyLevel.displayName ?? "载入中")，学习目标 \(profile?.learningGoal.displayName ?? "载入中")")
        .accessibilityHint("重新校准英语水平")
    }

    private var favoritesHotspot: some View {
        NavigationLink {
            favoritesBuilder()
        } label: {
            fixedSceneEntry(
                icon: "bookmark.fill",
                title: "收藏",
                rotation: -7,
                tilt: 4,
                phase: 0.35
            )
        }
        .buttonStyle(SceneHologramButtonStyle())
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
            fixedSceneEntry(
                icon: "slider.horizontal.3",
                title: "设置",
                rotation: 5,
                tilt: 5,
                phase: 0.8
            )
        }
        .buttonStyle(SceneHologramButtonStyle())
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
            fixedSceneEntry(
                icon: "person.crop.circle.badge.plus",
                title: "登录",
                rotation: 1,
                tilt: 3,
                phase: 1.15
            )
        }
        .buttonStyle(SceneHologramButtonStyle())
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
            fixedSceneEntry(
                icon: "photo.on.rectangle.angled",
                title: "记忆",
                rotation: 1.5,
                tilt: 4,
                phase: 0.1
            )
        }
        .buttonStyle(SceneHologramButtonStyle())
        .accessibilityLabel("记忆调试面板")
        .accessibilityHint("查看角色长期与近期记忆")
    }
    #endif

    private var profileSceneEntry: some View {
        ZStack(alignment: .topLeading) {
            SceneHologram(rotation: -6, tilt: 4, phase: 0) {
                HStack(spacing: 7) {
                    SceneHologramIcon(name: "person.crop.circle.fill", size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        SceneHologramText(displayName, size: 20, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        SceneHologramText(accountBadgeTitle, size: 13, weight: .semibold)
                            .lineLimit(1)
                        SceneHologramText("旅途朋友 \(occupiedFriendSlots)", size: 12, weight: .medium)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 178, height: 105)

            AvatarBadge(name: displayName, tint: .dsSky, size: 43)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 2.2, y: 1.4)
                .rotationEffect(.degrees(-5))
                .position(x: 88, y: 168)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var coinSceneEntry: some View {
        SceneHologram(rotation: 7, tilt: 4, phase: 0.55) {
            VStack(spacing: 2) {
                SceneHologramIcon(
                    name: "circle.grid.2x1.fill",
                    size: 38,
                    tint: .sceneHologramAmber
                )
                SceneHologramText(
                    "\(profile?.coins ?? 0) 金币",
                    size: 21,
                    weight: .bold,
                    tint: .sceneHologramAmber
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var learningSceneEntry: some View {
        SceneHologram(rotation: 1, tilt: 3, phase: 0.25) {
            VStack(spacing: 4) {
                SceneHologramIcon(name: "book.pages.fill", size: 39)
                SceneHologramText("英语旅程", size: 23, weight: .bold)
                SceneHologramText(
                    "\(profile?.difficultyLevel.displayName ?? "载入中") · \(profile?.learningGoal.displayName ?? "载入中")",
                    size: 14,
                    weight: .semibold
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                SceneHologramText(placementSummary, size: 14, weight: .bold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func fixedSceneEntry(
        icon: String,
        title: String,
        rotation: Double,
        tilt: Double,
        phase: Double
    ) -> some View {
        SceneHologram(rotation: rotation, tilt: tilt, phase: phase) {
            VStack(spacing: 2) {
                SceneHologramIcon(name: icon, size: 39)
                SceneHologramText(title, size: 26, weight: .bold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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

    private var placementSummary: String {
        guard let score = profile?.placementScore else { return "等待校准" }
        return "校准 \(score) / 100"
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

private struct SceneHologram<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let rotation: Double
    let tilt: Double
    let phase: Double
    let content: Content

    init(
        rotation: Double,
        tilt: Double,
        phase: Double,
        @ViewBuilder content: () -> Content
    ) {
        self.rotation = rotation
        self.tilt = tilt
        self.phase = phase
        self.content = content()
    }

    var body: some View {
        if reduceMotion {
            layers
        } else {
            layers
                .phaseAnimator([false, true]) { view, raised in
                    view
                        .offset(y: raised ? -1.8 : 1.2)
                        .brightness(raised ? 0.025 : 0)
                } animation: { _ in
                    .easeInOut(duration: 2.55 + phase * 0.22)
                        .delay(phase * 0.18)
                }
        }
    }

    private var layers: some View {
        ZStack {
            content
                .blur(radius: 3.4)
                .scaleEffect(x: 0.98, y: 0.93, anchor: .center)
                .offset(x: 1.4, y: 7.2)
                .opacity(0.11)

            content
        }
        .rotationEffect(.degrees(rotation))
        .rotation3DEffect(
            .degrees(tilt),
            axis: (x: 1, y: 0.12, z: 0),
            anchor: .center,
            perspective: 0.16
        )
    }
}

private struct SceneHologramText: View {
    let value: String
    let size: CGFloat
    let weight: Font.Weight
    let tint: Color

    init(
        _ value: String,
        size: CGFloat,
        weight: Font.Weight,
        tint: Color = .sceneHologramIvory
    ) {
        self.value = value
        self.size = size
        self.weight = weight
        self.tint = tint
    }

    var body: some View {
        Text(value)
            .font(.system(size: size, weight: weight, design: .rounded))
            .tracking(size >= 20 ? -0.45 : 0.08)
            .foregroundStyle(tint.opacity(0.9))
            .textRenderer(SceneHologramTextRenderer(tint: tint))
    }
}

private struct SceneHologramIcon: View {
    let name: String
    let size: CGFloat
    let tint: Color

    init(
        name: String,
        size: CGFloat,
        tint: Color = .sceneHologramIvory
    ) {
        self.name = name
        self.size = size
        self.tint = tint
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint.opacity(0.9))
            .shadow(color: tint.opacity(0.38), radius: 3.1)
            .shadow(color: .black.opacity(0.28), radius: 0.8, y: 0.8)
    }
}

private struct SceneHologramTextRenderer: TextRenderer {
    let tint: Color

    var displayPadding: EdgeInsets {
        EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var depthEdge = context
        depthEdge.addFilter(
            .shadow(
                color: .black.opacity(0.32),
                radius: 1.05,
                y: 0.85,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &depthEdge)

        var glow = context
        glow.opacity = 0.38
        glow.addFilter(
            .shadow(
                color: tint.opacity(0.48),
                radius: 3.2,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &glow)

        draw(layout, in: &context)
    }

    private func draw(_ layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                context.draw(run)
            }
        }
    }
}

private struct SceneHologramButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? 0.075 : 0)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

private extension Color {
    static let sceneHologramIvory = Color(red: 1, green: 0.97, blue: 0.88)
    static let sceneHologramAmber = Color(red: 0.96, green: 0.72, blue: 0.34)
}
