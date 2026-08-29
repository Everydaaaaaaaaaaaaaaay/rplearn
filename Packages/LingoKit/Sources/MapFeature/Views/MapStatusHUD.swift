import DesignSystem
import DomainKit
import SwiftUI

/// 地图顶部左侧的当前位置；资源与票根在右侧独立成列。
struct MapStatusHUD: View {
    let currentRegion: Region?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        locationLine
    }

    private var locationLine: some View {
        Group {
            if let currentRegion {
                Text("当前位于：")
                    .fontWeight(.regular)
                    + Text(currentRegion.flagEmoji)
                    + Text(currentRegion.countryNameZh)
                    .fontWeight(.heavy)
                    + Text(" ")
                    + Text(currentRegion.nameZh)
                    .fontWeight(.heavy)
            } else {
                Text("当前位于：")
                    .fontWeight(.regular)
                    + Text("正在载入")
                    .fontWeight(.heavy)
            }
        }
        .font(.system(size: 19, design: .rounded))
        .foregroundStyle(primaryForeground)
        .lineLimit(1)
        .minimumScaleFactor(0.84)
        .shadow(color: textHalo, radius: 1.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            currentRegion.map {
                "当前位于，\($0.countryNameZh)，\($0.nameZh)"
            } ?? "正在载入当前位置"
        )
    }

    private var primaryForeground: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var textHalo: Color {
        colorScheme == .dark ? .black.opacity(0.44) : .white.opacity(0.72)
    }
}

/// 地图右上角的两行资源数字。以极简线性图标和柔光建立层级。
struct MapResourceHUD: View {
    let ticketCount: Int
    let coins: Int?

    var body: some View {
        VStack(alignment: .trailing, spacing: 11) {
            resource(
                title: "机票",
                value: ticketCount.formatted(),
                tint: .dsSkyDeep,
                icon: .ticket
            )
            resource(
                title: "金币",
                value: coins?.formatted() ?? "—",
                tint: .dsSunset,
                icon: .coin
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func resource(
        title: String,
        value: String,
        tint: Color,
        icon: MapResourceIcon.Kind
    ) -> some View {
        HStack(spacing: 7) {
            MapResourceIcon(kind: icon)
                .frame(width: 17, height: 17)
                .mapHUDGlow(tint, depthOpacity: 0.12)

            Text(value)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .monospacedDigit()
                .mapHUDGlow(tint, depthOpacity: 0.08)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct MapResourceIcon: View {
    enum Kind {
        case ticket
        case coin
    }

    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .ticket:
                Image(systemName: "airplane")
                    .font(.system(size: 14, weight: .light))
            case .coin:
                MinimalCoinStackShape()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: 1.05,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(1)
            }
        }
    }
}

private struct MinimalCoinStackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let left = rect.minX + 1
        let right = rect.maxX - 1
        let top = rect.minY + 1
        let coinHeight = rect.height * 0.28
        let shoulderY = top + coinHeight / 2
        let bottomArcY = rect.maxY - 3

        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: left,
                y: top,
                width: right - left,
                height: coinHeight
            )
        )

        path.move(to: CGPoint(x: left, y: shoulderY))
        path.addLine(to: CGPoint(x: left, y: bottomArcY))
        path.addCurve(
            to: CGPoint(x: right, y: bottomArcY),
            control1: CGPoint(x: left, y: rect.maxY - 0.5),
            control2: CGPoint(x: right, y: rect.maxY - 0.5)
        )
        path.addLine(to: CGPoint(x: right, y: shoulderY))

        for separatorY in [rect.midY - 1.5, rect.midY + 1.8] {
            path.move(to: CGPoint(x: left, y: separatorY))
            path.addCurve(
                to: CGPoint(x: right, y: separatorY),
                control1: CGPoint(x: left, y: separatorY + 2.5),
                control2: CGPoint(x: right, y: separatorY + 2.5)
            )
        }

        return path
    }
}

extension View {
    /// 地图上的同色柔光与下投影：光晕提供发光感，偏移暗影赋予轻微厚度。
    func mapHUDGlow(_ color: Color, depthOpacity: Double = 0.16) -> some View {
        shadow(color: .white.opacity(0.76), radius: 1)
            .shadow(color: color.opacity(0.58), radius: 3)
            .shadow(color: color.opacity(0.32), radius: 7)
            .shadow(color: .black.opacity(depthOpacity), radius: 1.1, x: 0, y: 1)
    }
}
