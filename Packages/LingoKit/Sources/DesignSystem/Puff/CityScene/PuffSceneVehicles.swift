import SwiftUI

/// 会动的交通工具：巴士、电车、出租车和船。
extension PuffScenePainter {
    enum Vehicle: Sendable, Equatable {
        /// 伦敦红色双层巴士。
        case doubleDecker
        /// 单层城市巴士，传入车身色。
        case bus(UInt32)
        /// 有轨电车，传入车身色。
        case tram(UInt32)
        /// 纽约黄色出租车。
        case taxi
    }

    enum Boat: Sendable, Equatable {
        case ferry(UInt32)
        case sailboat(UInt32)
        case paddleSteamer
        case narrowboat
    }

    /// 车辆从左到右循环驶过整幅全景；`period` 秒一圈，`phase` 错开多辆车。
    func drive(_ vehicle: Vehicle, period: Double = 26, phase: Double = 0) {
        guard moverPass != .far else { return }
        let span = Self.width + 140
        let progress = ((time + phase).truncatingRemainder(dividingBy: period)) / period
        let x = -70 + CGFloat(progress) * span
        // 轻轻上下颠簸，像在路上欢快地开。
        let bob = CGFloat(sin(time * 7 + phase)) * 0.45
        let wheelSpin = time * 8
        switch vehicle {
        case .doubleDecker: doubleDecker(x, bob: bob, spin: wheelSpin)
        case .bus(let color): cityBus(x, color: color, bob: bob, spin: wheelSpin)
        case .tram(let color): tram(x, color: color, bob: bob * 0.5)
        case .taxi: taxi(x, bob: bob, spin: wheelSpin)
        }
    }

    private func wheel(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, spin: Double) {
        circle(x, y, radius, c(0x3B3F5C))
        circle(x, y, radius * 0.45, c(0xDADDE8))
        let angle = spin
        circle(x + CGFloat(cos(angle)) * radius * 0.7, y + CGFloat(sin(angle)) * radius * 0.7, radius * 0.16, c(0x8D92AB))
    }

    private func doubleDecker(_ x: CGFloat, bob: CGFloat, spin: Double) {
        let base = Self.roadBase
        let top = base - 32 + bob
        let red = c(0xFF5A63)
        rect(x - 25, top, 50, 28, red, r: 6)
        rect(x - 25, top + 13.5, 50, 1.8, c(0xE4434E))
        rect(x - 25, top + 24, 50, 3, c(0xE4434E), r: 1)
        // 上下两排窗。
        for row in 0..<2 {
            let y = top + 3.5 + CGFloat(row) * 11.5
            for column in 0..<4 {
                rect(x - 21 + CGFloat(column) * 9.6, y, 7.6, 7, window(0xFFF3E4), r: 2)
            }
        }
        rect(x + 18, top + 3.5, 5.4, 7, window(0xFFF3E4), r: 2)
        rect(x + 18.6, top + 15, 4.8, 9, window(0xDDEBFF, lit: false), r: 1.6)
        circle(x + 23.4, top + 22, 1.4, SceneInk(0xFFE38F).color)
        rect(x - 12, top + 13.8, 16, 1.2, c(0xFFE0A0).opacity(0.9))
        wheel(x - 14, base - 2, 4.4, spin: spin)
        wheel(x + 15, base - 2, 4.4, spin: spin)
    }

    private func cityBus(_ x: CGFloat, color: UInt32, bob: CGFloat, spin: Double) {
        let base = Self.roadBase
        let top = base - 22 + bob
        rect(x - 24, top, 48, 18, c(color), r: 5)
        rect(x - 24, top + 13, 48, 2.6, tone(SceneInk(color).mixed(with: SceneInk(0x000000), 0.15)))
        for column in 0..<4 {
            rect(x - 20 + CGFloat(column) * 9.4, top + 3, 7.4, 7.4, window(0xF2F8FF), r: 2)
        }
        rect(x + 18, top + 3, 4.8, 9, window(0xDDEBFF, lit: false), r: 1.6)
        circle(x + 22.6, top + 13.5, 1.3, SceneInk(0xFFE38F).color)
        wheel(x - 13, base - 2, 4, spin: spin)
        wheel(x + 14, base - 2, 4, spin: spin)
    }

    private func tram(_ x: CGFloat, color: UInt32, bob: CGFloat) {
        let base = Self.roadBase
        let top = base - 23 + bob
        // 架空线和受电弓。
        line(CGPoint(x: x - 6, y: top), CGPoint(x: x + 2, y: top - 8), c(0x6C7396), width: 1)
        line(CGPoint(x: x + 2, y: top - 8), CGPoint(x: x + 8, y: top), c(0x6C7396), width: 1)
        rect(x - 30, top, 60, 19, c(color), r: 6)
        rect(x - 30, top + 12.5, 60, 2.4, c(0xFFF3D8))
        for column in 0..<5 {
            rect(x - 26 + CGFloat(column) * 10.6, top + 3, 8.4, 7.6, window(0xF2F8FF), r: 2)
        }
        circle(x + 28.6, top + 15, 1.3, SceneInk(0xFFE38F).color)
        for wheelX in [x - 20, x - 12, x + 12, x + 20] {
            circle(wheelX, base - 2.2, 2.8, c(0x3B3F5C))
        }
    }

