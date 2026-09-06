import AVFoundation
import SwiftUI

/// A shuffled bag of actual complete passes, not cloned or time-warped actors.
struct CafeEventSchedule {
    private var remaining: [Int] = []
    private(set) var previous: Int?

    mutating func next(using random: inout some RandomNumberGenerator) -> Int {
        if remaining.isEmpty {
            remaining = Array(0..<3).shuffled(using: &random)
            if remaining.last == previous { remaining.swapAt(0, 2) }
        }
        let next = remaining.removeLast()
        previous = next
        return next
    }
}

/// A single decoder, held on its empty final plate between events. No per-frame
/// UI state. Offscreen/background suspension preserves the remaining quiet time.
struct CafeMotionLayer: UIViewRepresentable {
    let playing: Bool
    let onFailure: () -> Void
    let onPlayback: (Bool) -> Void
    let onEvent: (Int) -> Void
    let onQuiet: (Bool) -> Void

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    @MainActor final class Coordinator {
        let player = AVPlayer()
        var schedule = CafeEventSchedule()
        var random = SystemRandomNumberGenerator()
        var enabled = false
        var waiting = true
        var delay: Double = 2
        var startedWaiting: ContinuousClock.Instant?
        var task: Task<Void, Never>?
        var endObserver: NSObjectProtocol?
        var failedObserver: NSObjectProtocol?
        var observation: NSKeyValueObservation?
        var timeObservation: NSKeyValueObservation?
        var eventCount = 0
        var owner: CafeMotionLayer

        init(_ owner: CafeMotionLayer) { self.owner = owner }
        func setPlaying(_ enabled: Bool) {
            guard self.enabled != enabled else { return }
            self.enabled = enabled
            if enabled {
                if waiting { waitForNext() } else { player.play() }
            } else {
                player.pause()
                if let startedWaiting {
                    let elapsed = startedWaiting.duration(to: .now).components
                    delay = max(0, delay - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18)
                }
                startedWaiting = nil
                task?.cancel(); task = nil
            }
        }
        func waitForNext() {
            guard task == nil else { return }
            owner.onQuiet(true)
            startedWaiting = .now
            task = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for: .seconds(self.delay)) } catch { return }
                guard self.enabled, !Task.isCancelled else { return }
                self.task = nil; self.startedWaiting = nil
                self.installNext()
            }
        }
        func installNext() {
            let event = schedule.next(using: &random)
            guard let url = ActivitySceneView.asset("activity-cafe-event-\(event)", "mp4") else {
                owner.onFailure(); return
            }
            clearItemObservers()
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            waiting = false
            owner.onQuiet(false)
            observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in self?.owner.onFailure() }
            }
            failedObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.owner.onFailure() } }
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.eventCount += 1
                    self.owner.onEvent(self.eventCount)
                    self.waiting = true
                    self.delay = Double.random(in: 12...30, using: &self.random)
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_CADENCE"] == "accelerated" {
                        self.delay = 0.3
                    }
                    #endif
                    self.owner.onQuiet(true)
                    if self.enabled { self.waitForNext() }
                }
            }
            if enabled { player.play() }
        }
        func clearItemObservers() {
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
            endObserver = nil; failedObserver = nil; observation = nil
        }
        func stop() {
            setPlaying(false)
            task?.cancel(); task = nil
            clearItemObservers()
            timeObservation = nil
            player.replaceCurrentItem(with: nil)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect
        let coordinator = context.coordinator
        coordinator.player.isMuted = true
        coordinator.player.actionAtItemEnd = .pause
        coordinator.player.preventsDisplaySleepDuringVideoPlayback = false
        view.playerLayer.player = coordinator.player
        coordinator.timeObservation = coordinator.player.observe(\.timeControlStatus, options: [.new]) { [weak coordinator] player, _ in
            let running = player.timeControlStatus == .playing
            Task { @MainActor in coordinator?.owner.onPlayback(running) }
        }
        return view
    }
    func updateUIView(_ view: Surface, context: Context) {
        context.coordinator.owner = self
        context.coordinator.setPlaying(playing)
    }
    static func dismantleUIView(_ view: Surface, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }
}
