@preconcurrency import AVFoundation
import CoreKit
import Foundation

/// 水平校准只播放随包固定音频，避免慢设备现场运行 TTS 导致卡顿或题目口音漂移。
@MainActor
final class PlacementListeningAudioPlayer {
    private var player: AVAudioPlayer?
    private var delegateBox: DelegateBox?
    private let audioSession: AudioSessionCoordinator

    init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
    }

    @discardableResult
    func play(assetName: String) async -> Bool {
        stop()
        guard let url = Self.resourceURL(assetName: assetName) else {
            Log.speech.error("缺少水平测试听力音频：\(assetName, privacy: .public)")
            return false
        }

        do {
            try await audioSession.activate(.playback)
            let player = try AVAudioPlayer(contentsOf: url)
            let delegateBox = DelegateBox { [weak self] in
                Task { @MainActor [weak self] in
                    self?.player = nil
                    self?.delegateBox = nil
                }
            }
            player.delegate = delegateBox
            player.prepareToPlay()
            guard player.play() else { return false }
            self.player = player
            self.delegateBox = delegateBox
            NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: nil)
            return true
        } catch {
            Log.speech.error("水平测试听力音频播放失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        delegateBox = nil
    }

    private static func resourceURL(assetName: String) -> URL? {
        Bundle.module.url(
            forResource: assetName,
            withExtension: "m4a",
            subdirectory: "Listening"
        ) ?? Bundle.module.url(forResource: assetName, withExtension: "m4a")
    }

    private final class DelegateBox: NSObject, AVAudioPlayerDelegate {
        private let onFinish: @Sendable () -> Void

        init(onFinish: @escaping @Sendable () -> Void) {
            self.onFinish = onFinish
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            onFinish()
        }
    }
}
