import SwiftUI

/// 其余城市使用的可组合地标。每个函数都以地面基线为底，只画卡通化的识别特征。
extension PuffScenePainter {
    enum TowerTop: Sendable {
        case flat
        case stepped
        case slant
        case round
        case antenna
        case gold
    }

    // MARK: - 高楼

    func skyscraper(_ x: CGFloat, width: CGFloat, height: CGFloat, color: UInt32, glass: UInt32 = 0xEAF4FF, top: TowerTop = .flat, seed: Int = 0) {
        let ground = Self.horizon
        let left = x - width / 2
        let topY = ground - height
        switch top {
        case .slant:
            poly([CGPoint(x: left, y: ground), CGPoint(x: left, y: topY + 10), CGPoint(x: left + width, y: topY), CGPoint(x: left + width, y: ground)], c(color))
        case .round:
            topRounded(left, topY, width, height, c(color), r: width / 2)
        default:
            topRounded(left, topY, width, height, c(color), r: 2)
        }
        rect(left + width * 0.72, topY + (top == .round ? width / 2 : 4), width * 0.28, height - (top == .round ? width / 2 : 4), tone(SceneInk(color).mixed(with: SceneInk(0x24305E), 0.12)).opacity(mood == .night ? 0 : 0.55))
        let columns = max(Int((width - 6) / 6), 1)
        let rows = max(Int((height - 16) / 9), 1)
        let gap = (width - 6 - CGFloat(columns) * 3) / CGFloat(max(columns - 1, 1))
        windowGrid(x: left + 3, y: topY + 10, columns: columns, rows: rows, w: 3, h: 4, gapX: gap, gapY: 5, color: glass, litPattern: seed)
        switch top {
        case .stepped:
            topRounded(x - width * 0.32, topY - 9, width * 0.64, 9, c(color), r: 2)
            topRounded(x - width * 0.16, topY - 16, width * 0.32, 7, c(color), r: 2)
        case .antenna:
            line(CGPoint(x: x, y: topY), CGPoint(x: x, y: topY - 16), c(0x8D97B8), width: 1.2)
            circle(x, topY - 16, 1.4, isNight ? SceneInk(0xFF7A8A).color : c(0xFF7A8A))
        case .gold:
            topRounded(left, topY, width, 8, c(0xF5C451), r: 2)
        default:
            break
        }
    }

    /// 一组高低错落的现代高楼。
    func towerCluster(from x0: CGFloat, to x1: CGFloat, seed: Int, minHeight: CGFloat = 40, maxHeight: CGFloat = 92, colors: [UInt32]) {
        var x = x0
        var index = 0
        while x < x1 {
            let width = 16 + Self.noise(seed + index * 5) * 14
            guard x + width <= x1 + 4 else { break }
            let height = minHeight + Self.noise(seed + index * 9 + 2) * (maxHeight - minHeight)
            let tops: [TowerTop] = [.flat, .antenna, .slant, .round, .flat, .stepped]
            let top = tops[Int(Self.noise(seed + index * 3 + 1) * CGFloat(tops.count)) % tops.count]
            skyscraper(x + width / 2, width: width, height: height, color: colors[index % colors.count], top: top, seed: seed + index)
            x += width + 2 + Self.noise(seed + index * 11) * 4
            index += 1
        }
    }

    /// 帝国大厦：阶梯收分加尖塔。
    func empireState(_ x: CGFloat) {
        let ground = Self.horizon
        let stone = 0xD9DDEB as UInt32
        topRounded(x - 15, ground - 74, 30, 74, c(stone), r: 2)
        topRounded(x - 11, ground - 96, 22, 22, c(stone), r: 2)
        topRounded(x - 7, ground - 108, 14, 12, c(stone), r: 2)
        topRounded(x - 4, ground - 116, 8, 8, c(0xC9CEE0), r: 2)
        line(CGPoint(x: x, y: ground - 116), CGPoint(x: x, y: ground - 134), c(0xAEB5CF), width: 1.6)
        windowGrid(x: x - 12, y: ground - 70, columns: 5, rows: 7, w: 2.6, h: 4.6, gapX: 2.8, gapY: 4.6, color: 0xF2F6FF)
        windowGrid(x: x - 8, y: ground - 93, columns: 4, rows: 2, w: 2.4, h: 4, gapX: 2.6, gapY: 4, color: 0xF2F6FF)
        if isNight { circle(x, ground - 134, 2, SceneInk(0xFF7A8A).color) }
    }

