import DesignSystem
import DomainKit
import SwiftUI

/// 地图页头标题下的当前所在城市：定位图标 + 国旗 + 城市名。
struct MapStatusHUD: View {
    let currentRegion: Region?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.system(size: 11, weight: Puff.Weight.icon))
                .foregroundStyle(PuffCandy.mint.deep)
            if let currentRegion {
                Text("\(currentRegion.flagEmoji) \(currentRegion.nameZh)")
                    .font(.puff(.subheadline, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("正在载入")
                    .font(.puff(.subheadline, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkFaint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            currentRegion.map {
                "当前位于，\($0.countryNameZh)，\($0.nameZh)"
            } ?? "正在载入当前位置"
        )
    }
}

/// 机票与金币：两枚白色小胶囊。
struct MapResourceHUD: View {
    let ticketCount: Int
    let coins: Int?

    var body: some View {
        HStack(spacing: 8) {
            resource(title: "机票", value: ticketCount.formatted(), tint: PuffCandy.sky.base, icon: .ticket)
            resource(title: "金币", value: coins?.formatted() ?? "—", tint: PuffCandy.sunny.deep, icon: .coin)
        }
        .accessibilityElement(children: .contain)
    }

    private func resource(title: String, value: String, tint: Color, icon: MapResourceIcon.Kind) -> some View {
        HStack(spacing: 5) {
            MapResourceIcon(kind: icon)
                .frame(width: 15, height: 15)
                .foregroundStyle(tint)
            Text(value)
                .font(.puff(.subheadline, Puff.Weight.emphasis))
                .monospacedDigit()
                .foregroundStyle(Puff.Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Puff.Palette.card, in: Capsule())
        .overlay { Capsule().strokeBorder(Puff.Palette.line, lineWidth: 1) }
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
                    .font(.system(size: 13, weight: .semibold))
            case .coin:
                MinimalCoinStackShape()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: 1.2,
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
