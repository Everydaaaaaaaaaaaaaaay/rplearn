import AVFoundation
import SwiftUI

/// A continuously decoded, seam-finished street take. Never hold a still frame
/// to simulate a quiet street: even between passers, the distant world moves.
struct CafeMotionLayer: UIViewRepresentable {
    let assetName: String
    let playing: Bool
    let onFailure: () -> Void
    let onPlayback: (Bool) -> Void
    let onLoop: (Int) -> Void
    let onProgress: (Int) -> Void

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var enabled = false
        var failed = false
        var observations: [NSKeyValueObservation] = []
        var progressObserver: Any?
        var owner: CafeMotionLayer

        init(_ owner: CafeMotionLayer) { self.owner = owner }

        func prepare() {
            guard let url = ActivitySceneView.asset(owner.assetName, "mp4") else {
                fail(); return
            }
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            // Prepare the next replica before this item ends. Replacing/seeking
            // from an end notification creates a visible decoder gap.
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            self.looper = looper
            observations = [
                looper.observe(\.status, options: [.initial, .new]) { [weak self] value, _ in
                    guard value.status == .failed else { return }
                    Task { @MainActor in self?.fail() }
                },
                player.observe(\.status, options: [.initial, .new]) { [weak self] value, _ in
                    guard value.status == .failed else { return }
                    Task { @MainActor in self?.fail() }
                },
                player.observe(\.timeControlStatus, options: [.new]) { [weak self] value, _ in
                    let running = value.timeControlStatus == .playing
                    Task { @MainActor in self?.owner.onPlayback(running) }
                },
                looper.observe(\.loopCount, options: [.new]) { [weak self] value, _ in
                    let count = value.loopCount
                    Task { @MainActor in self?.owner.onLoop(count) }
                }
            ]
            #if DEBUG
            // Test-only playhead evidence, also while an action hides entrances.
            // Production never invalidates SwiftUI on a frame/timer.
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

        func setPlaying(_ enabled: Bool) {
            guard !failed, self.enabled != enabled else { return }
            self.enabled = enabled
            if enabled { player.play() } else { player.pause() }
        }

        func fail() {
            guard !failed else { return }
            failed = true
            player.pause()
            owner.onFailure()
        }

        func stop() {
            player.pause()
            enabled = false
            observations.removeAll()
            if let progressObserver { player.removeTimeObserver(progressObserver) }
            progressObserver = nil
            looper?.disableLooping()
            looper = nil
            player.removeAllItems()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect
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
