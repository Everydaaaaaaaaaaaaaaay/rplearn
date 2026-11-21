import SwiftUI

/// 竖版地点场景的绘制：坐标宽 390 单位，`ground` 为地面线。
struct PuffPlaceStage {
    let painter: PuffScenePainter
    let kind: PuffPlaceScene.Kind
    let seed: Int
    let height: CGFloat

    private let width: CGFloat = 390
    var ground: CGFloat { height * 0.6 }

    private var p: PuffScenePainter { painter }

    // MARK: - 通用

    /// 生成一个对 painter 平移、缩放后的新 painter。
    private func shifted(dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1, time: TimeInterval? = nil) -> PuffScenePainter {
        var context = painter.ctx
        context.translateBy(x: dx, y: dy)
        context.scaleBy(x: scale, y: scale)
        return PuffScenePainter(ctx: context, mood: painter.mood, time: time ?? painter.time, clock: painter.clock)
    }

    private func noise(_ index: Int) -> CGFloat { PuffScenePainter.noise(seed &+ index &* 131) }

    private func pick<T>(_ options: [T], _ index: Int) -> T {
        options[Int(noise(index) * CGFloat(options.count)) % options.count]
    }

    private static let pastelFacades: [UInt32] = [0xFFD6E0, 0xFFE9B0, 0xCDEFE0, 0xDCD3FF, 0xCFE6FF, 0xFFD9C2]
    private static let candies: [UInt32] = [0xFF7EAA, 0x4DA6FF, 0x3DD39A, 0xFFC53D, 0x9B7BFF, 0xFF9A4D]

    func sky() {
        let atmosphere = p.atmosphere
        p.ctx.fill(
            Path(CGRect(x: -10, y: -10, width: width + 20, height: height + 20)),
            with: .linearGradient(
                Gradient(colors: [atmosphere.skyTop.color, atmosphere.skyBottom.color]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: ground - 80)
            )
        )
        shifted(dx: -30, dy: height * 0.1).celestial(x: 330)
    }

    /// 远处的城市天际线：沿用城市全景的远景与地标，静止并罩一层薄雾。
    func distantCity(_ recipe: PuffCityRecipe) {
        let scale: CGFloat = 0.92
        let horizon = ground - 120
        var cityContext = painter.ctx
        cityContext.translateBy(x: width / 2 - recipe.iconX * scale, y: horizon - PuffScenePainter.horizon * scale)
        cityContext.scaleBy(x: scale, y: scale)
        // 只保留远岸一线水面，近处道路上的车辆不入画。
        cityContext.clip(to: Path(CGRect(x: -400, y: -600, width: 1600, height: 600 + PuffScenePainter.horizon + 10)))
        let city = PuffScenePainter(ctx: cityContext, mood: painter.mood, time: 0, clock: painter.clock)
        recipe.backdrop(city)
        switch recipe.terrain {
        case .water: city.water()
        case .land: city.farGround()
        }
        recipe.landmarks(city)
        recipe.movers(city)
        // 薄雾把城市推远，让近处的地点成为主角。
        p.rect(-10, horizon - 200, width + 20, 230, p.atmosphere.skyBottom.color.opacity(0.32))
    }

    func clouds() {
        shifted(dx: -40, dy: height * 0.08).clouds(seed: seed)
        shifted(dx: -80, dy: height * 0.12).birds()
    }

    func place() {
        switch kind {
        case .street: street()
        case .market: market()
        case .park: park()
        case .community: community()
        case .bookshop: bookshop()
        case .transport: transport()
        case .cafe: cafe()
        }
    }

    func movers() {
        switch kind {
        case .market: bunting(y: ground - 236, sway: true)
        case .park: ducks()
        case .community: fountainDrops()
        case .transport: tram()
        case .cafe: steam()
        case .street, .bookshop: break
        }
    }

    // MARK: - 组件

    private func sidewalkAndRoad(sidewalk: CGFloat = 48) {
        p.rect(-10, ground, width + 20, sidewalk, p.c(0xF2EDE5))
        var x: CGFloat = 0
        while x < width {
            p.rect(x, ground, 1.5, sidewalk, p.c(0xE2DBCF))
            x += 32
        }
        p.rect(-10, ground + sidewalk, width + 20, 6, p.c(0xD8D1C5))
        p.rect(-10, ground + sidewalk + 6, width + 20, height, p.c(0xE4E2EC))
        var dash: CGFloat = 10
        while dash < width {
            p.rect(dash, ground + sidewalk + 70, 26, 4, p.c(0xFFFFFF), r: 2)
            dash += 52
        }
    }

