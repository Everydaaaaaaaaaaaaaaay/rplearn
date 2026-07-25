import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

enum TravelOutcome {
    case success(region: Region, serial: String)
    case failure(String)
}

struct TravelSheet: View {
    let region: Region
    let deps: MapDependencies
    let tickets: [ItemDTO]
    let onDone: (TravelOutcome) -> Void

    @State private var isWorking = false

    private var usable: [ItemDTO] {
        tickets.filter { TravelService.isTicketUsable($0, for: region) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(spacing: DSSpacing.sm) {
                Text(region.flagEmoji)
                    .font(.system(size: 32))
                    .frame(width: 56, height: 56)
                    .background(Color.dsBackground, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("确认目的地")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(region.nameZh)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(region.countryNameZh)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let ticket = usable.first {
                Label(
                    ticket.type == .ticketUniversal ? "使用通用机票" : "使用 \(ticket.countryCode ?? "") 国家机票",
                    systemImage: "ticket.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsSunset)

                Button {
                    travel(with: ticket)
                } label: {
                    workingLabel("确认出发")
                }
                .buttonStyle(.duoPrimary)
                .disabled(isWorking)
            } else {
                Label("当前没有可用机票", systemImage: "ticket")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    buyAndTravel()
                } label: {
                    workingLabel("花 \(EconomyService.Price.universalTicket) 金币购票并出发")
                }
                .buttonStyle(.duoPrimary)
                .disabled(isWorking)
            }

            Text("确认后将生成一张新的旅行票根。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.md)
    }

    private func workingLabel(_ title: String) -> some View {
        HStack {
            if isWorking { ProgressView().tint(.white) }
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func travel(with ticket: ItemDTO) {
        isWorking = true
        Task {
            do {
                let stub = try await deps.travelService.travel(to: region, using: ticket)
                Haptics.notify(.success)
                onDone(.success(region: region, serial: stub.serialNumber))
            } catch {
                onDone(.failure("出发失败：\(errorText(error))"))
            }
        }
    }

    private func buyAndTravel() {
        isWorking = true
        Task {
            do {
                let ticket = try await deps.economyService.buyTicket(type: .ticketUniversal)
                let stub = try await deps.travelService.travel(to: region, using: ticket)
                Haptics.notify(.success)
                onDone(.success(region: region, serial: stub.serialNumber))
            } catch {
                onDone(.failure("购票失败：\(errorText(error))"))
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        if case EconomyStore.EconomyError.insufficientCoins = error { return "金币不足" }
        return error.localizedDescription
    }
}
