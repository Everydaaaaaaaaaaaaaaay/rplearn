import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

struct FlightPresentation: Identifiable {
    let id = UUID()
    let fromRegionID: String
    let toRegionID: String
    let fromName: String
    let toName: String
    let ticketStub: TicketStubDTO?

    var isFirstArrival: Bool { ticketStub != nil }
}

struct FlightTransitionOverlay: View {
    let presentation: FlightPresentation
    let regionCatalog: RegionCatalog
    let onComplete: () -> Void

    var body: some View {
        DSFlightTransitionView(
            fromName: presentation.fromName,
            toName: presentation.toName,
            statusText: presentation.isFirstArrival
                ? "正在签发首次抵达纪念票根"
                : "自由往返 · 不产生新票根",
            statusIcon: presentation.isFirstArrival ? "rosette" : "arrow.left.arrow.right",
            autoCompletionDelay: presentation.isFirstArrival ? nil : .milliseconds(850),
            holdsOnArrival: holdsArrivalForUITest,
            celebratesOnArrival: presentation.isFirstArrival,
            onComplete: onComplete
        ) {
            arrivalContent
        }
    }

    @ViewBuilder
    private var arrivalContent: some View {
        if let stub = presentation.ticketStub {
            VStack(spacing: DSSpacing.md) {
                Spacer()

                VStack(spacing: 3) {
                    Text("城市收藏 +1")
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.78))
                    Text("首次抵达 \(presentation.toName)")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)

                TicketStubCard(
                    stub: stub,
                    regionCatalog: regionCatalog,
                    mode: .arrival
                )
                .padding(.horizontal, DSSpacing.lg)

                Label("唯一票根已收入票根夹", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.white)

                Button(action: onComplete) {
                    Text("收下票根")
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsSkyDeep)
                .background(.white, in: Capsule())
                .padding(.horizontal, DSSpacing.xl)
                .accessibilityHint("关闭抵达仪式并返回地图")

                Spacer()
            }
        } else {
            VStack(spacing: DSSpacing.md) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.white)
                Text("欢迎回到 \(presentation.toName)")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .multilineTextAlignment(.center)
                Text("已解锁城市可以自由往返\n这次不会重复生成票根")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .foregroundStyle(.white)
        }
    }

    private var holdsArrivalForUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["UI_TEST_FLIGHT_HOLD"] == "1"
        #else
        false
        #endif
    }
}