    /// 条纹遮阳棚，底边是一排扇贝。
    private func awning(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: UInt32) {
        let stripes = max(Int(w / 14), 3)
        let stripeWidth = w / CGFloat(stripes)
        for index in 0..<stripes {
            p.rect(x + CGFloat(index) * stripeWidth, y, stripeWidth + 0.5, h, p.c(index % 2 == 0 ? color : 0xFFFFFF))
        }
        for index in 0..<stripes {
            let cx = x + (CGFloat(index) + 0.5) * stripeWidth
            p.dome(cx, y + h, stripeWidth / 2, -stripeWidth * 0.45, p.c(index % 2 == 0 ? color : 0xFFFFFF))
        }
        p.rect(x - 3, y - 4, w + 6, 6, p.c(color).opacity(0.9), r: 3)
    }

    private func window(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, frame: UInt32 = 0xFFFFFF, lit: Bool = true) {
        p.rect(x - 2, y - 2, w + 4, h + 4, p.c(frame), r: 3)
        p.rect(x, y, w, h, p.window(0xCFE6FF, lit: lit), r: 2)
        p.rect(x + w / 2 - 1, y, 2, h, p.c(frame))
        p.rect(x, y + h * 0.45, w, 2, p.c(frame))
        if !p.isNight { p.rect(x + 3, y + 3, w * 0.25, h * 0.3, p.c(0xFFFFFF).opacity(0.6), r: 1) }
    }

    private func pottedPlant(_ x: CGFloat, base: CGFloat) {
        p.poly([CGPoint(x: x - 9, y: base - 16), CGPoint(x: x + 9, y: base - 16), CGPoint(x: x + 6, y: base), CGPoint(x: x - 6, y: base)], p.c(0xE58E62))
        p.circle(x - 6, base - 22, 8, p.c(0x5BC98E))
        p.circle(x + 6, base - 24, 9, p.c(0x6FD3A0))
        p.circle(x, base - 31, 8, p.c(0x86DDB0))
    }

    private func bicycle(_ x: CGFloat, base: CGFloat, color: UInt32) {
        let wheel = p.c(0x3B3F5C)
        for dx in [-18.0, 18.0] as [CGFloat] {
            p.stroke(Path(ellipseIn: CGRect(x: x + dx - 12, y: base - 24, width: 24, height: 24)), wheel, width: 3)
        }
        let frame = p.c(color)
        p.line(CGPoint(x: x - 18, y: base - 12), CGPoint(x: x, y: base - 12), frame, width: 3.5)
        p.line(CGPoint(x: x, y: base - 12), CGPoint(x: x + 8, y: base - 30), frame, width: 3.5)
        p.line(CGPoint(x: x - 18, y: base - 12), CGPoint(x: x - 6, y: base - 30), frame, width: 3.5)
        p.line(CGPoint(x: x - 6, y: base - 30), CGPoint(x: x + 8, y: base - 30), frame, width: 3.5)
        p.line(CGPoint(x: x + 8, y: base - 30), CGPoint(x: x + 18, y: base - 12), frame, width: 3.5)
        p.rect(x - 11, base - 35, 12, 4, wheel, r: 2)
        p.line(CGPoint(x: x + 8, y: base - 30), CGPoint(x: x + 10, y: base - 38), wheel, width: 3)
        p.rect(x + 4, base - 40, 14, 4, wheel, r: 2)
        // 车篮里的一束花。
        p.rect(x + 14, base - 34, 12, 10, p.c(0xE9C38E), r: 2)
        p.circle(x + 17, base - 36, 3.5, p.c(0xFF7EAA))
        p.circle(x + 23, base - 37, 3.5, p.c(0xFFC53D))
    }

    /// 一只坐着的小猫，`facing` 为 1 朝右。
    private func cat(_ x: CGFloat, base: CGFloat, color: UInt32 = 0xF2A65A, facing: CGFloat = 1) {
        let fur = p.c(color)
        p.ellipse(x, base - 12, 13, 12, fur)
        p.circle(x + 7 * facing, base - 28, 10, fur)
        p.poly([CGPoint(x: x + 0 * facing, y: base - 33), CGPoint(x: x + 4 * facing, y: base - 44), CGPoint(x: x + 9 * facing, y: base - 35)], fur)
        p.poly([CGPoint(x: x + 9 * facing, y: base - 35), CGPoint(x: x + 14 * facing, y: base - 44), CGPoint(x: x + 16 * facing, y: base - 31)], fur)
        let ink = SceneInk(0x2A3052).color
        if p.isNight {
            p.line(CGPoint(x: x + 4 * facing, y: base - 29), CGPoint(x: x + 7 * facing, y: base - 29), ink, width: 1.6)
            p.line(CGPoint(x: x + 11 * facing, y: base - 29), CGPoint(x: x + 14 * facing, y: base - 29), ink, width: 1.6)
        } else {
            p.circle(x + 5 * facing, base - 29, 1.8, ink)
            p.circle(x + 12 * facing, base - 29, 1.8, ink)
        }
        p.ellipse(x + 8.5 * facing, base - 24, 2.4, 1.4, SceneInk(0xFF8FA3).color)
        var tail = Path()
        tail.move(to: CGPoint(x: x - 10 * facing, y: base - 4))
        tail.addQuadCurve(to: CGPoint(x: x - 20 * facing, y: base - 24), control: CGPoint(x: x - 26 * facing, y: base - 4))
        p.stroke(tail, fur, width: 4.5)
    }

