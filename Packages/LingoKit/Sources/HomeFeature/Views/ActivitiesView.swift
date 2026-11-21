import DesignSystem
import BackendKit
import DomainKit
import PersistenceKit
import SwiftUI

/// City scene selection and reading share the app-owned outing coordinator.
public struct ActivitiesView: View {
    let journey: ActivityJourneyCoordinator
    let deps: HomeDependencies
    let storageNamespace: String
    let storage: UserDefaults
    let onCompleteOuting: (() -> Void)?
    let isVisible: Bool
    let onClose: () -> Void
    let onChat: (CharacterDTO) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cityID: String?
    @State private var cityName = ""
    @State private var records: [ActivityRecord] = []
    @State private var contextError: String?
    @State private var journalError: String?
    @State private var showsJournal = false
    @State private var recoveries: [CityOutingArchive] = []
    @State private var recentPeople: [CharacterDTO] = []
    @State private var placeCatalog: BackendActivityCatalog?
    @State private var resumableOuting: CityOutingArchive?
    @State private var automaticallyRestoreOuting = true
    @State private var loadRevision = 0

    public init(journey: ActivityJourneyCoordinator, deps: HomeDependencies, storageNamespace: String, isVisible: Bool,
                onClose: @escaping () -> Void,
                onChat: @escaping (CharacterDTO) -> Void,
                storage: UserDefaults = .standard,
                onCompleteOuting: (() -> Void)? = nil) {
        self.journey = journey
        self.deps = deps
        if let profile = deps.presentationCache?.profile,
           let region = deps.regionCatalog.region(id: profile.currentRegionID) {
            _cityName = State(initialValue: region.nameZh)
            if let releaseID = deps.activityReleaseID {
                let catalog = deps.presentationCache?.catalog(releaseID: releaseID, cityID: region.id)
                _placeCatalog = State(initialValue: catalog)
                _cityID = State(initialValue: catalog == nil ? nil : region.id)
            }
        }
        self.storageNamespace = storageNamespace
        self.storage = storage
        self.onCompleteOuting = onCompleteOuting
        self.isVisible = isVisible
        self.onClose = onClose
        self.onChat = onChat
    }