    private func taxi(_ x: CGFloat, bob: CGFloat, spin: Double) {
        let base = Self.roadBase
        let top = base - 16 + bob
        let yellow = c(0xFFCC3D)
        rect(x - 17, top + 4, 34, 10, yellow, r: 4)
        var cabin = Path()
        cabin.move(to: CGPoint(x: x - 10, y: top + 4.5))
        cabin.addLine(to: CGPoint(x: x - 6, y: top - 3))
        cabin.addLine(to: CGPoint(x: x + 7, y: top - 3))
        cabin.addLine(to: CGPoint(x: x + 11, y: top + 4.5))
        cabin.closeSubpath()
        fill(cabin, yellow)
        rect(x - 6.5, top - 1.5, 6, 5.4, window(0xF2F8FF), r: 1.2)
        rect(x + 1, top - 1.5, 6, 5.4, window(0xF2F8FF), r: 1.2)
        rect(x - 3, top - 6, 6, 3, c(0xFFF3C0), r: 1)
        // 车身的格子条。
        for column in 0..<8 {
            rect(x - 15 + CGFloat(column) * 3.8, top + 8, 1.9, 1.9, c(0x2E3250).opacity(column % 2 == 0 ? 0.85 : 0))
        }
        circle(x + 16, top + 7.5, 1.2, SceneInk(0xFFE38F).color)
        wheel(x - 9, base - 2.6, 3.6, spin: spin)
        wheel(x + 9, base - 2.6, 3.6, spin: spin)
    }

    /// 船在 `range` 区间内来回漂。
    func sail(_ boat: Boat, range: ClosedRange<CGFloat>, y: CGFloat = 151, period: Double = 40, phase: Double = 0) {
        guard moverPass != .near else { return }
        let t = (time + phase) / period * 2 * .pi
        let progress = (1 - cos(t)) / 2
        let x = range.lowerBound + CGFloat(progress) * (range.upperBound - range.lowerBound)
        let facingRight = sin(t) >= 0
        let rock = CGFloat(sin(time * 2.2 + phase)) * 0.8
        // 船尾拖出两道渐淡的白色水纹，速度越快越长。
        let speed = abs(CGFloat(sin(t)))
        if speed > 0.08 {
            let back: CGFloat = facingRight ? -1 : 1
            for index in 0..<3 {
                let length = (10 + CGFloat(index) * 7) * speed
                let start = x + back * (12 + CGFloat(index) * 9)
                let wobble = CGFloat(sin(time * 3 + Double(index))) * 0.4
                rect(min(start, start + back * length), y + 2.5 + CGFloat(index) * 0.9 + wobble, length, 1.1,
                     atmosphere.waterLight.color.opacity(0.75 - Double(index) * 0.2), r: 0.55)
            }
        }
        var context = ctx
        context.translateBy(x: x, y: y + rock)
        if !facingRight { context.scaleBy(x: -1, y: 1) }
        let painter = PuffScenePainter(ctx: context, mood: mood, time: time, clock: clock)
        painter.boatShape(boat)
    }

    private func boatShape(_ boat: Boat) {
        switch boat {
        case .ferry(let color):
            hull(width: 34, color: 0xFFFFFF, stripe: color)
            rect(-11, -10, 22, 7, c(0xFFFFFF), r: 2)
            rect(-9, -8.5, 18, 3.4, window(0xBFDFFF), r: 1)
            rect(-3, -15, 6, 5, c(color), r: 1)
        case .sailboat(let color):
            hull(width: 22, color: 0xFFFFFF, stripe: color)
            line(CGPoint(x: 0, y: -3), CGPoint(x: 0, y: -26), c(0x8D92AB), width: 1)
            poly([CGPoint(x: 1, y: -25), CGPoint(x: 1, y: -5), CGPoint(x: 13, y: -5)], c(0xFFFFFF))
            poly([CGPoint(x: -1, y: -21), CGPoint(x: -1, y: -6), CGPoint(x: -9, y: -6)], c(color))
        case .paddleSteamer:
            hull(width: 40, color: 0xFFFFFF, stripe: 0xFF6B6B)
            rect(-15, -9, 30, 6, c(0xFFFFFF), r: 1.5)
            rect(-11, -14, 22, 5, c(0xFFF6E6), r: 1.5)
            windowGrid(x: -13, y: -7.6, columns: 6, rows: 1, w: 3, h: 3, gapX: 1.8, gapY: 0, color: 0xBFDFFF)
            rect(-7, -24, 3.6, 10, c(0x3B3F5C))
            rect(3, -24, 3.6, 10, c(0x3B3F5C))
            circle(17, -2, 5, c(0xFF6B6B))
            circle(17, -2, 2, c(0xFFFFFF))
        case .narrowboat:
            hull(width: 44, color: 0x3E8E6B, stripe: 0xFFCC3D)
            rect(-16, -7, 30, 6, c(0xD8483F), r: 1.5)
            windowGrid(x: -13, y: -5.6, columns: 5, rows: 1, w: 3, h: 2.6, gapX: 2.6, gapY: 0, color: 0xFFF0C8)
        }
    }

    private func hull(width: CGFloat, color: UInt32, stripe: UInt32) {
        var path = Path()
        path.move(to: CGPoint(x: -width / 2, y: -4))
        path.addLine(to: CGPoint(x: width / 2 + 3, y: -4))
        path.addQuadCurve(to: CGPoint(x: width / 2 - 4, y: 3), control: CGPoint(x: width / 2, y: 2))
        path.addLine(to: CGPoint(x: -width / 2 + 3, y: 3))
        path.addQuadCurve(to: CGPoint(x: -width / 2, y: -4), control: CGPoint(x: -width / 2, y: 1))
        path.closeSubpath()
        fill(path, c(color))
        rect(-width / 2 + 1, -2.2, width, 1.6, c(stripe))
    }
}
