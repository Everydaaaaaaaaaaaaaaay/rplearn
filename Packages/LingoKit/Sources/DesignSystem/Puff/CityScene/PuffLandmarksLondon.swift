import SwiftUI

/// 英伦地标：议会大厦与大本钟、伦敦眼、圣保罗、小黄瓜、碎片大厦、塔桥。
extension PuffScenePainter {
    /// 议会大厦长楼与维多利亚塔，从 `x0` 延伸到 `x1`。
    func parliament(from x0: CGFloat, to x1: CGFloat, stone: UInt32 = 0xF3DCAA, trim: UInt32 = 0xE0BD7F) {
        let ground = Self.horizon
        let top: CGFloat = ground - 30
        rect(x0, top, x1 - x0, 30, c(stone))
        rect(x0, top + 10, x1 - x0, 1.6, c(trim))
        var x = x0 + 3
        while x < x1 - 2 {
            spire(x, top, width: 3.6, height: 7, c(trim))
            x += 9
        }
        windowGrid(x: x0 + 5, y: top + 3.5, columns: Int((x1 - x0 - 8) / 6.4), rows: 1, w: 2.4, h: 4.6, gapX: 4, gapY: 0, color: 0xD7B072)
        windowGrid(x: x0 + 5, y: top + 15, columns: Int((x1 - x0 - 8) / 6.4), rows: 2, w: 2.4, h: 5, gapX: 4, gapY: 3, color: 0xD7B072, litPattern: 1)
        // 中央尖塔。
        let mid = (x0 + x1) / 2 + 10
        rect(mid - 4, top - 10, 8, 10, c(stone))
        spire(mid, top - 10, width: 9, height: 16, c(trim))
        // 维多利亚塔。
        let towerX = x0 + 4
        rect(towerX, ground - 76, 24, 76, c(stone))
        rect(towerX + 17, ground - 76, 7, 76, c(0xEACB91))
        for corner in [towerX + 1.5, towerX + 22.5] {
            rect(corner - 1.5, ground - 84, 3, 8, c(stone))
            spire(corner, ground - 84, width: 4, height: 6, c(trim))
        }
        windowGrid(x: towerX + 5, y: ground - 66, columns: 3, rows: 4, w: 2.6, h: 8, gapX: 3.6, gapY: 6, color: 0xD7B072, litPattern: 2)
        line(CGPoint(x: towerX + 12, y: ground - 84), CGPoint(x: towerX + 12, y: ground - 98), c(0x8A7A6A), width: 1)
        poly([
            CGPoint(x: towerX + 12.5, y: ground - 98),
            CGPoint(x: towerX + 22, y: ground - 95),
            CGPoint(x: towerX + 12.5, y: ground - 92),
        ], c(0xFF7A8A))
    }

    /// 大本钟（伊丽莎白塔）。指针由动态图层 `bigBenHands` 绘制。
    func bigBen(_ x: CGFloat) {
        let ground = Self.horizon
        let stone = c(0xF3DCAA)
        let shade = c(0xE6C590)
        rect(x - 10, ground - 66, 20, 66, stone)
        rect(x + 4, ground - 66, 6, 66, shade)
        for offset: CGFloat in [-5, 0] {
            rect(x + offset - 0.6, ground - 62, 1.2, 58, c(0xE8CA94))
        }
        // 钟楼段。
        rect(x - 13, ground - 90, 26, 26, c(0xF7E4B9), r: 2)
        rect(x + 7, ground - 90, 6, 26, c(0xEBD09E), r: 1)
        circle(x, ground - 77, 10.2, c(0xD6A962))
        circle(x, ground - 77, 8.8, isNight ? SceneInk(0xFFF2C2).color : c(0xFFFDF4))
        for hour in 0..<12 {
            let angle = Double(hour) / 12 * 2 * .pi
            circle(x + CGFloat(sin(angle)) * 7, ground - 77 - CGFloat(cos(angle)) * 7, hour % 3 == 0 ? 0.9 : 0.5, c(0x8C7656))
        }
        // 钟声塔与尖顶。
        rect(x - 10.5, ground - 102, 21, 12, c(0xEFD39C))
        for column in 0..<3 {
            topRounded(x - 7.5 + CGFloat(column) * 5.6, ground - 100, 3.6, 8, c(0xC79B5E), r: 1.8)
        }
        poly([
            CGPoint(x: x - 13, y: ground - 102),
            CGPoint(x: x + 13, y: ground - 102),
            CGPoint(x: x, y: ground - 132),
        ], c(0x5D6E9F))
        poly([
            CGPoint(x: x, y: ground - 132),
            CGPoint(x: x + 13, y: ground - 102),
            CGPoint(x: x + 5, y: ground - 102),
        ], c(0x4D5D8E))
        for corner in [x - 12, x + 12] {
            spire(corner, ground - 101, width: 3, height: 8, c(0x5D6E9F))
        }
        line(CGPoint(x: x, y: ground - 132), CGPoint(x: x, y: ground - 138), c(0xE2B54C), width: 1.2)
        circle(x, ground - 139, 1.6, SceneInk(0xFFC94A).color)
    }

