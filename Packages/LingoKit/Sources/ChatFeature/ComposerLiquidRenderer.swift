@preconcurrency import MetalKit
import SwiftUI

/// Bounded, time-step-independent spring. Shared by the surface and its floating details.
struct ComposerLiquidMotion {
    var position = SIMD2<Double>.zero
    var velocity = SIMD2<Double>.zero
    var target = SIMD2<Double>.zero
    var settled: Bool { simd_length(position - target) < 0.001 && simd_length(velocity) < 0.005 }
    mutating func advance(_ elapsed: Double) {
        let duration = min(max(elapsed, 0), 0.1)
        let steps = max(1, Int(ceil(duration / (1.0 / 120))))
        let dt = duration / Double(steps)
        target = simd_clamp(target, SIMD2(repeating: -1), SIMD2(repeating: 1))
        for _ in 0..<steps {
            velocity += ((target - position) * 100 - velocity * 12) * dt
            position += velocity * dt
            position = simd_clamp(position, SIMD2(repeating: -1.2), SIMD2(repeating: 1.2))
        }
        if settled { position = target; velocity = .zero }
    }
}

struct ComposerLiquidRenderer: UIViewRepresentable {
    var tilt: SIMD2<Double>
    var purple: Bool
    var dark: Bool
    var active: Bool
    var reduceMotion: Bool
    var opaque: Bool
    var bottomInset: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isUserInteractionEnabled = false
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        context.coordinator.install(view)
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) { coordinator.stop(); view.delegate = nil }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        weak var view: MTKView?
        var pipeline: MTLRenderPipelineState?
        var queue: MTLCommandQueue?
        var motion = ComposerLiquidMotion()
        var config: ComposerLiquidRenderer?
        var reveal: Double = 0
        var link: CADisplayLink?
        var previous: Double = 0
        func install(_ view: MTKView) {
            self.view = view
            guard let device = view.device else { return }
            do {
                let library = try device.makeLibrary(source: Self.shader, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "liquidVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "liquidFragment")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                queue = device.makeCommandQueue()
            } catch { assertionFailure("Composer liquid shader: \(error)") }
            view.delegate = self
        }
        func update(_ value: ComposerLiquidRenderer) {
            let initial = config == nil
            config = value
            motion.target = value.reduceMotion ? .zero : value.tilt
            if initial || value.reduceMotion {
                reveal = value.purple ? 1 : 0
                motion.position = motion.target; motion.velocity = .zero
            }
            view?.setNeedsDisplay()
            guard value.active && !value.reduceMotion else { stop(); return }
            guard !motion.settled || abs(reveal - (value.purple ? 1 : 0)) > 0.001 else { return }
            guard link == nil else { return }
            let timer = CADisplayLink(target: self, selector: #selector(step(_:)))
            let economical = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
            timer.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: economical ? 30 : 60, preferred: economical ? 30 : 60)
            timer.add(to: .main, forMode: .common)
            link = timer
        }
        func stop() { link?.invalidate(); link = nil; previous = 0 }
        @objc func step(_ timer: CADisplayLink) {
            guard let config else { stop(); return }
            let dt = previous == 0 ? 1.0 / 60 : timer.timestamp - previous
            previous = timer.timestamp
            motion.advance(dt)
            let target = config.purple ? 1.0 : 0.0
            reveal += (target - reveal) * (1 - exp(-dt * 10))
            if abs(reveal - target) < 0.001 { reveal = target }
            view?.setNeedsDisplay()
            if motion.settled && reveal == target { stop() }
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }
        func draw(in view: MTKView) {
            guard let config, let pipeline, let queue, let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable, let command = queue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            var uniforms: [SIMD4<Float>] = [
                .init(Float(view.bounds.width), Float(view.bounds.height), Float(motion.position.x), Float(motion.position.y)),
                .init(Float(motion.velocity.x), Float(motion.velocity.y), Float(reveal), config.dark ? 1 : 0),
                .init(Float(config.bottomInset), config.opaque ? 1 : 0, 0, 0)
            ]
            encoder.setRenderPipelineState(pipeline)
            uniforms.withUnsafeMutableBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding(); command.present(drawable); command.commit()
        }
        static let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 position [[position]]; float2 uv; };
        vertex V liquidVertex(uint id [[vertex_id]]) {
            float2 p = float2((id << 1) & 2, id & 2);
            return {float4(p * float2(2,-2) + float2(-1,1),0,1),p};
        }
        float line(float d, float width) { return 1-smoothstep(width,width+0.9,abs(d)); }
        fragment float4 liquidFragment(V in [[stage_in]], constant float4 *u [[buffer(0)]]) {
            float2 size=u[0].xy, p=in.uv*size;
            float roll=u[0].z, pitch=u[0].w, mode=u[1].z, dark=u[1].w;
            float2 origin=float2(size.x-68,size.y-u[2].x-30);
            float reveal=1-smoothstep(mode*length(size)-5,mode*length(size)+5,distance(p,origin));
            if(mode<0.001) reveal=0;
            if(mode>0.999) reveal=1;
            float3 tint=mix(float3(.25,.69,.94),float3(.62,.48,.90),reveal);
            float3 base=mix(float3(.988,.994,1),float3(.075,.087,.12),dark);
            float2 halfSize=size*.5-float2(6,6);
            float2 q=abs(p-size*.5)-(halfSize-19);
            float wall=length(max(q,0.0))+min(max(q.x,q.y),0.0)-19;
            float mask=1-smoothstep(-.7,.7,wall);
            float x=clamp((p.x-6)/(size.x-12),0.0,1.0);
            float wave=sin(x*6.283)*u[1].x*1.4+sin(x*12.566)*u[1].y*.7;
            float depth=clamp(13+pitch*10,3.0,24.0);
            float farEdge=size.y*.32+(x-.5)*roll*28+wave;
            float nearEdge=farEdge+depth*(.55+.45*sin(x*3.14159));
            float water=smoothstep(farEdge-1,farEdge+1,p.y);
            float surface=water*(1-smoothstep(nearEdge-.7,nearEdge+.7,p.y));
            float body=smoothstep(nearEdge-1,nearEdge+1,p.y);
            float density=clamp((p.y-nearEdge)/max(size.y-nearEdge,1.0),0.0,1.0);
            float3 col=mix(base,tint,(surface*.24+body*(.07+.08*density))*(1-dark*.2));
            // Broad reflected light and subtle refraction of the internal backing only.
            float reflection=exp(-pow((x-.32-roll*.08-pitch*.04)*5,2.0));
            col+=float3(.025,.030,.035)*surface*reflection;
            float refractedX=x+sin(x*6.283+pitch)*.016*(1-density)+roll*.012;
            float backing=exp(-pow((refractedX-.65)*4,2.0));
            col+=float3(.018,.022,.025)*body*backing*(1-density);
            col+=float3(.014)*body*reflection*(1-density);
            col+=line(p.y-nearEdge,.12)*float3(.085,.095,.11)*(1-dark*.45);
            col+=line(p.y-farEdge,.10)*float3(.025);
            col=mix(col,tint,.12*line(wall+1,.5)*water);
            // Restrained, partially submerged lemon / petals, anchored near the side walls.
            for(int i=0;i<3;i++) {
                float cx=i==0?23.0:size.x-20.0-float(i)*13;
                cx+=roll*4+u[1].x*.6;
                float xx=clamp((cx-6)/(size.x-12),0.0,1.0);
                float cy=size.y*.32+(xx-.5)*roll*28+depth*.7+float(i)*5;
                float2 d=p-float2(cx,cy);
                float angle=roll*.5+u[1].x*.06;
                d=float2(cos(angle)*d.x-sin(angle)*d.y,sin(angle)*d.x+cos(angle)*d.y);
                float radius=length(d);
                if(i==0) {
                    float lemon=1-smoothstep(4.5,5.2,radius);
                    float petal=1-smoothstep(.8,1.0,length(d/float2(3,5)));
                    float3 lemonColor=mix(float3(.98,.88,.39),float3(1,.97,.73),line(radius-3.8,.4));
                    float segments=line(sin(atan2(d.y,d.x)*3)*radius,.22);
                    lemonColor=mix(lemonColor,float3(1,.98,.85),segments*.7);
                    col=mix(col,mix(lemonColor,float3(.81,.70,.94),reveal),mix(lemon,petal,reveal)*mix(.65,.35,smoothstep(-1.0,2.0,d.y)));
                } else {
                    col+=line(radius-(i==1?2.1:1.4),.3)*float3(.16);
                }
            }
            if(u[2].y>0.5) col=mix(base,tint,.12);
            return float4(col*mask,mask);
        }
        """
    }
}
