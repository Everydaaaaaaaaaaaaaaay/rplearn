import DesignSystem
import DomainKit
import SwiftUI
import UIKit

/// 城市主题背景：优先约定资产，缺图时以代码天际线兜底。
struct CityBackdropView: View {
    let region: Region
    let parallax: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var palette: DSScenePalette.City {
        DSScenePalette.city(region.id)
    }

    private var assetName: String {
        "city_backdrop_\(region.id)"
    }

    private var assetParallax: CGFloat {
        guard !reduceMotion else { return 0 }
        return min(max(parallax * 0.12, -36), 36)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [palette.skyTop, palette.skyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1.04)
                        .saturation(colorScheme == .dark ? 0.82 : 1)
                        .brightness(colorScheme == .dark ? -0.08 : 0)
                        .offset(y: assetParallax)
                } else {
                    cloudLayer(size: geometry.size)
                    CitySilhouetteView(regionID: region.id, palette: palette)
                        .offset(y: reduceMotion ? 0 : parallax * 0.3)
                }

                LinearGradient(
                    stops: [
                        .init(
                            color: .black.opacity(colorScheme == .dark ? 0.18 : 0.03),
                            location: 0
                        ),
                        .init(color: .clear, location: 0.28),
                        .init(color: .clear, location: 0.42),
                        .init(
                            color: Color.dsBackground.opacity(colorScheme == .dark ? 0.88 : 0.58),
                            location: 0.54
                        ),
                        .init(color: Color.dsBackground.opacity(0.96), location: 0.68),
                        .init(color: Color.dsBackground, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cloudLayer(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 20)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                CloudShape()
                    .fill(.white.opacity(0.48))
                    .frame(width: 118, height: 42)
                    .offset(
                        x: reduceMotion ? -80 : cloudX(time: time, width: size.width, speed: 9, offset: 0),
                        y: -size.height * 0.32
                    )
                CloudShape()
                    .fill(.white.opacity(0.32))
                    .frame(width: 82, height: 30)
                    .offset(
                        x: reduceMotion ? 110 : cloudX(time: time, width: size.width, speed: 13, offset: 190),
                        y: -size.height * 0.2
                    )
            }
        }
    }

    private func cloudX(time: TimeInterval, width: CGFloat, speed: Double, offset: Double) -> CGFloat {
        let span = Double(width + 280)
        return CGFloat((time * speed + offset).truncatingRemainder(dividingBy: span) - span / 2)
    }
}

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 0, y: rect.height * 0.42, width: rect.width * 0.42, height: rect.height * 0.48))
        path.addEllipse(in: CGRect(x: rect.width * 0.22, y: 0, width: rect.width * 0.48, height: rect.height * 0.85))
        path.addEllipse(in: CGRect(x: rect.width * 0.55, y: rect.height * 0.3, width: rect.width * 0.45, height: rect.height * 0.58))
        path.addRect(CGRect(x: rect.width * 0.14, y: rect.height * 0.55, width: rect.width * 0.72, height: rect.height * 0.34))
        return path
    }
}

private struct CitySilhouetteView: View {
    let regionID: String
    let palette: DSScenePalette.City

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                skyline(in: geometry.size, far: true)
                    .fill(palette.silhouetteFar.opacity(0.72))
                    .offset(y: -56)
                skyline(in: geometry.size, far: false)
                    .fill(palette.silhouetteNear.opacity(0.92))
                landmark(in: geometry.size)
                    .fill(palette.silhouetteNear)
            }
        }
    }

    private func skyline(in size: CGSize, far: Bool) -> Path {
        var path = Path()
        let base = size.height * (far ? 0.58 : 0.7)
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: base))
        let widths: [CGFloat] = far ? [44, 64, 38, 72, 52, 46, 80] : [58, 42, 74, 48, 66, 52]
        var x: CGFloat = 0
        var index = 0
        while x < size.width {
            let width = widths[index % widths.count]
            let seed = CGFloat((index * 37 + regionID.count * 17) % 70)
            let height = (far ? 45 : 72) + seed
            path.addLine(to: CGPoint(x: x, y: base - height))
            path.addLine(to: CGPoint(x: x + width, y: base - height))
            path.addLine(to: CGPoint(x: x + width, y: base))
            x += width
            index += 1
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func landmark(in size: CGSize) -> Path {
        var path = Path()
        switch regionID {
        case "melbourne":
            let x = size.width * 0.68
            path.addRoundedRect(
                in: CGRect(x: x, y: size.height * 0.38, width: 74, height: size.height * 0.35),
                cornerSize: CGSize(width: 6, height: 6)
            )
            path.move(to: CGPoint(x: x - 8, y: size.height * 0.38))
            path.addLine(to: CGPoint(x: x + 37, y: size.height * 0.3))
            path.addLine(to: CGPoint(x: x + 82, y: size.height * 0.38))
            path.closeSubpath()
        case "newyork":
            let x = size.width * 0.7
            path.addRect(CGRect(x: x, y: size.height * 0.27, width: 54, height: size.height * 0.46))
            path.move(to: CGPoint(x: x + 27, y: size.height * 0.12))
            path.addLine(to: CGPoint(x: x + 16, y: size.height * 0.27))
            path.addLine(to: CGPoint(x: x + 38, y: size.height * 0.27))
            path.closeSubpath()
        default:
            let x = size.width * 0.72
            path.addRect(CGRect(x: x, y: size.height * 0.3, width: 58, height: size.height * 0.43))
            path.addEllipse(in: CGRect(x: x + 6, y: size.height * 0.36, width: 46, height: 46))
            path.move(to: CGPoint(x: x + 29, y: size.height * 0.15))
            path.addLine(to: CGPoint(x: x + 16, y: size.height * 0.3))
            path.addLine(to: CGPoint(x: x + 42, y: size.height * 0.3))
            path.closeSubpath()
        }
        return path
    }
}
