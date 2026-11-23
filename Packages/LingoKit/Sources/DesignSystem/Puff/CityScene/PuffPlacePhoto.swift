import ImageIO
import SwiftUI
import UIKit

/// 地点实拍的风格化版本：App 资源里的 `styled-place-<地点 ID>.webp`（天空已抠空）与
/// `styled-place-<地点 ID>-motion.png`（R=树叶、G=水面、B=远近），由
/// `Tools/ContentPipeline/stylize-place-scenes.py` 从十五城地点实拍生成。
final class PuffPlacePhoto: @unchecked Sendable {
    let image: UIImage
    let motion: UIImage
    /// 照片上方有被抠空的天空，背后需要画天空；室内场景没有。
    let hasSky: Bool

    init(image: UIImage, motion: UIImage, hasSky: Bool) {
        self.image = image
        self.motion = motion
        self.hasSky = hasSky
    }

    var cost: Int { Int(image.size.width * image.size.height * image.scale * image.scale * 4) }
}

enum PuffPlacePhotoLibrary {
    nonisolated static func url(for placeID: String) -> URL? {
        guard !placeID.isEmpty, !placeID.contains("/"), !placeID.contains("..") else { return nil }
        return Bundle.main.url(forResource: "styled-place-\(placeID)", withExtension: "webp")
    }

    @MainActor private static let cache: NSCache<NSString, PuffPlacePhoto> = {
        let cache = NSCache<NSString, PuffPlacePhoto>()
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()

    @MainActor private static var loads: [String: Task<PuffPlacePhoto?, Never>] = [:]

    @MainActor static func cached(_ placeID: String) -> PuffPlacePhoto? {
        cache.object(forKey: placeID as NSString)
    }

    /// 在后台解码，同一地点同时只解一次。
    @MainActor static func load(_ placeID: String) async -> PuffPlacePhoto? {
        if let hit = cached(placeID) { return hit }
        let task = loads[placeID] ?? Task.detached(priority: .userInitiated) { decode(placeID) }
        loads[placeID] = task
        let result = await task.value
        loads[placeID] = nil
        if let result {
            cache.setObject(result, forKey: placeID as NSString, cost: result.cost)
        }
        return result
    }

    private nonisolated static func decode(_ placeID: String) -> PuffPlacePhoto? {
        guard let url = url(for: placeID),
              let motionURL = Bundle.main.url(forResource: "styled-place-\(placeID)-motion", withExtension: "png"),
              let image = decodeImage(url),
              let motion = decodeImage(motionURL) else { return nil }
        return PuffPlacePhoto(image: UIImage(cgImage: image), motion: UIImage(cgImage: motion), hasSky: hasTransparentTop(image))
    }

    private nonisolated static func decodeImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// 缩到 16×32 看上方四分之一有没有透明像素。
    private nonisolated static func hasTransparentTop(_ image: CGImage) -> Bool {
        let width = 16, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return true }
        for row in 0..<(height / 4) {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] < 128 {
                return true
            }
        }
        return false
    }
}

/// 照片版地点场景：背后是按当地时间变化的手绘天空和慢慢飘的云，前面是风格化照片，
/// 树叶随风轻摇、水面起波光，镜头缓慢漂移带出远近视差。
struct PuffPlacePhotoScene: View {
    let placeID: String
    let kind: PuffPlaceScene.Kind
    let seed: Int
    let mood: PuffSceneMood
    let clock: DateComponents
    let isPaused: Bool
    @State private var loaded: (id: String, photo: PuffPlacePhoto?)?