    /// 大本钟指针：显示城市当地时间。
    func bigBenHands(_ x: CGFloat) {
        guard moverPass != .near else { return }
        let center = CGPoint(x: x, y: Self.horizon - 77)
        let hour = Double(clock.hour ?? 10).truncatingRemainder(dividingBy: 12)
        let minute = Double(clock.minute ?? 10)
        let hourAngle = (hour + minute / 60) / 12 * 2 * .pi
        let minuteAngle = minute / 60 * 2 * .pi
        let ink = SceneInk(0x3B4470).color
        line(center, CGPoint(x: center.x + CGFloat(sin(hourAngle)) * 4.4, y: center.y - CGFloat(cos(hourAngle)) * 4.4), ink, width: 1.4)
        line(center, CGPoint(x: center.x + CGFloat(sin(minuteAngle)) * 6.6, y: center.y - CGFloat(cos(minuteAngle)) * 6.6), ink, width: 1)
        circle(center.x, center.y, 1, ink)
    }

    /// 摩天轮（伦敦眼、墨尔本之星、新加坡摩天观景轮）。缓慢旋转，座舱始终保持直立。
    func ferrisWheel(_ x: CGFloat, centerY: CGFloat, radius: CGFloat, legSpread: CGFloat? = nil) {
        guard moverPass != .near else { return }
        let rotation = time * 2 * .pi / 90
        let rim = c(0xFFFFFF)
        let detail = c(0xD7E0F2)
        let ring = Path(ellipseIn: CGRect(x: x - radius, y: centerY - radius, width: radius * 2, height: radius * 2))
        // 外圈一道淡蓝描边，让白色轮圈在浅色天空里也能看清。
        stroke(ring, c(0xB9CCEB), width: 4.4)
        stroke(ring, rim, width: 2.4)
        let inner = Path(ellipseIn: CGRect(x: x - radius + 4, y: centerY - radius + 4, width: (radius - 4) * 2, height: (radius - 4) * 2))
        stroke(inner, detail, width: 1)
        let spokes = 16
        for index in 0..<spokes {
            let angle = rotation + Double(index) / Double(spokes) * 2 * .pi
            let end = CGPoint(x: x + CGFloat(cos(angle)) * radius, y: centerY + CGFloat(sin(angle)) * radius)
            line(CGPoint(x: x, y: centerY), end, detail.opacity(0.9), width: 0.7)
        }
        let capsuleColors: [UInt32] = [0xFF8FB1, 0x7CC7FF, 0xFFD36B, 0x8EE0B5, 0xB9A2FF]
        for index in 0..<spokes {
            let angle = rotation + Double(index) / Double(spokes) * 2 * .pi
            let px = x + CGFloat(cos(angle)) * (radius + 1)
            let py = centerY + CGFloat(sin(angle)) * (radius + 1)
            let color = capsuleColors[index % capsuleColors.count]
            if isNight {
                circle(px, py, 5, SceneInk(color).color.opacity(0.35))
                rect(px - 3.6, py - 2.4, 7.2, 4.8, SceneInk(color).mixed(with: SceneInk(0xFFFFFF), 0.25).color, r: 2.4)
            } else {
                rect(px - 3.6, py - 2.4, 7.2, 4.8, c(color), r: 2.4)
            }
        }
        circle(x, centerY, 3.4, c(0xAFBCD8))
        let spread = legSpread ?? radius * 0.55
        let foot = Self.horizon
        line(CGPoint(x: x, y: centerY), CGPoint(x: x - spread, y: foot), c(0xC4CEE3), width: 2.6)
        line(CGPoint(x: x, y: centerY), CGPoint(x: x + spread, y: foot), c(0xC4CEE3), width: 2.6)
        circle(x, centerY, 1.6, c(0xFFFFFF))
    }