    /// 克莱斯勒大厦：拱形装饰顶。
    func chrysler(_ x: CGFloat) {
        let ground = Self.horizon
        topRounded(x - 11, ground - 84, 22, 84, c(0xE2E6F1), r: 2)
        windowGrid(x: x - 8, y: ground - 78, columns: 4, rows: 7, w: 2.4, h: 4.6, gapX: 2.4, gapY: 5, color: 0xF2F6FF, litPattern: 2)
        for (index, width) in [22.0, 17.0, 12.0, 7.0].enumerated() {
            let base = ground - 84 - CGFloat(index) * 7
            dome(x, base, CGFloat(width) / 2, 9, c(index % 2 == 0 ? 0xC9D2E6 : 0xF2F5FB))
        }
        line(CGPoint(x: x, y: ground - 112), CGPoint(x: x, y: ground - 126), c(0xAEB5CF), width: 1.2)
    }

    /// 自由女神像，立在小岛基座上。
    func liberty(_ x: CGFloat) {
        let ground = Self.horizon
        let green = c(0x7FD1B9)
        rect(x - 13, ground - 6, 26, 6, c(0xB8C6A2), r: 2)
        rect(x - 7, ground - 22, 14, 16, c(0xE3D3B4), r: 1.5)
        rect(x - 8.5, ground - 24, 17, 3, c(0xD5C29E), r: 1)
        var robe = Path()
        robe.move(to: CGPoint(x: x - 6, y: ground - 24))
        robe.addLine(to: CGPoint(x: x - 3, y: ground - 46))
        robe.addLine(to: CGPoint(x: x + 3, y: ground - 46))
        robe.addLine(to: CGPoint(x: x + 6, y: ground - 24))
        robe.closeSubpath()
        fill(robe, green)
        circle(x, ground - 49, 3.4, green)
        for spike in -2...2 {
            let angle = -Double.pi / 2 + Double(spike) * 0.38
            line(CGPoint(x: x, y: ground - 50), CGPoint(x: x + CGFloat(cos(angle)) * 6.4, y: ground - 50 + CGFloat(sin(angle)) * 6.4), green, width: 1.1)
        }
        line(CGPoint(x: x + 2.5, y: ground - 42), CGPoint(x: x + 6, y: ground - 58), green, width: 2.2)
        poly([CGPoint(x: x + 4.4, y: ground - 58), CGPoint(x: x + 7.8, y: ground - 58), CGPoint(x: x + 6.1, y: ground - 65)], SceneInk(0xFFC94A).color)
        if isNight { circle(x + 6.1, ground - 61, 4.4, SceneInk(0xFFC94A).color.opacity(0.3)) }
        rect(x - 6.5, ground - 38, 4, 6, c(0x6CC2AA), r: 1)
    }

    /// 布鲁克林大桥：两座哥特拱门塔与扇形钢索。
    func suspensionBridge(_ x: CGFloat, span: CGFloat = 220, stone: UInt32 = 0xD6C7B4) {
        let ground = Self.horizon
        let deckY = ground - 16
        let towers = [x - span * 0.25, x + span * 0.25]
        let cable = c(0x8E9CC0)
        var main = Path()
        main.move(to: CGPoint(x: x - span / 2, y: deckY))
        main.addLine(to: CGPoint(x: towers[0], y: ground - 70))
        main.addQuadCurve(to: CGPoint(x: towers[1], y: ground - 70), control: CGPoint(x: x, y: deckY + 10))
        main.addLine(to: CGPoint(x: x + span / 2, y: deckY))
        stroke(main, cable, width: 1.6)
        for tower in towers {
            for step in 1..<7 {
                let offset = CGFloat(step) * 7.5
                line(CGPoint(x: tower, y: ground - 66), CGPoint(x: tower - offset * 1.3, y: deckY), cable.opacity(0.6), width: 0.6)
                line(CGPoint(x: tower, y: ground - 66), CGPoint(x: tower + offset * 1.3, y: deckY), cable.opacity(0.6), width: 0.6)
            }
        }
        rect(x - span / 2, deckY, span, 5, c(0x9AA8C8), r: 1.5)
        for tower in towers {
            topRounded(tower - 11, ground - 74, 22, 74, c(stone), r: 3)
            rect(tower + 5, ground - 74, 6, 74, tone(SceneInk(stone).mixed(with: SceneInk(0x5A4A3A), 0.12)))
            for side in [-4.5, 4.5] as [CGFloat] {
                topRounded(tower + side - 2.6, ground - 62, 5.2, 18, atmosphere.skyBottom.color, r: 2.6)
            }
            rect(tower - 12, ground - 76, 24, 3, tone(SceneInk(stone).mixed(with: SceneInk(0x5A4A3A), 0.2)), r: 1)
        }
        if isNight {
            for index in 0..<14 {
                circle(x - span / 2 + 8 + CGFloat(index) * (span - 16) / 13, deckY - 1, 1, SceneInk(0xFFE9A6).color)
            }
        }
    }