    var body: some View {
        let current = (loaded?.id == placeID ? loaded?.photo : nil) ?? PuffPlacePhotoLibrary.cached(placeID)
        GeometryReader { proxy in
            ZStack {
                if current?.hasSky ?? true {
                    PuffPlacePhotoSky(kind: kind, seed: seed, mood: mood, clock: clock, isPaused: isPaused)
                } else {
                    Puff.Palette.page
                }
                if let current {
                    PuffLivingPhotoLayer(photo: current, size: proxy.size, mood: mood, isPaused: isPaused)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: placeID) {
            guard loaded?.id != placeID else { return }
            let photo = await PuffPlacePhotoLibrary.load(placeID)
            withAnimation(.easeOut(duration: 0.2)) { loaded = (placeID, photo) }
        }
    }
}

/// 照片背后的天空：静态的渐变与日月只在时段变化时重画，云、星星和飞鸟逐帧画。
private struct PuffPlacePhotoSky: View {
    let kind: PuffPlaceScene.Kind
    let seed: Int
    let mood: PuffSceneMood
    let clock: DateComponents
    let isPaused: Bool

    private struct Key: Equatable {
        let mood: PuffSceneMood
        let seed: Int
    }

    var body: some View {
        ZStack {
            PuffStaticCanvas(key: Key(mood: mood, seed: seed)) { context, size in
                draw(context, size, time: 0) { stage, _ in stage.sky() }
            }
            .equatable()
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused)) { timeline in
                // 云按完整时间平移，不取模，避免回绕时整片云跳位。
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: true) { context, size in
                    draw(context, size, time: time) { _, painter in
                        painter.stars()
                        painter.softClouds(height: size.height / (size.width / PuffPlaceSceneCanvas.width), seed: seed)
                        var birds = painter.ctx
                        birds.translateBy(x: -80, y: size.height / (size.width / PuffPlaceSceneCanvas.width) * 0.12)
                        PuffScenePainter(ctx: birds, mood: mood, time: time, clock: clock).birds()
                    }
                }
            }
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize, time: TimeInterval,
                      _ body: (PuffPlaceStage, PuffScenePainter) -> Void) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = size.width / PuffPlaceSceneCanvas.width
        var context = context
        context.scaleBy(x: scale, y: scale)
        let painter = PuffScenePainter(ctx: context, mood: mood, time: time, clock: clock)
        body(PuffPlaceStage(painter: painter, kind: kind, seed: seed, height: size.height / scale), painter)
    }
}

/// 风格化照片本身：着色器负责树叶、水面和视差，时段用整体染色表现（黄昏偏暖、夜里偏蓝变暗）。
private struct PuffLivingPhotoLayer: View {
    let photo: PuffPlacePhoto
    let size: CGSize
    let mood: PuffSceneMood
    let isPaused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 照片比画面略大，镜头漂移时边缘不露底。
    private static let overscan: CGFloat = 1.06
    private static let shaders = ShaderLibrary.bundle(.module)

    /// 室外夜里偏蓝变暗像月光；室内灯光仍亮，只略微压暗。
    private var tint: Color {
        switch (mood, photo.hasSky) {
        case (.day, _): .white
        case (.dusk, true): Color(red: 1, green: 0.87, blue: 0.8)
        case (.dusk, false): Color(red: 1, green: 0.94, blue: 0.88)
        case (.night, true): Color(red: 0.42, green: 0.47, blue: 0.74)
        case (.night, false): Color(red: 0.8, green: 0.8, blue: 0.9)
        }
    }

