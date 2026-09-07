import DomainKit
import PersistenceKit
import Foundation
import SwiftUI

struct DepartureChapter: Decodable, Identifiable, Sendable {
    let id: String
    let kind: String
    let city: String
    let title: String
    let subtitle: String

    var entitlementStoryID: String? {
        kind == "mainline" ? MainlineCatalog.chapters.first { $0.regionID == city }?.storyID
            : CityStoryCatalog.chapter(forRegion: city)?.storyID
    }
}

/// One entry for the new collection; opening a chapter never changes the old
/// completion ledger or grants duplicate rewards for an old story ID.
public struct DepartureStoriesView: View {
    private let deps: StoryDependencies
    private let storageNamespace: String
    private let access: JourneyAccess
    private let economy: EconomyStore
    @State private var profile: UserProfileDTO?
    @State private var chapters: [DepartureChapter] = []
    @State private var selected: DepartureChapter?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    public init(deps: StoryDependencies, storageNamespace: String, access: JourneyAccess, economy: EconomyStore) {
        self.deps = deps
        self.storageNamespace = storageNamespace
        self.access = access
        self.economy = economy
    }

    private func canRead(_ chapter: DepartureChapter) -> Bool {
        guard let profile, let legacyID = chapter.entitlementStoryID,
              access.allowsStory(legacyID, starterRegionID: profile.starterRegionID) else { return false }
        return chapter.kind == "mainline" || profile.currentRegionID == chapter.city || profile.unlockedRegionIDs.contains(chapter.city)
    }

    private func open(_ chapter: DepartureChapter) {
        guard canRead(chapter) else {
            if access.isGuest { access.requestSignIn("游客可体验起始城市的新主线和城市故事，登录后继续旅程。") }
            return
        }
        selected = chapter
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("从一次邀请出发，参与一些具体的生活。每篇都可以独立进入，你的选择会改变这一篇的经历。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(["mainline", "city"], id: \.self) { kind in
                    Section(kind == "mainline" ? "主线 · 五站" : "城市 · 十五篇") {
                        ForEach(chapters.filter { $0.kind == kind }) { chapter in
                            Button { open(chapter) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(chapter.title).font(.headline).foregroundStyle(.primary)
                                    Text(chapter.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                    if !canRead(chapter) { Text(access.isGuest ? "登录后继续旅程" : "抵达这座城市后可读").font(.caption).foregroundStyle(.secondary) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                            }
                            .accessibilityIdentifier("departures.chapter.\(chapter.id)")
                        }
                    }
                }
                if failed { Text("暂时无法载入故事目录，请稍后重试。") }
            }
            .navigationTitle("出发之后")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("返回剧情") { dismiss() } } }
            .task {
                profile = try? await economy.profile()
                struct Catalog: Decodable { let chapters: [DepartureChapter] }
                do {
                    guard let url = Bundle.main.url(forResource: "departures_catalog", withExtension: "json") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    chapters = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).chapters
                } catch { failed = true }
            }
            .fullScreenCover(item: $selected) { chapter in
                LondonEpisodeView(deps: deps, storageNamespace: storageNamespace, resourceName: chapter.id)
            }
        }
    }
}
