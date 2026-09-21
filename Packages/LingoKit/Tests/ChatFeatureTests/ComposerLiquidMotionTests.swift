import Testing
import simd
import Metal
@testable import ChatFeature

@Suite("输入面板水体运动")
struct ComposerLiquidMotionTests {
    @Test("Metal shader 编译与管线创建") @MainActor
    func shaderCompiles() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(source: ComposerLiquidRenderer.Coordinator.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "liquidVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "liquidFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        _ = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    @Test("实际 GPU 输出在极端倾斜下仍裁切于内壁，俯仰改变水面") @MainActor
    func renderedContainment() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(source: ComposerLiquidRenderer.Coordinator.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "liquidVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "liquidFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let queue = try #require(device.makeCommandQueue())
        let width = 390, height = 180
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: width, height: height, mipmapped: false)
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.renderTarget]
        let texture = try #require(device.makeTexture(descriptor: textureDescriptor))
        var previous: [UInt8]?
        for pitch: Float in [-1, 0, 1] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let command = try #require(queue.makeCommandBuffer())
            let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
            var uniforms: [SIMD4<Float>] = [.init(390, 180, 1.2, pitch), .init(0, 0, 1, 0), .zero]
            encoder.setRenderPipelineState(pipeline)
            uniforms.withUnsafeMutableBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            #expect(command.status == .completed)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes {
                texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                    from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            for y in 0..<height {
                for x in [0, 1, 2, width - 3, width - 2, width - 1] {
                    #expect(pixels[(y * width + x) * 4 + 3] == 0)
                }
            }
            #expect(pixels[(height / 2 * width + width / 2) * 4 + 3] == 255)
            if let previous { #expect(previous != pixels) }
            previous = pixels
        }
    }
    @Test("双轴极端输入保持有界并收敛")
    func boundedAndSettles() {
        var motion = ComposerLiquidMotion()
        motion.target = SIMD2(20, -20)
        for _ in 0..<600 {
            motion.advance(1.0 / 60)
            #expect(abs(motion.position.x) <= 1.2)
            #expect(abs(motion.position.y) <= 1.2)
        }
        #expect(motion.settled)
        #expect(motion.position == SIMD2(1, -1))
    }
    @Test("摇动后回稳且刷新率不改变运动结果")
    func frameRateIndependent() {
        var fast = ComposerLiquidMotion(), slow = ComposerLiquidMotion()
        fast.target = SIMD2(0.8, -0.6); slow.target = fast.target
        for _ in 0..<30 { fast.advance(1.0 / 60) }
        for _ in 0..<15 { slow.advance(1.0 / 30) }
        #expect(simd_length(fast.position - slow.position) < 0.01)
        fast.target = .zero
        for _ in 0..<300 { fast.advance(1.0 / 60) }
        #expect(fast.settled)
        #expect(fast.position == .zero)
    }
}