    /// 带观景舱的电视塔（CN 塔、天空塔、悉尼塔、海港中心）。
    func needleTower(_ x: CGFloat, height: CGFloat, podRatio: CGFloat = 0.72, podWidth: CGFloat = 16, color: UInt32 = 0xE3E8F3, podColor: UInt32 = 0xC9D3E8) {
        let ground = Self.horizon
        let topY = ground - height
        let podY = ground - height * podRatio
        poly([CGPoint(x: x - 7, y: ground), CGPoint(x: x + 7, y: ground), CGPoint(x: x + 2.4, y: podY), CGPoint(x: x - 2.4, y: podY)], c(color))
        poly([CGPoint(x: x + 2, y: ground), CGPoint(x: x + 7, y: ground), CGPoint(x: x + 2.4, y: podY)], tone(SceneInk(color).mixed(with: SceneInk(0x24305E), 0.1)))
        rect(x - podWidth / 2, podY - 6, podWidth, 9, c(podColor), r: 4.5)
        rect(x - podWidth / 2 + 2, podY - 3.4, podWidth - 4, 2.6, window(0x9FC4F0), r: 1.3)
        rect(x - podWidth * 0.3, podY - 12, podWidth * 0.6, 6, c(color), r: 3)
        rect(x - 1.6, topY + 12, 3.2, podY - 12 - topY - 12, c(color))
        line(CGPoint(x: x, y: topY + 12), CGPoint(x: x, y: topY), c(0xAEB5CF), width: 1.2)
        circle(x, topY, 1.6, SceneInk(0xFF7A8A).color)
        if isNight { circle(x, topY, 4, SceneInk(0xFF7A8A).color.opacity(0.3)) }
    }

    /// 不带观景舱的细尖塔（都柏林尖塔）。
    func needle(_ x: CGFloat, height: CGFloat) {
        let ground = Self.horizon
        rect(x - 6, ground - 4, 12, 4, c(0xC9D2E6), r: 1.5)
        poly([CGPoint(x: x - 3, y: ground - 4), CGPoint(x: x + 3, y: ground - 4), CGPoint(x: x, y: ground - height)], c(0xD5DEEE))
        poly([CGPoint(x: x, y: ground - 4), CGPoint(x: x + 3, y: ground - 4), CGPoint(x: x, y: ground - height)], c(0xB8C6E0))
        if isNight { circle(x, ground - height + 4, 2.4, SceneInk(0xFFF1BE).color.opacity(0.9)) }
    }

    /// 悉尼歌剧院：层叠白帆。
    func operaHouse(_ x: CGFloat) {
        let ground = Self.horizon
        rect(x - 58, ground - 8, 116, 8, c(0xE9D3B6), r: 2)
        let sails: [(dx: CGFloat, w: CGFloat, h: CGFloat, lean: CGFloat)] = [
            (-40, 22, 28, -1), (-24, 28, 40, -1), (-4, 26, 34, -1),
            (16, 22, 26, 1), (30, 26, 36, 1), (48, 18, 22, 1),
        ]
        for (index, sail) in sails.enumerated() {
            let baseX = x + sail.dx
            var path = Path()
            path.move(to: CGPoint(x: baseX - sail.w / 2, y: ground - 8))
            path.addQuadCurve(to: CGPoint(x: baseX + sail.lean * sail.w * 0.42, y: ground - 8 - sail.h), control: CGPoint(x: baseX - sail.w * 0.38 * sail.lean, y: ground - 8 - sail.h * 0.85))
            path.addQuadCurve(to: CGPoint(x: baseX + sail.w / 2, y: ground - 8), control: CGPoint(x: baseX + sail.w * 0.4, y: ground - 8 - sail.h * 0.4))
            path.closeSubpath()
            fill(path, c(index % 2 == 0 ? 0xFFFFFF : 0xE8EEF8))
            stroke(path, c(0xC9D3E6), width: 1)
        }
    }