    /// 圣保罗大教堂（远景色调更浅）。
    func stPauls(_ x: CGFloat) {
        let ground = Self.horizon
        rect(x - 26, ground - 22, 52, 22, c(0xCCD9EF), r: 2)
        windowGrid(x: x - 22, y: ground - 17, columns: 8, rows: 1, w: 2.6, h: 9, gapX: 3.2, gapY: 0, color: 0xB2C3E2)
        rect(x - 17, ground - 36, 34, 14, c(0xD4E0F3), r: 2)
        for column in 0..<6 {
            rect(x - 14 + CGFloat(column) * 5.6, ground - 33, 2, 9, c(0xBCCBE6))
        }
        dome(x, ground - 36, 18, 22, c(0xB9CAE8))
        dome(x - 5, ground - 44, 6, 9, c(0xD4E0F3).opacity(0.65))
        rect(x - 3, ground - 66, 6, 9, c(0xCCD9EF))
        dome(x, ground - 66, 3.6, 5, c(0xB9CAE8))
        line(CGPoint(x: x, y: ground - 71), CGPoint(x: x, y: ground - 78), c(0xE2B54C), width: 1.2)
        circle(x, ground - 74, 1.4, c(0xE2B54C))
        for tower in [x - 23, x + 23] {
            rect(tower - 4, ground - 38, 8, 16, c(0xD4E0F3), r: 1.5)
            dome(tower, ground - 38, 4, 7, c(0xB9CAE8))
        }
    }

    /// 小黄瓜大楼。
    func gherkin(_ x: CGFloat, height: CGFloat = 62) {
        let ground = Self.horizon
        var body = Path()
        body.move(to: CGPoint(x: x - 8, y: ground))
        body.addCurve(to: CGPoint(x: x, y: ground - height), control1: CGPoint(x: x - 14, y: ground - height * 0.45), control2: CGPoint(x: x - 9, y: ground - height))
        body.addCurve(to: CGPoint(x: x + 8, y: ground), control1: CGPoint(x: x + 9, y: ground - height), control2: CGPoint(x: x + 14, y: ground - height * 0.45))
        body.closeSubpath()
        fill(body, c(0x8FB6E6))
        var context = ctx
        context.clip(to: body)
        for index in 0..<7 {
            var stripe = Path()
            let y = ground - CGFloat(index) * height / 6
            stripe.move(to: CGPoint(x: x - 16, y: y))
            stripe.addQuadCurve(to: CGPoint(x: x + 16, y: y - 18), control: CGPoint(x: x, y: y - 2))
            context.stroke(stripe, with: .color(c(0xB8D3F2)), lineWidth: 2)
        }
        if isNight {
            circle(x, ground - height + 6, 2.2, SceneInk(0xFFE38F).color)
        }
    }

    /// 碎片大厦。
    func shard(_ x: CGFloat, height: CGFloat = 112) {
        let ground = Self.horizon
        poly([CGPoint(x: x - 19, y: ground), CGPoint(x: x + 17, y: ground), CGPoint(x: x + 1, y: ground - height)], c(0xA8C3EA))
        poly([CGPoint(x: x + 1, y: ground - height), CGPoint(x: x + 17, y: ground), CGPoint(x: x + 5, y: ground)], c(0xC9DBF4))
        poly([CGPoint(x: x + 1, y: ground - height), CGPoint(x: x - 6, y: ground), CGPoint(x: x - 2, y: ground)], c(0x96B4E0))
        if isNight {
            circle(x + 1, ground - height + 5, 3, SceneInk(0xFFF1BE).color.opacity(0.9))
            for index in 0..<6 {
                let y = ground - 12 - CGFloat(index) * 15
                let half = 17 * (y - (ground - height)) / height
                rect(x - half * 0.6, y, half * 1.2, 1.4, SceneInk(0xFFE38F).color.opacity(0.55))
            }
        }
    }