    private func bench(_ x: CGFloat, base: CGFloat) {
        let wood = p.c(0xD39A62)
        let iron = p.c(0x4D5A86)
        for dx in [-34.0, 30.0] as [CGFloat] {
            p.rect(x + dx, base - 22, 4, 22, iron)
        }
        p.rect(x - 40, base - 26, 80, 6, wood, r: 2)
        p.rect(x - 40, base - 46, 80, 5, wood, r: 2)
        p.rect(x - 40, base - 37, 80, 5, wood, r: 2)
        p.rect(x - 38, base - 46, 3, 22, iron)
        p.rect(x + 35, base - 46, 3, 22, iron)
    }

    /// 一串三角小彩旗。
    private func bunting(y: CGFloat, sway: Bool) {
        let sag: CGFloat = 26
        var string = Path()
        string.move(to: CGPoint(x: -10, y: y))
        string.addQuadCurve(to: CGPoint(x: width + 10, y: y), control: CGPoint(x: width / 2, y: y + sag * 2))
        p.stroke(string, p.c(0x8D92AB), width: 1.5)
        var x: CGFloat = 6
        var index = 0
        while x < width {
            let t = (x + 10) / (width + 20)
            let sy = (1 - t) * (1 - t) * y + 2 * (1 - t) * t * (y + sag * 2) + t * t * y
            let wiggle = sway ? CGFloat(sin(p.time * 2.4 + Double(index) * 0.7)) * 3 : 0
            p.poly([
                CGPoint(x: x - 9, y: sy),
                CGPoint(x: x + 9, y: sy),
                CGPoint(x: x + wiggle, y: sy + 20),
            ], p.c(Self.candies[index % Self.candies.count]))
            x += 26
            index += 1
        }
    }

    private func scaledTree(_ x: CGFloat, base: CGFloat, scale: CGFloat, pine: Bool = false) {
        let tree = shifted(dx: x, dy: base, scale: scale)
        if pine { tree.pineTree(0, baseY: 0) } else { tree.roundTree(0, baseY: 0) }
    }

    // MARK: - 街道

    private func street() {
        sidewalkAndRoad()
        let widths: [CGFloat] = [100, 96, 96, 98]
        var x: CGFloat = 0
        for (index, w) in widths.enumerated() {
            let h: CGFloat = 190 + noise(index * 3) * 60
            let facade: UInt32 = pick(Self.pastelFacades, index * 5 + 1)
            let top = ground - h
            p.rect(x, top, w - 2, h, p.c(facade))
            p.rect(x - 2, top - 8, w + 2, 10, p.tone(SceneInk(facade).mixed(with: SceneInk(0x6D5A9A), 0.25)).opacity(0.9), r: 2)
            let rows = Int((h - 110) / 46)
            for row in 0..<max(rows, 1) {
                window(x + 16, top + 20 + CGFloat(row) * 46, 24, 30)
                window(x + w - 42, top + 20 + CGFloat(row) * 46, 24, 30)
            }
            let awningColor: UInt32 = pick(Self.candies, index * 7 + 2)
            awning(x: x + 6, y: ground - 100, w: w - 14, h: 20, color: awningColor)
            p.rect(x + 8, ground - 70, w * 0.5, 58, p.window(0xCFE6FF), r: 3)
            if !p.isNight { p.rect(x + 12, ground - 66, 10, 22, p.c(0xFFFFFF).opacity(0.55), r: 2) }
            p.topRounded(x + w - 34, ground - 70, 24, 70, p.c(awningColor).opacity(0.95), r: 12)
            p.circle(x + w - 15, ground - 34, 2, p.c(0xFFE38F))
            pottedPlant(x + w * 0.5 + 18, base: ground + 2)
            x += w
        }
        shifted(dx: 98, dy: ground + 10, scale: 3).lampPost(0, baseY: 0)
        shifted(dx: 292, dy: ground + 10, scale: 3).lampPost(0, baseY: 0)
        bicycle(46, base: ground + 40, color: pick(Self.candies, 41))
    }

