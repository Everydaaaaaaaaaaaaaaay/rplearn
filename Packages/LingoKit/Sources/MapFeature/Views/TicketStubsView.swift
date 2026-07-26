import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 票根夹：每座城市只收藏一张首次抵达纪念票根。
public struct TicketStubsView: View {
    private let stubStore: TicketStubStore
    private let regionCatalog: RegionCatalog
    @State private var stubs: [TicketStubDTO] = []
    @State private var isLoading = true

    public init(stubStore: TicketStubStore, regionCatalog: RegionCatalog) {
        self.stubStore = stubStore
        self.regionCatalog = regionCatalog
    }

    public var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()

            if stubs.isEmpty && !isLoading {
                ContentUnavailableView(
                    "还没有纪念票根",
                    systemImage: "ticket",
                    description: Text("首次解锁一座城市后，它的唯一票根会收藏在这里")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DSSpacing.md) {
                        collectionHeader
                        ForEach(stubs) { stub in
                            TicketStubCard(stub: stub, regionCatalog: regionCatalog)
                        }
                    }
                    .padding(DSSpacing.md)
                }
            }
        }
        .navigationTitle("票根夹")
        .task {
            stubs = (try? await stubStore.all()) ?? []
            isLoading = false
        }
    }

    private var collectionHeader: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "rosette")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.dsSunset.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("首次抵达纪念")
                        .font(.headline)
                    Text("每座城市只签发一张")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(stubs.count) / \(regionCatalog.regions.count)")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsSky)
            }

            ProgressView(
                value: regionCatalog.regions.isEmpty
                    ? 0
                    : Double(stubs.count) / Double(regionCatalog.regions.count)
            )
            .tint(.dsSunset)
        }
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

/// 收藏级城市票根：目的地场景、首次抵达印章和唯一编号共同构成纪念物。
struct TicketStubCard: View {
    enum Mode {
        case collection
        case arrival

        var height: CGFloat {
            switch self {
            case .collection: 236
            case .arrival: 220
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
        "reykjavik": "KEF",
        "lisbon": "LIS",
        "tokyo": "TYO",
    ]

    private var palette: [Color] {
        DSScenePalette.ticket(stub.artSeed)
    }

    private var destination: Region? {
        regionCatalog.region(id: stub.toRegionID)
    }

    private func code(_ regionID: String) -> String {
        Self.airportCodes[regionID] ?? String(regionID.prefix(3)).uppercased()
    }

    private func name(_ regionID: String) -> String {
        regionCatalog.region(id: regionID)?.nameZh ?? regionID
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: palette,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image("city_backdrop_\(stub.toRegionID)")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    colors: [
                        .black.opacity(0.08),
                        .black.opacity(0.24),
                        .black.opacity(0.86),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("FIRST ARRIVAL", systemImage: "rosette")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        Text(stub.serialNumber)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(.black.opacity(0.24), in: Capsule())
                    }

                    Spacer()

                    HStack(alignment: .bottom, spacing: DSSpacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(destination?.flagEmoji ?? "🌍")
                                .font(.title2)
                            Text(destination?.nameZh ?? stub.toRegionID)
                                .font(.system(.title, design: .rounded, weight: .black))
                                .lineLimit(1)
                            Text("首次抵达 · \(destination?.countryNameZh ?? "")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        Spacer()
                        Text(code(stub.toRegionID))
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.8)
                    }

                    perforation
                        .padding(.vertical, 9)

                    HStack(spacing: DSSpacing.sm) {
                        Label(
                            "\(code(stub.fromRegionID)) → \(code(stub.toRegionID))",
                            systemImage: "airplane"
                        )
                        .font(.caption.weight(.bold))

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("ISSUED")
                                .font(.system(size: 7, weight: .black))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.66))
                            Text(stub.usedAt, style: .date)
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
                .padding(DSSpacing.md)
            }
        }
        .frame(height: mode.height)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name(stub.fromRegionID))前往\(name(stub.toRegionID))的首次抵达纪念票根，编号\(stub.serialNumber)"
        )
    }

    private var perforation: some View {
        HStack(spacing: 5) {
            ForEach(0..<26, id: \.self) { _ in
                Capsule()
                    .fill(.white.opacity(0.52))
                    .frame(width: 5, height: 1.5)
            }
        }
    }
}
