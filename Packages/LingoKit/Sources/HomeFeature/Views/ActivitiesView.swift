import DesignSystem
import SwiftUI

/// Production entry: a scene, never a category/route list. App owns the current
/// action so its existing left-edge gesture returns exactly one level.
public struct ActivitiesView: View {
    let deps: HomeDependencies
    let storageNamespace: String
    let isVisible: Bool
    @Binding var activity: SceneActivity?
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: ActivitySceneID = .park
    @State private var cityID: String?
    @State private var cityName = ""
    @State private var records: [ActivityRecord] = []
    @State private var contextError: String?
    @State private var journalError: String?
    @State private var showsJournal = false

    public init(deps: HomeDependencies, storageNamespace: String, isVisible: Bool,
                activity: Binding<SceneActivity?>, onClose: @escaping () -> Void) {
        self.deps = deps
        self.storageNamespace = storageNamespace
        self.isVisible = isVisible
        _activity = activity
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            ActivitySceneView(isVisible: isVisible && activity == nil && !showsJournal,
                              showsInterface: activity == nil,
                              scene: $scene, cityName: cityName,
                              completedCount: Set(records.map(\.activityID)).count,
                              onClose: onClose, onJournal: { showsJournal = true }) { selected in
                guard cityID != nil else { return }
                activity = selected
            }
            .allowsHitTesting(activity == nil && cityID != nil)
            .accessibilityHidden(activity != nil || cityID == nil)

            if let activity {
                ActivityActionView(activity: activity, isVisible: isVisible, onBack: onClose) { selections, runID in
                    guard let cityID else { throw ActivityJournal.JournalError.invalidCompletion }
                    records = try ActivityJournal(namespace: storageNamespace, city: cityID)
                        .complete(activity, selections: selections, runID: runID)
                }
                .id(activity.id)
                .transition(.opacity)
            }
            if cityID == nil {
                VStack(spacing: 16) {
                    if let contextError {
                        Text(contextError)
                        Button("重试") { Task { await loadContext() } }
                    } else { ProgressView("正在打开场景") }
                    Button("返回首页", action: onClose)
                }
                .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .animation(DSSceneTransition.animation(reduceMotion: reduceMotion), value: activity?.id)
        .task(id: storageNamespace) { await loadContext() }
        .sheet(isPresented: $showsJournal) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("\(cityName) · 仅保存在本机").font(.subheadline).foregroundStyle(.secondary)
                        if let journalError {
                            Text(journalError)
                            Button("重新读取记录") { readRecords() }
                        } else if records.isEmpty {
                            ContentUnavailableView("还没有行动记录", systemImage: "book.closed",
                                description: Text("完成场景中的行动后，你的选择会留在这里。"))
                        }
                        ForEach(records.reversed()) { record in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(record.title).font(.headline)
                                    Spacer()
                                    Text(record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(Array(record.choices.enumerated()), id: \.offset) { _, choice in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(choice.context).font(.caption).foregroundStyle(.secondary)
                                        Text(choice.question).font(.caption).foregroundStyle(.secondary)
                                        Text(choice.english).font(.body)
                                        Text(choice.chinese).font(.subheadline)
                                        Text(choice.response).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                    }.padding(24)
                }
                .navigationTitle("行动足迹").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsJournal = false } } }
            }
        }
    }

    @MainActor private func loadContext() async {
        contextError = nil
        do {
            let profile = try await deps.economyStore.profile()
            guard !Task.isCancelled else { return }
            cityID = profile.currentRegionID
            cityName = deps.regionCatalog.region(id: profile.currentRegionID)?.nameZh ?? "当前城市"
            readRecords()
        } catch {
            contextError = "城市信息暂时无法读取，请重试。"
        }
    }
    private func readRecords() {
        guard let cityID else { return }
        do {
            records = try ActivityJournal(namespace: storageNamespace, city: cityID).records()
            journalError = nil
        } catch {
            journalError = "原有记录暂时无法读取，已保留原数据。请重试；读取恢复前不会覆盖保存。"
        }
    }
}
