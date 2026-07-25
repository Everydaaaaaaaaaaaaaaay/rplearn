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
        VStack(spacing: DSSpacing.lg) {
            Capsule().fill(.tertiary).frame(width: 38, height: 5).padding(.top, 8)
            ZStack {
                Circle().fill(Color.dsSky.opacity(0.12))
                Image(systemName: "airplane.departure")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.dsSky)
            }
            .frame(width: 76, height: 76)
            Text("前往 \(region.nameZh)")
                .font(.title2.bold())
            Text(region.taglineZh)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let ticket = usable.first {
                Label(
                    ticket.type == .ticketUniversal ? "使用通用机票" : "使用 \(ticket.countryCode ?? "") 国家机票",
                    systemImage: "ticket.fill"
                )
                .foregroundStyle(Color.dsSunset)
                Button {
                    travel(with: ticket)
                } label: {
                    workingLabel("确认出发")
                }
                .buttonStyle(.duoPrimary)
                .disabled(isWorking)
            } else {
                Text("没有可用的机票")
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
            Spacer()
        }
        .padding(.horizontal, DSSpacing.xl)
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
