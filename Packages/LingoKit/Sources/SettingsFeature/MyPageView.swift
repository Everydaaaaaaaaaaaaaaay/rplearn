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
        self.isVisible = isVisible
        self.regionCatalog = regionCatalog
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
            } else {
                hubContent
            }
        }
        .background(Color.dsBackground.ignoresSafeArea())
        .task(id: "\(reloadToken)-\(isVisible)") {
            guard isVisible else { return }
            await reload()
            if section == nil { await reloadCredits() }
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
            VStack(spacing: 16) {
                hubProfile
                hubLearning
                VStack(spacing: 0) {
                    Button(action: onOpenFavorites) { hubRow("收藏夹", symbol: "bookmark") }.accessibilityIdentifier("me.favorites")
                    hubDivider
                    Button(action: onOpenMemory) { hubRow("记忆档案", symbol: "text.book.closed") }.accessibilityIdentifier("me.memory")
                }
                .dsSceneGlass(radius: 22, legibility: .shielded)
                VStack(spacing: 0) {
                    Button(action: onOpenSubscription) {
                        hubRow("会员订阅", symbol: "person.crop.circle.badge.checkmark", value: presentation.accountBadgeTitle)
                    }.accessibilityIdentifier("me.subscription")
                    hubDivider
                    Button(action: onOpenAccount) {
                        hubRow("金币", symbol: "circle.circle", value: profile.map { $0.coins.formatted() } ?? "—")
                    }
                    .accessibilityIdentifier("me.coinBalance")
                    hubDivider
                    if let accessClient {
                        NavigationLink { UsageAccessView(backend: accessClient, billing: billing) } label: {
                            hubRow("AI 积分", symbol: "sparkles", value: creditSummary)
                        }
                        .accessibilityIdentifier("me.credits")
                    }
                }
                .dsSceneGlass(radius: 22, legibility: .shielded)
            }
            .buttonStyle(DSSceneEntranceButtonStyle())
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await reload(); await reloadCredits() }
        .background {
            DSSceneBackdrop(imageName: DSCitySceneAssets.imageName(for: .profile, regionID: profile?.currentRegionID), tone: .cool)
                .accessibilityIdentifier("me.background.\(profile?.currentRegionID ?? "loading")")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DSHubHeader(title: "我的", symbol: "gearshape", actionLabel: "设置，AI、语音与偏好", action: onOpenSettings)
        }
        .foregroundStyle(Color.dsSceneTextPrimary)
        .toolbar(.hidden, for: .navigationBar).dsSceneTabBarBackground()
    }

    private var hubProfile: some View {
        Button(action: onOpenAccount) {
            HStack(spacing: 16) {
                UserAvatar(name: presentation.displayName, size: 58)
                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.displayName).font(.title2.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if !cityName.isEmpty {
                        Label(cityName, systemImage: "mappin").font(.subheadline)
                            .foregroundStyle(Color.dsSceneTextSecondary)
                    }
                }
                Spacer(minLength: 0)
                hubChevron
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .shielded)
        }
        .accessibilityIdentifier("me.profile")
        .accessibilityValue(cityName)
        .accessibilityLabel("个人资料，\(presentation.displayName)，\(presentation.accountBadgeTitle)，已认识 \(occupiedFriendSlots) 位旅途朋友")
    }

    private var hubLearning: some View {
        Button(action: onCalibrateLevel) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "book.pages").font(.system(size: 22, weight: .regular)).frame(width: 26, height: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text("英语旅程").font(.body.weight(.medium))
                    if let profile {
                        Text("\(profile.difficultyLevel.displayName) · \(profile.learningGoalsDisplayName)")
                            .font(.subheadline).foregroundStyle(Color.dsSceneTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(presentation.placementSummary).font(.caption).foregroundStyle(Color.dsSceneTextTertiary)
                }
                Spacer(minLength: 0)
                hubChevron.padding(.top, 6)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .shielded)
        }
        .accessibilityIdentifier("me.learning")
    }

    private var creditSummary: String {
        if let credits { return credits.remaining.formatted(.number.precision(.fractionLength(2))) }
        return isLoadingCredits ? "读取中" : creditsError == nil ? "查看用量" : "暂未更新"
    }

    private func hubRow(_ title: String, symbol: String, value: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 19, weight: .regular)).frame(width: 26)
            Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(Color.dsSceneTextTertiary)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.trailing)
            }
            hubChevron
        }
        .padding(.horizontal, 20).padding(.vertical, 18).frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private var hubChevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.dsSceneTextTertiary)
    }

    private var hubDivider: some View {
        Rectangle().fill(Color.dsSceneTextPrimary.opacity(0.12)).frame(height: 0.5)
            .padding(.leading, 60).padding(.trailing, 20)
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