    /// 钢拱桥（悉尼海港大桥）。
    func archBridge(_ x: CGFloat, span: CGFloat = 240) {
        let ground = Self.horizon
        let deckY = ground - 24
        let steel = c(0x8293BC)
        let left = x - span / 2 + 26
        let right = x + span / 2 - 26
        var outer = Path()
        outer.move(to: CGPoint(x: left, y: ground - 10))
        outer.addQuadCurve(to: CGPoint(x: right, y: ground - 10), control: CGPoint(x: x, y: ground - 118))
        stroke(outer, steel, width: 3)
        var inner = Path()
        inner.move(to: CGPoint(x: left + 8, y: ground - 12))
        inner.addQuadCurve(to: CGPoint(x: right - 8, y: ground - 12), control: CGPoint(x: x, y: ground - 96))
        stroke(inner, steel, width: 2)
        for step in 1..<12 {
            let t = CGFloat(step) / 12
            let outerX = left + (right - left) * t
            let outerY = (1 - t) * (1 - t) * (ground - 10) + 2 * (1 - t) * t * (ground - 118) + t * t * (ground - 10)
            line(CGPoint(x: outerX, y: outerY), CGPoint(x: outerX, y: deckY), steel.opacity(0.7), width: 0.9)
        }
        rect(x - span / 2, deckY, span, 5, c(0x6F82AE), r: 1.5)
        for pylon in [x - span / 2 + 12, x + span / 2 - 12] {
            topRounded(pylon - 10, ground - 44, 20, 44, c(0xE6DACB), r: 2)
            rect(pylon + 4, ground - 44, 6, 44, c(0xD8C9B5))
        }
    }

    /// 爱丁堡城堡与城堡岩。
    func castleRock(_ x: CGFloat) {
        let ground = Self.horizon
        var rock = Path()
        rock.move(to: CGPoint(x: x - 90, y: ground))
        rock.addCurve(to: CGPoint(x: x - 40, y: ground - 46), control1: CGPoint(x: x - 70, y: ground - 10), control2: CGPoint(x: x - 60, y: ground - 44))
        rock.addLine(to: CGPoint(x: x + 50, y: ground - 50))
        rock.addCurve(to: CGPoint(x: x + 90, y: ground), control1: CGPoint(x: x + 62, y: ground - 40), control2: CGPoint(x: x + 70, y: ground - 8))
        rock.closeSubpath()
        fill(rock, c(0x9AA9BF))
        ellipse(x - 20, ground - 30, 18, 6, c(0x8798B2))
        ellipse(x + 30, ground - 22, 22, 6, c(0x8798B2))
        let wall = c(0xC9C1B5)
        let crest = ground - 48
        rect(x - 44, crest - 14, 96, 14, wall, r: 1)
        var bx = x - 44
        while bx < x + 52 {
            rect(bx, crest - 18, 4, 4, wall)
            bx += 7
        }
        for tower in [(x - 30, 26.0), (x + 4, 34.0), (x + 34, 24.0)] {
            rect(tower.0 - 8, crest - CGFloat(tower.1), 16, CGFloat(tower.1), c(0xD6CEC2), r: 1)
            for battlement in 0..<3 {
                rect(tower.0 - 8 + CGFloat(battlement) * 6, crest - CGFloat(tower.1) - 3.4, 4, 3.4, c(0xD6CEC2))
            }
            windowGrid(x: tower.0 - 4, y: crest - CGFloat(tower.1) + 6, columns: 2, rows: 1, w: 2.6, h: 5, gapX: 3, gapY: 0, color: 0x8C8A9C)
        }
        line(CGPoint(x: x + 4, y: crest - 37), CGPoint(x: x + 4, y: crest - 52), c(0x8A7A6A), width: 1)
        poly([CGPoint(x: x + 4.5, y: crest - 52), CGPoint(x: x + 15, y: crest - 49), CGPoint(x: x + 4.5, y: crest - 46)], c(0x4F8EE8))
        line(CGPoint(x: x + 5, y: crest - 51), CGPoint(x: x + 14, y: crest - 47), c(0xFFFFFF), width: 0.7)
    }

