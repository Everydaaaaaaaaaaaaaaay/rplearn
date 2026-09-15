import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// Production entry: a scene, never a category/route list. App owns the current
/// action so its existing left-edge gesture returns exactly one level.
public struct ActivitiesView: View {
    @ObservedObject var journey: ActivityJourneyCoordinator
    let deps: HomeDependencies
    let storageNamespace: String
    let isVisible: Bool
    @Binding var activity: SceneActivity?
    let onClose: () -> Void
    let onChat: (CharacterDTO) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: ActivitySceneID = .park
    @State private var cityID: String?
    @State private var cityName = ""
    @State private var records: [ActivityRecord] = []
    @State private var contextError: String?
    @State private var journalError: String?
    @State private var showsJournal = false
    @State private var recentPeople: [CharacterDTO] = []

    public init(journey: ActivityJourneyCoordinator, deps: HomeDependencies, storageNamespace: String, isVisible: Bool,
                activity: Binding<SceneActivity?>, onClose: @escaping () -> Void,
                onChat: @escaping (CharacterDTO) -> Void) {
        self.journey = journey
        self.deps = deps
        self.storageNamespace = storageNamespace
        self.isVisible = isVisible
        _activity = activity
        self.onClose = onClose
        self.onChat = onChat
    }

    public var body: some View {
        ZStack {
            ActivitySceneView(isVisible: isVisible && !showsJournal && activity == nil,
                              showsInterface: activity == nil,
                              scene: $scene, cityName: cityName,
                              completedCount: records.count,
                              onClose: onClose, onJournal: { showsJournal = true }) { selected in
                guard let cityID, let region = deps.regionCatalog.region(id: cityID) else { return }
                journey.prepare(activity: selected, region: region, deps: deps, namespace: storageNamespace)
                activity = journey.activeActivity
            }
            .allowsHitTesting(activity == nil && cityID != nil)
            .accessibilityHidden(cityID == nil || activity != nil)

            if let activity, let cityID, let model = journey.model {
                ActivityActionView(model: model, journey: journey, deps: deps, isVisible: isVisible,
                                   onBack: onClose) { selections, runID, character, responses in
                    if let tutorial = deps.tutorial { tutorial.onEvent("ending"); return }
                    let journal = ActivityJournal(namespace: storageNamespace, city: cityID)
                    if model.isSolitude {
                        records = try journal.completeSolitude(activity, runID: runID)
                    } else {
                        records = try journal.complete(model.activity, selections: selections, runID: runID,
                            characterID: character?.id, characterName: character?.card.name, responses: responses, chapters: model.chapters)
                    }
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
        .onAppear { journey.setViewing(isVisible) }
        .onDisappear { journey.setViewing(false) }
        .onChange(of: isVisible) { _, visible in journey.setViewing(visible) }
        .task(id: storageNamespace) { await loadContext() }
        .sheet(isPresented: $showsJournal) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("\(cityName) · 仅保存在本机").font(.subheadline).foregroundStyle(.secondary)
                        if !recentPeople.isEmpty {
                            Text("在这里认识的人").font(.title3.weight(.semibold))
                            ForEach(recentPeople) { person in
                                Button {
                                    showsJournal = false
                                    onChat(person)
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarBadge(name: person.card.name, size: 44,
                                            imageName: person.card.avatarAssetName,
                                            remoteURL: person.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                                        Text(person.displayName)
                                        Spacer()
                                        Text("继续聊天").font(.caption)
                                    }
                                }.buttonStyle(.plain)
                            }
                            Divider()
                        }
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
                                if let story = record.solitudeStory { Text(story).lineSpacing(5) }
                                if let name = record.characterName {
                                    Text("与 \(name) 的这次交流").font(.subheadline)
                                }
                                if let chapters = record.chapters {
                                    DisclosureGroup("完整故事") {
                                        ForEach(Array(chapters.enumerated()), id: \.offset) { stage, chapter in
                                            ForEach(Array(chapter.beats.enumerated()), id: \.offset) { _, beat in
                                                Text(beat.english).font(.body).padding(.top, 8)
                                                Text(beat.chinese).font(.caption).foregroundStyle(.secondary)
                                            }
                                            if record.choices.indices.contains(stage) {
                                                Text("你的选择：" + record.choices[stage].chinese).font(.subheadline.weight(.medium)).padding(.vertical, 8)
                                            }
                                        }
                                    }
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
                .navigationTitle("相遇与足迹").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsJournal = false } } }
                .task {
                    let people = (try? await deps.rosterStore.friends()) ?? []
                    let encounteredIDs = Set(records.compactMap(\.characterID))
                    recentPeople = people.filter { encounteredIDs.contains($0.id) }
                }
            }
        }
    }

    @MainActor private func loadContext() async {
        contextError = nil
        if let model = journey.model, model.started {
            cityID = model.region.id
            cityName = model.region.nameZh
            readRecords()
            return
        }
        do {
            var profile = try await deps.economyStore.profile()
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_SOCIAL_FIXTURE"] == "1",
               ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"] != nil {
                // The App uses an empty, in-memory container for this fixture.
                // Seed its city without invoking production account activation.
                profile = try await deps.economyStore.updateProfile {
                    $0.currentRegionID = "london"
                    $0.hasCompletedOnboarding = true
                }
            }
            #endif
            guard !Task.isCancelled else { return }
            guard deps.regionCatalog.region(id: profile.currentRegionID) != nil else {
                contextError = "没有找到当前城市，请返回首页后重试。"
                return
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_MARKETING_CAPTURE"] == "1",
               ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "encounter",
               ProcessInfo.processInfo.environment["UI_TEST_SOCIAL_FIXTURE"] == "1",
               let selected = SceneActivity.catalog.first(where: { $0.id == "park-route" }),
               let region = deps.regionCatalog.region(id: profile.currentRegionID) {
                journey.prepare(activity: selected, region: region, deps: deps, namespace: storageNamespace)
                activity = journey.activeActivity
                journey.start()
            }
            #endif
            cityID = profile.currentRegionID
            cityName = deps.regionCatalog.region(id: profile.currentRegionID)?.nameZh ?? "当前城市"
            readRecords()
        } catch {
            contextError = "城市信息暂时无法读取，请重试。"
        }
    }
    private func readRecords() {
        guard deps.tutorial == nil, let cityID else { return }
        do {
            records = try ActivityJournal(namespace: storageNamespace, city: cityID).records()
            journalError = nil
        } catch {
            journalError = "原有记录暂时无法读取，已保留原数据。请重试；读取恢复前不会覆盖保存。"
        }
    }
}
