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

    private var journey: MainlineJourney? {
        profile.map { MainlineCatalog.journey(starterRegionID: $0.starterRegionID) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let journey, let profile {
                    header(journey)
                    ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                        let status = stopStatus(index: index, journey: journey)
                        if canOpen(stop, status: status, profile: profile) {
                            NavigationLink(value: stop.chapter) {
                                stopCard(stop, index: index, status: status, profile: profile)
                            }
                            .buttonStyle(.pressableCard)
                        } else {
                            stopCard(stop, index: index, status: status, profile: profile)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle("主线剧情")
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private func header(_ journey: MainlineJourney) -> some View {
        let done = journey.stops.filter { completed.contains($0.chapter.storyID) }.count
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("五城回声")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.dsSky)
                    Text(journey.title)
                        .font(.headline)
                }
                Spacer()
                Text("\(done) / \(journey.stops.count) 站")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done) / Double(journey.stops.count))
                .tint(.dsSuccess)
        }
        .dsCard()
    }

    private enum StopStatus: Equatable {
        case completed
        case active
        case future
    }

    private func stopStatus(index: Int, journey: MainlineJourney) -> StopStatus {
        let stop = journey.stops[index]
        if completed.contains(stop.chapter.storyID) {
            return .completed
        }
        let activeIndex = journey.stops.firstIndex {
            !completed.contains($0.chapter.storyID)
        } ?? journey.stops.count
        return index == activeIndex ? .active : .future
    }

    private func canOpen(
        _ stop: MainlineStop,
        status: StopStatus,
        profile: UserProfileDTO
    ) -> Bool {
        status != .future && profile.currentRegionID == stop.regionID
    }

    private func stopCard(
        _ stop: MainlineStop,
        index: Int,
        status: StopStatus,
        profile: UserProfileDTO
    ) -> some View {
        let chapter = stop.chapter
        let isDone = status == .completed
        let isActive = status == .active
        let isFuture = status == .future
        let isHere = profile.currentRegionID == stop.regionID
        let region = deps.regionCatalog.region(id: stop.regionID)

        return HStack(spacing: DSSpacing.sm) {
            ZStack {
                Text(region.map { flag($0.countryCode) } ?? "🌍")
                    .font(.title2)
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.dsSuccess)
                        .background(Color.dsSurface, in: Circle())
                        .offset(x: 15, y: 15)
                }
            }
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(
                    isActive ? .white.opacity(0.18) : Color.dsSky.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: DSRadius.inline)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("第 \(index + 1) 站 · \(region?.nameZh ?? stop.regionID)")
                        .font(.caption.weight(.black))
                    if isHere {
                        Text("当前城市")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.dsSuccess.opacity(isActive ? 0.26 : 0.12), in: Capsule())
                    }
                }
                Text(chapter.title)
                    .font(.subheadline.weight(.bold))
                Text(chapter.subtitle)
                    .font(.footnote)
                    .foregroundStyle(isActive ? .white.opacity(0.86) : .secondary)
                    .lineLimit(2)
                Text(actionText(status: status, isHere: isHere, regionName: region?.nameZh))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isActive ? .white : (isDone ? Color.dsSuccess : .secondary))
            }
            Spacer()
            Image(systemName: canOpen(stop, status: status, profile: profile) ? "chevron.right" : "lock.fill")
                .font(.caption.bold())
                .foregroundStyle(isActive ? Color.white : Color.secondary.opacity(0.55))
        }
        .foregroundStyle(isActive ? .white : .primary)
        .padding(DSSpacing.md)
        .background {
            if isActive {
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
                .stroke(isActive ? .white.opacity(0.22) : Color.dsBorder, lineWidth: 1)
        }
        .opacity(isFuture ? 0.6 : (isDone ? 0.82 : 1))
    }

    private func actionText(status: StopStatus, isHere: Bool, regionName: String?) -> String {
        switch status {
        case .completed:
            isHere ? "可重温" : "回到\(regionName ?? "这座城市")后重温"
        case .active:
            isHere ? "开展剧情" : "请先前往\(regionName ?? "目标城市")"
        case .future:
            "完成上一站后解锁"
        }
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