    /// 哥特式尖塔纪念碑（司各特纪念塔）。
    func gothicSpire(_ x: CGFloat, height: CGFloat, color: UInt32 = 0x9890A6) {
        let ground = Self.horizon
        rect(x - 13, ground - 22, 26, 22, c(color), r: 1)
        topRounded(x - 5, ground - 18, 10, 14, atmosphere.skyBottom.color, r: 5)
        poly([CGPoint(x: x - 11, y: ground - 22), CGPoint(x: x + 11, y: ground - 22), CGPoint(x: x + 2, y: ground - height), CGPoint(x: x - 2, y: ground - height)], c(color))
        for side in [-14.0, 14.0] as [CGFloat] {
            spire(x + side, ground - 18, width: 4, height: 22, c(color))
        }
        for level in 0..<3 {
            let y = ground - 34 - CGFloat(level) * 18
            let half = 11 - CGFloat(level) * 3
            spire(x - half, y, width: 3, height: 9, c(color))
            spire(x + half, y, width: 3, height: 9, c(color))
        }
    }

    /// 一排连栋小屋。`balconies` 用于新奥尔良铁艺阳台，`doors` 画彩色门。
    func terraces(from x0: CGFloat, to x1: CGFloat, colors: [UInt32], height: CGFloat = 30, roof: UInt32 = 0x7C88AE, balconies: Bool = false, seed: Int = 0) {
        let ground = Self.horizon
        var x = x0
        var index = 0
        while x < x1 - 8 {
            let width = min(20 + Self.noise(seed + index * 7) * 6, x1 - x)
            let h = height + Self.noise(seed + index * 13) * 8
            let color = colors[index % colors.count]
            rect(x, ground - h, width - 1, h, c(color))
            if index % 2 == 0 {
                poly([CGPoint(x: x - 1, y: ground - h), CGPoint(x: x + width, y: ground - h), CGPoint(x: x + width / 2 - 0.5, y: ground - h - 8)], c(roof))
            } else {
                rect(x - 0.5, ground - h - 3, width, 3, c(roof), r: 1)
            }
            let rows = Int((h - 12) / 10)
            windowGrid(x: x + 4, y: ground - h + 5, columns: 2, rows: max(rows, 1), w: 4, h: 5, gapX: width - 13, gapY: 5, color: 0xFFFFFF, litPattern: seed + index)
            let doorColors: [UInt32] = [0xFF6B7A, 0x4DA8FF, 0xFFC93C, 0x3FC48C, 0x9B7BFF]
            topRounded(x + width / 2 - 3, ground - 8, 6, 8, c(doorColors[(index + seed) % doorColors.count]), r: 3)
            if balconies {
                for row in 0..<max(rows, 1) {
                    let y = ground - h + 11 + CGFloat(row) * 10
                    rect(x + 1, y, width - 3, 1.4, c(0x3B4470))
                    var bx = x + 2.5
                    while bx < x + width - 2 {
                        rect(bx, y - 3.4, 0.7, 3.4, c(0x3B4470))
                        bx += 2.6
                    }
                }
            }
            x += width
            index += 1
        }
    }

    /// 都柏林半便士桥：白色铸铁拱桥。
    func footArchBridge(_ x: CGFloat, span: CGFloat = 110) {
        let ground = Self.horizon
        var arch = Path()
        arch.move(to: CGPoint(x: x - span / 2, y: ground + 6))
        arch.addQuadCurve(to: CGPoint(x: x + span / 2, y: ground + 6), control: CGPoint(x: x, y: ground - 26))
        stroke(arch, c(0xFFFFFF), width: 3.6)
        var rail = Path()
        rail.move(to: CGPoint(x: x - span / 2, y: ground - 2))
        rail.addQuadCurve(to: CGPoint(x: x + span / 2, y: ground - 2), control: CGPoint(x: x, y: ground - 32))
        stroke(rail, c(0xFFFFFF), width: 1.6)
        for step in 1..<10 {
            let t = CGFloat(step) / 10
            let px = x - span / 2 + span * t
            let lowerY = (1 - t) * (1 - t) * (ground + 6) + 2 * (1 - t) * t * (ground - 26) + t * t * (ground + 6)
            let upperY = (1 - t) * (1 - t) * (ground - 2) + 2 * (1 - t) * t * (ground - 32) + t * t * (ground - 2)
            line(CGPoint(x: px, y: lowerY), CGPoint(x: px, y: upperY), c(0xFFFFFF).opacity(0.85), width: 0.8)
        }
        for lamp in [x - span * 0.2, x + span * 0.2] {
            line(CGPoint(x: lamp, y: ground - 12), CGPoint(x: lamp, y: ground - 22), c(0xFFFFFF), width: 1)
            circle(lamp, ground - 23, 1.6, isNight ? SceneInk(0xFFE38F).color : c(0xFFFFFF))
        }
    }

