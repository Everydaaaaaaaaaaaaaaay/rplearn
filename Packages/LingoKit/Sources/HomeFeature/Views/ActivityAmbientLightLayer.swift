import SwiftUI
import UIKit

/// Compositor-only leaf shadows. No video decoder, moving photo, display link,
/// per-frame SwiftUI updates, repeated people or whole-image dissolve.
struct ActivityAmbientLightLayer: UIViewRepresentable {
    let scene: ActivitySceneID
    let playing: Bool
    let onPlayback: (Bool) -> Void
    let onProgress: (Int, Int) -> Void

    nonisolated static let cycle: TimeInterval = 60

    nonisolated static func permitsMotion(requested: Bool, reduceMotion: Bool,
                                         lowPower: Bool, thermal: ProcessInfo.ThermalState) -> Bool {
        requested && !reduceMotion && !lowPower && thermal != .serious && thermal != .critical
    }

    /// Same position AND velocity at the boundary; these are shadow texture
    /// pixels, never displacement of the photographic geometry.
    nonisolated static func drift(at seconds: TimeInterval, phase: Double) -> CGPoint {
        let t = 2 * Double.pi * seconds / cycle
        return CGPoint(x: 7 * sin(3 * t + phase) + 3 * sin(7 * t),
                       y: 4 * cos(2 * t + phase) + 2 * sin(5 * t))
    }

    @MainActor final class Surface: UIView {
        private let canvas = CALayer()
        private var requested = false
        private(set) var running = false
        var didChangePlayback: ((Bool) -> Void)?

        init(scene: ActivitySceneID) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.addSublayer(canvas)
            canvas.bounds = CGRect(x: 0, y: 0, width: 852, height: 1847)
            canvas.anchorPoint = .zero
            canvas.speed = 0
            canvas.timeOffset = 0
            for (index, quad) in scene.media.lightPlanes.enumerated() {
                addPlane(quad, seed: scene.media.seed + UInt64(index))
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            canvas.setAffineTransform(CGAffineTransform(scaleX: bounds.width / 852, y: bounds.height / 1847))
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updatePlayback()
        }

        func setPlaying(_ value: Bool) {
            requested = value
            updatePlayback()
        }

        var elapsed: TimeInterval { canvas.convertTime(CACurrentMediaTime(), from: nil) }

        private func updatePlayback() {
            let next = requested && window != nil
            guard running != next else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if next {
                let paused = canvas.timeOffset
                canvas.speed = 1
                canvas.timeOffset = 0
                canvas.beginTime = 0
                canvas.beginTime = canvas.convertTime(CACurrentMediaTime(), from: nil) - paused
            } else {
                let paused = elapsed
                canvas.speed = 0
                canvas.timeOffset = paused
            }
            CATransaction.commit()
            running = next
            didChangePlayback?(next)
        }

        private func addPlane(_ quad: HomePerspectiveQuad, seed: UInt64) {
            let plane = CALayer()
            plane.bounds = CGRect(x: 0, y: 0, width: 512, height: 512)
            plane.anchorPoint = .zero
            let h = HomeHomography(quad: quad)
            var matrix = CATransform3DIdentity
            matrix.m11 = h.a / 512; matrix.m12 = h.d / 512; matrix.m14 = h.g / 512
            matrix.m21 = h.b / 512; matrix.m22 = h.e / 512; matrix.m24 = h.h / 512
            matrix.m41 = h.c; matrix.m42 = h.f; matrix.m44 = h.i
            plane.transform = matrix
            // Feather before the edge so the receiving plane is not a visible box.
            let edge = CALayer()
            edge.frame = plane.bounds
            edge.contents = Self.edgeMask
            plane.mask = edge

            let shade = CALayer()
            shade.frame = plane.bounds.insetBy(dx: -24, dy: -24)
            shade.contents = Self.canopyTexture(seed: seed).cgImage
            shade.opacity = 0.12
            let phase = Double(seed % 17) / 17 * 2 * .pi
            let drift = CAKeyframeAnimation(keyPath: "position")
            drift.values = (0...240).map { index in
                let offset = ActivityAmbientLightLayer.drift(at: Double(index) / 4, phase: phase)
                return NSValue(cgPoint: CGPoint(x: 256 + offset.x, y: 256 + offset.y))
            }
            drift.duration = ActivityAmbientLightLayer.cycle
            drift.calculationMode = .linear
            drift.repeatCount = .infinity
            drift.isRemovedOnCompletion = false
            shade.add(drift, forKey: "canopy.wind")
            plane.addSublayer(shade)
            canvas.addSublayer(plane)
        }

        /// A procedural shadow graphic, not a generated/repainted photograph.
        /// Rasterized once per surface; only its transform moves afterwards.
        private static func canopyTexture(seed: UInt64) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: CGSize(width: 560, height: 560), format: format).image { renderer in
                let context = renderer.cgContext
                var state = seed
                func random() -> CGFloat {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    return CGFloat(state >> 32) / CGFloat(UInt32.max)
                }
                context.setFillColor(UIColor.black.cgColor)
                context.setShadow(offset: .zero, blur: 11, color: UIColor.black.cgColor)
                for _ in 0..<80 {
                    context.saveGState()
                    context.translateBy(x: random() * 560, y: random() * 560)
                    context.rotate(by: random() * .pi)
                    let length = 16 + random() * 35
                    context.fillEllipse(in: CGRect(x: -length / 2, y: -8, width: length, height: 16))
                    context.restoreGState()
                }
            }
        }

        private static let edgeMask: CGImage? = {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { renderer in
                let colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors, locations: [0, 0.3, 1]) else { return }
                renderer.cgContext.drawRadialGradient(gradient,
                    startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                    endCenter: CGPoint(x: 256, y: 256), endRadius: 248, options: [])
            }.cgImage
        }()
    }

    @MainActor final class Coordinator {
        var owner: ActivityAmbientLightLayer
        #if DEBUG
        var timer: Timer?
        #endif
        init(_ owner: ActivityAmbientLightLayer) { self.owner = owner }
        func stop() {
            #if DEBUG
            timer?.invalidate()
            timer = nil
            #endif
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Surface {
        let view = Surface(scene: scene)
        let coordinator = context.coordinator
        view.didChangePlayback = { [weak coordinator] running in
            DispatchQueue.main.async { coordinator?.owner.onPlayback(running) }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "activities" {
            coordinator.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak view, weak coordinator] _ in
                Task { @MainActor in
                    guard let view, let coordinator else { return }
                    let elapsed = max(0, view.elapsed)
                    coordinator.owner.onProgress(Int(elapsed / ActivityAmbientLightLayer.cycle),
                        Int(elapsed.truncatingRemainder(dividingBy: ActivityAmbientLightLayer.cycle)))
                }
            }
        }
        #endif
        return view
    }
    func updateUIView(_ view: Surface, context: Context) {
        context.coordinator.owner = self
        view.setPlaying(playing)
    }
    static func dismantleUIView(_ view: Surface, coordinator: Coordinator) {
        view.didChangePlayback = nil
        view.setPlaying(false)
        coordinator.stop()
    }
}
