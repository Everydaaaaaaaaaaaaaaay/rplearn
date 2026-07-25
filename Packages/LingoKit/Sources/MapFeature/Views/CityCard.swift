import DesignSystem
import DomainKit
import SwiftUI

struct CityCard: View {
    let region: Region
    let state: CityPinView.PinState
    let ticketCount: Int
    let onTravel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DSScenePalette.city(region.id).skyTop,
                                    DSScenePalette.city(region.id).silhouetteNear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Image(systemName: landmarkIcon)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(region.nameZh)
                            .font(.title2.bold())
                        DSChip(state.accessibilityText, tint: state == .current ? .dsSuccess : .dsSky)
                    }
                    Text("\(region.countryNameZh) · \(region.taglineZh)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: DSSpacing.sm) {
                Label("可用机票 ×\(ticketCount)", systemImage: "ticket.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSunset)
                Spacer()
                if state != .current {
                    Button {
                        onTravel()
                    } label: {
                        Label("前往", systemImage: "airplane")
                    }
                    .buttonStyle(.duo(.primary, fullWidth: false, compact: true))
                } else {
                    Label("你在这里", systemImage: "location.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.dsSuccess)
                }
            }
        }
        .dsCard()
    }

    private var landmarkIcon: String {
        switch region.id {
        case "melbourne": "tram.fill"
        case "newyork": "building.2.fill"
        default: "clock.fill"
        }
    }
}