    /// 带穹顶的长楼（都柏林海关大楼、弗林德斯街车站）。
    func domedHall(_ x: CGFloat, width: CGFloat, height: CGFloat = 26, wall: UInt32, dome domeColor: UInt32, clock: Bool = false) {
        let ground = Self.horizon
        rect(x - width / 2, ground - height, width, height, c(wall), r: 2)
        rect(x - width / 2, ground - height, width, 3, tone(SceneInk(wall).mixed(with: SceneInk(0x5A4A3A), 0.15)), r: 1)
        windowGrid(x: x - width / 2 + 5, y: ground - height + 7, columns: Int((width - 8) / 7), rows: 2, w: 3, h: 5, gapX: 4, gapY: 4, color: 0xFFF8EA)
        rect(x - 12, ground - height - 12, 24, 12, c(wall), r: 1)
        dome(x, ground - height - 12, 13, 17, c(domeColor))
        rect(x - 2, ground - height - 34, 4, 6, c(domeColor))
        circle(x, ground - height - 35, 2, c(0xF5C451))
        if clock {
            rect(x + width / 2 - 14, ground - height - 30, 12, 30, c(wall), r: 1)
            circle(x + width / 2 - 8, ground - height - 22, 4, c(0xFFFDF4))
            line(CGPoint(x: x + width / 2 - 8, y: ground - height - 22), CGPoint(x: x + width / 2 - 8, y: ground - height - 25), c(0x3B4470), width: 0.8)
            spire(x + width / 2 - 8, ground - height - 30, width: 12, height: 8, c(domeColor))
        }
    }

    /// 圣路易斯大教堂：白色立面与三座尖塔。
    func cathedral(_ x: CGFloat) {
        let ground = Self.horizon
        let white = c(0xFBFAF6)
        rect(x - 26, ground - 34, 52, 34, white, r: 1)
        rect(x + 12, ground - 34, 14, 34, c(0xEDEAE3))
        for (dx, h) in [(-20.0, 52.0), (0.0, 70.0), (20.0, 52.0)] as [(CGFloat, CGFloat)] {
            rect(x + dx - 6, ground - h, 12, h - 30, white)
            spire(x + dx, ground - h, width: 12, height: 18, c(0x6A7193))
            line(CGPoint(x: x + dx, y: ground - h - 18), CGPoint(x: x + dx, y: ground - h - 23), c(0x6A7193), width: 1)
        }
        circle(x, ground - 50, 4, c(0xFFFDF4))
        topRounded(x - 5, ground - 14, 10, 14, c(0x8A6B54), r: 5)
        windowGrid(x: x - 21, y: ground - 28, columns: 2, rows: 2, w: 3.4, h: 6, gapX: 34, gapY: 6, color: 0xBFD4F2)
    }

    /// 加拿大广场：码头上的白帆屋顶。
    func canadaPlace(_ x: CGFloat) {
        let ground = Self.horizon
        rect(x - 46, ground - 12, 92, 12, c(0xE6EBF4), r: 2)
        windowGrid(x: x - 42, y: ground - 9, columns: 12, rows: 1, w: 4, h: 4, gapX: 3.1, gapY: 0, color: 0xB7D2F2)
        for index in 0..<5 {
            let sx = x - 34 + CGFloat(index) * 17
            let h: CGFloat = index == 2 ? 30 : 24
            poly([CGPoint(x: sx - 8, y: ground - 12), CGPoint(x: sx + 8, y: ground - 12), CGPoint(x: sx, y: ground - 12 - h)], c(index % 2 == 0 ? 0xFFFFFF : 0xF2F5FB))
            line(CGPoint(x: sx, y: ground - 12), CGPoint(x: sx, y: ground - 12 - h), c(0xD4DCEC), width: 0.6)
        }
    }

    /// 滨海湾金沙：三栋塔楼顶着一艘“船”。
    func marinaBaySands(_ x: CGFloat) {
        let ground = Self.horizon
        for dx in [-28.0, 0.0, 28.0] as [CGFloat] {
            poly([CGPoint(x: x + dx - 10, y: ground), CGPoint(x: x + dx + 10, y: ground), CGPoint(x: x + dx + 8, y: ground - 84), CGPoint(x: x + dx - 8, y: ground - 84)], c(0xDDE5F2))
            rect(x + dx + 2, ground - 84, 6, 84, c(0xC9D5EA))
            windowGrid(x: x + dx - 6, y: ground - 78, columns: 3, rows: 8, w: 2.6, h: 4, gapX: 2.4, gapY: 4.8, color: 0xF2F7FF, litPattern: Int(dx))
        }
        var deck = Path()
        deck.move(to: CGPoint(x: x - 46, y: ground - 88))
        deck.addLine(to: CGPoint(x: x + 54, y: ground - 88))
        deck.addQuadCurve(to: CGPoint(x: x + 44, y: ground - 83), control: CGPoint(x: x + 52, y: ground - 83))
        deck.addLine(to: CGPoint(x: x - 42, y: ground - 83))
        deck.closeSubpath()
        fill(deck, c(0xB8C7E2))
        for tree in 0..<6 { circle(x - 36 + CGFloat(tree) * 14, ground - 90, 2.2, c(0x6FCF98)) }
    }

