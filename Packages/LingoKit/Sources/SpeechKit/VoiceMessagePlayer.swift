import AVFoundation
import CoreKit
import Foundation
import Observation

/// 语音条回放（AVAudioPlayer），同一时刻只播一条。
@MainActor
@Observable
public final class VoiceMessagePlayer {
    public private(set) var playingFileName: String?

    private var player: AVAudioPlayer?
    private var delegateBox: DelegateBox?
    private let audioSession: AudioSessionCoordinator

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
    }

    public func togglePlay(fileName: String) async {
        if playingFileName == fileName {
            stop()
            return
        }
        stop()
        do {
            let url = try VoiceMessageStorage.url(for: fileName)
            try await audioSession.activate(.playback)
            let player = try AVAudioPlayer(contentsOf: url)
            let box = DelegateBox { [weak self] in
                Task { @MainActor [weak self] in
                    self?.playingFileName = nil
                }
            }
            player.delegate = box
            player.play()
            self.player = player
            self.delegateBox = box
            playingFileName = fileName
        } catch {
            Log.speech.error("语音回放失败：\(error)")
            playingFileName = nil
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        delegateBox = nil
        playingFileName = nil
    }

    private final class DelegateBox: NSObject, AVAudioPlayerDelegate {
        private let onFinish: @Sendable () -> Void

        init(onFinish: @escaping @Sendable () -> Void) {
            self.onFinish = onFinish
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }
    }
}