    var body: some View {
        let frame = CGSize(width: size.width * Self.overscan, height: size.height * Self.overscan)
        let imageSize = photo.image.size
        let fill = max(frame.width / max(imageSize.width, 1), frame.height / max(imageSize.height, 1))
        let drawn = CGRect(
            x: (frame.width - imageSize.width * fill) / 2, y: (frame.height - imageSize.height * fill) / 2,
            width: imageSize.width * fill, height: imageSize.height * fill
        )
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused || reduceMotion)) { timeline in
            // 漂移和微尘用完整的双精度时间，不取模，永不回跳；着色器的时间对 600 取模（见 puffLivingPhoto）。
            let seconds = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let time = seconds.truncatingRemainder(dividingBy: 600)
            let drift = CGSize(width: sin(seconds * 2 * .pi / 17) * 5, height: sin(seconds * 2 * .pi / 23) * 1.6)
            ZStack {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .colorMultiply(tint)
                    .layerEffect(
                        Self.shaders.puffLivingPhoto(
                            .float4(Float(drawn.minX), Float(drawn.minY), Float(drawn.width), Float(drawn.height)),
                            .float(Float(time)),
                            .image(Image(uiImage: photo.motion)),
                            .float2(Float(drift.width), Float(drift.height)),
                            .float(1)
                        ),
                        maxSampleOffset: CGSize(width: 10, height: 10),
                        isEnabled: !reduceMotion
                    )
                if !photo.hasSky && !reduceMotion {
                    dustMotes(time: seconds).frame(width: frame.width, height: frame.height)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// 室内光里慢慢浮起的微尘。
    private func dustMotes(time: TimeInterval) -> some View {
        Canvas { context, canvas in
            for index in 0..<18 {
                let n1 = PuffScenePainter.noise(index * 17 + 3)
                let n2 = PuffScenePainter.noise(index * 29 + 5)
                let n3 = PuffScenePainter.noise(index * 41 + 11)
                let speed = 5 + n3 * 7
                let rise = (n2 + CGFloat(time) * speed / canvas.height).truncatingRemainder(dividingBy: 1)
                let x = n1 * canvas.width + CGFloat(sin(time * 0.4 + Double(index))) * 12
                let y = canvas.height * (1 - rise)
                let radius = 1.2 + n3 * 2
                let glow = 0.14 + 0.2 * pow(sin(time * 0.8 + Double(index)), 2)
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(Color(red: 1, green: 0.96, blue: 0.86).opacity(glow)))
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

extension PuffScenePainter {
    /// 照片背后的柔边云：几团叠在一起，上亮下带天色阴影，边缘轻微虚化。
    /// 坐标宽 390，`height` 为画面高度。
    func softClouds(height: CGFloat, seed: Int) {
        let specs: [(x: CGFloat, y: CGFloat, scale: CGFloat, speed: Double)] = [
            (20, 0.07, 1.3, 2.2), (230, 0.13, 0.95, 3.0), (120, 0.22, 0.75, 3.8),
            (320, 0.29, 1.05, 2.6), (40, 0.36, 0.62, 4.4),
        ]
        let span: CGFloat = 390 + 260
        let shadow = atmosphere.cloud.mixed(with: atmosphere.skyTop, 0.45).mixed(with: SceneInk(0x8E9BC8), 0.12)
        for (index, spec) in specs.enumerated() {
            let start = spec.x + Self.noise(seed + index * 37) * 90
            let travelled = CGFloat((time * spec.speed).truncatingRemainder(dividingBy: Double(span)))
            var x = start + travelled
            if x > 390 + 130 { x -= span }
            let y = height * spec.y + Self.noise(seed + index * 41) * 14
            softCloud(x, y, spec.scale, seed: seed + index * 7, shadow: shadow)
        }
    }

    private func softCloud(_ x: CGFloat, _ y: CGFloat, _ scale: CGFloat, seed: Int, shadow: SceneInk) {
        var path = Path()
        let puffs = 6
        for index in 0..<puffs {
            let t = CGFloat(index) / CGFloat(puffs - 1)
            let radius = (11 + Self.noise(seed + index * 13) * 10) * scale * (1 - abs(t - 0.45) * 0.7)
            let cx = x + (t - 0.5) * 70 * scale
            let cy = y - radius * 0.55 + Self.noise(seed + index * 5) * 4 * scale
            path.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        }
        path.addRoundedRect(in: CGRect(x: x - 40 * scale, y: y - 6 * scale, width: 80 * scale, height: 12 * scale),
                            cornerSize: CGSize(width: 6 * scale, height: 6 * scale))
        let bounds = path.boundingRect
        var layer = ctx
        layer.opacity = atmosphere.cloudOpacity
        layer.addFilter(.blur(radius: 1.4 * scale))
        layer.fill(path, with: .linearGradient(
            Gradient(colors: [atmosphere.cloud.color, atmosphere.cloud.color, shadow.color]),
            startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
            endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
        ))
    }
}