    /// 滨海湾花园的擎天大树。
    func supertree(_ x: CGFloat, height: CGFloat, color: UInt32 = 0xB28BFF) {
        let ground = Self.horizon
        poly([CGPoint(x: x - 3.4, y: ground), CGPoint(x: x + 3.4, y: ground), CGPoint(x: x + 1.6, y: ground - height + 10), CGPoint(x: x - 1.6, y: ground - height + 10)], c(0x9A7FD6))
        var crown = Path()
        crown.move(to: CGPoint(x: x - 2, y: ground - height + 12))
        crown.addQuadCurve(to: CGPoint(x: x - 15, y: ground - height), control: CGPoint(x: x - 12, y: ground - height + 8))
        crown.addLine(to: CGPoint(x: x + 15, y: ground - height))
        crown.addQuadCurve(to: CGPoint(x: x + 2, y: ground - height + 12), control: CGPoint(x: x + 12, y: ground - height + 8))
        crown.closeSubpath()
        fill(crown, isNight ? SceneInk(color).mixed(with: SceneInk(0xFFFFFF), 0.15).color : c(color))
        if isNight { ellipse(x, ground - height + 2, 18, 6, SceneInk(color).color.opacity(0.3)) }
        for leaf in 0..<4 {
            circle(x - 9 + CGFloat(leaf) * 6, ground - height - 1, 1.8, c(0x6FCF98))
        }
    }

    /// 肯雅塔国际会议中心：圆柱塔顶着“飞碟”，旁边是锥形会堂。
    func kicc(_ x: CGFloat) {
        let ground = Self.horizon
        poly([CGPoint(x: x + 8, y: ground), CGPoint(x: x + 44, y: ground), CGPoint(x: x + 26, y: ground - 26)], c(0xC9875D))
        topRounded(x - 9, ground - 92, 18, 92, c(0xE2B48C), r: 3)
        rect(x + 3, ground - 92, 6, 92, c(0xD5A47B))
        windowGrid(x: x - 6, y: ground - 86, columns: 3, rows: 9, w: 2.4, h: 4.4, gapX: 2.2, gapY: 4.4, color: 0xFFF0D8)
        ellipse(x, ground - 95, 16, 4, c(0xC9875D))
        rect(x - 1, ground - 108, 2, 11, c(0xC9875D))
        circle(x, ground - 109, 1.4, c(0xF5C451))
    }

    /// 长颈鹿，朝右；`size` 为整体缩放。
    func giraffe(_ x: CGFloat, baseY: CGFloat = 160, size: CGFloat = 1, facing: CGFloat = 1) {
        let body = c(0xF6C56B)
        let spot = c(0xD98E3E)
        func px(_ dx: CGFloat) -> CGFloat { x + dx * size * facing }
        func py(_ dy: CGFloat) -> CGFloat { baseY - dy * size }
        for leg in [-7.0, -3.0, 5.0, 8.5] as [CGFloat] {
            rect(min(px(leg), px(leg + 2)), py(13), 2 * size, 13 * size, body, r: 0.8)
        }
        ellipse(px(1), py(16), 11 * size, 5.4 * size, body)
        var neck = Path()
        neck.move(to: CGPoint(x: px(4), y: py(18)))
        neck.addLine(to: CGPoint(x: px(11), y: py(38)))
        neck.addLine(to: CGPoint(x: px(15), y: py(37)))
        neck.addLine(to: CGPoint(x: px(10), y: py(15)))
        neck.closeSubpath()
        fill(neck, body)
        ellipse(px(15), py(39), 5 * size, 2.8 * size, body)
        line(CGPoint(x: px(12), y: py(41)), CGPoint(x: px(12), y: py(45)), spot, width: 1 * size)
        line(CGPoint(x: px(14.5), y: py(41)), CGPoint(x: px(14.5), y: py(45)), spot, width: 1 * size)
        circle(px(16), py(40), 0.8 * size, c(0x3B3F5C))
        for (dx, dy) in [(-5.0, 17.0), (0.0, 15.0), (5.0, 17.5), (-1.5, 19.5), (7.0, 25.0), (10.0, 32.0)] as [(CGFloat, CGFloat)] {
            circle(px(dx), py(dy), 1.5 * size, spot)
        }
    }

