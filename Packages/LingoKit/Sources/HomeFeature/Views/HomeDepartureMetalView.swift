@preconcurrency import MetalKit
@preconcurrency import MetalPerformanceShaders
import DesignSystem
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
    var camera: CGSize = .zero

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
        context.coordinator.setCamera(camera)
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

        func setCamera(_ camera: CGSize) {
            renderer?.camera = camera
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
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc
        private func stepAnimation(_ link: CADisplayLink) {
            let previous = previousTimestamp ?? link.timestamp
            let delta = min(max(link.timestamp - previous, 1.0 / 120.0), 1.0 / 30.0)
            previousTimestamp = link.timestamp
            var isSettled = true

            for entry in HomeSceneEntryID.allCases {
                let target: CGFloat = entry == pressedEntry ? 1 : 0
                var value = pressAmounts[entry, default: 0]
                var velocity = pressVelocities[entry, default: 0]

                // 与“我的”页读取相同的按下与回弹参数。较短回弹在 60 Hz 设备上
                // 通过子步积分保持稳定，同时仍能从当前速度无缝反向。
                let response = CGFloat(
                    target > 0
                        ? DSSceneEntranceMotion.pressResponse
                        : DSSceneEntranceMotion.releaseDuration
                )
                let damping = CGFloat(
                    target > 0
                        ? DSSceneEntranceMotion.pressDampingFraction
                        : 1 - DSSceneEntranceMotion.releaseBounce
                )
                let angularFrequency = 2 * CGFloat.pi / response
                let stepCount = max(1, Int(ceil(delta / (1.0 / 240.0))))
                let stepDuration = CGFloat(delta) / CGFloat(stepCount)
                for _ in 0..<stepCount {
                    let acceleration = angularFrequency * angularFrequency * (target - value)
                        - 2 * damping * angularFrequency * velocity
                    velocity += acceleration * stepDuration
                    value += velocity * stepDuration
                }
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
    /// 首页锚点所在的浅墙面/反光地板比“我的”页深色实物更容易显得过曝。
    /// 保持共用材质的半径、颜色与内外光比例，仅做统一的场景曝光补偿。
    private static let sceneGlowExposure: Float = 0.10
    private static let sceneEdgeLightExposure: Float = 0.50

    private struct VertexUniforms {
        var homographyColumn0: SIMD4<Float>
        var homographyColumn1: SIMD4<Float>
        var homographyColumn2: SIMD4<Float>
        var region: SIMD4<Float>
        var transform: SIMD4<Float>
        var spatialCamera: SIMD4<Float>
    }

    private struct FragmentUniforms {
        var tint: SIMD4<Float>
        var parameters: SIMD4<Float>
    }

    private struct ArtworkTextures {
        let face: MTLTexture
        let blurredByRadius: [CGFloat: MTLTexture]

        func blurred(radius: CGFloat) -> MTLTexture {
            blurredByRadius[radius] ?? face
        }
    }

    private struct Item {
        let entry: HomeSceneEntryID?
        let region: HomeProjectedRegion
        let textures: ArtworkTextures
        let footprintOffset: CGSize
        let extrusionOffset: CGSize
        let material: DSHologramEffectMetrics
    }

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    private let device: MTLDevice
    private var items: [Item] = []
    var pressAmounts: [HomeSceneEntryID: CGFloat] = [:]
    var camera = CGSize.zero

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
        // 地面入口处于明显斜视角；各向异性过滤能保住笔画横纵方向的同等锐度。
        samplerDescriptor.maxAnisotropy = 8
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }

        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.sampler = sampler
        self.device = device
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
           let textures = makeTextures(
               image: HomePerspectiveArtwork.location(
                   flag: flag,
                   cityName: cityName,
                   size: layout.location.renderSize
               ),
               material: DSHologramMaterial.text
           )
        {
            nextItems.append(Item(
                entry: nil,
                region: layout.location.projectedRegion(),
                textures: textures,
                footprintOffset: CGSize(width: 1.4, height: 3.0),
                extrusionOffset: CGSize(width: 0.30, height: 0.75),
                material: DSHologramMaterial.text
            ))
        }

        append(
            entry: .map,
            artwork: HomePerspectiveArtwork.entryLayers(
                symbol: "map",
                title: "世界地图",
                subtitle: nil,
                size: layout.map.renderSize,
                iconSize: 34,
                titleSize: 20
            ),
            layout: layout.map,
            footprintOffset: CGSize(width: -2.4, height: 4.8),
            extrusionOffset: CGSize(width: -0.40, height: 0.95),
            to: &nextItems
        )
        append(
            entry: .story,
            artwork: HomePerspectiveArtwork.entryLayers(
                symbol: "book.pages",
                title: "剧情",
                subtitle: storySubtitle,
                size: layout.story.renderSize,
                iconSize: 36,
                titleSize: 21
            ),
            layout: layout.story,
            footprintOffset: CGSize(width: -2.0, height: 5.6),
            extrusionOffset: CGSize(width: -0.35, height: 1.05),
            to: &nextItems
        )
        append(
            entry: .activities,
            artwork: HomePerspectiveArtwork.entryLayers(
                symbol: "figure.walk.motion",
                title: "城市活动",
                subtitle: nil,
                size: layout.activities.renderSize,
                iconSize: 35,
                titleSize: 20
            ),
            layout: layout.activities,
            footprintOffset: CGSize(width: 3.2, height: 5.8),
            extrusionOffset: CGSize(width: 0.50, height: 1.10),
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
            draw(item: item, press: press, canvasSize: view.bounds.size, encoder: encoder)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func append(
        entry: HomeSceneEntryID,
        artwork: [HomePerspectiveArtworkLayer],
        layout: HomeDepartureHotspotLayout,
        footprintOffset: CGSize,
        extrusionOffset: CGSize,
        to items: inout [Item]
    ) {
        let region = layout.projectedRegion()
        for layer in artwork {
            guard let textures = makeTextures(image: layer.image, material: layer.material) else { continue }
            items.append(Item(
                entry: entry,
                region: region,
                textures: textures,
                footprintOffset: footprintOffset,
                extrusionOffset: extrusionOffset,
                material: layer.material
            ))
        }
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

    /// SwiftUI 的 shadow 使用连续高斯核。这里在内容变化时一次性生成同半径的
    /// 模糊纹理，避免在每一帧用稀疏采样近似，后者在大半径下会显出多个字形副本。
    private func makeTextures(
        image: UIImage,
        material: DSHologramEffectMetrics
    ) -> ArtworkTextures? {
        guard let face = makeTexture(image),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return nil
        }

        let radii: Set<CGFloat> = [
            DSHologramMaterial.footprintRadius,
            DSHologramMaterial.extrusionRadius,
            material.depthEdgeRadius,
            material.outerGlowRadius,
            material.innerGlowRadius,
            material.edgeLightRadius,
        ]
        var blurredByRadius: [CGFloat: MTLTexture] = [:]
        for radius in radii {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: face.pixelFormat,
                width: face.width,
                height: face.height,
                mipmapped: false
            )
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let blurred = device.makeTexture(descriptor: descriptor) else { return nil }
            blurred.label = "Home hologram gaussian \(radius)pt"
            MPSImageGaussianBlur(device: device, sigma: Float(radius * 3)).encode(
                commandBuffer: commandBuffer,
                sourceTexture: face,
                destinationTexture: blurred
            )
            blurredByRadius[radius] = blurred
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        return ArtworkTextures(face: face, blurredByRadius: blurredByRadius)
    }

    private func draw(
        item: Item,
        press: CGFloat,
        canvasSize: CGSize,
        encoder: MTLRenderCommandEncoder
    ) {
        let homography = item.region.surface.homography
        let pressedScale = Float(1 - press * (1 - DSSceneEntranceMotion.pressedScale))
        let pressedOffset = press * DSSceneEntranceMotion.pressedOffset
        let shadowCompression = 1 - press * 0.72
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
            transform: SIMD4(
                pressedScale,
                0,
                Float(pressedOffset / max(canvasSize.height, 1)),
                0
            ),
            spatialCamera: SIMD4(Float(camera.width / max(canvasSize.width, 1)),
                                 Float(camera.height / max(canvasSize.height, 1)),
                                 0, 0)
        )
        // DSHologramSurface 的大半径落影。低透明度只负责说明标牌离开了承载面，
        // 不再用一份偏移的完整字形模拟深度。
        drawEffect(
            vertex: &vertex,
            offset: item.footprintOffset.scaled(by: shadowCompression),
            canvasSize: canvasSize,
            color: SIMD3(0, 0, 0),
            opacity: Float(DSHologramMaterial.footprintOpacity),
            radius: DSHologramMaterial.footprintRadius,
            textures: item.textures,
            press: press,
            encoder: encoder
        )

        // 极薄的挤出边与文字/图标自身的深色接触边共同建立实体厚度。
        drawEffect(
            vertex: &vertex,
            offset: item.extrusionOffset.scaled(by: shadowCompression),
            canvasSize: canvasSize,
            color: SIMD3(0, 0, 0),
            opacity: Float(DSHologramMaterial.extrusionOpacity),
            radius: DSHologramMaterial.extrusionRadius,
            textures: item.textures,
            press: press,
            encoder: encoder
        )
        drawEffect(
            vertex: &vertex,
            offset: item.material.depthEdgeOffset,
            canvasSize: canvasSize,
            color: SIMD3(0, 0, 0),
            opacity: Float(item.material.depthEdgeOpacity),
            radius: item.material.depthEdgeRadius,
            textures: item.textures,
            press: press,
            encoder: encoder
        )

        // 与“我的”页相同的两级溢光：外层宽而淡，内层窄而克制。它们都先于
        // 不透明核心绘制，所以不会把笔画正面洗亮、洗糊。
        let glowColor = SIMD3(
            Float(DSHologramMaterial.glowRed),
            Float(DSHologramMaterial.glowGreen),
            Float(DSHologramMaterial.glowBlue)
        )
        drawEffect(
            vertex: &vertex,
            offset: .zero,
            canvasSize: canvasSize,
            color: glowColor,
            opacity: Float(item.material.outerGlowOpacity) * Self.sceneGlowExposure,
            radius: item.material.outerGlowRadius,
            textures: item.textures,
            press: press,
            encoder: encoder
        )
        drawEffect(
            vertex: &vertex,
            offset: .zero,
            canvasSize: canvasSize,
            color: glowColor,
            opacity: Float(item.material.innerGlowOpacity) * Self.sceneGlowExposure,
            radius: item.material.innerGlowRadius,
            textures: item.textures,
            press: press,
            encoder: encoder
        )
        drawEffect(
            vertex: &vertex,
            offset: item.material.edgeLightOffset,
            canvasSize: canvasSize,
            color: SIMD3(1, 1, 1),
            opacity: Float(item.material.edgeLightOpacity) * Self.sceneEdgeLightExposure,
            radius: item.material.edgeLightRadius,
            textures: item.textures,
            press: press,
            encoder: encoder
        )

        vertex.transform.y = 0
        vertex.transform.z = Float(pressedOffset / max(canvasSize.height, 1))
        encoder.setVertexBytes(&vertex, length: MemoryLayout<VertexUniforms>.stride, index: 0)
        encoder.setFragmentTexture(item.textures.face, index: 0)
        var face = FragmentUniforms(
            tint: SIMD4(1, 1, 1, 1),
            parameters: SIMD4(
                0,
                Float(DSHologramMaterial.coreOpacity)
                    * Float(1 - press * (1 - DSSceneEntranceMotion.pressedOpacity)),
                0,
                -0.28
            )
        )
        encoder.setFragmentBytes(&face, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func drawEffect(
        vertex: inout VertexUniforms,
        offset: CGSize,
        canvasSize: CGSize,
        color: SIMD3<Float>,
        opacity: Float,
        radius: CGFloat,
        textures: ArtworkTextures,
        press: CGFloat,
        encoder: MTLRenderCommandEncoder
    ) {
        vertex.transform.y = Float(offset.width / max(canvasSize.width, 1))
        vertex.transform.z = Float(
            (offset.height + press * DSSceneEntranceMotion.pressedOffset)
                / max(canvasSize.height, 1)
        )
        encoder.setVertexBytes(&vertex, length: MemoryLayout<VertexUniforms>.stride, index: 0)
        encoder.setFragmentTexture(textures.blurred(radius: radius), index: 0)
        var effect = FragmentUniforms(
            tint: SIMD4(color.x, color.y, color.z, opacity),
            parameters: SIMD4(1, Float(1 - press * 0.18), 0, 0)
        )
        encoder.setFragmentBytes(&effect, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
}

private extension CGSize {
    func scaled(by factor: CGFloat) -> CGSize {
        CGSize(width: width * factor, height: height * factor)
    }
}

private struct HomePerspectiveArtworkLayer {
    let image: UIImage
    let material: DSHologramEffectMetrics
}

@MainActor
private enum HomePerspectiveArtwork {
    private static let warmWhite = UIColor(
        red: CGFloat(DSHologramMaterial.coreRed),
        green: CGFloat(DSHologramMaterial.coreGreen),
        blue: CGFloat(DSHologramMaterial.coreBlue),
        alpha: 1
    )

    static func entryLayers(
        symbol: String,
        title: String,
        subtitle: String?,
        size: CGSize,
        iconSize: CGFloat,
        titleSize: CGFloat
    ) -> [HomePerspectiveArtworkLayer] {
        let iconConfiguration = UIImage.SymbolConfiguration(
            pointSize: iconSize,
            weight: .medium,
            scale: .medium
        )
        let icon = UIImage(systemName: symbol, withConfiguration: iconConfiguration)
            ?? UIImage(systemName: "circle", withConfiguration: iconConfiguration)
        let tintedIcon = icon?.withTintColor(warmWhite, renderingMode: .alwaysOriginal)
        let titleFont = roundedFont(size: titleSize, weight: .bold)
        let subtitleFont = roundedFont(size: 11, weight: .semibold)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: warmWhite,
            .kern: -0.45,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: warmWhite,
            .kern: 0.08,
        ]
        let titleMeasured = (title as NSString).size(withAttributes: titleAttributes)
        let subtitleMeasured = subtitle.map { ($0 as NSString).size(withAttributes: subtitleAttributes) }
        let iconMeasured = tintedIcon?.size ?? CGSize(width: iconSize, height: iconSize)
        let totalHeight = iconMeasured.height + 5 + titleMeasured.height
            + (subtitleMeasured.map { 2 + $0.height } ?? 0)
        let iconY = (size.height - totalHeight) / 2
        let titleY = iconY + iconMeasured.height + 5

        let iconLayer = render(size: size) { _ in
            if let tintedIcon {
                tintedIcon.draw(
                    in: CGRect(
                        x: (size.width - iconMeasured.width) / 2,
                        y: iconY,
                        width: iconMeasured.width,
                        height: iconMeasured.height
                    )
                )
            }
        }
        let textLayer = render(size: size) { _ in
            (title as NSString).draw(
                at: CGPoint(x: (size.width - titleMeasured.width) / 2, y: titleY),
                withAttributes: titleAttributes
            )
            if let subtitle, let subtitleMeasured {
                (subtitle as NSString).draw(
                    at: CGPoint(
                        x: (size.width - subtitleMeasured.width) / 2,
                        y: titleY + titleMeasured.height + 2
                    ),
                    withAttributes: subtitleAttributes
                )
            }
        }
        return [
            HomePerspectiveArtworkLayer(image: iconLayer, material: DSHologramMaterial.sceneIcon),
            HomePerspectiveArtworkLayer(image: textLayer, material: DSHologramMaterial.text),
        ]
    }

    static func location(flag: String, cityName: String, size: CGSize) -> UIImage {
        render(size: size) { _ in
            let cityFont = roundedFont(size: 20, weight: .bold)
            let captionFont = roundedFont(size: 11, weight: .regular)
            let cityAttributes: [NSAttributedString.Key: Any] = [
                .font: cityFont,
                .foregroundColor: warmWhite,
                .kern: -0.45,
            ]
            let captionAttributes: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: warmWhite,
                .kern: 0.08,
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
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setAllowsAntialiasing(true)
            context.cgContext.setShouldAntialias(true)
            context.cgContext.setShouldSmoothFonts(true)
            context.cgContext.interpolationQuality = .high
            actions(context)
        }
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
