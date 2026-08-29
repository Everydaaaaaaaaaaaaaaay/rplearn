import DesignSystem
import DomainKit
import SwiftUI
import UIKit

struct CityPinAnnotationView: View {
    static let mapAnchor = UnitPoint.bottom

    let region: Region
    let state: CityPinView.PinState
    let isSelected: Bool

    var body: some View {
        CityPinView(
            region: region,
            state: state,
            isSelected: isSelected
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(region.nameZh)，\(state.accessibilityText)")
        .accessibilityHint("轻点选择城市，拖动可继续移动地图")
        .accessibilityAddTraits(.isButton)
    }
}

struct SelectedCityActionBar: View {
    let region: Region
    let state: CityPinView.PinState
    let hasUsableTicket: Bool
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(region.flagEmoji)
                .font(.system(size: 24))
                .frame(width: 42, height: 42)
                .background(Color.dsSurface.opacity(0.7), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(region.nameZh)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .lineLimit(1)
                Text(state.accessibilityText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if state != .current {
                Button(action: onAction) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(actionBackground.gradient, in: Capsule())
                        .overlay {
                            Capsule().stroke(.white.opacity(0.72), lineWidth: 1)
                        }
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel("\(actionTitle)：\(region.nameZh)")
                .accessibilityHint(actionAccessibilityHint)
            } else {
                Label("当前", systemImage: "location.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.dsSuccess)
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(Color.dsSuccess.opacity(0.1), in: Capsule())
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消选择")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .dsSceneGlass(radius: 22, interactive: true, legibility: .enhanced)
        .accessibilityElement(children: .contain)
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
        .animation(DSAnimation.snappy, value: isSelected)
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
