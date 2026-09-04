@preconcurrency import MetalKit
import SwiftUI
import UIKit

/// 使用照片平面单应矩阵绘制首页入口。每个位于同一物理平面的入口共享完全相同的
/// 投影矩阵，因此不会再出现各自手调角度造成的漂移。
@MainActor
struct HomeDepartureMetalView: UIViewRepresentable {
    let layout: HomeDepartureSceneLayout
    let flag: String?
    let cityName: String?
    let storySubtitle: String
    let pressedEntry: HomeSceneEntryID?
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MTKView(frame: .zero)
        }
        let view = MTKView(frame: .zero, device: device)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.sampleCount = 4
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.autoResizeDrawable = true
        context.coordinator.install(in: view, device: device)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(
            layout: layout,
            flag: flag,
            cityName: cityName,
            storySubtitle: storySubtitle,
            pressedEntry: pressedEntry,
            reduceMotion: reduceMotion
        )
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.stopAnimation()
        view.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private weak var view: MTKView?
        private var renderer: HomePerspectiveMetalRenderer?
        private var contentKey = ""
        private var pressedEntry: HomeSceneEntryID?
        private var pressAmounts: [HomeSceneEntryID: CGFloat] = [:]
        private var pressVelocities: [HomeSceneEntryID: CGFloat] = [:]
        private var displayLink: CADisplayLink?
        private var previousTimestamp: CFTimeInterval?
        private var reduceMotion = false

        func install(in view: MTKView, device: MTLDevice) {
            self.view = view
            renderer = HomePerspectiveMetalRenderer(device: device, sampleCount: view.sampleCount)
            view.delegate = self
        }

        func update(
            layout: HomeDepartureSceneLayout,
            flag: String?,
            cityName: String?,
            storySubtitle: String,
            pressedEntry: HomeSceneEntryID?,
            reduceMotion: Bool
        ) {
            let nextContentKey = [
                layout.assetName,
                flag ?? "",
                cityName ?? "",
                storySubtitle,
            ].joined(separator: "|")
            if nextContentKey != contentKey {
                contentKey = nextContentKey
                renderer?.replaceContent(
                    layout: layout,
                    flag: flag,
                    cityName: cityName,
                    storySubtitle: storySubtitle
                )
            }

            self.reduceMotion = reduceMotion
            guard pressedEntry != self.pressedEntry else { return }
            self.pressedEntry = pressedEntry
            if reduceMotion {
                for entry in HomeSceneEntryID.allCases {
                    pressAmounts[entry] = entry == pressedEntry ? 1 : 0
                    pressVelocities[entry] = 0
                }
                renderer?.pressAmounts = pressAmounts
            } else {
                startAnimationIfNeeded()
            }
        }

        func draw(in view: MTKView) {
            renderer?.draw(in: view)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func stopAnimation() {
            displayLink?.invalidate()
            displayLink = nil
            previousTimestamp = nil
        }

        private func startAnimationIfNeeded() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(stepAnimation(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc
        private func stepAnimation(_ link: CADisplayLink) {
            let previous = previousTimestamp ?? link.timestamp
            let delta = min(max(link.timestamp - previous, 1.0 / 120.0), 1.0 / 30.0)
            previousTimestamp = link.timestamp
            var isSettled = true

            // 临界阻尼弹簧：按下立即响应，松手后没有多余回摆；整个过程可随时被反向打断。
            let angularFrequency: CGFloat = 24
            for entry in HomeSceneEntryID.allCases {
                let target: CGFloat = entry == pressedEntry ? 1 : 0
                var value = pressAmounts[entry, default: 0]
                var velocity = pressVelocities[entry, default: 0]
                let acceleration = angularFrequency * angularFrequency * (target - value)
                    - 2 * angularFrequency * velocity
                velocity += acceleration * CGFloat(delta)
                value += velocity * CGFloat(delta)
                value = min(max(value, 0), 1)
                pressAmounts[entry] = value
                pressVelocities[entry] = velocity
                if abs(target - value) > 0.002 || abs(velocity) > 0.02 {
                    isSettled = false
                }
            }
            renderer?.pressAmounts = pressAmounts
            view?.setNeedsDisplay()
            if isSettled {
                stopAnimation()
            }
        }
    }
}

@MainActor
private final class HomePerspectiveMetalRenderer {
    private struct VertexUniforms {
        var homographyColumn0: SIMD4<Float>
        var homographyColumn1: SIMD4<Float>
        var homographyColumn2: SIMD4<Float>
        var region: SIMD4<Float>
        var transform: SIMD4<Float>
    }

    private struct FragmentUniforms {
        var tint: SIMD4<Float>
        var parameters: SIMD4<Float>
    }

    private struct Item {
        let entry: HomeSceneEntryID?
        let region: HomeProjectedRegion
        let texture: MTLTexture
        let shadowOffset: CGSize
        let shadowOpacity: Float
        let glowOpacity: Float
    }

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    private var items: [Item] = []
    var pressAmounts: [HomeSceneEntryID: CGFloat] = [:]

    init?(device: MTLDevice, sampleCount: Int) {
        guard let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .main),
              let vertex = library.makeFunction(name: "homePerspectiveVertex"),
              let fragment = library.makeFunction(name: "homePerspectiveFragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Home Perspective Pipeline"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.rasterSampleCount = sampleCount
        let attachment = descriptor.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }

        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.sampler = sampler
        textureLoader = MTKTextureLoader(device: device)
    }

    func replaceContent(
        layout: HomeDepartureSceneLayout,
        flag: String?,
        cityName: String?,
        storySubtitle: String
    ) {
        var nextItems: [Item] = []
        if let flag, let cityName,
           let texture = makeTexture(
               HomePerspectiveArtwork.location(
                   flag: flag,
                   cityName: cityName,
                   size: layout.location.renderSize
               )
           )
        {
            nextItems.append(Item(
                entry: nil,
                region: layout.location.projectedRegion(),
                texture: texture,
                shadowOffset: CGSize(width: 1.4, height: 3.0),
                shadowOpacity: 0.30,
                glowOpacity: 0.62
            ))
        }

        append(
            entry: .map,
            artwork: HomePerspectiveArtwork.entry(
                symbol: "map",
                title: "世界地图",
                subtitle: nil,
                size: layout.map.renderSize,
                iconSize: 34,
                titleSize: 20
            ),
            layout: layout.map,
            shadowOffset: CGSize(width: -2.4, height: 4.8),
            shadowOpacity: 0.37,
            glowOpacity: 0.76,
            to: &nextItems
        )
        append(
            entry: .story,
            artwork: HomePerspectiveArtwork.entry(
                symbol: "book.pages",
                title: "剧情",
                subtitle: storySubtitle,
                size: layout.story.renderSize,
                iconSize: 36,
                titleSize: 21
            ),
            layout: layout.story,
            shadowOffset: CGSize(width: -2.0, height: 5.6),
            shadowOpacity: 0.39,
            glowOpacity: 0.84,
            to: &nextItems
        )
        append(
            entry: .activities,
            artwork: HomePerspectiveArtwork.entry(
                symbol: "figure.walk.motion",
                title: "城市活动",
                subtitle: nil,
                size: layout.activities.renderSize,
                iconSize: 35,
                titleSize: 20
            ),
            layout: layout.activities,
            shadowOffset: CGSize(width: 3.2, height: 5.8),
            shadowOpacity: 0.41,
            glowOpacity: 0.90,
            to: &nextItems
        )
        items = nextItems
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }
        encoder.label = "Home Perspective Entries"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)

        for item in items {
            let press = item.entry.flatMap { pressAmounts[$0] } ?? 0
            draw(item: item, press: press, encoder: encoder)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func append(
        entry: HomeSceneEntryID,
        artwork: UIImage,
        layout: HomeDepartureHotspotLayout,
        shadowOffset: CGSize,
        shadowOpacity: Float,
        glowOpacity: Float,
        to items: inout [Item]
    ) {
        guard let texture = makeTexture(artwork) else { return }
        items.append(Item(
            entry: entry,
            region: layout.projectedRegion(),
            texture: texture,
            shadowOffset: shadowOffset,
            shadowOpacity: shadowOpacity,
            glowOpacity: glowOpacity
        ))
    }

    private func makeTexture(_ image: UIImage) -> MTLTexture? {
        guard let image = image.cgImage else { return nil }
        return try? textureLoader.newTexture(
            cgImage: image,
            options: [
                .SRGB: true,
                .origin: MTKTextureLoader.Origin.topLeft,
                .generateMipmaps: true,
            ]
        )
    }

    private func draw(item: Item, press: CGFloat, encoder: MTLRenderCommandEncoder) {
        let homography = item.region.surface.homography
        let pressedScale = Float(1 - press * 0.032)
        let shadowCompression = 1 - press * 0.72
        let offset = CGSize(
            width: item.shadowOffset.width * shadowCompression,
            height: item.shadowOffset.height * shadowCompression
        )
        var vertex = VertexUniforms(
            homographyColumn0: SIMD4(Float(homography.a), Float(homography.d), Float(homography.g), 0),
            homographyColumn1: SIMD4(Float(homography.b), Float(homography.e), Float(homography.h), 0),
            homographyColumn2: SIMD4(Float(homography.c), Float(homography.f), Float(homography.i), 0),
            region: SIMD4(
                Float(item.region.planeCenter.x),
                Float(item.region.planeCenter.y),
                Float(item.region.planeSize.width),
                Float(item.region.planeSize.height)
            ),
            transform: SIMD4(pressedScale, 0, 0, 0)
        )
        encoder.setVertexBytes(&vertex, length: MemoryLayout<VertexUniforms>.stride, index: 0)
        encoder.setFragmentTexture(item.texture, index: 0)

        vertex.transform.y = Float(offset.width / HomeDepartureCanvas.width)
        vertex.transform.z = Float(offset.height / HomeDepartureCanvas.height)
        encoder.setVertexBytes(&vertex, length: MemoryLayout<VertexUniforms>.stride, index: 0)
        var shadow = FragmentUniforms(
            tint: SIMD4(0.14, 0.085, 0.035, item.shadowOpacity),
            parameters: SIMD4(2, Float(1 - press * 0.24), 1.4, 0)
        )
        encoder.setFragmentBytes(&shadow, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        vertex.transform.y = 0
        vertex.transform.z = 0
        encoder.setVertexBytes(&vertex, length: MemoryLayout<VertexUniforms>.stride, index: 0)
        var glow = FragmentUniforms(
            tint: SIMD4(1.0, 0.74, 0.30, item.glowOpacity),
            parameters: SIMD4(1, Float(1 - press * 0.18), 3.2, 0)
        )
        encoder.setFragmentBytes(&glow, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        var face = FragmentUniforms(
            tint: SIMD4(1, 1, 1, 1),
            parameters: SIMD4(0, 1, 0, 0)
        )
        encoder.setFragmentBytes(&face, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
}

@MainActor
private enum HomePerspectiveArtwork {
    private static let warmWhite = UIColor(red: 1.0, green: 0.965, blue: 0.82, alpha: 1)

    static func entry(
        symbol: String,
        title: String,
        subtitle: String?,
        size: CGSize,
        iconSize: CGFloat,
        titleSize: CGFloat
    ) -> UIImage {
        render(size: size) { context in
            let iconConfiguration = UIImage.SymbolConfiguration(
                pointSize: iconSize,
                weight: .regular,
                scale: .medium
            )
            let icon = UIImage(systemName: symbol, withConfiguration: iconConfiguration)
                ?? UIImage(systemName: "circle", withConfiguration: iconConfiguration)
            let tintedIcon = icon?.withTintColor(warmWhite, renderingMode: .alwaysOriginal)
            let titleFont = roundedFont(size: titleSize, weight: .medium)
            let subtitleFont = roundedFont(size: 11, weight: .regular)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: warmWhite,
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: warmWhite.withAlphaComponent(0.94),
            ]
            let titleMeasured = (title as NSString).size(withAttributes: titleAttributes)
            let subtitleMeasured = subtitle.map { ($0 as NSString).size(withAttributes: subtitleAttributes) }
            let iconMeasured = tintedIcon?.size ?? CGSize(width: iconSize, height: iconSize)
            let totalHeight = iconMeasured.height + 5 + titleMeasured.height
                + (subtitleMeasured.map { 2 + $0.height } ?? 0)
            var y = (size.height - totalHeight) / 2

            if let tintedIcon {
                tintedIcon.draw(
                    in: CGRect(
                        x: (size.width - iconMeasured.width) / 2,
                        y: y,
                        width: iconMeasured.width,
                        height: iconMeasured.height
                    )
                )
            }
            y += iconMeasured.height + 5
            (title as NSString).draw(
                at: CGPoint(x: (size.width - titleMeasured.width) / 2, y: y),
                withAttributes: titleAttributes
            )
            if let subtitle, let subtitleMeasured {
                y += titleMeasured.height + 2
                (subtitle as NSString).draw(
                    at: CGPoint(x: (size.width - subtitleMeasured.width) / 2, y: y),
                    withAttributes: subtitleAttributes
                )
            }

            context.cgContext.setAllowsAntialiasing(true)
        }
    }

    static func location(flag: String, cityName: String, size: CGSize) -> UIImage {
        render(size: size) { _ in
            let cityFont = roundedFont(size: 20, weight: .medium)
            let captionFont = roundedFont(size: 11, weight: .regular)
            let cityAttributes: [NSAttributedString.Key: Any] = [
                .font: cityFont,
                .foregroundColor: warmWhite,
            ]
            let captionAttributes: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: warmWhite.withAlphaComponent(0.94),
            ]
            let flagAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20),
            ]
            let flagSize = (flag as NSString).size(withAttributes: flagAttributes)
            let citySize = (cityName as NSString).size(withAttributes: cityAttributes)
            let caption = "当前驻地"
            let captionSize = (caption as NSString).size(withAttributes: captionAttributes)
            let textWidth = max(citySize.width, captionSize.width)
            let totalWidth = flagSize.width + 7 + textWidth
            let startX = (size.width - totalWidth) / 2
            let textHeight = citySize.height + captionSize.height
            let textY = (size.height - textHeight) / 2
            (flag as NSString).draw(
                at: CGPoint(x: startX, y: (size.height - flagSize.height) / 2 - 1),
                withAttributes: flagAttributes
            )
            (cityName as NSString).draw(
                at: CGPoint(x: startX + flagSize.width + 7, y: textY),
                withAttributes: cityAttributes
            )
            (caption as NSString).draw(
                at: CGPoint(x: startX + flagSize.width + 7, y: textY + citySize.height - 1),
                withAttributes: captionAttributes
            )
        }
    }

    private static func render(size: CGSize, actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: actions)
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
