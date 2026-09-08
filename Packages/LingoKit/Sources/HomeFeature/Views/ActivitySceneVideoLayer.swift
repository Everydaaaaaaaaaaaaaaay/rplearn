import AVFoundation
import SwiftUI

/// One silent decoder for the visible scene. Every asset is a pre-finished,
/// forward-only loop; the park asset contains its own sparse runner schedule.
struct ActivitySceneVideoLayer: UIViewRepresentable {
    let assetName: String
    let playing: Bool
    let onFailure: () -> Void
    let onPlayback: (Bool) -> Void
    let onLoop: (Int) -> Void
    let onProgress: (Int) -> Void

    nonisolated static func permitsMotion(requested: Bool, reduceMotion: Bool,
                                          lowPower: Bool, thermal: ProcessInfo.ThermalState) -> Bool {
        requested && !reduceMotion && !lowPower && thermal != .serious && thermal != .critical
    }

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor final class Coordinator {
        let player: AVQueuePlayer
        var looper: AVPlayerLooper?
        var observations: [NSKeyValueObservation] = []
        var failureObservation: NSObjectProtocol?
        var progressObserver: Any?
        var enabled = false
        var failed = false
        var owner: ActivitySceneVideoLayer

        init(_ owner: ActivitySceneVideoLayer) {
            self.owner = owner
            player = AVQueuePlayer()
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

            let looper = AVPlayerLooper(player: player, templateItem: item)
            self.looper = looper
            observations.append(looper.observe(\.status, options: [.initial, .new]) { [weak self] value, _ in
                guard value.status == .failed else { return }
                Task { @MainActor in self?.fail() }
            })
            observations.append(looper.observe(\.loopCount, options: [.new]) { [weak self] value, _ in
                let count = value.loopCount
                Task { @MainActor in self?.owner.onLoop(count) }
            })

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
                player.play()
            } else {
                player.pause()
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
            player.pause()
            observations.removeAll()
            if let progressObserver { player.removeTimeObserver(progressObserver) }
            progressObserver = nil
            if let failureObservation { NotificationCenter.default.removeObserver(failureObservation) }
            failureObservation = nil
            looper?.disableLooping()
            looper = nil
            player.removeAllItems()
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