    // MARK: - 市集

    private func market() {
        p.rect(-10, ground - 4, width + 20, height, p.c(0xF3E6D6))
        for index in 0..<60 {
            let cx = noise(index * 2) * width
            let cy = ground + 10 + noise(index * 2 + 1) * (height - ground)
            p.ellipse(cx, cy, 7, 3, p.c(0xE6D5C0))
        }
        if seed % 2 == 0 {
            // 玻璃拱顶市场大厅。
            var arch = Path()
            arch.move(to: CGPoint(x: 10, y: ground - 120))
            arch.addQuadCurve(to: CGPoint(x: width - 10, y: ground - 120), control: CGPoint(x: width / 2, y: ground - 360))
            arch.addLine(to: CGPoint(x: width - 10, y: ground))
            arch.addLine(to: CGPoint(x: 10, y: ground))
            arch.closeSubpath()
            p.fill(arch, p.c(0xC9DCF3).opacity(0.85))
            for index in 1..<8 {
                let rx = 10 + CGFloat(index) * (width - 20) / 8
                p.line(CGPoint(x: rx, y: ground), CGPoint(x: rx, y: ground - 240 + abs(rx - width / 2) * 0.55), p.c(0xFFFFFF), width: 3)
            }
            p.stroke(arch, p.c(0x6F82AE), width: 5)
        }
        let produce: [[UInt32]] = [[0xFF5A63, 0xFF7A6B], [0xFFA53D, 0xFFC53D], [0x6FCF98, 0xA6E08A], [0xB28BFF, 0xFF7EAA]]
        for (index, cx) in ([72, 195, 318] as [CGFloat]).enumerated() {
            let canopy: UInt32 = pick(Self.candies, index * 11 + 3)
            p.rect(cx - 54, ground - 150, 4, 150, p.c(0x8A6B54))
            p.rect(cx + 50, ground - 150, 4, 150, p.c(0x8A6B54))
            awning(x: cx - 58, y: ground - 166, w: 116, h: 30, color: canopy)
            p.rect(cx - 56, ground - 52, 112, 10, p.c(0xD9A574), r: 2)
            p.rect(cx - 52, ground - 42, 104, 36, p.tone(SceneInk(canopy).mixed(with: SceneInk(0xFFFFFF), 0.7)), r: 3)
            for crate in 0..<3 {
                let bx = cx - 48 + CGFloat(crate) * 34
                p.rect(bx, ground - 74, 30, 22, p.c(0xC98E5C), r: 2)
                p.rect(bx, ground - 66, 30, 2, p.c(0xAE7748))
                let colors = produce[(index + crate) % produce.count]
                for fruit in 0..<4 {
                    p.circle(bx + 5 + CGFloat(fruit) * 6.5, ground - 77 - CGFloat(fruit % 2) * 3, 5, p.c(colors[fruit % 2]))
                }
            }
        }
    }

    // MARK: - 公园

    private func park() {
        p.ellipse(90, ground + 6, 200, 50, p.c(0xA6DB92))
        p.ellipse(320, ground + 10, 190, 44, p.c(0x9CD68A))
        p.rect(-10, ground + 10, width + 20, height, p.c(0xB4E3A0))
        var path = Path()
        path.move(to: CGPoint(x: 150, y: height + 10))
        path.addCurve(to: CGPoint(x: 186, y: ground + 4), control1: CGPoint(x: 210, y: ground + 150), control2: CGPoint(x: 120, y: ground + 60))
        path.addLine(to: CGPoint(x: 202, y: ground + 4))
        path.addCurve(to: CGPoint(x: 250, y: height + 10), control1: CGPoint(x: 150, y: ground + 60), control2: CGPoint(x: 270, y: ground + 150))
        path.closeSubpath()
        p.fill(path, p.c(0xF3E3C3))
        scaledTree(300, base: ground + 4, scale: 2.4)
        scaledTree(92, base: ground + 10, scale: 2.6, pine: true)
        scaledTree(36, base: ground + 40, scale: 3.4)
        scaledTree(356, base: ground + 50, scale: 3.6)
        p.ellipse(290, ground + 104, 78, 24, p.c(0x8DCBFF))
        p.ellipse(290, ground + 100, 66, 16, p.c(0xB6DEFF))
        for reed in 0..<4 {
            let rx: CGFloat = 214 + CGFloat(reed) * 5
            p.line(CGPoint(x: rx, y: ground + 110), CGPoint(x: rx - 2, y: ground + 84 - CGFloat(reed % 2) * 6), p.c(0x5BAF7A), width: 2)
        }
        bench(86, base: ground + 92)
        cat(70, base: ground + 66, color: pick([0xF2A65A, 0x9AA0B8, 0x4A4E69], 17))
        for index in 0..<26 {
            let side: CGFloat = index % 2 == 0 ? -1 : 1
            let fy = ground + 20 + noise(index * 3) * (height - ground - 30)
            let fx = 200 + side * (30 + noise(index * 3 + 1) * 140)
            p.circle(fx, fy, 3.2, p.c(Self.candies[index % Self.candies.count]))
            p.circle(fx, fy, 1.2, p.c(0xFFF3C0))
        }
    }

