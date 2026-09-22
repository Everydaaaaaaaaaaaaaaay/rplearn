import Combine
import SwiftUI
import UIKit

/// 手指移动不插值；只有释放后使用显示同步的弹簧。显示位置也是下一次抓取的起点。
@MainActor
final class MyPageSpatialMotion: ObservableObject {
    @Published private(set) var camera = CGSize.zero
    private var origin = CGSize.zero
    private var previousTime: TimeInterval?
    private var velocity = CGSize.zero
    private var dragging = false
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    func drag(_ translation: CGSize, time: TimeInterval) {
        if !dragging {
            stopLink()
            origin = MyPageSpatialGeometry.unresisted(camera)
            previousTime = nil
            velocity = .zero
            dragging = true
        }
        let next = MyPageSpatialGeometry.resisted(CGSize(
            width: origin.width + translation.width,
            height: origin.height + translation.height
        ))
        if let previousTime, time > previousTime {
            let dt = max(time - previousTime, 1.0 / 240)
            velocity = CGSize(width: (next.width - camera.width) / dt, height: (next.height - camera.height) / dt)
        }
        previousTime = time
        camera = next
    }

    func release(time: TimeInterval) {
        guard dragging else { return }
        dragging = false
        // 停住后松手不继承过期速度；快速甩动也限制释放能量。
        if time - (previousTime ?? time) > 0.08 { velocity = .zero }
        velocity.width = min(max(velocity.width, -100), 100)
        velocity.height = min(max(velocity.height, -100), 100)
        lastFrame = 0
        let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func reset() {
        stopLink()
        dragging = false
        previousTime = nil
        velocity = .zero
        camera = .zero
    }

    private func step(_ link: CADisplayLink) {
        let dt = min(lastFrame == 0 ? link.targetTimestamp - link.timestamp : link.timestamp - lastFrame, 1.0 / 30)
        lastFrame = link.timestamp
        advance(seconds: dt)
    }

    func advance(seconds dt: TimeInterval) {
        // 分步积分使 60/120 Hz 的回弹保持一致，近临界阻尼不反复振荡。
        let count = max(1, Int(ceil(dt / (1.0 / 240))))
        let h = dt / Double(count)
        var next = camera
        for _ in 0..<count {
            velocity.width += (-300 * next.width - 32 * velocity.width) * h
            velocity.height += (-300 * next.height - 32 * velocity.height) * h
            next.width += velocity.width * h
            next.height += velocity.height * h
        }
        camera = next
        if hypot(next.width, next.height) < 0.015 && hypot(velocity.width, velocity.height) < 0.15 {
            reset()
        }
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @MainActor
    private final class WeakTarget: NSObject {
        weak var owner: MyPageSpatialMotion?
        init(_ owner: MyPageSpatialMotion) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.step(link)
        }
    }
}

struct MyPageSpatialScene<Content: View>: View {
    let content: (CGSize) -> Content
    @StateObject private var motion = MyPageSpatialMotion()
    @GestureState private var gestureActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(@ViewBuilder content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    var body: some View {
        content(reduceMotion ? .zero : motion.camera)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .updating($gestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        guard !reduceMotion else { return }
                        // 手势坐标属于稳定视口，不随背景变换；设备缩放不改变手感。
                        motion.drag(value.translation, time: value.time.timeIntervalSinceReferenceDate)
                    }
                    .onEnded { value in motion.release(time: value.time.timeIntervalSinceReferenceDate) }
            )
            .onChange(of: gestureActive) { _, active in
                if !active { motion.release(time: Date.timeIntervalSinceReferenceDate) }
            }
            .onChange(of: reduceMotion) { _, _ in motion.reset() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { motion.reset() } }
            .onDisappear { motion.reset() }
    }
}
