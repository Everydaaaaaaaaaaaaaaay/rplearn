import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

enum TravelOutcome {
    case success(region: Region, result: TravelResult)
    case failure(String)
}

struct TravelSheet: View {
    let region: Region
    let requiresTicket: Bool
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

            if !requiresTicket {
                Label("已经去过，可直接前往", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsSuccess)

                Button {
                    travel()
                } label: {
                    workingLabel("直接出发")
                }
                .buttonStyle(.dsActionPrimary)
                .disabled(isWorking)
            } else if let ticket = usable.first {
                Label(
                    ticket.type == .ticketUniversal
                        ? "使用通用机票解锁"
                        : "使用 \(ticket.countryCode ?? "") 国家机票解锁",
                    systemImage: "ticket.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsSunset)

                Button {
                    travel(with: ticket)
                } label: {
                    workingLabel("使用机票并出发")
                }
                .buttonStyle(.dsActionPrimary)
                .disabled(isWorking)
            } else {
                Label("首次前往需要一张可用机票", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    buyAndTravel()
                } label: {
                    workingLabel("花 \(EconomyService.Price.universalTicket) 金币购票并解锁")
                }
                .buttonStyle(.dsActionPrimary)
                .disabled(isWorking)
            }

            Text(
                requiresTicket
                    ? "首次解锁会收藏一张唯一的城市纪念票根；以后可以自由往返。"
                    : "这次旅行不会消耗机票，也不会重复生成票根。"
            )
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

    private func travel(with ticket: ItemDTO? = nil) {
        isWorking = true
        Task {
            do {
                let result = try await deps.travelService.travel(to: region, using: ticket)
                Haptics.notify(.success)
                onDone(.success(region: region, result: result))
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
                let result = try await deps.travelService.travel(to: region, using: ticket)
                Haptics.notify(.success)
                onDone(.success(region: region, result: result))
            } catch {
                onDone(.failure("购票失败：\(errorText(error))"))
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        if case EconomyStore.EconomyError.insufficientCoins = error { return "金币不足" }
        if let travelError = error as? TravelService.TravelError {
            switch travelError {
            case .ticketRequired:
                return "首次前往需要一张可用机票"
            case .ticketNotUsable:
                return "这张机票不能用于解锁该城市"
            case .alreadyThere:
                return "你已经在这里了"
            }
        }
        return error.localizedDescription
    }
}