    private func ducks() {
        for index in 0..<2 {
            let t = p.time * 0.25 + Double(index) * 2.4
            let dx = CGFloat(sin(t)) * 46
            let x = 290 + dx
            let y = ground + 98 + CGFloat(index) * 6 + CGFloat(sin(p.time * 3 + Double(index))) * 1.2
            let facing: CGFloat = cos(t) >= 0 ? 1 : -1
            p.ellipse(x, y, 11, 6, p.c(index == 0 ? 0xFFFFFF : 0xFFE38F))
            p.circle(x + 7 * facing, y - 8, 5, p.c(index == 0 ? 0xFFFFFF : 0xFFE38F))
            p.poly([CGPoint(x: x + 11 * facing, y: y - 9), CGPoint(x: x + 17 * facing, y: y - 7.5), CGPoint(x: x + 11 * facing, y: y - 6)], p.c(0xFF9A4D))
            p.circle(x + 8.5 * facing, y - 9.5, 1, SceneInk(0x2A3052).color)
        }
    }

    // MARK: - 社区建筑

    private func community() {
        p.rect(-10, ground, width + 20, height, p.c(0xEFE8DD))
        p.ellipse(195, ground + 120, 150, 40, p.c(0xE6DCCB))
        let stone = p.c(0xF4E6C8)
        let shade = p.c(0xE6D3AE)
        for step in 0..<3 {
            p.rect(40 - CGFloat(step) * 8, ground - 8 - CGFloat(step) * 8 + 16, 310 + CGFloat(step) * 16, 8, shade)
        }
        p.rect(50, ground - 176, 290, 160, stone)
        p.rect(44, ground - 192, 302, 16, shade, r: 2)
        p.poly([CGPoint(x: 40, y: ground - 192), CGPoint(x: 350, y: ground - 192), CGPoint(x: 195, y: ground - 250)], stone)
        p.poly([CGPoint(x: 70, y: ground - 196), CGPoint(x: 320, y: ground - 196), CGPoint(x: 195, y: ground - 240)], shade)
        p.circle(195, ground - 214, 10, p.c(0xFFFDF4))
        for index in 0..<6 {
            let cx: CGFloat = 70 + CGFloat(index) * 50
            guard abs(cx - 195) > 30 else { continue }
            p.rect(cx - 9, ground - 170, 18, 150, p.c(0xFFFFFF))
            p.rect(cx - 12, ground - 176, 24, 8, shade, r: 2)
            p.rect(cx - 12, ground - 22, 24, 6, shade, r: 2)
            p.rect(cx + 2, ground - 170, 5, 150, p.c(0xF1E9DA))
        }
        p.topRounded(173, ground - 110, 44, 94, p.c(0x8A6B54), r: 22)
        p.rect(193, ground - 104, 4, 88, p.c(0x77594A))
        p.rect(30, ground - 260, 3, 70, p.c(0x8D92AB))
        p.poly([CGPoint(x: 33, y: ground - 260), CGPoint(x: 60, y: ground - 252), CGPoint(x: 33, y: ground - 244)], p.c(pick(Self.candies, 5)))
        scaledTree(20, base: ground + 30, scale: 3)
        scaledTree(372, base: ground + 30, scale: 3)
        // 喷泉。
        let fx: CGFloat = 195
        let fy = ground + 126
        p.ellipse(fx, fy, 66, 16, p.c(0xD8CFC0))
        p.ellipse(fx, fy - 4, 58, 12, p.c(0x8DCBFF))
        p.rect(fx - 6, fy - 46, 12, 42, p.c(0xD8CFC0))
        p.ellipse(fx, fy - 46, 24, 7, p.c(0xD8CFC0))
        p.ellipse(fx, fy - 48, 19, 4.5, p.c(0xB6DEFF))
    }

