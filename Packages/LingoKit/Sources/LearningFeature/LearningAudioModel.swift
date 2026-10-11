@preconcurrency import AVFoundation
import BackendKit
import CoreKit
import Foundation
import Observation
import SpeechKit

@MainActor
protocol LearningAudioPlayback: AnyObject {
    func play(data: Data, rate: Float, completed: @escaping @MainActor @Sendable (Bool) -> Void) async throws
    func stop()
}

@MainActor @Observable
final class LearningAudioModel {
    enum State: Equatable { case idle, loading, ready, playing, interrupted, failed }
    private(set) var state: State = .idle
    private(set) var hasListened = false
    var isPlaybackActive: Bool { state == .playing || (state == .loading && data != nil) }
    let playbackID = UUID()
    @ObservationIgnored private let service: any LearningServing
    @ObservationIgnored private let playback: any LearningAudioPlayback
    @ObservationIgnored private let beforePlayback: @Sendable () async -> Void
    @ObservationIgnored private var data: Data?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var playTask: Task<Void, Never>?

    init(service: any LearningServing, playback: any LearningAudioPlayback, beforePlayback: @escaping @Sendable () async -> Void = {}) {
        self.service = service; self.playback = playback; self.beforePlayback = beforePlayback
    }

    func prepare(attemptID: UUID, question: LearningQuestion?) async {
        guard let question, let audio = question.audio else { reset(); return }
        await prepare(attemptID: attemptID, questionID: question.id, assetID: audio.assetId)
    }

    func prepare(attemptID: UUID, questionID: String, assetID: String) async {
        reset()
        let requestRevision = revision
        state = .loading
        do {
            let loaded = try await service.learningAudio(attemptID, questionID: questionID, assetID: assetID)
            guard revision == requestRevision, !Task.isCancelled else { return }
            data = loaded; state = .ready
        } catch {
            guard revision == requestRevision, !Task.isCancelled else { return }
            state = .failed
        }
    }

    func play(slow: Bool) {
        guard let data, state != .loading else { return }
        stop()
        let requestRevision = revision
        state = .loading
        playTask = Task { [weak self] in
            guard let self else { return }
            await beforePlayback()
            guard revision == requestRevision, !Task.isCancelled else { return }
            do {
                try await playback.play(data: data, rate: slow ? 0.75 : 1) { [weak self] success in
                    guard let self, revision == requestRevision else { return }
                    if success { hasListened = true; state = .ready } else { state = .failed }
                }
                guard revision == requestRevision, !Task.isCancelled else { return }
                state = .playing
                NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: playbackID)
            } catch {
                guard revision == requestRevision, !Task.isCancelled else { return }
                playback.stop()
                state = .failed
            }
        }
    }

    func stop(interrupted: Bool = false) {
        revision = UUID()
        playTask?.cancel(); playTask = nil
        playback.stop()
        state = data == nil ? .idle : interrupted ? .interrupted : .ready
    }

    func reset() { stop(); data = nil; hasListened = false; state = .idle }
}

@MainActor
final class NativeLearningAudioPlayback: LearningAudioPlayback {
    private let session: AudioSessionCoordinator
    private var player: AVAudioPlayer?
    private var delegate: Delegate?
    private var revision = UUID()
    private var lease: UUID?
    init(session: AudioSessionCoordinator) { self.session = session }
    func play(data: Data, rate: Float, completed: @escaping @MainActor @Sendable (Bool) -> Void) async throws {
        stop()
        let requestRevision = revision
        let acquired = try await session.acquirePlayback()
        guard revision == requestRevision, !Task.isCancelled else {
            await session.releasePlayback(acquired)
            throw CancellationError()
        }
        lease = acquired
        let audio = try AVAudioPlayer(data: data)
        let delegate = Delegate { [weak self] success in
            guard let self, revision == requestRevision else { return }
            stop()
            completed(success)
        }
        audio.delegate = delegate; audio.enableRate = true; audio.rate = rate
        audio.prepareToPlay()
        guard audio.play() else { throw BackendClientError.invalidResponse }
        self.player = audio; self.delegate = delegate
    }
    func stop() {
        revision = UUID(); player?.stop(); player = nil; delegate = nil
        if let lease { self.lease = nil; Task { await session.releasePlayback(lease) } }
    }
    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        let completed: @MainActor @Sendable (Bool) -> Void
        init(completed: @escaping @MainActor @Sendable (Bool) -> Void) { self.completed = completed }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor [completed] in completed(flag) }
        }
        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            Task { @MainActor [completed] in completed(false) }
        }
    }
}