    /// 塔桥：双塔、上层步道、桥面与悬索。桥墩伸入河中。
    func towerBridge(_ x: CGFloat) {
        let ground = Self.horizon
        let blue = c(0x7DB4EE)
        let towers = [x - 34, x + 34]
        // 悬索与桥面。
        for (index, tower) in towers.enumerated() {
            let outward: CGFloat = index == 0 ? -1 : 1
            let end = tower + outward * 52
            var chain = Path()
            chain.move(to: CGPoint(x: tower + outward * 11, y: ground - 58))
            chain.addQuadCurve(to: CGPoint(x: end, y: ground - 12), control: CGPoint(x: tower + outward * 30, y: ground - 20))
            stroke(chain, blue, width: 2.4)
            for step in 1..<6 {
                let t = CGFloat(step) / 6
                let px = tower + outward * (11 + t * 41)
                let py = (1 - t) * (1 - t) * (ground - 58) + 2 * (1 - t) * t * (ground - 20) + t * t * (ground - 12)
                line(CGPoint(x: px, y: py), CGPoint(x: px, y: ground - 11), blue.opacity(0.7), width: 0.8)
            }
        }
        rect(x - 88, ground - 12, 176, 5, blue, r: 1.5)
        rect(x - 88, ground - 7.5, 176, 1.6, c(0x5E97D6))
        // 上层步道。
        rect(x - 24, ground - 70, 48, 4, blue, r: 1)
        rect(x - 24, ground - 63, 48, 3, blue, r: 1)
        for index in 0..<7 {
            let px = x - 22 + CGFloat(index) * 7.3
            line(CGPoint(x: px, y: ground - 66), CGPoint(x: px + 3.6, y: ground - 63), c(0x5E97D6), width: 0.8)
        }
        for tower in towers {
            rect(tower - 14, ground - 6, 28, 15, c(0xB7C3DA), r: 2)
            rect(tower - 11, ground - 78, 22, 72, c(0xDDE3EF))
            rect(tower + 4, ground - 78, 7, 72, c(0xC7D0E2))
            topRounded(tower - 5, ground - 50, 10, 30, c(0xA8B8D6), r: 5)
            topRounded(tower - 4, ground - 70, 8, 12, c(0xA8B8D6), r: 4)
            if isNight {
                topRounded(tower - 3, ground - 48, 6, 10, SceneInk(0xFFE38F).color.opacity(0.85), r: 3)
            }
            poly([CGPoint(x: tower - 13, y: ground - 78), CGPoint(x: tower + 13, y: ground - 78), CGPoint(x: tower, y: ground - 100)], c(0x56699F))
            for corner in [tower - 11, tower + 11] {
                rect(corner - 1.8, ground - 86, 3.6, 8, c(0xDDE3EF))
                spire(corner, ground - 86, width: 4.4, height: 7, c(0x56699F))
            }
            circle(tower, ground - 102, 1.4, c(0xE2B54C))
        }
        if isNight {
            for index in 0..<16 {
                circle(x - 84 + CGFloat(index) * 11.2, ground - 13, 1.1, SceneInk(0xFFE9A6).color)
            }
        }
    }

    /// 红色电话亭，底部落在 `baseY`。
    func phoneBox(_ x: CGFloat, baseY: CGFloat = 161) {
        topRounded(x - 5.5, baseY - 24, 11, 24, c(0xFF5A63), r: 3)
        rect(x - 4.5, baseY - 21, 9, 2.4, c(0x2E3250), r: 0.6)
        for row in 0..<3 {
            for column in 0..<2 {
                rect(x - 3.6 + CGFloat(column) * 3.8, baseY - 17.5 + CGFloat(row) * 4.4, 3.2, 3.6, window(0xFFE6E8), r: 0.6)
            }
        }
        rect(x - 6, baseY - 1.6, 12, 1.6, c(0xD8424D))
    }

    /// 维多利亚式路灯，夜里亮起。
    func lampPost(_ x: CGFloat, baseY: CGFloat = 161) {
        rect(x - 0.8, baseY - 20, 1.6, 20, c(0x4D5A86))
        rect(x - 2.4, baseY - 24, 4.8, 4.6, isNight ? SceneInk(0xFFE38F).color : c(0xFFF4D2), r: 1.2)
        if isNight { circle(x, baseY - 22, 7, SceneInk(0xFFE38F).color.opacity(0.22)) }
        rect(x - 3, baseY - 25, 6, 1.4, c(0x4D5A86), r: 0.7)
    }
}