    private func fountainDrops() {
        let fx: CGFloat = 195
        let top = ground + 126 - 50
        for index in 0..<10 {
            let phase = (p.time * 0.9 + Double(index) / 10).truncatingRemainder(dividingBy: 1)
            let side: CGFloat = index % 2 == 0 ? -1 : 1
            let spread = CGFloat(index / 2 + 1) * 6
            let x = fx + side * spread * CGFloat(phase)
            let y = top - 26 * CGFloat(sin(phase * .pi)) + CGFloat(phase) * 30
            p.circle(x, y, 2.4, p.c(0x8DCBFF).opacity(1 - phase * 0.5))
        }
    }

    // MARK: - 书店

    private func bookshop() {
        sidewalkAndRoad()
        let facade: UInt32 = pick([0x3E8E6B, 0x2E4A7D, 0x9B3B4E, 0x6B4FA0], 3)
        p.rect(18, ground - 300, 354, 120, p.c(0xEADCC6))
        for index in 0..<3 {
            window(52 + CGFloat(index) * 110, ground - 280, 46, 60, frame: 0xFFFFFF)
        }
        p.rect(14, ground - 180, 362, 180, p.c(facade))
        p.rect(30, ground - 168, 330, 34, p.tone(SceneInk(facade).mixed(with: SceneInk(0x000000), 0.2)), r: 4)
        p.ctx.draw(
            Text("BOOKS").font(.system(size: 24, weight: .heavy, design: .serif)).foregroundColor(p.c(0xF5C451)),
            at: CGPoint(x: 195, y: ground - 151)
        )
        for (wx, ww) in [(34.0, 130.0), (226.0, 130.0)] as [(CGFloat, CGFloat)] {
            p.rect(wx, ground - 118, ww, 100, p.window(0xE8F3FF, lit: true), r: 4)
            for shelf in 0..<3 {
                let sy = ground - 112 + CGFloat(shelf) * 32
                var bx = wx + 4
                var index = shelf * 13 + Int(wx)
                while bx < wx + ww - 8 {
                    let bw: CGFloat = 6 + noise(index) * 6
                    let bh: CGFloat = 18 + noise(index + 1) * 8
                    p.rect(bx, sy + 26 - bh, bw, bh, p.c(Self.candies[index % Self.candies.count]), r: 1)
                    bx += bw + 1.5
                    index += 1
                }
                p.rect(wx, sy + 26, ww, 3, p.c(0xB98A5E))
            }
            p.stroke(Path(roundedRect: CGRect(x: wx, y: ground - 118, width: ww, height: 100), cornerRadius: 4), p.c(0xF5C451), width: 3)
        }
        cat(120, base: ground - 50, color: pick([0xF2A65A, 0xFFFFFF, 0x4A4E69], 9), facing: -1)
        p.topRounded(174, ground - 116, 42, 116, p.tone(SceneInk(facade).mixed(with: SceneInk(0x000000), 0.3)), r: 6)
        p.rect(182, ground - 106, 26, 36, p.window(0xCFE6FF), r: 3)
        p.circle(208, ground - 56, 2.4, p.c(0xF5C451))
        // 门口的书箱和花盆。
        p.rect(36, ground + 4, 58, 30, p.c(0xC98E5C), r: 3)
        for index in 0..<7 {
            p.rect(40 + CGFloat(index) * 7.6, ground - 10, 6, 16, p.c(Self.candies[(index + 2) % Self.candies.count]), r: 1)
        }
        pottedPlant(330, base: ground + 26)
        pottedPlant(356, base: ground + 30)
    }

    // MARK: - 交通

