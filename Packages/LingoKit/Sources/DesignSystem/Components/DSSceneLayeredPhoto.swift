@preconcurrency import MetalKit
import SwiftUI

/// 刚性图层视差与一次性窄带微补全。拖动时只更新各层位置，不重新生成背景。
public struct DSSceneLayeredPhoto: UIViewRepresentable {
    let assetName: String
    let camera: CGSize
    let size: CGSize
    let backgroundDepth: CGFloat
    let layers: [DSSceneParallaxLayer]
    let onReady: (Bool) -> Void

    public init(assetName: String, camera: CGSize, size: CGSize, backgroundDepth: CGFloat,
                layers: [DSSceneParallaxLayer], onReady: @escaping (Bool) -> Void) {
        self.assetName = assetName
        self.camera = camera
        self.size = size
        self.backgroundDepth = backgroundDepth
        self.layers = layers
        self.onReady = onReady
    }

    public func makeCoordinator() -> Renderer { Renderer() }
    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isUserInteractionEnabled = false
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        context.coordinator.install(view, assetName: assetName, layers: layers)
        let ready = context.coordinator.isReady
        DispatchQueue.main.async { onReady(ready) }
        return view
    }
    public func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.camera = camera
        context.coordinator.size = size
        context.coordinator.backgroundDepth = backgroundDepth
        view.setNeedsDisplay()
    }
    public static func dismantleUIView(_ view: MTKView, coordinator: Renderer) { view.delegate = nil }

    @MainActor
    public final class Renderer: NSObject, MTKViewDelegate {
        struct Uniforms {
            var region: SIMD4<Float>
            var motion: SIMD4<Float>
            var mask: SIMD4<Float>
        }
        var camera = CGSize.zero
        var size = CGSize(width: 402, height: 929)
        var backgroundDepth: CGFloat = 0
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var original: MTLTexture?
        private var repaired: MTLTexture?
        private var points: MTLBuffer?
        private var contourRanges: MTLBuffer?
        private var layers: [DSSceneParallaxLayer] = []
        private var masks: [SIMD4<Float>] = []
        var isReady: Bool { pipeline != nil && repaired != nil && original != nil && points != nil && contourRanges != nil }

        func install(_ view: MTKView, assetName: String, layers: [DSSceneParallaxLayer]) {
            guard !layers.isEmpty, layers.allSatisfy({ $0.contours.allSatisfy { $0.count >= 3 } }),
                  let device = view.device, let queue = device.makeCommandQueue(),
                  let library = try? device.makeDefaultLibrary(bundle: .main),
                  let vertex = library.makeFunction(name: "sceneParallaxVertex"),
                  let fragment = library.makeFunction(name: "sceneParallaxFragment"),
                  let repair = library.makeFunction(name: "sceneParallaxRepair"),
                  let image = UIImage(named: assetName)?.cgImage else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = view.colorPixelFormat
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
                  let compute = try? device.makeComputePipelineState(function: repair),
                  let original = try? MTKTextureLoader(device: device).newTexture(
                    cgImage: image, options: [.SRGB: true, .origin: MTKTextureLoader.Origin.topLeft]
                  ) else { return }
            var allPoints: [SIMD2<Float>] = []
            var ranges: [SIMD2<UInt32>] = []
            for layer in layers {
                masks.append(SIMD4(Float(ranges.count), Float(layer.contours.count), layer.inverted ? 1 : 0, 1))
                for contour in layer.contours {
                    ranges.append(SIMD2(UInt32(allPoints.count), UInt32(contour.count)))
                    allPoints += contour.map { SIMD2(Float($0.x), Float($0.y)) }
                }
            }
            guard let points = device.makeBuffer(bytes: allPoints, length: allPoints.count * MemoryLayout<SIMD2<Float>>.stride),
                  let contourRanges = device.makeBuffer(bytes: ranges, length: ranges.count * MemoryLayout<SIMD2<UInt32>>.stride),
                  let maskBuffer = device.makeBuffer(bytes: masks, length: masks.count * MemoryLayout<SIMD4<Float>>.stride) else { return }
            let plate = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: original.width, height: original.height, mipmapped: false)
            plate.usage = [.shaderRead, .shaderWrite]
            plate.storageMode = .private
            guard let repaired = device.makeTexture(descriptor: plate),
                  let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { return }
            var count = UInt32(layers.count)
            encoder.setComputePipelineState(compute)
            encoder.setTexture(original, index: 0)
            encoder.setTexture(repaired, index: 1)
            encoder.setBuffer(points, offset: 0, index: 0)
            encoder.setBuffer(maskBuffer, offset: 0, index: 1)
            encoder.setBuffer(contourRanges, offset: 0, index: 3)
            encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)
            encoder.dispatchThreads(MTLSize(width: original.width, height: original.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            encoder.endEncoding()
            // 同一命令队列保证修补先于首帧完成，不在主线程等待 GPU。
            command.commit()
            self.queue = queue
            self.pipeline = pipeline
            self.original = original
            self.repaired = repaired
            self.points = points
            self.contourRanges = contourRanges
            self.layers = layers
            view.delegate = self
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        public func draw(in view: MTKView) {
            guard let pipeline, let original, let repaired, let points, let contourRanges,
                  let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let command = queue?.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBuffer(points, offset: 0, index: 1)
            encoder.setFragmentBuffer(contourRanges, offset: 0, index: 2)
            func draw(_ photo: MTLTexture, region: CGRect, depth: CGFloat, mask: SIMD4<Float>) {
                var u = Uniforms(region: SIMD4(Float(region.minX), Float(region.minY), Float(region.width), Float(region.height)),
                    motion: SIMD4(Float(camera.width * depth / max(size.width, 1)), Float(camera.height * depth / max(size.height, 1)), 0, 0),
                    mask: mask)
                encoder.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.setFragmentTexture(photo, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            let full = CGRect(x: 0, y: 0, width: 1, height: 1)
            // 零视点直接采样原图，静止像素不受分层抗锯齿或修补影响。
            if hypot(camera.width, camera.height) < 0.001 {
                draw(original, region: full, depth: 0, mask: .zero)
            } else {
                draw(repaired, region: full, depth: backgroundDepth, mask: .zero)
                for (index, layer) in layers.enumerated() {
                    let bounds = layer.bounds.insetBy(dx: -10 / CGFloat(original.width), dy: -10 / CGFloat(original.height))
                    draw(original, region: bounds, depth: layer.depth, mask: masks[index])
                }
            }
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}
