import DesignSystem
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// “我的”聚合页：资料、订阅、金币与二级入口。
public struct MyPageView: View {
    @Bindable private var settings: LLMSettingsStore
    private let router: LLMRouter
    private let economyStore: EconomyStore
    private let economyService: EconomyService
    private let memoryStore: MemoryStore
    private let rosterStore: RosterStore
    private let chatStore: ChatStore
    private let speech: any SpeechService
    private let favoritesBuilder: @MainActor () -> AnyView

    @State private var profile: UserProfileDTO?
    @State private var occupiedFriendSlots = 0
    @State private var showsTierPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        settings: LLMSettingsStore,
        router: LLMRouter,
        economyStore: EconomyStore,
        economyService: EconomyService,
        memoryStore: MemoryStore,
        rosterStore: RosterStore,
        chatStore: ChatStore,
        speech: any SpeechService,
        favoritesBuilder: @escaping @MainActor () -> AnyView
    ) {
        self.settings = settings
        self.router = router
        self.economyStore = economyStore
        self.economyService = economyService
        self.memoryStore = memoryStore
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.speech = speech
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
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var profileCard: some View {
        HStack(spacing: DSSpacing.md) {
            AvatarBadge(name: displayName, tint: .dsSky, size: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.title2.bold())
                if let tier = profile?.subscriptionTier {
                    DSChip(tier.displayName, tint: tier == .free ? .secondary : .dsSky, prominent: tier != .free)
                }
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
        .dsCard()
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LingoTrip \(profile?.subscriptionTier.displayName ?? "免费版")")
                        .font(.title3.bold())
                    Text("更长的角色记忆，让每段友谊都有延续")
                        .font(.footnote)
                        .opacity(0.86)
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.largeTitle)
            }

            Button {
                withAnimation(reduceMotion ? nil : DSAnimation.bouncy) {
                    showsTierPicker.toggle()
                }
            } label: {
                Label(showsTierPicker ? "收起" : "更换订阅", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.duo(.outline, fullWidth: false, compact: true))
            .tint(.white)

            if showsTierPicker {
                Picker("订阅等级", selection: subscriptionBinding) {
                    ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                Text("本地模拟订阅，暂未接入真实支付。")
                    .font(.caption2)
                    .opacity(0.72)
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

    private var entryList: some View {
        VStack(spacing: 0) {
            NavigationLink {
                favoritesBuilder()
            } label: {
                entryRow("收藏夹", subtitle: "保存喜欢的表达", icon: "star.fill", tint: .dsSunset)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            NavigationLink {
                SettingsView(
                    settings: settings,
                    router: router,
                    economyStore: economyStore,
                    economyService: economyService,
                    memoryStore: memoryStore,
                    rosterStore: rosterStore,
                    chatStore: chatStore,
                    speech: speech
                )
            } label: {
                entryRow("设置", subtitle: "AI、语音与学习偏好", icon: "gearshape.fill", tint: .dsSky)
            }
            .buttonStyle(.plain)
        }
        .dsCard(padding: 0)
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
        .dsCard(padding: 0)
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

    private var subscriptionBinding: Binding<SubscriptionTier> {
        Binding(
            get: { profile?.subscriptionTier ?? .free },
            set: { tier in
                Task {
                    profile = try? await economyService.subscribe(to: tier)
                }
            }
        )
    }

    private var displayName: String {
        let value = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "旅行者" : value
    }

    private func reload() async {
        async let loadedProfile = try? economyStore.profile()
        async let loadedSlots = try? rosterStore.occupiedFriendSlots()
        profile = await loadedProfile
        occupiedFriendSlots = await loadedSlots ?? 0
    }
}