    private func transport() {
        let stone = p.c(0xEADFCB)
        p.rect(24, ground - 260, 342, 262, stone)
        p.rect(18, ground - 272, 354, 14, p.c(0xD8C9AE), r: 3)
        var arch = Path()
        arch.addRoundedRect(in: CGRect(x: 90, y: ground - 230, width: 210, height: 240), cornerRadii: RectangleCornerRadii(topLeading: 105, bottomLeading: 0, bottomTrailing: 0, topTrailing: 105))
        p.fill(arch, p.window(0xCFE6FF))
        var context = p.ctx
        context.clip(to: arch)
        for index in 0..<7 {
            let angle = Double.pi * (Double(index) / 6)
            let end = CGPoint(x: 195 - CGFloat(cos(angle)) * 120, y: ground - 125 - CGFloat(sin(angle)) * 120)
            context.stroke({ var path = Path(); path.move(to: CGPoint(x: 195, y: ground - 125)); path.addLine(to: end); return path }(), with: .color(p.c(0xFFFFFF)), lineWidth: 3)
        }
        context.stroke(Path(ellipseIn: CGRect(x: 160, y: ground - 160, width: 70, height: 70)), with: .color(p.c(0xFFFFFF)), lineWidth: 3)
        for row in 1..<4 {
            context.fill(Path(CGRect(x: 90, y: ground - 125 + CGFloat(row) * 32, width: 210, height: 3)), with: .color(p.c(0xFFFFFF)))
        }
        p.stroke(arch, p.c(0xC9B48F), width: 6)
        // 站钟，指针显示城市当地时间。
        let clockCenter = CGPoint(x: 195, y: ground - 262)
        p.circle(clockCenter.x, clockCenter.y, 26, p.c(0xD8C9AE))
        p.circle(clockCenter.x, clockCenter.y, 21, p.isNight ? SceneInk(0xFFF2C2).color : p.c(0xFFFDF4))
        let hour = Double(p.clock.hour ?? 10).truncatingRemainder(dividingBy: 12)
        let minute = Double(p.clock.minute ?? 10)
        let ink = SceneInk(0x3B4470).color
        let hourAngle = (hour + minute / 60) / 12 * 2 * .pi
        let minuteAngle = minute / 60 * 2 * .pi
        p.line(clockCenter, CGPoint(x: clockCenter.x + CGFloat(sin(hourAngle)) * 10, y: clockCenter.y - CGFloat(cos(hourAngle)) * 10), ink, width: 3)
        p.line(clockCenter, CGPoint(x: clockCenter.x + CGFloat(sin(minuteAngle)) * 16, y: clockCenter.y - CGFloat(cos(minuteAngle)) * 16), ink, width: 2)
        p.circle(clockCenter.x, clockCenter.y, 2.5, ink)
        for wx in [40.0, 312.0] as [CGFloat] {
            window(wx, ground - 220, 38, 54)
            window(wx, ground - 140, 38, 54)
        }
        // 站台与轨道。
        p.rect(-10, ground, width + 20, 44, p.c(0xE8E2D8))
        p.rect(-10, ground + 36, width + 20, 6, p.c(0xFFD25A))
        p.rect(-10, ground + 44, width + 20, height, p.c(0xD7D3DE))
        for rail in [ground + 96, ground + 120] {
            p.rect(-10, rail, width + 20, 5, p.c(0x8D92AB))
        }
        var tie: CGFloat = -4
        while tie < width {
            p.rect(tie, ground + 90, 10, 38, p.c(0xB8A58F), r: 2)
            tie += 26
        }
    }

    private func tram() {
        let span = width + 340
        let progress = CGFloat((p.time / 16).truncatingRemainder(dividingBy: 1))
        let x = -170 + progress * span
        let body: UInt32 = pick([0x3FAF7A, 0xE5484D, 0x2E7FD6, 0xFFC53D], 23)
        let top = ground + 30
        p.rect(x - 150, top, 300, 78, p.c(body), r: 18)
        p.rect(x - 150, top + 58, 300, 8, p.c(0xFFFFFF).opacity(0.85))
        for index in 0..<6 {
            p.rect(x - 136 + CGFloat(index) * 46, top + 12, 36, 32, p.window(0xE8F3FF), r: 6)
        }
        for wheel in [x - 110, x - 70, x + 70, x + 110] {
            p.circle(wheel, top + 82, 9, p.c(0x3B3F5C))
            p.circle(wheel, top + 82, 3.5, p.c(0xDADDE8))
        }
        p.circle(x + 140, top + 50, 4, SceneInk(0xFFE38F).color)
    }

    // MARK: - 咖啡馆

