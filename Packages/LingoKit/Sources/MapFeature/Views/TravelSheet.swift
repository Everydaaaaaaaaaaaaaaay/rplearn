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
        VStack(alignment: .leading, spacing: Puff.Space.m) {
            ZStack(alignment: .bottomLeading) {
                PuffCityScene(regionID: region.id, viewport: .west)
                    .frame(height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.large, style: .continuous))
                    .puffTapBurst()
                Text(region.flagEmoji)
                    .font(.system(size: 28))
                    .frame(width: 52, height: 52)
                    .background(Puff.Palette.card, in: Circle())
                    .overlay { Circle().strokeBorder(Puff.Palette.line, lineWidth: 1.5) }
                    .offset(x: Puff.Space.m, y: 26)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(region.nameZh)
                    .font(.puff(.title, Puff.Weight.display))
                    .foregroundStyle(Puff.Palette.ink)
                Text(region.countryNameZh)
                    .font(.puff(.subheadline, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkSoft)
            }

            if deps.access.isGuest {
                Button("登录并继续旅程") {
                    deps.access.requestSignIn("登录后即可飞往其他城市。")
                }
                .buttonStyle(PuffCandyButtonStyle(.sky))
                .frame(maxWidth: .infinity)
            } else if !requiresTicket {
                PuffTag("已经去过", systemImage: "checkmark.seal.fill", candy: .mint)

                Button {
                    travel()
                } label: {
                    workingLabel("直接出发")
                }
                .buttonStyle(PuffCandyButtonStyle(.sky))
                .disabled(isWorking)
            } else if let ticket = usable.first {
                PuffTag(
                    ticket.type == .ticketUniversal
                        ? "通用机票"
                        : "\(ticket.countryCode ?? "") 国家机票",
                    systemImage: "ticket.fill",
                    candy: .tangerine
                )

                Button {
                    travel(with: ticket)
                } label: {
                    workingLabel("使用机票并出发")
                }
                .buttonStyle(PuffCandyButtonStyle(.tangerine))
                .disabled(isWorking)
            } else {
                PuffTag("需要一张机票", systemImage: "lock.fill", candy: .grape)

                Button {
                    buyAndTravel()
                } label: {
                    workingLabel("花 \(EconomyService.Price.universalTicket) 金币购票并解锁")
                }
                .buttonStyle(PuffCandyButtonStyle(.sunny))
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, Puff.Space.l)
        .padding(.top, Puff.Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Puff.Palette.page.ignoresSafeArea())
    }

    private func workingLabel(_ title: String) -> some View {
        HStack {
            if isWorking { PuffLoadingDots().scaleEffect(0.6).frame(width: 34, height: 20) }
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func travel(with ticket: ItemDTO? = nil) {
        guard !deps.access.isGuest, deps.travelService.allowsTravel else {
            deps.access.requestSignIn("登录后即可飞往其他城市。")
            return
        }
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
        guard !deps.access.isGuest, deps.travelService.allowsTravel else {
            deps.access.requestSignIn("登录后即可飞往其他城市。")
            return
        }
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
            case .loginRequired:
                return "登录后即可飞往其他城市"
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
