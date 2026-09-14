import BackendKit
import BillingKit
import CoreKit
import DesignSystem
import DomainKit
import PersistenceKit
import PhotosUI
import StoreKit
import SwiftUI

public enum MyPageSection: Sendable { case account, subscription }

/// “我的”聚合页：资料、订阅、金币与二级入口。
public struct MyPageView: View {
    private let accessClient: BackendClient?
    private let economyStore: EconomyStore
    private let economyService: EconomyService
    private let rosterStore: RosterStore
    private let authSession: AuthSession
    private let billing: BillingController
    private let reloadToken: Int
    private let onCalibrateLevel: @MainActor () -> Void
    private let onOpenFavorites: @MainActor () -> Void
    private let onOpenSettings: @MainActor () -> Void
    private let section: MyPageSection?
    private let onOpenAccount: @MainActor () -> Void
    private let onOpenSubscription: @MainActor () -> Void
    private let onOpenMemory: @MainActor () -> Void

    @Environment(\.userAvatar) private var userAvatar
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var avatarError: String?
    @State private var isSavingAvatar = false

    @State private var credits: BackendAccessSnapshot.Credits?
    @State private var creditsError: String?
    @State private var isLoadingCredits = false
    @State private var profile: UserProfileDTO?
    @State private var occupiedFriendSlots = 0
    @StateObject private var sceneActions = DSSceneActionCoordinator<MyPageSceneHotspot>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: MyPagePresentation {
        MyPagePresentation(
            profile: profile,
            tier: billing.tier
        )
    }

    private var sceneLayout: TravelDeskSceneLayout {
        .production
    }

    public init(
        accessClient: BackendClient? = nil,
        economyStore: EconomyStore,
        economyService: EconomyService,
        rosterStore: RosterStore,
        authSession: AuthSession,
        billing: BillingController,
        reloadToken: Int = 0,
        onCalibrateLevel: @escaping @MainActor () -> Void,
        onOpenFavorites: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void,
        onOpenMemory: @escaping @MainActor () -> Void = {},
        section: MyPageSection? = nil,
        onOpenAccount: @escaping @MainActor () -> Void = {},
        onOpenSubscription: @escaping @MainActor () -> Void = {}
    ) {
        self.accessClient = accessClient
        self.economyStore = economyStore
        self.economyService = economyService
        self.rosterStore = rosterStore
        self.authSession = authSession
        self.billing = billing
        self.reloadToken = reloadToken
        self.onCalibrateLevel = onCalibrateLevel
        self.onOpenFavorites = onOpenFavorites
        self.onOpenSettings = onOpenSettings
        self.onOpenMemory = onOpenMemory
        self.section = section
        self.onOpenAccount = onOpenAccount
        self.onOpenSubscription = onOpenSubscription
    }