    private func cafe() {
        p.rect(-10, ground, width + 20, height, p.c(0xF4EEE6))
        var row: CGFloat = 0
        while ground + row < height {
            p.rect(-10, ground + row, width + 20, 1.5, p.c(0xE6DDD0))
            row += 34
        }
        let facade: UInt32 = pick(Self.pastelFacades, 29)
        p.rect(18, ground - 250, 354, 250, p.c(facade))
        p.rect(12, ground - 262, 366, 14, p.tone(SceneInk(facade).mixed(with: SceneInk(0x6D5A9A), 0.25)), r: 3)
        for index in 0..<3 {
            let wx = 52 + CGFloat(index) * 110
            window(wx, ground - 236, 46, 54)
            p.rect(wx - 6, ground - 178, 58, 10, p.c(0xC98E5C), r: 2)
            for flower in 0..<5 {
                p.circle(wx + CGFloat(flower) * 11, ground - 182, 4.5, p.c(Self.candies[(flower + index) % Self.candies.count]))
            }
        }
        let awningColor: UInt32 = pick(Self.candies, 31)
        awning(x: 28, y: ground - 140, w: 334, h: 30, color: awningColor)
        p.rect(36, ground - 100, 120, 90, p.window(0xCFE6FF), r: 4)
        p.rect(234, ground - 100, 120, 90, p.window(0xCFE6FF), r: 4)
        p.ctx.draw(
            Text("CAFÉ").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(p.c(awningColor)),
            at: CGPoint(x: 96, y: ground - 74)
        )
        p.topRounded(174, ground - 106, 42, 106, p.tone(SceneInk(awningColor).mixed(with: SceneInk(0x000000), 0.25)), r: 21)
        p.circle(208, ground - 52, 2.4, p.c(0xFFE38F))
        // 挂牌：一杯咖啡。
        p.line(CGPoint(x: 330, y: ground - 196), CGPoint(x: 330, y: ground - 180), p.c(0x4D5A86), width: 2)
        p.circle(330, ground - 160, 20, p.c(0xFFFFFF))
        p.stroke(Path(ellipseIn: CGRect(x: 310, y: ground - 180, width: 40, height: 40)), p.c(awningColor), width: 3)
        p.rect(320, ground - 166, 18, 14, p.c(0x8A6B54), r: 3)
        p.stroke(Path(ellipseIn: CGRect(x: 335, y: ground - 164, width: 7, height: 8)), p.c(0x8A6B54), width: 2)
        // 黑板立牌。
        p.poly([CGPoint(x: 190, y: ground + 52), CGPoint(x: 210, y: ground + 52), CGPoint(x: 214, y: ground + 4), CGPoint(x: 186, y: ground + 4)], p.c(0x3B3F5C))
        p.rect(189, ground + 10, 22, 30, p.c(0x2F5E4E), r: 2)
        for line in 0..<3 {
            p.rect(193, ground + 15 + CGFloat(line) * 8, 14, 2, p.c(0xFFFFFF).opacity(0.8), r: 1)
        }
        for (tx, color) in [(96.0, 0), (300.0, 1)] as [(CGFloat, Int)] {
            table(tx, base: ground + 110, umbrella: pick(Self.candies, 37 + color))
        }
    }

    private func table(_ x: CGFloat, base: CGFloat, umbrella: UInt32) {
        p.rect(x - 2, base - 130, 4, 130, p.c(0x8D92AB))
        p.dome(x, base - 120, 62, 32, p.c(umbrella))
        for stripe in [-30.0, 0.0, 30.0] as [CGFloat] {
            p.dome(x + stripe, base - 120, 9, 26 - abs(stripe) * 0.4, p.c(0xFFFFFF).opacity(0.85))
        }
        p.ellipse(x, base - 46, 34, 8, p.c(0xFFFFFF))
        p.rect(x - 3, base - 46, 6, 46, p.c(0x8D92AB))
        p.rect(x - 14, base - 3, 28, 4, p.c(0x8D92AB), r: 2)
        for side in [-1.0, 1.0] as [CGFloat] {
            let cx = x + side * 48
            p.rect(cx - 12, base - 34, 24, 6, p.c(0xD39A62), r: 2)
            p.rect(cx + side * 9 - 2, base - 62, 4, 30, p.c(0xD39A62))
            p.rect(cx - 10, base - 28, 3, 28, p.c(0x8D92AB))
            p.rect(cx + 7, base - 28, 3, 28, p.c(0x8D92AB))
        }
        p.rect(x - 8, base - 60, 12, 12, p.c(0xFFFFFF), r: 3)
        p.stroke(Path(ellipseIn: CGRect(x: x + 3, y: base - 57, width: 5, height: 6)), p.c(0xFFFFFF), width: 1.6)
    }

    private func steam() {
        for (index, x) in ([94.0, 298.0] as [CGFloat]).enumerated() {
            for wisp in 0..<2 {
                let phase = (p.time * 0.5 + Double(index) * 0.3 + Double(wisp) * 0.5).truncatingRemainder(dividingBy: 1)
                let y = ground + 110 - 62 - CGFloat(phase) * 26
                var path = Path()
                path.move(to: CGPoint(x: x + CGFloat(wisp) * 5, y: y))
                path.addCurve(
                    to: CGPoint(x: x + CGFloat(wisp) * 5, y: y - 14),
                    control1: CGPoint(x: x + 5 + CGFloat(wisp) * 5, y: y - 4),
                    control2: CGPoint(x: x - 5 + CGFloat(wisp) * 5, y: y - 10)
                )
                p.stroke(path, p.c(0xFFFFFF).opacity(0.85 * (1 - phase)), width: 2)
            }
        }
    }
}
