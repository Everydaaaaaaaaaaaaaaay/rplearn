import AVFoundation
import CoreKit
import Foundation
import Observation

/// 原始录音回放。同一时刻只播放一条，以消息身份跟踪下载与播放。
@MainActor
@Observable
public final class VoiceMessagePlayer {
    public private(set) var playingFileName: String?
    public private(set) var playingMessageID: UUID?
    public private(set) var loadingMessageID: UUID?
    public private(set) var failedMessageID: UUID?

    private var player: AVAudioPlayer?
    private var delegateBox: DelegateBox?
    private let audioSession: AudioSessionCoordinator
    private var playbackLease: UUID?
    private var requestID = UUID()

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
    }

    public func togglePlay(
        messageID: UUID,
        resolveFile: @MainActor () async -> String?
    ) async {
        if playingMessageID == messageID || loadingMessageID == messageID {
            stop()
            return
        }
        stop()
        let request = requestID
        loadingMessageID = messageID
        defer {
            if requestID == request { loadingMessageID = nil }
        }
        let resolvedFile = await resolveFile()
        guard requestID == request, !Task.isCancelled else { return }
        guard let fileName = resolvedFile else {
            failedMessageID = messageID
            return
        }
        await play(fileName: fileName, messageID: messageID, request: request)
    }

    public func togglePlay(fileName: String) async {
        if playingFileName == fileName {
            stop()
            return
        }
        stop()
        await play(fileName: fileName, messageID: nil, request: requestID)
    }

    private func play(fileName: String, messageID: UUID?, request: UUID) async {
        guard requestID == request, !Task.isCancelled else { return }
        do {
            let url = try VoiceMessageStorage.url(for: fileName)
            let lease = try await audioSession.acquirePlayback()
            guard requestID == request, !Task.isCancelled else {
                await audioSession.releasePlayback(lease)
                return
            }
            playbackLease = lease
            let player = try AVAudioPlayer(contentsOf: url)
            let box = DelegateBox { [weak self] success in
                Task { @MainActor [weak self] in
                    guard let self, self.requestID == request else { return }
                    self.stop()
                    if !success { self.failedMessageID = messageID }
                }
            }
            player.delegate = box
            guard player.play() else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.player = player
            delegateBox = box
            playingFileName = fileName
            playingMessageID = messageID
            loadingMessageID = nil
        } catch {
            guard requestID == request else { return }
            Log.speech.error("语音回放失败：\(error)")
            stop()
            failedMessageID = messageID
        }
    }

    public func stop() {
        requestID = UUID()
        player?.stop()
        player = nil
        delegateBox = nil
        playingFileName = nil
        playingMessageID = nil
        loadingMessageID = nil
        failedMessageID = nil
        if let lease = playbackLease {
            playbackLease = nil
            Task { await audioSession.releasePlayback(lease) }
        }
    }

    private final class DelegateBox: NSObject, AVAudioPlayerDelegate {
        private let onFinish: @Sendable (Bool) -> Void

        init(onFinish: @escaping @Sendable (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish(flag)
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            onFinish(false)
        }
    }
}
