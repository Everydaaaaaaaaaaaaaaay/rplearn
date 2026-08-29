import DesignSystem
import DomainKit
import SwiftUI

struct JourneyGuideView: View {
    let guidance: JourneyMapGuidance
    let regionCatalog: RegionCatalog
    let state: (Region) -> CityPinState
    let ticketCount: (Region) -> Int
    let onTravel: (Region) -> Void
    let onOpenMainline: @MainActor () -> Void

    @ViewBuilder
    var body: some View {
        switch guidance {
        case .travel(let eyebrow, let title, let detail, let regionIDs):
            let regions = regionIDs.compactMap(regionCatalog.region(id:))
            VStack(alignment: .leading, spacing: 9) {
                guideHeader(eyebrow: eyebrow, title: title, detail: detail)
                destinationLayout(regions)
            }
            .padding(10)
            .background(
                Color.dsSurface.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(.white.opacity(0.68), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        case .continueStory(let chapter, let objective):
            ContinueStoryGuide(
                chapter: chapter,
                objective: objective,
                region: regionCatalog.region(id: chapter.regionID),
                onOpenMainline: onOpenMainline
            )
        case .complete(let title, let detail):
            EmptyJourneyGuide(title: title, detail: detail)
        }
    }

    private func guideHeader(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Color.dsSky)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func destinationLayout(_ regions: [Region]) -> some View {
        switch regions.count {
        case 0:
            EmptyJourneyGuide(
                title: "下一站正在准备",
                detail: "先回到主线查看最新的剧情目标。"
            )
        case 1:
            destinationCard(regions[0], mode: .wide)
        case 2:
            HStack(spacing: 10) {
                ForEach(regions) { region in
                    destinationCard(region, mode: .compact)
                }
            }
        default:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(regions) { region in
                        destinationCard(region, mode: .scrolling)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 1, for: .scrollContent)
            .frame(height: 86)
        }
    }

    private func destinationCard(_ region: Region, mode: JourneyCityCard.Mode) -> some View {
        JourneyCityCard(
            region: region,
            mode: mode,
            state: state(region),
            ticketCount: ticketCount(region),
            onTravel: { onTravel(region) }
        )
    }
}

private struct JourneyCityCard: View {
    enum Mode {
        case wide
        case compact
        case scrolling

        var width: CGFloat? {
            switch self {
            case .wide, .compact: nil
            case .scrolling: 196
            }
        }
    }

    let region: Region
    let mode: Mode
    let state: CityPinState
    let ticketCount: Int
    let onTravel: () -> Void

    private var statusLabel: String {
        switch state {
        case .current: "已抵达"
        case .unlocked: "已去过 · 免费前往"
        case .locked: ticketCount > 0 ? "使用机票解锁" : "首次前往需机票"
        }
    }

    var body: some View {
        Button(action: onTravel) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    DSScenePalette.city(region.id).skyTop
                    Image("city_map_card_\(region.id)")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.74)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    HStack(alignment: .bottom, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(region.flagEmoji) \(region.nameZh)")
                                .font(.system(.headline, design: .rounded, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(statusLabel)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: state == .locked ? "ticket.fill" : "airplane")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.dsSky.opacity(0.92), in: Circle())
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            }
        }
        .frame(width: mode.width, height: 86)
        .buttonStyle(.pressableCard)
        .accessibilityLabel("\(region.nameZh)，\(statusLabel)")
        .accessibilityHint("打开前往确认")
    }
}

private struct ContinueStoryGuide: View {
    let chapter: MainlineChapter
    let objective: String
    let region: Region?
    let onOpenMainline: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "book.pages.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.dsSuccess.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("已抵达 · 继续主线")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color.dsSuccess)
                Text(chapter.title)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .lineLimit(1)
                Text(objective)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("去主线") {
                onOpenMainline()
            }
            .buttonStyle(.dsAction(.primary, fullWidth: false, compact: true))
        }
        .padding(12)
        .background(
            Color.dsSurface.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 9, y: 3)
        .accessibilityElement(children: .contain)
    }
}

private struct EmptyJourneyGuide: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.dsSunset)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color.dsSurface.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}
