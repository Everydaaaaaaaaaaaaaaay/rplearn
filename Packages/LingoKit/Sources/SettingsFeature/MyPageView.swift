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
        .background(Color.dsBackground.ignoresSafeArea())
        .task(id: "\(reloadToken)-\(isVisible)") {
            guard isVisible else { return }
            await reload()
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
            VStack(alignment: .leading, spacing: 24) {
                hubProfile
                hubGroup("英语旅程") { hubLearning }
                hubGroup("会员与资产") { hubMembership }
                hubGroup("常用") {
                    VStack(spacing: 0) {
                        Button(action: onOpenFavorites) {
                            hubRow("收藏夹", symbol: "bookmark")
                        }
                        .accessibilityIdentifier("me.favorites")
                        hubDivider
                        Button(action: onOpenSettings) {
                            hubRow("设置", symbol: "gearshape")
                        }
                        .accessibilityLabel("设置，AI、语音与偏好")
                        .accessibilityIdentifier("me.settings")
                    }
                    .dsSceneGlass(radius: 24, legibility: .frosted)
                }
            }
            .buttonStyle(DSSceneEntranceButtonStyle())
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await reload(); await creditBalance.reload(using: accessClient) }
        .background {
            DSSceneBackdrop(imageName: DSCitySceneAssets.imageName(for: .profile, regionID: profile?.currentRegionID), tone: .cool)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.22), .clear],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 280).ignoresSafeArea(edges: .top)
                }
                .accessibilityIdentifier("me.background.\(profile?.currentRegionID ?? "loading")")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DSHubHeader(title: "我的")
        }
        .foregroundStyle(Color.dsSceneTextPrimary)
        .toolbar(.hidden, for: .navigationBar).dsSceneTabBarBackground()
    }

    private func hubGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .tracking(1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 4, y: 1)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var hubProfile: some View {
        Button(action: onOpenAccount) {
            HStack(spacing: 16) {
                UserAvatar(name: presentation.displayName, size: 70)
                    .overlay { Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.displayName).font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !cityName.isEmpty {
                        Label(cityName, systemImage: "mappin")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.94))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
            .padding(.horizontal, 6).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("me.profile")
        .accessibilityValue(cityName)
        .accessibilityLabel("个人资料，\(presentation.displayName)，\(presentation.accountBadgeTitle)，已认识 \(occupiedFriendSlots) 位旅途朋友")
    }

    private var hubLearning: some View {
        Button(action: onCalibrateLevel) {
            HStack(spacing: 14) {
                hubIcon("book.pages")
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile?.difficultyLevel.displayName ?? "英语旅程")
                        .font(.title3.weight(.medium))
                    if let profile {
                        Text(profile.learningGoalsDisplayName)
                            .font(.subheadline).foregroundStyle(Color.dsSceneTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(presentation.placementSummary)
                        .font(.caption).foregroundStyle(Color.dsSceneTextTertiary)
                }
                Spacer(minLength: 0)
                hubChevron
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 24, interactive: true, legibility: .frosted)
        }
        .accessibilityLabel("英语旅程，\(profile?.difficultyLevel.displayName ?? "读取中")，\(profile?.learningGoalsDisplayName ?? "")，\(presentation.placementSummary)")
        .accessibilityIdentifier("me.learning")
    }

    private var hubMembership: some View {
        VStack(spacing: 0) {
            Button(action: onOpenSubscription) {
                HStack(spacing: 14) {
                    hubIcon("crown")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.accountBadgeTitle).font(.headline.weight(.medium))
                        Text("会员订阅").font(.caption).foregroundStyle(Color.dsSceneTextSecondary)
                    }
                    Spacer(minLength: 8)
                    Text("管理").font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.dsSceneTextPrimary.opacity(0.06), in: Capsule())
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("会员订阅，\(presentation.accountBadgeTitle)，管理会员")
            .accessibilityIdentifier("me.subscription")

            Rectangle().fill(Color.dsSceneTextPrimary.opacity(0.12)).frame(height: 0.5)
                .padding(.horizontal, 18)
            hubBalanceLayout {
                MyPageBalanceMetric(title: "金币", value: profile.map { $0.coins.formatted() } ?? "—", isLoaded: profile != nil, identifier: "me.coinBalance")
                if accessClient != nil {
                    Rectangle().fill(Color.dsSceneTextPrimary.opacity(0.12))
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 0.5,
                               height: dynamicTypeSize.isAccessibilitySize ? 0.5 : 36)
                    MyPageCreditMetric(balance: creditBalance)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
        }
        .dsSceneGlass(radius: 24, legibility: .frosted)
    }

    private var hubBalanceLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        }
        return AnyLayout(HStackLayout(alignment: .top, spacing: 20))
    }

    private func hubIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(Color.dsSceneTextSecondary)
            .frame(width: 36, height: 36)
            .background(Color.dsSceneTextPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }

    private func hubRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            hubIcon(symbol)
            Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            hubChevron
        }
        .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private var hubChevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.dsSceneTextTertiary)
    }

    private var hubDivider: some View {
        Rectangle().fill(Color.dsSceneTextPrimary.opacity(0.12)).frame(height: 0.5)
            .padding(.leading, 68).padding(.trailing, 18)
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
            .refreshable { await reload() }
        }
    }
}