    /// 红白条纹灯塔。
    func lighthouse(_ x: CGFloat, stripe: UInt32 = 0xFF6B6B) {
        let ground = Self.horizon
        rect(x - 12, ground - 4, 24, 4, c(0xB8C2D8), r: 2)
        poly([CGPoint(x: x - 8, y: ground - 4), CGPoint(x: x + 8, y: ground - 4), CGPoint(x: x + 5, y: ground - 50), CGPoint(x: x - 5, y: ground - 50)], c(0xFFFFFF))
        for band in 0..<3 {
            let y = ground - 12 - CGFloat(band) * 14
            let inset = CGFloat(band) * 1 + 1.4
            rect(x - 8 + inset, y - 5, 16 - inset * 2, 5, c(stripe))
        }
        rect(x - 6, ground - 58, 12, 8, isNight ? SceneInk(0xFFE38F).color : c(0xFFF4C8), r: 2)
        dome(x, ground - 58, 7, 6, c(stripe))
        if isNight {
            poly([CGPoint(x: x + 5, y: ground - 56), CGPoint(x: x + 70, y: ground - 66), CGPoint(x: x + 70, y: ground - 46)], SceneInk(0xFFE38F).color.opacity(0.18))
        }
    }

    /// 曼彻斯特市政厅式钟楼。
    func gothicClockTower(_ x: CGFloat, height: CGFloat = 96, stone: UInt32 = 0xE3C79E, roof: UInt32 = 0x5E6E9F) {
        let ground = Self.horizon
        rect(x - 9, ground - height, 18, height, c(stone))
        rect(x + 3, ground - height, 6, height, tone(SceneInk(stone).mixed(with: SceneInk(0x5A4A3A), 0.12)))
        circle(x, ground - height + 12, 6, c(0xFFFDF4))
        line(CGPoint(x: x, y: ground - height + 12), CGPoint(x: x + 2.4, y: ground - height + 9), c(0x3B4470), width: 0.9)
        line(CGPoint(x: x, y: ground - height + 12), CGPoint(x: x, y: ground - height + 7.6), c(0x3B4470), width: 0.7)
        windowGrid(x: x - 5, y: ground - height + 26, columns: 2, rows: 5, w: 2.6, h: 7, gapX: 5, gapY: 6, color: 0xFFF3DC)
        poly([CGPoint(x: x - 11, y: ground - height), CGPoint(x: x + 11, y: ground - height), CGPoint(x: x, y: ground - height - 26)], c(roof))
        for corner in [x - 9, x + 9] {
            spire(corner, ground - height, width: 3, height: 9, c(roof))
        }
    }

    /// 红砖纺织厂与烟囱。
    func brickMill(_ x: CGFloat, width: CGFloat = 70) {
        let ground = Self.horizon
        let brick = c(0xD9826A)
        rect(x - width / 2, ground - 40, width, 40, brick, r: 1)
        rect(x - width / 2, ground - 42, width, 3, c(0xBF6A55), r: 1)
        windowGrid(x: x - width / 2 + 4, y: ground - 35, columns: Int((width - 6) / 7), rows: 3, w: 3.6, h: 6, gapX: 3.4, gapY: 4.4, color: 0xFFF3DC)
        rect(x + width / 2 - 14, ground - 74, 8, 32, c(0xC9715B), r: 1)
        rect(x + width / 2 - 15, ground - 76, 10, 3, c(0xB3604C), r: 1)
    }

    /// 平缓的低矮体育馆穹顶（罗杰斯中心）。
    func lowDome(_ x: CGFloat, width: CGFloat = 70) {
        let ground = Self.horizon
        rect(x - width / 2, ground - 14, width, 14, c(0xE6EBF4), r: 2)
        dome(x, ground - 14, width / 2 - 2, 14, c(0xF7F9FC))
        for rib in 1..<5 {
            let rx = x - width / 2 + 2 + CGFloat(rib) * (width - 4) / 5
            line(CGPoint(x: rx, y: ground - 14), CGPoint(x: x + (rx - x) * 0.6, y: ground - 24), c(0xD4DCEC), width: 0.7)
        }
    }
}
