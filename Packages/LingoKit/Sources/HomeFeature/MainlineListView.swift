import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct MainlineListView: View {
    private let deps: HomeDependencies
    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []

    public init(deps: HomeDependencies) {
        self.deps = deps
    }

    private var region: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let region {
                    header(region)
                    let chapters = MainlineCatalog.chapters(forRegion: region.id)
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        NavigationLink(value: chapter) {
                            chapterCard(chapter, index: index, chapters: chapters)
                        }
                        .buttonStyle(.pressableCard)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(DSSpacing.md)
            .padding(.bottom, 90)
        }
        .background(Color.dsBackground)
        .navigationTitle("主线剧情")
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private func header(_ region: Region) -> some View {
        let chapters = MainlineCatalog.chapters(forRegion: region.id)
        let done = chapters.filter { completed.contains($0.storyID) }.count
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                DSChip("\(flag(region.countryCode)) \(region.nameZh)", tint: .dsSky, prominent: true)
                Spacer()
                Text("\(done) / \(chapters.count) 章")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: chapters.isEmpty ? 0 : Double(done) / Double(chapters.count))
                .tint(.dsSuccess)
        }
        .dsCard()
    }

    private func chapterCard(
        _ chapter: MainlineChapter,
        index: Int,
        chapters: [MainlineChapter]
    ) -> some View {
        let isDone = completed.contains(chapter.storyID)
        let firstOpenIndex = chapters.firstIndex { !completed.contains($0.storyID) } ?? chapters.count
        let isCurrent = !isDone && index == firstOpenIndex
        let isFuture = !isDone && !isCurrent

        return HStack(spacing: DSSpacing.sm) {
            Image(systemName: isDone ? "checkmark.seal.fill" : (isFuture ? "lock.open.fill" : "book.pages.fill"))
                .font(.title2)
                .foregroundStyle(isDone ? Color.dsSuccess : (isFuture ? .secondary : .white))
                .frame(width: 44, height: 44)
                .background(
                    isCurrent ? .white.opacity(0.18) : Color.dsSky.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: DSRadius.inline)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(.headline)
                Text(chapter.subtitle)
                    .font(.footnote)
                    .foregroundStyle(isCurrent ? .white.opacity(0.86) : .secondary)
                    .lineLimit(2)
                Text(isDone ? "重温" : (isCurrent ? "继续故事" : "可提前浏览"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? .white : (isDone ? Color.dsSuccess : Color.dsSky))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(isCurrent ? Color.white : Color.secondary.opacity(0.55))
        }
        .foregroundStyle(isCurrent ? .white : .primary)
        .padding(DSSpacing.md)
        .background {
            if isCurrent {
                LinearGradient(
                    colors: [Color.dsSky, DSScenePalette.city(chapter.regionID).accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.dsSurface
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(isCurrent ? .white.opacity(0.22) : Color.dsBorder, lineWidth: 1)
        }
        .opacity(isDone ? 0.76 : 1)
    }

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        completed = (try? await deps.storyProgress.completedStoryIDs()) ?? []
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}
