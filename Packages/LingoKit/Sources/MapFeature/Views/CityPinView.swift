import DesignSystem
import DomainKit
import SwiftUI

struct CityPinView: View {
    enum PinState {
        case current
        case unlocked
        case locked

        var accessibilityText: String {
            switch self {
            case .current: "当前城市"
            case .unlocked: "已解锁"
            case .locked: "未解锁"
            }
        }
    }

    let region: Region
    let state: PinState
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.dsSurface)
                Text(region.flagEmoji)
                    .font(.system(size: 24))
                Image(systemName: stateIcon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(stateTint, in: Circle())
                    .overlay(Circle().stroke(Color.dsSurface, lineWidth: 2))
            }
            .frame(width: 48, height: 48)
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.dsSky : Color.dsBorder, lineWidth: isSelected ? 3 : 1)
            }
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.1), radius: isSelected ? 7 : 4, y: 2)

            Text(region.nameZh)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.dsSurface, in: Capsule())
                .overlay(Capsule().stroke(Color.dsBorder, lineWidth: 1))
        }
        .opacity(state == .locked ? 0.78 : 1)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(DSAnimation.gentle, value: isSelected)
        .contentShape(Rectangle())
    }

    private var stateTint: Color {
        switch state {
        case .current: .dsSuccess
        case .unlocked: .dsSky
        case .locked: .gray
        }
    }

    private var stateIcon: String {
        switch state {
        case .current: "location.fill"
        case .unlocked: "checkmark"
        case .locked: "lock.fill"
        }
    }
}
