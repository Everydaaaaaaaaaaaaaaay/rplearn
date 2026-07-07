import DomainKit
import PersistenceKit
import SwiftUI

/// MapFeature 依赖。
public struct MapDependencies: Sendable {
    public let economyStore: EconomyStore
    public let itemStore: ItemStore
    public let stubStore: TicketStubStore
    public let travelService: TravelService
    public let economyService: EconomyService
    public let regionCatalog: RegionCatalog

    public init(
        economyStore: EconomyStore,
        itemStore: ItemStore,
        stubStore: TicketStubStore,
        travelService: TravelService,
        economyService: EconomyService,
        regionCatalog: RegionCatalog
    ) {
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.stubStore = stubStore
        self.travelService = travelService
        self.economyService = economyService
        self.regionCatalog = regionCatalog
    }
}

/// 地图页：地区卡片（当前/已解锁/未解锁），用机票前往；机票不足可金币购票。
public struct MapView: View {
    private let deps: MapDependencies
    @State private var profile: UserProfileDTO?
    @State private var tickets: [ItemDTO] = []
    @State private var travelTarget: Region?
    @State private var feedback: String?

    public init(deps: MapDependencies) {
        self.deps = deps
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                walletCard
                ForEach(deps.regionCatalog.regions) { region in
                    regionCard(region)
                }
            }
            .padding(16)
        }
        .navigationTitle("地图")
        .task {
            await reload()
        }
        .sheet(item: $travelTarget) { region in
            TravelSheet(region: region, deps: deps, tickets: tickets) { message in
                travelTarget = nil
                feedback = message
                Task { await reload() }
            }
            .presentationDetents([.medium])
        }
        .alert(feedback ?? "", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("好", role: .cancel) {}
        }
    }

    private var walletCard: some View {
        HStack(spacing: 16) {
            if let profile {
                Label("\(profile.coins)", systemImage: "circle.grid.2x1.fill")
                    .foregroundStyle(.orange)
            }
            Label("机票 ×\(tickets.count)", systemImage: "airplane")
                .foregroundStyle(Color.accentColor)
            Spacer()
        }
        .font(.subheadline.weight(.medium))
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func regionCard(_ region: Region) -> some View {
        let isCurrent = profile?.currentRegionID == region.id
        let isUnlocked = profile?.unlockedRegionIDs.contains(region.id) ?? false

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(flag(region.countryCode))
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.nameZh).font(.headline)
                    Text(region.nameEn).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Text("当前")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                } else if isUnlocked {
                    Text("已解锁")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                }
            }
            Text(region.taglineZh)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !isCurrent {
                Button {
                    travelTarget = region
                } label: {
                    Label("前往", systemImage: "airplane.departure")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isCurrent || isUnlocked ? 1 : 0.75)
    }

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        tickets = (try? await deps.itemStore.unconsumedTickets()) ?? []
    }

    private func flag(_ countryCode: String) -> String {
        countryCode.unicodeScalars.reduce(into: "") { result, scalar in
            if let flagScalar = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
    }
}

/// 出行确认弹层：选机票（无可用票时用金币购票）。
private struct TravelSheet: View {
    let region: Region
    let deps: MapDependencies
    let tickets: [ItemDTO]
    let onDone: (String) -> Void

    @State private var isWorking = false

    private var usable: [ItemDTO] {
        tickets.filter { TravelService.isTicketUsable($0, for: region) }
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("前往 \(region.nameZh)")
                .font(.title3.bold())
                .padding(.top, 20)
            Text(region.taglineZh)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let ticket = usable.first {
                Label(
                    ticket.type == .ticketUniversal ? "使用通用机票" : "使用 \(ticket.countryCode ?? "") 国家机票",
                    systemImage: "ticket"
                )
                .font(.subheadline)
                Button {
                    travel(with: ticket)
                } label: {
                    Text("确认出发")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            } else {
                Text("没有可用的机票")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    buyAndTravel()
                } label: {
                    Text("花 \(EconomyService.Price.universalTicket) 金币购买通用机票并出发")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func travel(with ticket: ItemDTO) {
        isWorking = true
        Task {
            do {
                let stub = try await deps.travelService.travel(to: region, using: ticket)
                onDone("✈️ 已抵达\(region.nameZh)！票根 \(stub.serialNumber) 已收入票根夹。")
            } catch {
                onDone("出发失败：\(errorText(error))")
            }
        }
    }

    private func buyAndTravel() {
        isWorking = true
        Task {
            do {
                let ticket = try await deps.economyService.buyTicket(type: .ticketUniversal)
                let stub = try await deps.travelService.travel(to: region, using: ticket)
                onDone("✈️ 已抵达\(region.nameZh)！票根 \(stub.serialNumber) 已收入票根夹。")
            } catch {
                onDone("购票失败：\(errorText(error))")
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        if case EconomyStore.EconomyError.insufficientCoins = error {
            return "金币不足"
        }
        return error.localizedDescription
    }
}
