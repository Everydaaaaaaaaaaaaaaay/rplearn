import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 记忆调试面板：按角色可视化 long/mid/short 三层记忆、对照订阅配额，
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
        ZStack {
            DSWorkbenchBackdrop(focus: .archive)

            ScrollView {
                DSWorkbenchPaperSheet(radius: 28, padding: 0) {
                    VStack(spacing: 0) {
                        archiveSummary
                        paperSectionDivider
                        characterPanel

                        if selectedID != nil {
                            paperSectionDivider
                            tierPanel(
                                title: "长期了解",
                                code: "long",
                                icon: "archivebox.fill",
                                items: longs,
                                cap: quota?.long
                            )
                            paperSectionDivider
                            tierPanel(
                                title: "阶段合并",
                                code: "mid",
                                icon: "square.stack.3d.up.fill",
                                items: mids,
                                cap: quota?.shortMid
                            )
                            paperSectionDivider
                            tierPanel(
                                title: "近期事件",
                                code: "short",
                                icon: "clock.arrow.circlepath",
                                items: shorts,
                                cap: quota?.shortMid
                            )
                        }
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("记忆档案")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.dsBrandCream)
                    .shadow(color: Color.dsFoilGold.opacity(0.46), radius: 5)
                    .shadow(color: Color.black.opacity(0.78), radius: 1.4, y: 1)
                    .accessibilityAddTraits(.isHeader)
            }
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

    private var archiveSummary: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(spacing: DSSpacing.md) {
                DSObsidianMedallion(systemImage: "archivebox", size: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text("记忆档案库")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.dsPaperInk)
                    Text("\(subscription.displayName) 订阅 · 三层角色记忆")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                }
                Spacer(minLength: 0)
            }

            if let quota {
                HStack(spacing: DSSpacing.sm) {
                    quotaMetric("原文", value: quota.rawWindow, systemImage: "doc.text")
                    quotaMetric("短期", value: quota.shortMid, systemImage: "clock")
                    quotaMetric("长期", value: quota.long, systemImage: "archivebox")
                }
            }
        }
        .padding(DSSpacing.lg)
    }

    private func quotaMetric(_ title: String, value: Int, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.dsSkyDeep)
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.dsPaperInk)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.dsPaperInkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.sm)
        .background(
            Color.dsTravelNavy.opacity(0.055),
            in: RoundedRectangle(cornerRadius: DSRadius.inline)
        )
    }

    private var characterPanel: some View {
        HStack(spacing: DSSpacing.md) {
            Label("角色档案", systemImage: "person.text.rectangle")
                .font(.headline)
                .foregroundStyle(Color.dsPaperInk)
            Spacer()

            if characters.isEmpty {
                Text("暂无角色")
                    .foregroundStyle(Color.dsPaperInkSecondary)
            } else {
                Picker("选择角色", selection: $selectedID) {
                    ForEach(characters) { character in
                        Text(character.card.name).tag(Optional(character.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.dsSkyDeep)
                .onChange(of: selectedID) { _, _ in Task { await reloadMemories() } }
            }
        }
        .frame(minHeight: 48)
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
    }

    // MARK: - 分层

    private func tierPanel(
        title: String,
        code: String,
        icon: String,
        items: [MemoryDTO],
        cap: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(Color.dsSkyDeep)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.dsPaperInk)
                    Text(code)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.dsPaperInkSecondary)
                }
                Spacer()
                Text(cap.map { "\(items.count) / \($0)" } ?? "\(items.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(overCap(items.count, cap) ? Color.dsDanger : Color.dsPaperInkSecondary)
            }

            if let cap, cap > 0 {
                ProgressView(value: min(Double(items.count) / Double(cap), 1))
                    .tint(overCap(items.count, cap) ? Color.dsDanger : Color.dsSkyDeep)
            }

            Divider().overlay(Color.dsPaperInk.opacity(0.12))

            if items.isEmpty {
                Text("暂无记录")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsPaperInkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, memory in
                    memoryRow(memory)
                    if index < items.count - 1 {
                        Divider().overlay(Color.dsPaperInk.opacity(0.08))
                    }
                }
            }
        }
        .padding(DSSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) \(code)")
    }

    private func memoryRow(_ memory: MemoryDTO) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: 5) {
                Text(memory.content)
                    .font(.subheadline)
                    .foregroundStyle(Color.dsPaperInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(repeating: "★", count: memory.importance)
                    + String(repeating: "☆", count: max(0, 5 - memory.importance)))
                    .font(.caption2)
                    .foregroundStyle(Color.dsSunset)
                    .accessibilityLabel("重要度 \(memory.importance) 星")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await delete(items: [memory]) }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsDanger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("删除这条记忆")
        }
        .padding(.vertical, DSSpacing.xs)
    }

    private func overCap(_ count: Int, _ cap: Int?) -> Bool {
        guard let cap else { return false }
        return count > cap
    }

    private var paperSectionDivider: some View {
        Divider()
            .overlay(Color.dsPaperInk.opacity(0.12))
            .padding(.horizontal, DSSpacing.lg)
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