    public var body: some View {
        Group {
            if section == .subscription {
                SubscriptionView(billing: billing)
            } else if let section {
                detailPage(section)
            } else if dynamicTypeSize.isAccessibilitySize {
                accessibleContent
            } else {
                modernTravelDesk
            }
        }
        .background(Color.dsBackground.ignoresSafeArea())
        .task(id: reloadToken) { await reload() }
        .task(id: selectedAvatar) {
            guard let item = selectedAvatar, let userAvatar else { return }
            isSavingAvatar = true
            defer { isSavingAvatar = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                try Task.checkCancellation()
                try await userAvatar.save(photoData: data)
            } catch is CancellationError {
            } catch {
                avatarError = "头像保存失败：\(error.localizedDescription)"
            }
        }
        .alert("未能更换头像", isPresented: Binding(
            get: { avatarError != nil }, set: { if !$0 { avatarError = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(avatarError ?? "") }
        .onDisappear(perform: sceneActions.cancel)

    }

    private var accessibleContent: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileCard
                learningProfileCard
                Button("会员订阅", action: onOpenSubscription)
                usageButton
                entryList
                debugCard
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
            .dsSceneDragMotion(viewport: proxy.size)
            .background { compactHeightBackdrop(size: proxy.size) }
            .clipped()
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .dsSceneTabBarBackground()
    }

    /// 极短屏幕缩小参考画布后只会留下很窄的侧边余量；使用同源场景作柔化衬底，
    /// 避免硬色带，同时不参与任何入口的定位与点击。
    private func compactHeightBackdrop(size: CGSize) -> some View {
        MyPageCompactTravelDeskBackdrop(
            assetName: sceneLayout.assetName,
            size: size,
            overlayOpacity: colorScheme == .dark ? 0.3 : 0.035
        )
            .equatable()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// 所有背景像素、入口、微光和点击区域都在同一参考画布中布局。
    /// 运行时只整体等比缩放画布，避免不同 iPhone 宽度下出现独立取整与锚点漂移。
    private var travelDeskCanvas: some View {
        let width = TravelDeskLayout.canvasWidth
        let sceneHeight = TravelDeskLayout.canvasHeight
        let layout = sceneLayout

        return ZStack(alignment: .topLeading) {
            travelDeskBackground(width: width, height: sceneHeight)

            profileHotspot
                .frame(width: layout.profile.size.width, height: layout.profile.size.height)
                .position(x: width * layout.profile.center.x, y: sceneHeight * layout.profile.center.y)

            coinHotspot
                .frame(width: layout.coin.size.width, height: layout.coin.size.height)
                .position(x: width * layout.coin.center.x, y: sceneHeight * layout.coin.center.y)

            learningHotspot
                .frame(width: layout.learning.size.width, height: layout.learning.size.height)
                .position(x: width * layout.learning.center.x, y: sceneHeight * layout.learning.center.y)

            favoritesHotspot
                .frame(width: layout.favorites.size.width, height: layout.favorites.size.height)
                .position(x: width * layout.favorites.center.x, y: sceneHeight * layout.favorites.center.y)

            settingsHotspot
                .frame(width: layout.settings.size.width, height: layout.settings.size.height)
                .position(x: width * layout.settings.center.x, y: sceneHeight * layout.settings.center.y)

            accountHotspot
                .frame(width: layout.account.size.width, height: layout.account.size.height)
                .position(x: width * layout.account.center.x, y: sceneHeight * layout.account.center.y)

            memoryDebugHotspot
                .frame(width: layout.memory.size.width, height: layout.memory.size.height)
                .position(x: width * layout.memory.center.x, y: sceneHeight * layout.memory.center.y)
        }
        .frame(width: width, height: sceneHeight, alignment: .topLeading)
    }

    private func travelDeskBackground(width: CGFloat, height: CGFloat) -> some View {
        MyPageTravelDeskBackground(
            assetName: sceneLayout.assetName,
            size: CGSize(width: width, height: height),
            overlayOpacity: colorScheme == .dark ? 0.28 : 0.02
        )
            .equatable()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var profileHotspot: some View {
        Button {
            sceneActions.perform(for: .profile) {
                onOpenAccount()
            }
        } label: {
            profileSceneEntry
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .profile))
        .accessibilityIdentifier("me.profile")
        .accessibilityLabel("个人资料，\(presentation.displayName)，\(presentation.accountBadgeTitle)，已认识 \(occupiedFriendSlots) 位旅途朋友")
        .accessibilityHint("查看账号、用量与权益")
    }

    private var coinHotspot: some View {
        coinLabel
            .accessibilityIdentifier("me.coinBalance")
    }

    private var coinLabel: some View {
        coinSceneEntry
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(profile?.coins ?? 0) 金币")
    }

    private var learningHotspot: some View {
        Button {
            sceneActions.perform(for: .learning, action: onCalibrateLevel)
        } label: {
            learningSceneEntry
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .learning))
        .accessibilityIdentifier("me.level")
        .accessibilityLabel("英语旅程，当前水平 \(profile?.difficultyLevel.displayName ?? "载入中")，学习目标 \(profile?.learningGoal.displayName ?? "载入中")")
        .accessibilityHint("重新校准英语水平")
    }

    private var favoritesHotspot: some View {
        Button {
            sceneActions.perform(for: .favorites, action: onOpenFavorites)
        } label: {
            fixedSceneEntry(
                glyph: .bookmarkStar,
                title: "收藏",
                plane: sceneLayout.favorites.plane,
                scale: sceneLayout.favorites.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .favorites))
        .accessibilityLabel("收藏夹，单词与语法点")
        .accessibilityHint("查看收藏的单词与语法点")
    }

    private var settingsHotspot: some View {
        Button {
            sceneActions.perform(for: .settings, action: onOpenSettings)
        } label: {
            fixedSceneEntry(
                glyph: .system("slider.horizontal.3"),
                title: "设置",
                plane: sceneLayout.settings.plane,
                scale: sceneLayout.settings.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .settings))
        .accessibilityLabel("设置，AI、语音与偏好")
        .accessibilityHint("打开设置")
    }

    private var accountHotspot: some View {
        Button {
            sceneActions.perform(for: .account) {
                onOpenSubscription()
            }
        } label: {
            fixedSceneEntry(
                glyph: .system("sparkles.rectangle.stack"),
                title: "订阅",
                plane: sceneLayout.account.plane,
                scale: sceneLayout.account.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .account))
        .accessibilityIdentifier("me.subscription")
        .accessibilityLabel("会员订阅")
        .accessibilityHint("查看会员权益与订阅方案")
    }

    private var memoryDebugHotspot: some View {
        Button {
            sceneActions.perform(for: .memory, action: onOpenMemory)
        } label: {
            fixedSceneEntry(
                glyph: .system("photo"),
                title: "记忆",
                plane: sceneLayout.memory.plane,
                scale: sceneLayout.memory.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .memory))
        .accessibilityLabel("记忆档案")
        .accessibilityHint("查看角色长期与近期记忆")
    }

    private var profileSceneEntry: some View {
        let scale = sceneLayout.profile.contentScale

        return MyPageProfileSceneEntry(
            plane: sceneLayout.profile.plane,
            scale: scale,
            displayName: presentation.displayName,
            accountBadgeTitle: presentation.accountBadgeTitle,
            occupiedFriendSlots: occupiedFriendSlots
        )
    }

    private var coinSceneEntry: some View {
        fixedSceneEntry(
            glyph: .coinStacks,
            title: "\(profile?.coins ?? 0) 金币",
            plane: sceneLayout.coin.plane,
            tint: .sceneHologramYellow,
            scale: sceneLayout.coin.contentScale
        )
    }

    private var learningSceneEntry: some View {
        let scale = sceneLayout.learning.contentScale

        return SceneHologram(plane: sceneLayout.learning.plane) {
            VStack(spacing: 7 * scale) {
                SceneHologramIcon(glyph: .journeyBook, size: 44 * scale)
                SceneHologramText("英语旅程", size: 20 * scale, weight: .bold)
                SceneHologramText(
                    "\(profile?.difficultyLevel.displayName ?? "载入中") · \(profile?.learningGoal.displayName ?? "载入中")",
                    size: 11.25 * scale,
                    weight: .semibold
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 8)
                SceneHologramText(presentation.placementSummary, size: 11.5 * scale, weight: .bold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func fixedSceneEntry(
        glyph: SceneHologramGlyph,
        title: String,
        plane: SceneHologramPlane,
        tint: Color = .sceneHologramYellow,
        scale: CGFloat
    ) -> some View {
        SceneHologram(plane: plane, tint: tint) {
            VStack(spacing: 6 * scale) {
                SceneHologramIcon(glyph: glyph, size: 48 * scale, tint: tint)
                SceneHologramText(title, size: 24 * scale, weight: .bold, tint: tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func avatarPicker(size: CGFloat) -> some View {
        let avatar = UserAvatar(name: presentation.displayName, size: size)
        let saving = isSavingAvatar
        return PhotosPicker(selection: $selectedAvatar, matching: .images) {
            avatar
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dsSkyDeep)
                        .padding(6).background(.regularMaterial, in: Circle())
                }
                .overlay { if saving { ProgressView() } }
        }
        .buttonStyle(.plain)
        .disabled(isSavingAvatar || userAvatar == nil)
        .accessibilityLabel("从相册更换头像")
        .accessibilityIdentifier("profile.avatarPicker")
    }

    private var profileCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(spacing: DSSpacing.sm) {
                        avatarPicker(size: 60)
                        Text(presentation.displayName)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DSChip(
                        presentation.accountBadgeTitle,
                        tint: presentation.accountBadgeTint,
                        prominent: billing.tier != .free
                    )
                    Label("已认识 \(occupiedFriendSlots) 位旅途朋友", systemImage: "person.2.fill")
                        .foregroundStyle(.secondary)
                    Label("\(profile?.coins ?? 0) 金币", systemImage: "circle.grid.2x1.fill")
                        .foregroundStyle(Color.dsSunset)
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: DSSpacing.md) {
                    avatarPicker(size: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.displayName)
                            .font(.title2.bold())
                        DSChip(
                            presentation.accountBadgeTitle,
                            tint: presentation.accountBadgeTint,
                            prominent: billing.tier != .free
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

    private var accountCredits: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("AI 积分").font(.headline)
            if let credits {
                LabeledContent("可用积分", value: credits.remaining.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("已用积分", value: credits.used.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("本期额度", value: credits.limit.formatted(.number.precision(.fractionLength(2))))
            } else if isLoadingCredits {
                ProgressView("正在读取积分…")
            } else {
                Text(creditsError ?? "暂无积分用量")
                    .font(.footnote)
                    .foregroundStyle(Color.dsPaperInkSecondary)
                Button("重试") { Task { await reloadCredits() } }
            }
            usageButton
            Button(action: onOpenSubscription) {
                HStack {
                    Label("查看会员订阅", systemImage: "sparkles")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.subscription")
        }
        .monospacedDigit()
    }

    private func reloadCredits() async {
        guard let accessClient, !isLoadingCredits else { return }
        isLoadingCredits = true
        defer { isLoadingCredits = false }
        do {
            credits = try await accessClient.accessSnapshot().credits
            creditsError = nil
        } catch is CancellationError {
        } catch {
            creditsError = "积分暂时无法加载，请重试。"
        }
    }

    private var usageButton: some View {
        Group {
            if let accessClient {
                NavigationLink {
                    UsageAccessView(backend: accessClient, billing: billing)
                } label: {
                    HStack {
                        Label("积分余额与明细", systemImage: "chart.bar.fill")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("me.credits")
            }
        }
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

    private var entryList: some View {
        VStack(spacing: 0) {
            Button(action: onOpenFavorites) {
                MyPageEntryRow("收藏夹", subtitle: "收集旅途中遇到的单词与语法点", icon: "star.fill", tint: .dsSunset)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            Button(action: onOpenSettings) {
                MyPageEntryRow("设置", subtitle: "AI、语音与学习偏好", icon: "gearshape.fill", tint: .dsSky)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            Button(role: .destructive) {
                Task { await authSession.logout() }
            } label: {
                MyPageEntryRow(
                    "退出登录",
                    subtitle: "退出账号并返回登录页",
                    icon: "rectangle.portrait.and.arrow.right",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
        }
        .dsSurface(.grouped, padding: 0)
    }

    private var debugCard: some View {
        VStack(spacing: 0) {
            Button(action: onOpenMemory) {
                MyPageEntryRow("记忆档案", subtitle: "查看角色长期与近期记忆", icon: "brain.head.profile", tint: .dsQuiz)
            }
            .buttonStyle(.plain)
        }
        .dsSurface(.grouped, padding: 0)
    }

    private func reload() async {
        async let loadedProfile = try? economyStore.profile()
        async let loadedSlots = try? rosterStore.occupiedFriendSlots()
        profile = await loadedProfile
        occupiedFriendSlots = await loadedSlots ?? 0
    }
}

extension MyPageView {
    private func detailPage(_ section: MyPageSection) -> some View {
        ZStack {
            DSWorkbenchBackdrop(focus: section == .account ? .profile : .subscription)
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    if section == .account {
                        DSWorkbenchPaperSheet {
                            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                                HStack(spacing: DSSpacing.md) {
                                    avatarPicker(size: 72)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(presentation.displayName)
                                            .font(.title2.bold())
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(presentation.accountBadgeTitle)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.dsPaperInkSecondary)
                                        Text("已认识 \(occupiedFriendSlots) 位旅途朋友")
                                            .font(.footnote)
                                            .foregroundStyle(Color.dsPaperInkSecondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                Divider()
                                accountCredits
                                Divider()
                                NavigationLink {
                                    AccountSecurityView(session: authSession)
                                } label: {
                                    HStack {
                                        Label("账号与安全", systemImage: "person.badge.key.fill")
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                    }
                                    .frame(minHeight: 44)
                                }
                                Link(destination: URL(string: "https://qm.qq.com/q/Ft5ajqgxOw")!) {
                                    HStack(spacing: DSSpacing.sm) {
                                        Image(systemName: "person.2.fill")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("加入测试群")
                                            Text("咕游记Coovingo测试 · 群号 1104063286")
                                                .font(.footnote)
                                                .foregroundStyle(Color.dsPaperInkSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .frame(minHeight: 44)
                                }
                                .accessibilityIdentifier("profile.testGroup")
                                Button(role: .destructive) {
                                    Task { await authSession.logout() }
                                } label: {
                                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .foregroundStyle(Color.dsPaperInk)
                .frame(maxWidth: 620)
                .padding(DSSpacing.lg)
                .padding(.bottom, DSSpacing.lg)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .task { await reloadCredits() }
            .refreshable {
                await reload()
                await reloadCredits()
            }
        }
    }
}
