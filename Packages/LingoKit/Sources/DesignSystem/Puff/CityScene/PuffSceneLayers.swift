import SwiftUI

/// 天空、云、水面、地面、树等所有城市共用的图层。
extension PuffScenePainter {
    // MARK: - 天空

    func sky(extendingAbove top: CGFloat) {
        let frame = CGRect(x: -40, y: top, width: Self.width + 80, height: Self.horizon + 20 - top)
        ctx.fill(
            Path(frame),
            with: .linearGradient(
                Gradient(colors: [atmosphere.skyTop.color, atmosphere.skyBottom.color]),
                startPoint: CGPoint(x: 0, y: max(top, -20)),
                endPoint: CGPoint(x: 0, y: Self.horizon)
            )
        )
    }

    /// 太阳、晚霞落日或月亮。`x` 为全景中的位置。
    func celestial(x: CGFloat) {
        switch mood {
        case .day:
            let y: CGFloat = 40
            circle(x, y, 34, SceneInk(0xFFF1B8).color.opacity(0.35))
            circle(x, y, 25, SceneInk(0xFFE48A).color.opacity(0.5))
            circle(x, y, 17, SceneInk(0xFFD25A).color)
            circle(x - 5, y - 5, 5, SceneInk(0xFFE9A0).color)
        case .dusk:
            let y: CGFloat = 104
            circle(x, y, 40, SceneInk(0xFFC2A0).color.opacity(0.35))
            circle(x, y, 28, SceneInk(0xFFA987).color.opacity(0.5))
            circle(x, y, 20, SceneInk(0xFF9466).color)
        case .night:
            let y: CGFloat = 36
            circle(x, y, 24, SceneInk(0xFFF3C4).color.opacity(0.12))
            let moon = Path(ellipseIn: CGRect(x: x - 13, y: y - 13, width: 26, height: 26))
            let bite = Path(ellipseIn: CGRect(x: x - 6, y: y - 17, width: 24, height: 24))
            fill(moon.subtracting(bite), SceneInk(0xFFF1BE).color)
        }
    }

