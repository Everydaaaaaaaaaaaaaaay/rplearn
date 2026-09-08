import AVFoundation
import SwiftUI

/// One silent decoder for the visible scene. Park footage is a sparse event;
/// pond and rain footage use pre-finished forward-only loops.
struct ActivitySceneVideoLayer: UIViewRepresentable {
    let assetName: String
    let mode: ActivityScenePlaybackMode
    let playing: Bool
    let onFailure: () -> Void
    let onPlayback: (Bool) -> Void
    let onLoop: (Int) -> Void
    let onProgress: (Int) -> Void
    let onQuiet: (Bool) -> Void

    nonisolated static func permitsMotion(requested: Bool, reduceMotion: Bool,
                                          lowPower: Bool, thermal: ProcessInfo.ThermalState) -> Bool {
        requested && !reduceMotion && !lowPower && thermal != .serious && thermal != .critical
    }

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor final class Coordinator {
        let player: AVPlayer
        var looper: AVPlayerLooper?
        var observations: [NSKeyValueObservation] = []
        var endObservation: NSObjectProtocol?
        var failureObservation: NSObjectProtocol?
        var progressObserver: Any?
        var wakeTask: Task<Void, Never>?
        var enabled = false
        var failed = false
        var waiting = false
        var seeking = false
        var remainingDelay: TimeInterval = 0
        var waitStart: ContinuousClock.Instant?
        var passes = 0
        var cadence = ActivityAmbientCadence()
        var random = SystemRandomNumberGenerator()
        var owner: ActivitySceneVideoLayer

        init(_ owner: ActivitySceneVideoLayer) {
            self.owner = owner
            player = owner.mode == .seamlessLoop ? AVQueuePlayer() : AVPlayer()
        }

        func prepare() {
            guard let url = ActivitySceneView.asset(owner.assetName, "mp4") else {
                fail()
                return
            }
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] value, _ in
                let running = value.timeControlStatus == .playing
                Task { @MainActor in self?.owner.onPlayback(running) }
            })
            observations.append(player.observe(\.status, options: [.initial, .new]) { [weak self] value, _ in
                guard value.status == .failed else { return }
                Task { @MainActor in self?.fail() }
            })

            let item = AVPlayerItem(url: url)
            observations.append(item.observe(\.status, options: [.initial, .new]) { [weak self] value, _ in
                guard value.status == .failed else { return }
                Task { @MainActor in self?.fail() }
            })
            failureObservation = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.fail() }
            }

            switch owner.mode {
            case .seamlessLoop:
                guard let queue = player as? AVQueuePlayer else {
                    fail()
                    return
                }
                let looper = AVPlayerLooper(player: queue, templateItem: item)
                self.looper = looper
                observations.append(looper.observe(\.status, options: [.initial, .new]) { [weak self] value, _ in
                    guard value.status == .failed else { return }
                    Task { @MainActor in self?.fail() }
                })
                observations.append(looper.observe(\.loopCount, options: [.new]) { [weak self] value, _ in
                    let count = value.loopCount
                    Task { @MainActor in self?.owner.onLoop(count) }
                })
            case .sparseEvent:
                player.actionAtItemEnd = .pause
                player.replaceCurrentItem(with: item)
                endObservation = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.finishedPass() }
                }
            }

            #if DEBUG
            // Test-only playhead evidence. Production does not invalidate SwiftUI on a timer.
            if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "activities" {
                progressObserver = player.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
                ) { [weak self] time in
                    let seconds = time.seconds
                    guard seconds.isFinite else { return }
                    Task { @MainActor in self?.owner.onProgress(Int(seconds)) }
                }
            }
            #endif
        }

        func setPlaying(_ value: Bool) {
            guard !failed, enabled != value else { return }
            enabled = value
            if value {
                if waiting {
                    scheduleWake()
                } else if !seeking {
                    player.play()
                }
            } else {
                player.pause()
                if let waitStart {
                    let elapsed = waitStart.duration(to: .now).components
                    remainingDelay = max(0, remainingDelay - Double(elapsed.seconds)
                        - Double(elapsed.attoseconds) / 1e18)
                }
                waitStart = nil
                wakeTask?.cancel()
                wakeTask = nil
            }
        }

        func finishedPass() {
            guard owner.mode == .sparseEvent, !waiting else { return }
            passes += 1
            owner.onLoop(passes)
            waiting = true
            owner.onQuiet(true)
            remainingDelay = cadence.nextDelay(using: &random)
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_CADENCE"] == "accelerated" {
                remainingDelay = 2
            }
            #endif
            if enabled { scheduleWake() }
        }

        func scheduleWake() {
            guard wakeTask == nil, waiting, enabled else { return }
            waitStart = .now
            let delay = remainingDelay
            wakeTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard let self, self.enabled, !Task.isCancelled else { return }
                self.wakeTask = nil
                self.waitStart = nil
                self.remainingDelay = 0
                self.waiting = false
                self.seeking = true
                self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                    Task { @MainActor in
                        guard let self else { return }
                        self.seeking = false
                        guard finished else { return }
                        self.owner.onQuiet(false)
                        if self.enabled { self.player.play() }
                    }
                }
            }
        }

        func fail() {
            guard !failed else { return }
            failed = true
            player.pause()
            owner.onFailure()
        }

        func stop() {
            setPlaying(false)
            wakeTask?.cancel()
            wakeTask = nil
            player.pause()
            observations.removeAll()
            if let progressObserver { player.removeTimeObserver(progressObserver) }
            progressObserver = nil
            if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
            if let failureObservation { NotificationCenter.default.removeObserver(failureObservation) }
            endObservation = nil
            failureObservation = nil
            player.currentItem?.cancelPendingSeeks()
            looper?.disableLooping()
            looper = nil
            if let queue = player as? AVQueuePlayer {
                queue.removeAllItems()
            } else {
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = context.coordinator.player
        context.coordinator.prepare()
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