    public var body: some View {
        ZStack {
            if let placeCatalog, contextError == nil {
                CityPlacesView(cityName: cityName, catalog: placeCatalog, showsChrome: !journey.hasOpenOuting,
                    onBack: onClose,
                    onJournal: { readRecords(); showsJournal = true }, onSelect: { place in
                        guard resumableOuting == nil else { return }
                        do {
                            if let saved = try CityOutingArchive.load(namespace: storageNamespace, defaults: storage), saved.needsContinuation {
                                openPlaceArchive(saved)
                                return
                            }
                        } catch {
                            cityID = nil
                            contextError = "上次外出进度暂时无法读取，请重试。"
                            return
                        }
                        guard let region = deps.regionCatalog.region(id: placeCatalog.cityId),
                              let gateway = deps.outingGateway else { return }
                        journey.preparePlace(archive: .init(place: place, releaseID: placeCatalog.releaseId),
                            region: region, deps: deps, namespace: storageNamespace, gateway: gateway, storage: storage)
                    }, resumeTitle: resumableOuting.map {
                        $0.hasEnded ? "同步上次外出" : "继续上次在\($0.place.titleZh)的外出"
                    },
                    onResume: { if let archive = resumableOuting { openPlaceArchive(archive) } })
                    .allowsHitTesting(!journey.hasOpenOuting).accessibilityHidden(journey.hasOpenOuting)
            }
            if let outing = journey.cityOuting {
                CityOutingView(model: outing, isVisible: isVisible, showsTutorialGuidance: onCompleteOuting != nil,
                    onBack: {
                        if outing.archive.hasEnded {
                            resumableOuting = outing.archive.needsContinuation ? outing.archive : nil
                        }
                        journey.reset()
                    }, onChat: onChat, onFinish: {
                        let completed = outing.snapshot?.status == .completed
                        resumableOuting = outing.archive.needsContinuation ? outing.archive : nil
                        journey.reset()
                        if completed { onCompleteOuting?() }
                    })
                    .id(outing.archive.runID).transition(.opacity)
            } else if cityID == nil || contextError != nil {
                VStack(spacing: 16) {
                    if let contextError {
                        Text(contextError)
                        Button("重试") { loadRevision += 1 }
                            .accessibilityIdentifier("activities.catalog.retry")
                    } else { ProgressView("正在打开场景") }
                    Button("返回首页", action: onClose)
                }
                .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .animation(DSSceneTransition.animation(reduceMotion: reduceMotion), value: journey.hasOpenOuting)
        .onAppear { journey.setViewing(isVisible) }
        .onDisappear { journey.setViewing(false) }
        .onChange(of: isVisible) { _, visible in journey.setViewing(visible) }
        .task(id: loadRevision) { await loadContext() }
        .onChange(of: journey.hasOpenOuting) { _, isOpen in
            if !isOpen {
                automaticallyRestoreOuting = false
                loadRevision += 1
            }
        }
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
                        if !recoveries.isEmpty {
                            DisclosureGroup("合并与冲突前的本机记录") {
                                ForEach(Array(recoveries.enumerated()), id: \.offset) { _, archive in
                                    if let snapshot = archive.snapshot {
                                        DisclosureGroup(archive.place.titleZh) {
                                            Text("已保留的本机阅读进度").font(.caption).foregroundStyle(.secondary)
                                            if snapshot.mode == .solitude { Text(snapshot.solitude.chinese) }
                                            ForEach(Array(PlaceOutingProgress.chapters(snapshot).enumerated()), id: \.offset) { stage, chapter in
                                                ForEach(Array(chapter.beats.enumerated()), id: \.offset) { index, beat in
                                                    if stage < PlaceOutingProgress.chapters(snapshot).count - 1 || index <= snapshot.beatIndex {
                                                        Text(beat.english).padding(.top, 8)
                                                        Text(beat.chinese).font(.caption).foregroundStyle(.secondary)
                                                    }
                                                }
                                                if snapshot.choices.indices.contains(stage),
                                                   let index = Int(snapshot.choices[stage].split(separator: ":").last ?? ""),
                                                   chapter.choices.indices.contains(index) {
                                                    Text("你的选择：" + chapter.choices[index].chinese).font(.subheadline)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ForEach(records.reversed()) { record in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(record.title).font(.headline)
                                    Spacer()
                                    Text(record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                if let place = record.placeTitle {
                                    Text(place + (record.endedEarly == true ? " · 提前结束" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
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
        if let outing = journey.cityOuting {
            cityID = outing.region.id; cityName = outing.region.nameZh
            readRecords(); return
        }
        guard let releaseID = deps.activityReleaseID, let gateway = deps.outingGateway else {
            contextError = "城市地点暂未准备好，请稍后重试。"
            return
        }
        do {
            let profile = try await deps.economyStore.profile()
            try Task.checkCancellation()
            guard let region = deps.regionCatalog.region(id: profile.currentRegionID) else {
                contextError = "没有找到当前城市，请重试。"
                return
            }
            cityName = region.nameZh
            if placeCatalog?.cityId != region.id || placeCatalog?.releaseId != releaseID {
                placeCatalog = nil
                cityID = nil
            }
            if let local = deps.presentationCache?.catalog(releaseID: releaseID, cityID: region.id)
                ?? CityActivityRelease.bundled().flatMap({ $0.releaseId == releaseID ? $0.catalog(in: region.id) : nil }) {
                placeCatalog = local
                cityID = local.cityId
                readRecords()
            }
            let cached = try CityOutingArchive.load(namespace: storageNamespace, defaults: storage)
            resumableOuting = cached?.needsContinuation == true ? cached : nil
            if resumableOuting == nil, let active = try? await gateway.activeOuting() {
                try Task.checkCancellation()
                guard !journey.hasOpenOuting else { return }
                try PlaceOutingProgress.validate(active)
                let restored = CityOutingArchive(restoring: active)
                try restored.save(namespace: storageNamespace, defaults: storage)
                resumableOuting = restored
            }
            try Task.checkCancellation()
            guard !journey.hasOpenOuting else { return }
            if automaticallyRestoreOuting, let archive = resumableOuting {
                automaticallyRestoreOuting = false
                openPlaceArchive(archive); readRecords(); return
            }
            let remote: BackendActivityCatalog?
            do {
                if let cache = deps.presentationCache {
                    remote = try await cache.refreshCatalog(releaseID: releaseID, cityID: region.id, gateway: gateway)
                } else {
                    remote = try await gateway.activityCatalog(releaseID: releaseID)
                }
                try Task.checkCancellation()
                if let remote {
                    try CityActivityRelease.validate(remote)
                    guard remote.releaseId == releaseID, remote.cityId == region.id else {
                        throw PlaceOutingProgress.ProgressError.invalidContent
                    }
                    placeCatalog = remote
                    cityID = region.id
                }
            } catch where !Task.isCancelled && placeCatalog != nil {
                // An already downloaded catalog remains usable during a refresh failure.
            }
            try Task.checkCancellation()
            guard placeCatalog != nil else {
                cityID = nil
                contextError = "城市地点暂未准备好，请稍后重试。"
                return
            }
            automaticallyRestoreOuting = false
            readRecords()
        } catch is CancellationError {
        } catch {
            cityID = nil
            contextError = "城市信息暂时无法读取，请重试。"
        }
    }
    @MainActor private func openPlaceArchive(_ archive: CityOutingArchive) {
        guard let gateway = deps.outingGateway,
              let region = deps.regionCatalog.region(id: archive.snapshot?.cityId ?? archive.place.photo.cityId) else {
            contextError = "这次外出的城市暂不可用，请稍后重试。"; return
        }
        journey.preparePlace(archive: archive, region: region, deps: deps, namespace: storageNamespace, gateway: gateway, storage: storage)
        cityID = region.id
        cityName = region.nameZh
    }
    private func readRecords() {
        guard let cityID else { return }
        do {
            records = try ActivityJournal(namespace: storageNamespace, city: cityID, defaults: storage).records()
            recoveries = try CityOutingArchive.recoveries(namespace: storageNamespace, defaults: storage)
                .filter { $0.snapshot?.cityId == cityID }
            journalError = nil
        } catch {
            journalError = "原有记录暂时无法读取，已保留原数据。请重试；读取恢复前不会覆盖保存。"
        }
    }
}
