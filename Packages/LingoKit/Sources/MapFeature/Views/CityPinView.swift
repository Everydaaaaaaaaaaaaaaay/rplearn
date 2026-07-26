import DesignSystem
import DomainKit
import SwiftUI
import UIKit

struct CityPinAnnotationView: View {
    static let mapAnchor = UnitPoint(x: 0.5, y: 0.69)

    let region: Region
    let state: CityPinView.PinState
    let isSelected: Bool
    let hasUsableTicket: Bool
    let onSelect: () -> Void
    let onAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onSelect) {
                CityPinView(
                    region: region,
                    state: state,
                    isSelected: isSelected
                )
            }
            .buttonStyle(.pressableCard)
            .frame(height: 76, alignment: .top)
            .accessibilityLabel("\(region.nameZh)，\(state.accessibilityText)")
            .accessibilityHint("显示这个地点的前往操作")

            if isSelected {
                actionButton
                    .transition(
                        .opacity.combined(
                            with: reduceMotion
                                ? .identity
                                : .scale(scale: 0.96, anchor: .top)
                        )
                    )
            } else {
                Color.clear
                    .frame(height: 30)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 110, alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSelected)
        .zIndex(isSelected ? 1 : 0)
    }

    private var actionButton: some View {
        Button {
            guard state != .current else { return }
            onAction()
        } label: {
            Label(actionTitle, systemImage: actionIcon)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(actionForeground)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(actionBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(state == .current ? 0.58 : 0.8), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        }
        .buttonStyle(.pressableCard)
        .disabled(state == .current)
        .accessibilityLabel("\(actionTitle)：\(region.nameZh)")
        .accessibilityHint(actionAccessibilityHint)
    }

    private var actionTitle: String {
        switch state {
        case .current:
            "已在这里"
        case .unlocked:
            "前往"
        case .locked:
            hasUsableTicket ? "使用机票" : "购买机票"
        }
    }

    private var actionIcon: String {
        switch state {
        case .current:
            "location.fill"
        case .unlocked:
            "airplane"
        case .locked:
            "ticket.fill"
        }
    }

    private var actionForeground: Color {
        state == .current ? .secondary : .white
    }

    private var actionBackground: Color {
        switch state {
        case .current:
            Color.dsSurface.opacity(0.92)
        case .unlocked:
            Color.dsSky
        case .locked:
            Color.dsSunset
        }
    }

    private var actionAccessibilityHint: String {
        switch state {
        case .current:
            "当前已经在这个城市"
        case .unlocked:
            "打开出发确认"
        case .locked:
            hasUsableTicket ? "使用已有机票解锁并前往" : "购买机票并解锁这个城市"
        }
    }
}

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
            ZStack {
                cityThumbnail
                    .overlay {
                        Circle()
                            .stroke(
                                ringColor,
                                lineWidth: isSelected ? 3 : (state == .current ? 2 : 1)
                            )
                    }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Text(region.flagEmoji)
                            .font(.system(size: 10))
                            .frame(width: 18, height: 18)
                            .background(Color.dsSurface.opacity(0.96), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.88), lineWidth: 1))
                            .shadow(color: .black.opacity(0.13), radius: 2, y: 1)
                        Spacer()
                        stateBadge
                    }
                    .offset(y: 2)
                }
            }
            .frame(width: 48, height: 48)
            .shadow(
                color: .black.opacity(isSelected ? 0.2 : 0.12),
                radius: isSelected ? 7 : 4,
                y: 2
            )

            Text(region.nameZh)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.dsSurface.opacity(0.96), in: Capsule())
                .overlay(Capsule().stroke(ringColor.opacity(isSelected ? 0.7 : 0.28), lineWidth: 1))
        }
        .opacity(state == .locked ? 0.88 : 1)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(DSAnimation.gentle, value: isSelected)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cityThumbnail: some View {
        if UIImage(named: "city_backdrop_\(region.id)") != nil {
            Image("city_backdrop_\(region.id)")
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .saturation(state == .locked ? 0.3 : 1)
                .brightness(state == .locked ? -0.08 : 0)
                .overlay {
                    Circle()
                        .fill(.black.opacity(state == .locked ? 0.14 : 0))
                }
        } else {
            ZStack {
                DSScenePalette.city(region.id).accent.opacity(0.2)
                Text(region.flagEmoji)
                    .font(.system(size: 22))
            }
            .clipShape(Circle())
        }
    }

    private var stateBadge: some View {
        Image(systemName: stateIcon)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 17, height: 17)
            .background(stateTint, in: Circle())
            .overlay(Circle().stroke(Color.dsSurface, lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    private var ringColor: Color {
        if isSelected {
            return .dsSky
        }
        switch state {
        case .current:
            return .dsSuccess
        case .unlocked:
            return .white.opacity(0.92)
        case .locked:
            return Color.dsBorder
        }
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
