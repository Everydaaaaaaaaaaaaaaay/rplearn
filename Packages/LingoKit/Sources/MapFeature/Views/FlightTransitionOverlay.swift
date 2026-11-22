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
    let onComplete: @MainActor () -> Void

    var body: some View {
        DSFlightTransitionView(
            fromName: presentation.fromName,
            toName: presentation.toName,
            statusText: presentation.isFirstArrival
                ? "正在签发首次抵达纪念票根"
                : "自由往返 · 不产生新票根",
            statusIcon: presentation.isFirstArrival ? "rosette" : "arrow.left.arrow.right",
            autoCompletionDelay: presentation.isFirstArrival ? nil : .milliseconds(1_100),
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
            VStack(spacing: Puff.Space.m) {
                Spacer()

                BrandMascotView(pose: .celebrate, size: 84, reactsToTap: true)

                VStack(spacing: 4) {
                    Text("城市收藏 +1")
                        .font(.puff(.caption, Puff.Weight.emphasis))
                        .foregroundStyle(PuffCandy.sunny.deep)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(PuffCandy.sunny.wash, in: Capsule())
                    Text("首次抵达 \(presentation.toName)")
                        .font(.puff(.largeTitle, Puff.Weight.display))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }

                TicketStubCard(
                    stub: stub,
                    regionCatalog: regionCatalog,
                    mode: .arrival
                )
                .padding(.horizontal, Puff.Space.l)

                Button(action: onComplete) {
                    Label("收下票根", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PuffCandyButtonStyle(.sunny))
                .padding(.horizontal, Puff.Space.xl)
                .accessibilityHint("关闭抵达仪式并返回地图")

                Spacer()
            }
        } else {
            VStack(spacing: Puff.Space.m) {
                Spacer()
                BrandMascotView(pose: .celebrate, size: 92, reactsToTap: true)
                Text("欢迎回到 \(presentation.toName)")
                    .font(.puff(.largeTitle, Puff.Weight.display))
                    .multilineTextAlignment(.center)
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
