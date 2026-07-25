import DesignSystem
import DomainKit
import SwiftUI

struct CityCard: View {
    let region: Region
    let state: CityPinView.PinState
    let ticketCount: Int
    let onTravel: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(region.flagEmoji)
                .font(.system(size: 30))
                .frame(width: 54, height: 54)
                .background(Color.dsBackground, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: DSSpacing.xs) {
                    Text(region.nameZh)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    DSChip(state.accessibilityText, tint: stateTint)
                }
                Text(region.countryNameZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if state != .current {
                    Label(ticketLabel, systemImage: "ticket.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ticketCount > 0 ? Color.dsSunset : Color.gray)
                }
            }

            Spacer(minLength: DSSpacing.xs)

            if state != .current {
                Button {
                    onTravel()
                } label: {
                    Label("前往", systemImage: "airplane")
                }
                .buttonStyle(.duo(.primary, fullWidth: false, compact: true))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dsSuccess)
                    .accessibilityLabel("当前所在城市")
            }
        }
        .dsCard()
    }

    private var ticketLabel: String {
        ticketCount > 0 ? "\(ticketCount) 张机票可用" : "下一步可购票"
    }

    private var stateTint: Color {
        switch state {
        case .current: .dsSuccess
        case .unlocked: .dsSky
        case .locked: .gray
        }
    }
}
