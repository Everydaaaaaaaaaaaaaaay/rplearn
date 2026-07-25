import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 票根夹：翻阅精致票根卡片（artSeed 决定配色）。
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
        Group {
            if stubs.isEmpty && !isLoading {
                ContentUnavailableView(
                    "还没有票根",
                    systemImage: "ticket",
                    description: Text("使用机票旅行后，票根会收藏在这里")
                )
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(stubs) { stub in
                            TicketStubCard(stub: stub, regionCatalog: regionCatalog)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("票根夹")
        .task {
            stubs = (try? await stubStore.all()) ?? []
            isLoading = false
        }
    }
}

/// 单张票根：登机牌风格，配色花纹由 artSeed 决定。
struct TicketStubCard: View {
    let stub: TicketStubDTO
    let regionCatalog: RegionCatalog

    private static let airportCodes = ["london": "LON", "melbourne": "MEL", "newyork": "NYC"]

    private var palette: [Color] {
        DSScenePalette.ticket(stub.artSeed)
    }

    private func code(_ regionID: String) -> String {
        Self.airportCodes[regionID] ?? String(regionID.prefix(3)).uppercased()
    }

    private func name(_ regionID: String) -> String {
        regionCatalog.region(id: regionID)?.nameZh ?? regionID
    }

    var body: some View {
        VStack(spacing: 0) {
            // 上联：航段
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(code(stub.fromRegionID))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text(name(stub.fromRegionID))
                        .font(.caption2)
                        .opacity(0.85)
                }
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "airplane")
                        .font(.title3)
                    Rectangle()
                        .frame(height: 1)
                        .opacity(0.5)
                }
                .frame(maxWidth: 90)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(code(stub.toRegionID))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text(name(stub.toRegionID))
                        .font(.caption2)
                        .opacity(0.85)
                }
            }
            .padding(16)

            // 撕票线
            HStack(spacing: 5) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle()
                        .fill(.white.opacity(0.55))
                        .frame(height: 1.5)
                }
            }
            .padding(.horizontal, 12)

            // 下联：序列号与日期
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOARDING PASS")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.7)
                    Text(stub.serialNumber)
                        .font(.footnote.monospaced().bold())
                }
                Spacer()
                Text(stub.usedAt, style: .date)
                    .font(.caption2)
                    .opacity(0.85)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}
