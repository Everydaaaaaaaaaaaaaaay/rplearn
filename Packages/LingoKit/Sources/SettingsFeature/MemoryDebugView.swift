import DomainKit
import PersistenceKit
import SwiftUI

/// 记忆调试面板（plan.md §3.5）：按角色可视化 long/mid/short 三层记忆、对照订阅配额，
/// 可删除单条、手动整理、注入示例，便于开发期观察分层压缩行为。
public struct MemoryDebugView: View {
    private let memoryStore: MemoryStore
    private let rosterStore: RosterStore
    private let economyStore: EconomyStore
    private let memoryService: MemoryService

    @State private var characters: [CharacterDTO] = []
    @State private var selectedID: UUID?
    @State private var longs: [MemoryDTO] = []
    @State private var mids: [MemoryDTO] = []
    @State private var shorts: [MemoryDTO] = []
    @State private var quota: MemoryQuota?
    @State private var subscription: SubscriptionTier = .free
    @State private var isBusy = false

    public init(
        memoryStore: MemoryStore,
        rosterStore: RosterStore,
        economyStore: EconomyStore,
        memoryService: MemoryService
    ) {
        self.memoryStore = memoryStore
        self.rosterStore = rosterStore
        self.economyStore = economyStore
        self.memoryService = memoryService
    }

    public var body: some View {
        List {
            quotaSection
            characterSection
            if selectedID != nil {
                tierSection(title: "长期了解 · long", tier: .long, items: longs, cap: quota?.long)
                tierSection(title: "阶段合并 · mid", tier: .mid, items: mids, cap: quota?.shortMid)
                tierSection(title: "近期事件 · short", tier: .short, items: shorts, cap: quota?.shortMid)
            }
        }
        .navigationTitle("记忆调试面板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("注入示例 short 记忆") { Task { await seedSamples() } }
                    Button("手动整理分层") { Task { await consolidate() } }
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .disabled(selectedID == nil || isBusy)
            }
        }
        .task { await bootstrap() }
    }

    // MARK: - 配额

    private var quotaSection: some View {
        Section("订阅配额") {
            LabeledContent("当前订阅", value: subscription.displayName)
            if let quota {
                LabeledContent("原文窗口 rawWindow", value: "\(quota.rawWindow)")
                LabeledContent("short+mid 上限", value: "\(quota.shortMid)")
                LabeledContent("long 上限", value: "\(quota.long)")
            }
        }
    }

    private var characterSection: some View {
        Section("角色") {
            if characters.isEmpty {
                Text("暂无角色").foregroundStyle(.secondary)
            } else {
                Picker("选择角色", selection: $selectedID) {
                    ForEach(characters) { character in
                        Text(character.card.name).tag(Optional(character.id))
                    }
                }
                .onChange(of: selectedID) { _, _ in Task { await reloadMemories() } }
            }
        }
    }

    // MARK: - 分层

    private func tierSection(title: String, tier: MemoryTier, items: [MemoryDTO], cap: Int?) -> some View {
        Section {
            if items.isEmpty {
                Text("（空）").foregroundStyle(.tertiary).font(.footnote)
            } else {
                ForEach(items) { memory in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(memory.content).font(.subheadline)
                        Text(String(repeating: "★", count: memory.importance)
                            + String(repeating: "☆", count: max(0, 5 - memory.importance)))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .onDelete { offsets in
                    Task { await delete(items: offsets.map { items[$0] }) }
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text(cap.map { "\(items.count) / \($0)" } ?? "\(items.count)")
                    .foregroundStyle(overCap(items.count, cap) ? .red : .secondary)
                    .monospacedDigit()
            }
        }
    }

    private func overCap(_ count: Int, _ cap: Int?) -> Bool {
        guard let cap else { return false }
        return count > cap
    }

    // MARK: - 数据

    private func bootstrap() async {
        characters = (try? await rosterStore.allCharacters()) ?? []
        if selectedID == nil { selectedID = characters.first?.id }
        subscription = (try? await economyStore.profile().subscriptionTier) ?? .free
        quota = await memoryService.quota()
        await reloadMemories()
    }

    private func reloadMemories() async {
        guard let selectedID else { longs = []; mids = []; shorts = []; return }
        longs = (try? await memoryStore.memories(characterID: selectedID, tier: .long)) ?? []
        mids = (try? await memoryStore.memories(characterID: selectedID, tier: .mid)) ?? []
        shorts = (try? await memoryStore.memories(characterID: selectedID, tier: .short)) ?? []
    }

    private func delete(items: [MemoryDTO]) async {
        try? await memoryStore.deleteMemories(ids: items.map(\.id))
        await reloadMemories()
    }

    private func seedSamples() async {
        guard let selectedID else { return }
        isBusy = true
        defer { isBusy = false }
        let samples = (1...4).map { index in
            MemoryStore.NewMemory(content: "调试样例记忆 #\(index)（\(Date.now.formatted(date: .omitted, time: .standard))）", importance: (index % 5) + 1)
        }
        try? await memoryStore.addMemories(characterID: selectedID, tier: .short, facts: samples, sourceUpToIndex: 0)
        await reloadMemories()
    }

    private func consolidate() async {
        guard let selectedID,
              let character = characters.first(where: { $0.id == selectedID }) else { return }
        isBusy = true
        defer { isBusy = false }
        await memoryService.maintainTiers(characterID: selectedID, characterName: character.card.name)
        await reloadMemories()
    }
}
