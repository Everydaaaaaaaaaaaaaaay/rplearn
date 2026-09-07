import DesignSystem
import DomainKit
import SwiftUI

/// 统一旅行工具栏中的当前位置，以单行排版保留地图可视面积。
struct MapStatusHUD: View {
    let currentRegion: Region?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            locationLine(showsContext: true)
            locationLine(showsContext: false)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            currentRegion.map {
                "当前位于，\($0.countryNameZh)，\($0.nameZh)"
            } ?? "正在载入当前位置"
        )
    }

    private func locationLine(showsContext: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsSky)

            if showsContext {
                Text("当前位置")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize()
            }

            if let currentRegion {
                Text(currentRegion.flagEmoji)
                    .font(.system(size: 16))
                    .fixedSize()

                Text(currentRegion.nameZh)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } else {
                Text("正在载入")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 与当前位置同高的单行资源计数器。
struct MapResourceHUD: View {
    let ticketCount: Int
    let coins: Int?

    var body: some View {
        HStack(spacing: 10) {
            resource(
                title: "机票",
                value: ticketCount.formatted(),
                tint: .dsSky,
                icon: .ticket
            )
            resource(
                title: "金币",
                value: coins?.formatted() ?? "—",
                tint: .dsSunset,
                icon: .coin
            )
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private func resource(
        title: String,
        value: String,
        tint: Color,
        icon: MapResourceIcon.Kind
    ) -> some View {
        HStack(spacing: 4) {
            MapResourceIcon(kind: icon)
                .frame(width: 15, height: 15)
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
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