    /// 夜晚星星，带轻微闪烁。
    func stars() {
        guard isNight else { return }
        for index in 0..<26 {
            let x = Self.noise(index * 3 + 1) * Self.width
            let y = 8 + Self.noise(index * 5 + 2) * 84
            let phase = Self.noise(index * 11 + 7) * 6.28
            let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(time * 1.6 + phase))
            let size = 0.9 + Self.noise(index * 13) * 1.4
            if index % 5 == 0 {
                sparkle(x, y, size * 2.2, SceneInk(0xFFF6D0).color.opacity(twinkle))
            } else {
                circle(x, y, size, SceneInk(0xFFFFFF).color.opacity(twinkle * 0.85))
            }
        }
    }

    /// 四角星。
    func sparkle(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: y - size))
        path.addQuadCurve(to: CGPoint(x: x + size, y: y), control: CGPoint(x: x + size * 0.18, y: y - size * 0.18))
        path.addQuadCurve(to: CGPoint(x: x, y: y + size), control: CGPoint(x: x + size * 0.18, y: y + size * 0.18))
        path.addQuadCurve(to: CGPoint(x: x - size, y: y), control: CGPoint(x: x - size * 0.18, y: y + size * 0.18))
        path.addQuadCurve(to: CGPoint(x: x, y: y - size), control: CGPoint(x: x - size * 0.18, y: y - size * 0.18))
        fill(path, color)
    }

    /// 缓慢漂移的云朵。
    func clouds(seed: Int = 0) {
        let base: [(x: CGFloat, y: CGFloat, scale: CGFloat, speed: Double)] = [
            (40, 30, 1.0, 3.2), (230, 58, 0.72, 4.4), (420, 24, 1.15, 2.6),
            (600, 52, 0.85, 3.8), (720, 34, 0.7, 4.8),
        ]
        let specs = base.enumerated().map { index, spec in
            (x: spec.x + Self.noise(seed + index * 37) * 120, y: spec.y + Self.noise(seed + index * 41) * 10 - 5, scale: spec.scale, speed: spec.speed)
        }
        let span = Self.width + 160
        for spec in specs {
            let travelled = CGFloat((time * spec.speed).truncatingRemainder(dividingBy: Double(span)))
            var x = spec.x + travelled
            if x > Self.width + 80 { x -= span }
            cloud(x, spec.y, spec.scale)
        }
    }

    func cloud(_ x: CGFloat, _ y: CGFloat, _ scale: CGFloat) {
        let color = atmosphere.cloud.color.opacity(atmosphere.cloudOpacity)
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: x - 26 * scale, y: y - 2 * scale, width: 52 * scale, height: 14 * scale),
            cornerSize: CGSize(width: 7 * scale, height: 7 * scale)
        )
        path.addEllipse(in: CGRect(x: x - 20 * scale, y: y - 12 * scale, width: 20 * scale, height: 20 * scale))
        path.addEllipse(in: CGRect(x: x - 6 * scale, y: y - 19 * scale, width: 24 * scale, height: 24 * scale))
        path.addEllipse(in: CGRect(x: x + 10 * scale, y: y - 9 * scale, width: 16 * scale, height: 16 * scale))
        fill(path, color)
    }

    /// 两三只扇着翅膀飞过的小鸟。
    func birds() {
        guard !isNight else { return }
        let span = Self.width + 120
        for index in 0..<3 {
            let offset = CGFloat(index) * 15
            let progress = CGFloat((time * 9 + Double(index) * 4).truncatingRemainder(dividingBy: Double(span)))
            let x = Self.width + 60 - progress - offset
            let y = 70 + CGFloat(index % 2) * 8 + sin(time * 0.8 + Double(index)) * 3
            let flap = CGFloat(sin(time * 9 + Double(index) * 1.7)) * 2.2
            var path = Path()
            path.move(to: CGPoint(x: x - 4.5, y: y - 1 - flap))
            path.addQuadCurve(to: CGPoint(x: x, y: y + 0.6), control: CGPoint(x: x - 2, y: y - 2.4 - flap))
            path.addQuadCurve(to: CGPoint(x: x + 4.5, y: y - 1 - flap), control: CGPoint(x: x + 2, y: y - 2.4 - flap))
            stroke(path, SceneInk(0x7A86B8).color.opacity(0.8), width: 1.3)
        }
    }

    // MARK: - 远景天际线

    /// 柔和的远处楼群剪影。`skip` 中的区间留给地标。
    func farSkyline(seed: Int, minHeight: CGFloat = 16, maxHeight: CGFloat = 46, skip: [ClosedRange<CGFloat>] = []) {
        var x: CGFloat = -10
        var index = 0
        while x < Self.width + 10 {
            let width = 16 + Self.noise(seed + index * 7) * 20
            let height = minHeight + Self.noise(seed + index * 13 + 5) * (maxHeight - minHeight)
            let center = x + width / 2
            if !skip.contains(where: { $0.contains(center) }) {
                let shade = index % 3 == 0 ? atmosphere.farShade : atmosphere.far
                topRounded(x, Self.horizon - height, width - 2, height, shade.color, r: 4)
                if isNight, Self.noise(seed + index * 17) > 0.35 {
                    let rows = Int(height / 9)
                    for row in 0..<max(rows - 1, 0) where Self.noise(seed + index * 31 + row) > 0.45 {
                        rect(x + width * 0.3, Self.horizon - height + 6 + CGFloat(row) * 9, 3, 3.6, SceneInk(0xFFE38F).color.opacity(0.75), r: 1)
                    }
                }
            }
            x += width
            index += 1
        }
    }

    /// 远山。`flatTop` 用于桌山这类平顶山。
    func mountain(
        _ x: CGFloat, width: CGFloat, height: CGFloat,
        color: UInt32, snow: Bool = false, flatTop: CGFloat = 0
    ) {
        let base = Self.horizon + 2
        let top = base - height
        var path = Path()
        path.move(to: CGPoint(x: x - width / 2, y: base))
        if flatTop > 0 {
            path.addCurve(
                to: CGPoint(x: x - flatTop / 2, y: top),
                control1: CGPoint(x: x - width * 0.3, y: base - height * 0.5),
                control2: CGPoint(x: x - flatTop / 2 - 6, y: top + 4)
            )
            path.addLine(to: CGPoint(x: x + flatTop / 2, y: top + 1))
            path.addCurve(
                to: CGPoint(x: x + width / 2, y: base),
                control1: CGPoint(x: x + flatTop / 2 + 6, y: top + 4),
                control2: CGPoint(x: x + width * 0.3, y: base - height * 0.5)
            )
        } else {
            path.addQuadCurve(to: CGPoint(x: x, y: top), control: CGPoint(x: x - width * 0.2, y: top + height * 0.05))
            path.addQuadCurve(to: CGPoint(x: x + width / 2, y: base), control: CGPoint(x: x + width * 0.2, y: top + height * 0.05))
        }
        path.closeSubpath()
        fill(path, c(color))
        if snow, flatTop == 0 {
            // 裁剪到山体内，画一条锯齿状雪线。
            var context = ctx
            context.clip(to: path)
            let capY = top + height * 0.3
            var cap = Path()
            cap.move(to: CGPoint(x: x - width / 2, y: top - 4))
            cap.addLine(to: CGPoint(x: x + width / 2, y: top - 4))
            cap.addLine(to: CGPoint(x: x + width / 2, y: capY))
            let teeth = 12
            for tooth in 0...teeth {
                let tx = x + width / 2 - CGFloat(tooth) * width / CGFloat(teeth)
                cap.addLine(to: CGPoint(x: tx, y: capY + (tooth % 2 == 0 ? 0 : 5)))
            }
            cap.closeSubpath()
            context.fill(cap, with: .color(c(0xFFFFFF)))
        }
    }

    // MARK: - 地形

    /// 远岸到近岸之间的河或海。
    func water(from top: CGFloat = PuffScenePainter.horizon, to bottom: CGFloat = 157) {
        var path = Path()
        path.move(to: CGPoint(x: -20, y: top))
        path.addLine(to: CGPoint(x: Self.width + 20, y: top))
        path.addLine(to: CGPoint(x: Self.width + 20, y: bottom))
        path.addLine(to: CGPoint(x: -20, y: bottom))
        path.closeSubpath()
        fill(path, atmosphere.water.color)
        // 远岸的一道细亮边。
        rect(-20, top, Self.width + 40, 1.6, atmosphere.waterLight.color.opacity(0.9))
    }

    /// 水面上的亮片，随时间轻轻晃动。
    func waterSparkles(top: CGFloat = PuffScenePainter.horizon, bottom: CGFloat = 157) {
        for index in 0..<22 {
            let baseX = Self.noise(index * 19 + 3) * Self.width
            let y = top + 4 + Self.noise(index * 23 + 1) * (bottom - top - 8)
            let sway = CGFloat(sin(time * 1.2 + Double(index))) * 3
            let length = 5 + Self.noise(index * 29) * 9
            rect(baseX + sway, y, length, 1.6, atmosphere.waterLight.color.opacity(0.85), r: 0.8)
        }
    }

    /// 远处地面（无水城市）。
    func farGround() {
        rect(-20, Self.horizon, Self.width + 40, 18, atmosphere.grassShade.color)
        rect(-20, Self.horizon, Self.width + 40, 2, atmosphere.grass.color)
    }

    /// 近岸：草边、道路、路沿。
    func nearBank(top: CGFloat = 157) {
        rect(-20, top, Self.width + 40, Self.height - top + 20, atmosphere.grass.color)
        rect(-20, top, Self.width + 40, 3, atmosphere.grassShade.color)
        let roadTop: CGFloat = 161
        rect(-20, roadTop, Self.width + 40, 14, atmosphere.road.color)
        rect(-20, roadTop + 14, Self.width + 40, 2, atmosphere.grassShade.color.opacity(0.7))
        var x: CGFloat = 4
        while x < Self.width {
            rect(x, roadTop + 6.5, 10, 1.6, atmosphere.roadLine.color.opacity(0.95), r: 0.8)
            x += 22
        }
    }

    // MARK: - 植物

    /// 棒棒糖形状的圆树，底部落在 `baseY`。
    func roundTree(_ x: CGFloat, baseY: CGFloat = 161, size: CGFloat = 1) {
        rect(x - 1.6 * size, baseY - 12 * size, 3.2 * size, 12 * size, c(0xC49A74), r: 1)
        circle(x, baseY - 19 * size, 10 * size, c(0x6FCF98))
        circle(x - 3 * size, baseY - 22 * size, 4 * size, c(0x9BE4B9))
    }

    /// 尖顶松树。
    func pineTree(_ x: CGFloat, baseY: CGFloat = 161, size: CGFloat = 1) {
        rect(x - 1.4 * size, baseY - 6 * size, 2.8 * size, 6 * size, c(0xB48C6A))
        poly([CGPoint(x: x - 9 * size, y: baseY - 5 * size), CGPoint(x: x + 9 * size, y: baseY - 5 * size), CGPoint(x: x, y: baseY - 21 * size)], c(0x4FBF8E))
        poly([CGPoint(x: x - 7 * size, y: baseY - 13 * size), CGPoint(x: x + 7 * size, y: baseY - 13 * size), CGPoint(x: x, y: baseY - 28 * size)], c(0x63CC9C))
    }

    /// 椰子树。
    func palmTree(_ x: CGFloat, baseY: CGFloat = 161, size rawSize: CGFloat = 1, lean: CGFloat = 1) {
        let size = rawSize * 1.3
        var trunk = Path()
        trunk.move(to: CGPoint(x: x - 1.6 * size, y: baseY))
        trunk.addQuadCurve(to: CGPoint(x: x + 5 * lean * size, y: baseY - 30 * size), control: CGPoint(x: x - 2 * size, y: baseY - 18 * size))
        trunk.addLine(to: CGPoint(x: x + 7.5 * lean * size, y: baseY - 30 * size))
        trunk.addQuadCurve(to: CGPoint(x: x + 1.6 * size, y: baseY), control: CGPoint(x: x + 1 * size, y: baseY - 18 * size))
        trunk.closeSubpath()
        fill(trunk, c(0xD1A574))
        let crown = CGPoint(x: x + 6 * lean * size, y: baseY - 31 * size)
        for (index, angle) in [-2.7, -2.1, -1.5, -0.9, -0.35].enumerated() {
            let length = (13 + CGFloat(index % 2) * 3) * size
            let tip = CGPoint(x: crown.x + cos(angle) * length, y: crown.y + sin(angle) * length * 0.6 + 6 * size)
            var leaf = Path()
            leaf.move(to: crown)
            leaf.addQuadCurve(to: tip, control: CGPoint(x: (crown.x + tip.x) / 2, y: crown.y - 7 * size))
            leaf.addQuadCurve(to: crown, control: CGPoint(x: (crown.x + tip.x) / 2, y: crown.y - 1 * size))
            fill(leaf, c(index % 2 == 0 ? 0x4CC48E : 0x6BD3A2))
        }
        circle(crown.x, crown.y + 1.5 * size, 1.8 * size, c(0x9A6A45))
    }

    /// 金合欢树（内罗毕）：伞形树冠。
    func acaciaTree(_ x: CGFloat, baseY: CGFloat = 161, size: CGFloat = 1) {
        line(CGPoint(x: x, y: baseY), CGPoint(x: x + 1 * size, y: baseY - 16 * size), c(0xA77B57), width: 2.4 * size)
        line(CGPoint(x: x + 1 * size, y: baseY - 12 * size), CGPoint(x: x - 6 * size, y: baseY - 18 * size), c(0xA77B57), width: 1.6 * size)
        line(CGPoint(x: x + 1 * size, y: baseY - 13 * size), CGPoint(x: x + 8 * size, y: baseY - 18 * size), c(0xA77B57), width: 1.6 * size)
        ellipse(x + 1 * size, baseY - 21 * size, 17 * size, 5.5 * size, c(0x7FC77D))
        ellipse(x - 3 * size, baseY - 23 * size, 8 * size, 3 * size, c(0xA2DA92))
    }
}
