@preconcurrency import MetalKit
import SwiftUI

/// 原图纹理只上传一次；静止不持续绘制，拖动仅更新两个相机参数。
struct MyPageSpatialPhoto: UIViewRepresentable {
    let assetName: String
    let camera: CGSize
    let onReady: (Bool) -> Void

    func makeCoordinator() -> Renderer { Renderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isUserInteractionEnabled = false
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        context.coordinator.install(view, assetName: assetName)
        let ready = context.coordinator.isReady
        DispatchQueue.main.async { onReady(ready) }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.camera = camera
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.delegate = nil
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        var camera = CGSize.zero
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var texture: MTLTexture?
        private var vertices: MTLBuffer?
        private var vertexCount = 0
        var isReady: Bool { pipeline != nil && texture != nil && vertices != nil && queue != nil }

        func install(_ view: MTKView, assetName: String) {
            guard let device = view.device,
                  let library = try? device.makeDefaultLibrary(bundle: .main),
                  let vertex = library.makeFunction(name: "deskSpatialVertex"),
                  let fragment = library.makeFunction(name: "deskSpatialFragment"),
                  let image = UIImage(named: assetName)?.cgImage else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
                  let texture = try? MTKTextureLoader(device: device).newTexture(
                    cgImage: image, options: [.SRGB: true, .origin: MTKTextureLoader.Origin.topLeft]
                  ) else { return }
            self.pipeline = pipeline
            self.texture = texture
            queue = device.makeCommandQueue()
            // 约 4 pt 间距，细化轮廓过渡；三角形共享相同采样，避免接缝。
            let columns = 100
            let rows = 232
            var mesh: [SIMD4<Float>] = []
            mesh.reserveCapacity(columns * rows * 6)
            func sample(_ x: Int, _ y: Int) -> SIMD4<Float> {
                let point = CGPoint(x: CGFloat(x) / CGFloat(columns), y: CGFloat(y) / CGFloat(rows))
                return SIMD4(Float(point.x), Float(point.y), Float(MyPageSpatialGeometry.depth(at: point)), 0)
            }
            let samples = (0...rows).flatMap { y in (0...columns).map { x in sample(x, y) } }
            for y in 0..<rows {
                for x in 0..<columns {
                    let index = y * (columns + 1) + x
                    let a = samples[index], b = samples[index + 1]
                    let c = samples[index + columns + 1], d = samples[index + columns + 2]
                    mesh.append(contentsOf: [a, b, c, c, b, d])
                }
            }
            vertexCount = mesh.count
            vertices = device.makeBuffer(bytes: mesh, length: mesh.count * MemoryLayout<SIMD4<Float>>.stride)
            view.delegate = self
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let texture, let vertices,
                  let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let command = queue?.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            var uniforms = SIMD4<Float>(
                Float(camera.width / MyPageSpatialGeometry.size.width),
                Float(camera.height / MyPageSpatialGeometry.size.height), 0, 0
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}
