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
    private let isVisible: Bool
    private let regionCatalog: RegionCatalog?
    private let onCalibrateLevel: @MainActor () -> Void
    private let onOpenFavorites: @MainActor () -> Void
    private let onOpenSettings: @MainActor () -> Void
    private let section: MyPageSection?
    private let onOpenAccount: @MainActor () -> Void
    private let onOpenSubscription: @MainActor () -> Void

    @Environment(\.userAvatar) private var userAvatar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var avatarError: String?
    @State private var isSavingAvatar = false

    @State private var creditBalance = MyPageCreditBalance()
    @State private var profile: UserProfileDTO?
    @State private var occupiedFriendSlots = 0
    @State private var hasEntered = false

    private var presentation: MyPagePresentation {
        MyPagePresentation(
            profile: profile,
            tier: billing.tier
        )
    }

    public init(
        accessClient: BackendClient? = nil,
        economyStore: EconomyStore,
        economyService: EconomyService,
        rosterStore: RosterStore,
        authSession: AuthSession,
        billing: BillingController,
        reloadToken: Int = 0,
        isVisible: Bool = true,
        regionCatalog: RegionCatalog? = nil,
        onCalibrateLevel: @escaping @MainActor () -> Void,
        onOpenFavorites: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void,
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
        self.isVisible = isVisible
        self.regionCatalog = regionCatalog
        self.onCalibrateLevel = onCalibrateLevel
        self.onOpenFavorites = onOpenFavorites
        self.onOpenSettings = onOpenSettings
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
            } else {
                hubContent
            }
        }
        .background(Puff.Palette.page.ignoresSafeArea())
        .task(id: "\(reloadToken)-\(isVisible)") {
            guard isVisible else { return }
            await reload()
            if !hasEntered {
                try? await Task.sleep(for: .milliseconds(40))
                hasEntered = true
            }
            if section == nil { await creditBalance.reload(using: accessClient) }
        }
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

    }

    private var cityName: String {
        guard let id = profile?.currentRegionID else { return "" }
        return regionCatalog?.region(id: id)?.nameZh ?? BackendAppointment.cityDisplayName(id: id, fallback: id)
    }

    private var hubContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Puff.Space.m) {
                hubProfile
                    .puffEntrance(index: 0, isShown: hasEntered)
                hubGroup("英语旅程") { hubLearning }
                    .puffEntrance(index: 1, isShown: hasEntered)
                hubGroup("会员与资产") { hubMembership }
                    .puffEntrance(index: 2, isShown: hasEntered)
                hubGroup("常用") {
                    VStack(spacing: 0) {
                        Button(action: onOpenFavorites) {
                            hubRow("收藏夹", symbol: "bookmark.fill", candy: .bubblegum)
                        }
                        .accessibilityIdentifier("me.favorites")
                        hubDivider
                        Button(action: onOpenSettings) {
                            hubRow("设置", symbol: "gearshape.fill", candy: .sky)
                        }
                        .accessibilityLabel("设置，AI、语音与偏好")
                        .accessibilityIdentifier("me.settings")
                    }
                    .buttonStyle(.puffRow)
                    .padding(.vertical, 6)
                    .puffCard(radius: Puff.Radius.huge)
                }
                .puffEntrance(index: 3, isShown: hasEntered)
            }
            .padding(.horizontal, Puff.Space.m).padding(.top, 2).padding(.bottom, Puff.Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await reload(); await creditBalance.reload(using: accessClient) }
        .puffPageHeader(title: "我的")
    }

    private func hubGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Puff.Space.xs) {
            Text(title)
                .font(.puff(.subheadline, Puff.Weight.emphasis))
                .foregroundStyle(Puff.Palette.inkSoft)
                .padding(.horizontal, Puff.Space.xs)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// 个人卡片：所在城市的卡通画上探出头像。
    private var hubProfile: some View {
        Button(action: onOpenAccount) {
            VStack(spacing: 0) {
                PuffCityScene(regionID: profile?.currentRegionID, viewport: .east, isActive: isVisible)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                    .padding([.horizontal, .top], 6)
                HStack(alignment: .bottom, spacing: Puff.Space.s) {
                    UserAvatar(name: presentation.displayName, size: 78)
                        .padding(5)
                        .background(Puff.Palette.card, in: Circle())
                        .offset(y: -6)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.displayName)
                            .font(.puff(.title2, Puff.Weight.display))
                            .foregroundStyle(Puff.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            if !cityName.isEmpty {
                                PuffTag(cityName, systemImage: "location.fill", candy: .sky)
                            }
                            PuffTag(presentation.accountBadgeTitle, systemImage: "crown.fill", candy: .sunny)
                        }
                    }
                    .padding(.bottom, Puff.Space.m)
                    Spacer(minLength: Puff.Space.xs)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: Puff.Weight.icon, design: .rounded))
                        .foregroundStyle(Puff.Palette.inkFaint)
                        .padding(.bottom, Puff.Space.l)
                }
                .padding(.horizontal, Puff.Space.m)
                .padding(.top, -34)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.huge))
        .accessibilityIdentifier("me.profile")
        .accessibilityValue(cityName)
        .accessibilityLabel("个人资料，\(presentation.displayName)，\(presentation.accountBadgeTitle)，已认识 \(occupiedFriendSlots) 位旅途朋友")
    }

    private var hubLearning: some View {
        Button(action: onCalibrateLevel) {
            HStack(spacing: Puff.Space.s) {
                PuffIconBubble("book.pages.fill", candy: .grape, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.difficultyLevel.displayName ?? "英语旅程")
                        .font(.puff(.headline, Puff.Weight.title))
                        .foregroundStyle(Puff.Palette.ink)
                    if let profile {
                        Text(profile.learningGoalsDisplayName)
                            .font(.puff(.subheadline, Puff.Weight.label))
                            .foregroundStyle(Puff.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PuffTag(presentation.placementSummary, systemImage: "chart.bar.fill", candy: .grape)
                }
                Spacer(minLength: 0)
                hubChevron
            }
            .padding(Puff.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.huge))
        .accessibilityLabel("英语旅程，\(profile?.difficultyLevel.displayName ?? "读取中")，\(profile?.learningGoalsDisplayName ?? "")，\(presentation.placementSummary)")
        .accessibilityIdentifier("me.learning")
    }

    private var hubMembership: some View {
        VStack(spacing: 0) {
            Button(action: onOpenSubscription) {
                HStack(spacing: Puff.Space.s) {
                    PuffIconBubble("crown.fill", candy: .sunny, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(presentation.accountBadgeTitle)
                            .font(.puff(.headline, Puff.Weight.title))
                            .foregroundStyle(Puff.Palette.ink)
                        Text("会员订阅")
                            .font(.puff(.caption, Puff.Weight.label))
                            .foregroundStyle(Puff.Palette.inkSoft)
                    }
                    Spacer(minLength: Puff.Space.xs)
                    Text("管理")
                        .font(.puff(.subheadline, Puff.Weight.emphasis))
                        .foregroundStyle(PuffCandy.sunny.deep)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(PuffCandy.sunny.wash, in: Capsule())
                }
                .padding(Puff.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.puffRow)
            .accessibilityLabel("会员订阅，\(presentation.accountBadgeTitle)，管理会员")
            .accessibilityIdentifier("me.subscription")

            hubBalanceLayout {
                MyPageBalanceMetric(title: "金币", value: profile.map { $0.coins.formatted() } ?? "—", isLoaded: profile != nil,
                                    identifier: "me.coinBalance", symbol: "circle.circle.fill", candy: .sunny)
                if accessClient != nil {
                    MyPageCreditMetric(balance: creditBalance)
                }
            }
            .padding(.horizontal, Puff.Space.s)
            .padding(.bottom, Puff.Space.s)
        }
        .puffCard(radius: Puff.Radius.huge)
    }

    private var hubBalanceLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: Puff.Space.xs))
        }
        return AnyLayout(HStackLayout(alignment: .top, spacing: Puff.Space.xs))
    }

    private func hubRow(_ title: String, symbol: String, candy: PuffCandy) -> some View {
        HStack(spacing: Puff.Space.s) {
            PuffIconBubble(symbol, candy: candy, size: 40)
            Text(title)
                .font(.puff(.headline, Puff.Weight.title))
                .foregroundStyle(Puff.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Puff.Space.xs)
            hubChevron
        }
        .padding(.horizontal, Puff.Space.m).padding(.vertical, 10).frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var hubChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: Puff.Weight.icon, design: .rounded))
            .foregroundStyle(Puff.Palette.inkFaint)
    }

    private var hubDivider: some View {
        Rectangle().fill(Puff.Palette.line).frame(height: 1)
            .padding(.leading, Puff.Space.m + 40 + Puff.Space.s).padding(.trailing, Puff.Space.m)
    }

    private func avatarPicker(size: CGFloat) -> some View {
        let avatar = UserAvatar(name: presentation.displayName, size: size)
        let saving = isSavingAvatar
        return PhotosPicker(selection: $selectedAvatar, matching: .images) {
            avatar
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: Puff.Weight.icon))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(PuffCandy.sky.base, in: Circle())
                        .overlay { Circle().strokeBorder(Puff.Palette.card, lineWidth: 2) }
                }
                .overlay { if saving { ProgressView() } }
        }
        .buttonStyle(.plain)
        .disabled(isSavingAvatar || userAvatar == nil)
        .accessibilityLabel("从相册更换头像")
        .accessibilityIdentifier("profile.avatarPicker")
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
        ScrollView {
            VStack(alignment: .leading, spacing: Puff.Space.m) {
                if section == .account {
                    HStack(spacing: Puff.Space.m) {
                        avatarPicker(size: 76)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(presentation.displayName)
                                .font(.puff(.title2, Puff.Weight.display))
                                .foregroundStyle(Puff.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            PuffTag(presentation.accountBadgeTitle, systemImage: "crown.fill", candy: .sunny)
                            Text("已认识 \(occupiedFriendSlots) 位旅途朋友")
                                .font(.puff(.footnote, Puff.Weight.label))
                                .foregroundStyle(Puff.Palette.inkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Puff.Space.m)
                    .puffCard(radius: Puff.Radius.huge)

                    VStack(spacing: 0) {
                        NavigationLink {
                            AccountSecurityView(session: authSession)
                        } label: {
                            accountRow("账号与安全", symbol: "person.badge.key.fill", candy: .sky)
                        }
                        Rectangle().fill(Puff.Palette.line).frame(height: 1)
                            .padding(.leading, Puff.Space.m + 40 + Puff.Space.s).padding(.trailing, Puff.Space.m)
                        Link(destination: URL(string: "https://qm.qq.com/q/Ft5ajqgxOw")!) {
                            accountRow("加入测试群", detail: "咕游记Coovingo测试 · 群号 1104063286",
                                       symbol: "person.2.fill", candy: .mint, external: true)
                        }
                        .accessibilityIdentifier("profile.testGroup")
                    }
                    .buttonStyle(.puffRow)
                    .padding(.vertical, 6)
                    .puffCard(radius: Puff.Radius.huge)

                    Button(role: .destructive) {
                        Task { await authSession.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.puff(.headline, Puff.Weight.title))
                            .foregroundStyle(Puff.Palette.cherry)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.large))
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, Puff.Space.m)
            .padding(.top, Puff.Space.xs)
            .padding(.bottom, Puff.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable { await reload() }
    }

    private func accountRow(
        _ title: String, detail: String? = nil, symbol: String, candy: PuffCandy, external: Bool = false
    ) -> some View {
        HStack(spacing: Puff.Space.s) {
            PuffIconBubble(symbol, candy: candy, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.puff(.headline, Puff.Weight.title))
                    .foregroundStyle(Puff.Palette.ink)
                if let detail {
                    Text(detail)
                        .font(.puff(.footnote, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 13, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(Puff.Palette.inkFaint)
        }
        .padding(.horizontal, Puff.Space.m).padding(.vertical, 10).frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}
