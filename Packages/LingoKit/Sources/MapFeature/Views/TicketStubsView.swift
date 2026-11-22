import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 票根夹：每座城市只收藏一张首次抵达纪念票根。
///
/// 页头画在页面里（不用系统导航栏）：地图也隐藏系统栏，缩放转场两端都不切换导航栏显隐，
/// 交互返回中途取消时不会把顶栏和返回按钮弄丢。
public struct TicketStubsView: View {
    private let stubStore: TicketStubStore
    private let regionCatalog: RegionCatalog
    @State private var stubs: [TicketStubDTO] = []
    @State private var isLoading = true
    @State private var hasEntered = false
    private let slotColumns = [GridItem(.flexible(), spacing: Puff.Space.s), GridItem(.flexible(), spacing: Puff.Space.s)]

    public init(stubStore: TicketStubStore, regionCatalog: RegionCatalog) {
        self.stubStore = stubStore
        self.regionCatalog = regionCatalog
    }

    private var total: Int { regionCatalog.regions.count }

    /// 还没有票根的城市，按目录顺序。
    private var remaining: [Region] {
        let collected = Set(stubs.map(\.toRegionID))
        return regionCatalog.regions.filter { !collected.contains($0.id) }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Puff.Space.m) {
                if !isLoading {
                    progressCard
                        .puffEntrance(index: 0, isShown: hasEntered)
                    ForEach(Array(stubs.enumerated()), id: \.element.id) { index, stub in
                        TicketStubCard(stub: stub, regionCatalog: regionCatalog)
                            .puffEntrance(index: index + 1, isShown: hasEntered)
                    }
                    if !remaining.isEmpty {
                        Text("待收集")
                            .font(.puff(.headline, Puff.Weight.title))
                            .foregroundStyle(Puff.Palette.inkSoft)
                            .padding(.top, stubs.isEmpty ? 0 : Puff.Space.s)
                            .padding(.leading, 4)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: slotColumns, spacing: Puff.Space.s) {
                            ForEach(Array(remaining.enumerated()), id: \.element.id) { index, region in
                                TicketSlot(region: region, code: TicketStubCard.code(for: region.id))
                                    .puffEntrance(index: min(stubs.count + 2 + index / 2, 10), isShown: hasEntered)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Puff.Space.m)
            .padding(.bottom, Puff.Space.xl)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background { PuffPageBackdrop() }
        .fontDesign(.rounded)
        .puffPageHeader(title: "票根夹", showsBack: true)
        .puffPageTint(.mint, cameo: PuffPageCameo(.gugu, pose: stubs.isEmpty ? .point : .proud))
        .task {
            stubs = (try? await stubStore.all()) ?? []
            isLoading = false
            hasEntered = true
        }
    }

    private var progressCard: some View {
        let fraction = total == 0 ? 0 : Double(stubs.count) / Double(total)
        return VStack(alignment: .leading, spacing: Puff.Space.s) {
            HStack(spacing: Puff.Space.s) {
                PuffIconBubble("rosette", candy: .tangerine, size: 44)
                Text("首次抵达纪念")
                    .font(.puff(.headline, Puff.Weight.title))
                    .foregroundStyle(Puff.Palette.ink)
                Spacer(minLength: 0)
                Text("\(stubs.count) / \(total)")
                    .font(.puff(.title3, Puff.Weight.display))
                    .monospacedDigit()
                    .foregroundStyle(PuffCandy.tangerine.deep)
            }
            GeometryReader { geometry in
                Capsule().fill(Puff.Palette.cloud)
                    .overlay(alignment: .leading) {
                        Capsule().fill(PuffCandy.tangerine.base)
                            .frame(width: max(fraction > 0 ? 12 : 0, geometry.size.width * fraction))
                    }
            }
            .frame(height: 12)
        }
        .padding(Puff.Space.l)
        .puffCard(radius: Puff.Radius.huge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("首次抵达纪念，已收藏 \(stubs.count) 张，共 \(total) 座城市。第一次飞到新城市时会收到那里的纪念票根")
    }
}

/// 还没收集到的城市：虚线小票位，城市图标褪色带锁。
struct TicketSlot: View {
    let region: Region
    let code: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = PuffCitySnapshot.icon(regionID: region.id, size: CGSize(width: 44, height: 44)) {
                        Image(uiImage: icon).resizable().scaledToFill()
                    } else {
                        Puff.Palette.cloud
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .saturation(0.15)
                .opacity(0.7)
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Puff.Palette.inkFaint, in: Circle())
                    .overlay { Circle().strokeBorder(Puff.Palette.card, lineWidth: 2) }
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(region.nameZh)
                    .font(.puff(.subheadline, Puff.Weight.emphasis))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(code)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Puff.Palette.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Puff.Palette.card.opacity(0.72), in: RoundedRectangle(cornerRadius: Puff.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Puff.Radius.medium, style: .continuous)
                .strokeBorder(Puff.Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("待收集：\(region.nameZh)")
    }
}

/// 收藏级城市票根：上半是目的地的卡通街景，下半是白色票根，中间一道齿孔撕线。
struct TicketStubCard: View {
    enum Mode {
        case collection
        case arrival

        var sceneHeight: CGFloat {
            switch self {
            case .collection: 132
            case .arrival: 118
            }
        }
    }

    let stub: TicketStubDTO
    let regionCatalog: RegionCatalog
    var mode: Mode = .collection

    private static let airportCodes = [
        "london": "LON",
        "melbourne": "MEL",
        "newyork": "NYC",
        "capetown": "CPT",
        "singapore": "SIN",
        "dublin": "DUB",
        "edinburgh": "EDI",
        "vancouver": "YVR",
        "auckland": "AKL",
        "nairobi": "NBO",
        "toronto": "YYZ",
        "sydney": "SYD",
        "neworleans": "MSY",
        "manchester": "MAN",
        "kingston": "KIN",
    ]

    private var candy: PuffCandy { PuffCandy.stable(for: stub.toRegionID) }

    private var destination: Region? {
        regionCatalog.region(id: stub.toRegionID)
    }

    static func code(for regionID: String) -> String {
        airportCodes[regionID] ?? String(regionID.prefix(3)).uppercased()
    }

    private func code(_ regionID: String) -> String { Self.code(for: regionID) }

    private func name(_ regionID: String) -> String {
        regionCatalog.region(id: regionID)?.nameZh ?? regionID
    }

    var body: some View {
        VStack(spacing: 0) {
            PuffCityScene(regionID: stub.toRegionID, viewport: .east)
                .frame(height: mode.sceneHeight)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                .overlay(alignment: .top) {
                    HStack {
                        Label("首次抵达", systemImage: "rosette")
                            .font(.puff(.caption, Puff.Weight.emphasis))
                            .foregroundStyle(candy.deep)
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Puff.Palette.card, in: Capsule())
                        Spacer()
                        Text(stub.serialNumber)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Puff.Palette.inkSoft)
                            .padding(.horizontal, 9).frame(height: 28)
                            .background(Puff.Palette.card, in: Capsule())
                    }
                    .padding(10)
                }
                .padding([.horizontal, .top], 6)

            HStack(alignment: .bottom, spacing: Puff.Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(destination?.flagEmoji ?? "🌍") \(destination?.nameZh ?? stub.toRegionID)")
                        .font(.puff(.title2, Puff.Weight.display))
                        .foregroundStyle(Puff.Palette.ink)
                        .lineLimit(1)
                    Text(destination?.countryNameZh ?? "")
                        .font(.puff(.caption, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.inkSoft)
                }
                Spacer()
                Text(code(stub.toRegionID))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(candy.deep)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Puff.Space.l).padding(.top, Puff.Space.s)

            perforation
                .padding(.vertical, 10)

            HStack(spacing: Puff.Space.s) {
                Label("\(code(stub.fromRegionID)) → \(code(stub.toRegionID))", systemImage: "airplane")
                    .font(.puff(.caption, Puff.Weight.emphasis))
                    .foregroundStyle(Puff.Palette.ink)
                Spacer()
                Text(stub.usedAt, style: .date)
                    .font(.puff(.caption, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkSoft)
            }
            .padding(.horizontal, Puff.Space.l).padding(.bottom, Puff.Space.m)
        }
        .puffCard(radius: Puff.Radius.huge)
        // 撕线两端的半圆缺口真正挖空卡片，放在任何底色上都像票根。
        .compositingGroup()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name(stub.fromRegionID))前往\(name(stub.toRegionID))的首次抵达纪念票根，编号\(stub.serialNumber)"
        )
    }

    /// 票根撕线：两端半圆缺口 + 中间虚线。
    private var perforation: some View {
        HStack(spacing: 0) {
            notch.offset(x: -7)
            Line()
                .stroke(Puff.Palette.line, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 6]))
                .frame(height: 2)
            notch.offset(x: 7)
        }
        .accessibilityHidden(true)
    }

    private var notch: some View {
        Circle().fill(.black).frame(width: 16, height: 16).blendMode(.destinationOut)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
