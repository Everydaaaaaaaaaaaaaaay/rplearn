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
            let widthScale = proxy.size.width / TravelDeskLayout.canvasWidth
            let heightScale = proxy.size.height / TravelDeskLayout.interactiveContentBottom
            let sceneScale = min(widthScale, heightScale)
            let horizontalInset = max(
                0,
                (proxy.size.width - TravelDeskLayout.canvasWidth * sceneScale) / 2
            )

            ZStack(alignment: .topLeading) {
                if sceneScale < widthScale {
                    compactHeightBackdrop(size: proxy.size)
                }

                travelDeskCanvas
                    .frame(
                        width: TravelDeskLayout.canvasWidth,
                        height: TravelDeskLayout.canvasHeight,
                        alignment: .topLeading
                    )
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .scaleEffect(sceneScale, anchor: .topLeading)
                    .offset(x: horizontalInset)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .clipped()
        }
        .ignoresSafeArea(edges: .top)
    }

    /// 极短屏幕缩小参考画布后只会留下很窄的侧边余量；使用同源场景作柔化衬底，
    /// 避免硬色带，同时不参与任何入口的定位与点击。
    private func compactHeightBackdrop(size: CGSize) -> some View {
        Image("profile_modern_travel_desk_interactive_scene", bundle: .main)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .blur(radius: 5)
            .overlay(Color.black.opacity(colorScheme == .dark ? 0.3 : 0.035))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// 所有背景像素、入口、微光和点击区域都在同一参考画布中布局。
    /// 运行时只整体等比缩放画布，避免不同 iPhone 宽度下出现独立取整与锚点漂移。
    private var travelDeskCanvas: some View {
        let width = TravelDeskLayout.canvasWidth
        let sceneHeight = TravelDeskLayout.canvasHeight

        return ZStack(alignment: .topLeading) {
            travelDeskBackground(width: width, height: sceneHeight)

            profileHotspot
                .frame(width: 190, height: 190)
                .position(x: width * 0.20, y: sceneHeight * 0.195)

            coinHotspot
                .frame(width: 118, height: 110)
                .position(x: width * 0.845, y: sceneHeight * 0.19)

            learningHotspot
                .frame(width: 176, height: 210)
                .position(x: width * 0.54, y: sceneHeight * 0.41)

            favoritesHotspot
                .frame(width: 112, height: 120)
                .position(x: width * 0.135, y: sceneHeight * 0.59)

            settingsHotspot
                .frame(width: 112, height: 124)
                .position(x: width * 0.82, y: sceneHeight * 0.605)

            accountHotspot
                .frame(width: 118, height: 126)
                .position(x: width * 0.52, y: sceneHeight * 0.66)

            #if DEBUG
            memoryDebugHotspot
                .frame(width: 114, height: 126)
                .position(x: width * 0.535, y: sceneHeight * 0.12)
            #endif
        }
        .frame(width: width, height: sceneHeight, alignment: .topLeading)
    }

    private func travelDeskBackground(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Image("profile_modern_travel_desk_interactive_scene", bundle: .main)
                .resizable()
                .frame(width: width, height: height)

            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.02)
        }
        .frame(width: width, height: height)
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
        .accessibilityLabel("\(profile?.coins ?? 0) 金币")
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
                plane: .phrasebook
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
                plane: .watch
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
                plane: .phone
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
                plane: .camera
            )
        }
        .buttonStyle(SceneHologramButtonStyle())
        .accessibilityLabel("记忆调试面板")
        .accessibilityHint("查看角色长期与近期记忆")
    }
    #endif

    private var profileSceneEntry: some View {
        ZStack(alignment: .topLeading) {
            SceneHologram(plane: .identityHolder) {
                VStack(spacing: 5) {
                    SceneHologramIcon(name: "person.crop.circle", size: 46)

                    VStack(alignment: .leading, spacing: 0) {
                        SceneHologramText(displayName, size: 17, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        SceneHologramText(accountBadgeTitle, size: 14, weight: .semibold)
                            .lineLimit(1)
                        SceneHologramText("\(occupiedFriendSlots) 位旅途朋友", size: 12, weight: .medium)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 150, height: 138)
            .position(x: 78, y: 58)

            AvatarBadge(name: displayName, tint: .dsSky, size: 43)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 2.2, y: 1.4)
                .rotationEffect(.degrees(-5))
                .position(x: 76, y: 168)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var coinSceneEntry: some View {
        SceneHologram(
            plane: .wallet,
            tint: .sceneHologramAmber
        ) {
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
        SceneHologram(plane: .tablet) {
            VStack(spacing: 4) {
                SceneHologramIcon(name: "book.pages.fill", size: 43)
                SceneHologramText("英语旅程", size: 25, weight: .bold)
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
        plane: SceneHologramPlane
    ) -> some View {
        SceneHologram(plane: plane) {
            VStack(spacing: 2) {
                SceneHologramIcon(name: icon, size: 43)
                SceneHologramText(title, size: 28, weight: .bold)
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

/// 视觉稿以 iPhone 17 Pro 的 402 pt 宽度为参考；高度严格保持 825 × 1906 母版比例。
/// 任何机型适配都只能缩放这个画布，不能分别重算图片与入口的位置。
private enum TravelDeskLayout {
    static let canvasWidth: CGFloat = 402
    static let canvasHeight: CGFloat = canvasWidth * 1906 / 825

    /// 参考画布中最低入口（登录）的视觉与点击范围底边，含少量微光余量。
    /// 短屏按此高度整体缩放，保证入口停在系统 Tab 栏上方。
    static let interactiveContentBottom: CGFloat = 682
}

/// 每个入口都使用承载物自身的局部平面，而不是套用同一组“伪透视”。
/// 参数按 825 × 1906 的母版逐物件校准；足迹方向同时表达悬浮高度与环境光方向。
private struct SceneHologramPlane {
    let rotationZ: Double
    let tiltX: Double
    let tiltY: Double
    let perspective: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let footprintOffset: CGSize
    let extrusionOffset: CGSize
    let footprintWidth: CGFloat
    let pedestalOffset: CGSize?

    static let identityHolder = SceneHologramPlane(
        rotationZ: -3,
        tiltX: 8,
        tiltY: -2,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.985,
        footprintOffset: CGSize(width: 3, height: 13),
        extrusionOffset: CGSize(width: 1, height: 2.6),
        footprintWidth: 66,
        pedestalOffset: CGSize(width: 4, height: 66)
    )
    static let camera = SceneHologramPlane(
        rotationZ: 0,
        tiltX: 6,
        tiltY: 1,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.99,
        footprintOffset: CGSize(width: 1, height: 13),
        extrusionOffset: CGSize(width: 0.5, height: 2.6),
        footprintWidth: 62,
        pedestalOffset: nil
    )
    static let wallet = SceneHologramPlane(
        rotationZ: 3,
        tiltX: 7,
        tiltY: -2,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: -3, height: 13),
        extrusionOffset: CGSize(width: -0.8, height: 2.6),
        footprintWidth: 66,
        pedestalOffset: CGSize(width: -2, height: 45)
    )
    static let tablet = SceneHologramPlane(
        rotationZ: 1,
        tiltX: 6,
        tiltY: -1,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.985,
        footprintOffset: CGSize(width: -1, height: 14),
        extrusionOffset: CGSize(width: -0.4, height: 2.8),
        footprintWidth: 78,
        pedestalOffset: nil
    )
    static let phrasebook = SceneHologramPlane(
        rotationZ: -3.5,
        tiltX: 7,
        tiltY: 1.5,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: 3, height: 13),
        extrusionOffset: CGSize(width: 0.8, height: 2.6),
        footprintWidth: 60,
        pedestalOffset: nil
    )
    static let watch = SceneHologramPlane(
        rotationZ: 4.5,
        tiltX: 9,
        tiltY: -2.5,
        perspective: 0.22,
        scaleX: 1,
        scaleY: 0.97,
        footprintOffset: CGSize(width: -3, height: 14),
        extrusionOffset: CGSize(width: -0.8, height: 2.9),
        footprintWidth: 60,
        pedestalOffset: nil
    )
    static let phone = SceneHologramPlane(
        rotationZ: 0.5,
        tiltX: 6,
        tiltY: 0,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: -2, height: 14),
        extrusionOffset: CGSize(width: -0.6, height: 2.8),
        footprintWidth: 64,
        pedestalOffset: nil
    )
}

private struct SceneHologram<Content: View>: View {
    let plane: SceneHologramPlane
    let tint: Color
    let content: Content

    init(
        plane: SceneHologramPlane,
        tint: Color = .sceneHologramIvory,
        @ViewBuilder content: () -> Content
    ) {
        self.plane = plane
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        layers
    }

    private var layers: some View {
        ZStack {
            if let pedestalOffset = plane.pedestalOffset {
                SceneHologramPedestal(
                    tint: tint,
                    width: plane.footprintWidth
                )
                .offset(pedestalOffset)
            }

            content
                .blur(radius: 7.5)
                .offset(
                    x: plane.footprintOffset.width,
                    y: plane.footprintOffset.height
                )
                .opacity(0.13)
                .accessibilityHidden(true)

            content
                .blur(radius: 3.6)
                .opacity(0.36)
                .accessibilityHidden(true)

            ForEach(1 ... 3, id: \.self) { slice in
                content
                    .offset(
                        x: plane.extrusionOffset.width * CGFloat(slice) / 3,
                        y: plane.extrusionOffset.height * CGFloat(slice) / 3
                    )
                    .opacity(0.11)
                    .accessibilityHidden(true)
            }

            content
        }
        .scaleEffect(x: plane.scaleX, y: plane.scaleY)
        .rotationEffect(.degrees(plane.rotationZ))
        .rotation3DEffect(
            .degrees(plane.tiltX),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: plane.perspective
        )
        .rotation3DEffect(
            .degrees(plane.tiltY),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: plane.perspective
        )
    }
}

private struct SceneHologramPedestal: View {
    let tint: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            Ellipse()
                .fill(tint.opacity(0.34))
                .frame(width: width, height: 10)
                .blur(radius: 7)

            Ellipse()
                .stroke(tint.opacity(0.82), lineWidth: 1.2)
                .frame(width: width * 0.72, height: 7)
                .blur(radius: 0.7)

            HStack(spacing: 6) {
                Capsule()
                    .frame(width: 1.2, height: 13)
                Capsule()
                    .frame(width: 1.2, height: 18)
                Capsule()
                    .frame(width: 1.2, height: 13)
            }
            .foregroundStyle(tint.opacity(0.3))
            .blur(radius: 1.8)
            .offset(y: -8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            .foregroundStyle(tint.opacity(0.98))
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
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(0.42), radius: 10)
            .shadow(color: tint.opacity(0.82), radius: 3.4)
            .shadow(color: .white.opacity(0.48), radius: 1)
            .shadow(color: .black.opacity(0.36), radius: 0.8, y: 1)
    }
}

private struct SceneHologramTextRenderer: TextRenderer {
    let tint: Color

    var displayPadding: EdgeInsets {
        EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
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

        var outerGlow = context
        outerGlow.opacity = 0.36
        outerGlow.addFilter(
            .shadow(
                color: tint.opacity(0.55),
                radius: 9,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &outerGlow)

        var innerGlow = context
        innerGlow.opacity = 0.75
        innerGlow.addFilter(
            .shadow(
                color: tint.opacity(0.85),
                radius: 3,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &innerGlow)

        var edgeLight = context
        edgeLight.opacity = 0.42
        edgeLight.translateBy(x: 0.7, y: 1.1)
        edgeLight.addFilter(
            .shadow(
                color: .white.opacity(0.75),
                radius: 1.2,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &edgeLight)

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
    static let sceneHologramIvory = Color(red: 1, green: 0.99, blue: 0.95)
    static let sceneHologramAmber = Color(red: 0.96, green: 0.72, blue: 0.34)
}
