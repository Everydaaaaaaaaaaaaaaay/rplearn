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
                    Label(statusLabel, systemImage: statusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
            }

            Spacer(minLength: DSSpacing.xs)

            if state != .current {
                Button {
                    onTravel()
                } label: {
                    Label(actionLabel, systemImage: actionIcon)
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

    private var statusLabel: String {
        switch state {
        case .current:
            ""
        case .unlocked:
            "已去过，可直接前往"
        case .locked:
            ticketCount > 0 ? "\(ticketCount) 张机票可解锁" : "首次前往需要机票"
        }
    }

    private var statusIcon: String {
        state == .unlocked ? "arrow.triangle.2.circlepath" : "ticket.fill"
    }

    private var statusTint: Color {
        switch state {
        case .current: .dsSuccess
        case .unlocked: .dsSky
        case .locked: ticketCount > 0 ? .dsSunset : .gray
        }
    }

    private var actionLabel: String {
        state == .locked ? "解锁" : "前往"
    }

    private var actionIcon: String {
        state == .locked ? "ticket.fill" : "airplane"
    }

    private var stateTint: Color {
        switch state {
        case .current: .dsSuccess
        case .unlocked: .dsSky
        case .locked: .gray
        }
    }
}
