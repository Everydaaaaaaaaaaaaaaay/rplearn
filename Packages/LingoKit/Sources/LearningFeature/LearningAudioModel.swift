@preconcurrency import AVFoundation
import BackendKit
import CoreKit
import Foundation
import Observation
import SpeechKit

/// 只在当前挑战内复用脚本，不跨账号或挑战共享；失败和取消均不入缓存。
actor LearningAudioCache {
    private struct Key: Hashable {
        let attemptID: UUID
        let assetID: String
        let questionID: String
    }
    private let byteLimit: Int
    private var entries: [Key: LearningSpeechScript] = [:]
    private var order: [Key] = []
    private var byteCount = 0

    init(byteLimit: Int = 2 * 1024 * 1024) { self.byteLimit = byteLimit }

    func load(service: any LearningServing, attemptID: UUID, questionID: String, assetID: String) async throws -> LearningSpeechScript {
        try Task.checkCancellation()
        let key = Key(attemptID: attemptID, assetID: assetID, questionID: questionID)
        if let cached = entries[key] {
            order.removeAll { $0 == key }; order.append(key)
            return cached
        }
        let data = try await service.learningSpeech(attemptID, questionID: questionID, assetID: assetID)
        try Task.checkCancellation()
        let size = data.segments.reduce(0) { $0 + $1.text.utf8.count }
        guard size <= byteLimit else { return data }
        if let previous = entries.removeValue(forKey: key) { byteCount -= previous.segments.reduce(0) { $0 + $1.text.utf8.count } }
        order.removeAll { $0 == key }
        while byteCount + size > byteLimit || order.count >= 12 {
            let oldest = order.removeFirst()
            byteCount -= entries.removeValue(forKey: oldest)?.segments.reduce(0) { $0 + $1.text.utf8.count } ?? 0
        }
        entries[key] = data; order.append(key); byteCount += size
        return data
    }
}

@MainActor
protocol LearningAudioPlayback: AnyObject {
    func play(script: LearningSpeechScript, voice: SupertonicVoice, rate: Float, started: @escaping @MainActor @Sendable () -> Void, completed: @escaping @MainActor @Sendable (Bool) -> Void) async throws
    func stop()
}

@MainActor @Observable
final class LearningAudioModel {
    enum State: Equatable { case idle, loading, ready, playing, interrupted, failed }
    private(set) var state: State = .idle
    private(set) var hasListened = false
    private(set) var completedPlayCount = 0
    var canPlay: Bool { completedPlayCount < ListeningVoicePolicy.maximumPlayCount }
    var isPlaybackActive: Bool { state == .playing || (state == .loading && data != nil) }
    let playbackID = UUID()
    @ObservationIgnored private let service: any LearningServing
    @ObservationIgnored private let playback: any LearningAudioPlayback
    @ObservationIgnored private let beforePlayback: @Sendable () async -> Void
    @ObservationIgnored private let cache: LearningAudioCache
    @ObservationIgnored private var completedPlays: [String: Int] = [:]
    @ObservationIgnored private var currentAssetKey: String?
    @ObservationIgnored private var data: LearningSpeechScript?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var playTask: Task<Void, Never>?

    init(service: any LearningServing, playback: any LearningAudioPlayback, beforePlayback: @escaping @Sendable () async -> Void = {}, cache: LearningAudioCache = LearningAudioCache()) {
        self.service = service; self.playback = playback; self.beforePlayback = beforePlayback; self.cache = cache
    }

    func prepare(attemptID: UUID, question: LearningQuestion?) async {
        guard let question, let audio = question.audio else { reset(); return }
        await prepare(attemptID: attemptID, questionID: question.id, assetID: audio.assetId)
    }

    func prepare(attemptID: UUID, questionID: String, assetID: String) async {
        reset()
        currentAssetKey = "\(attemptID.uuidString):\(assetID)"
        completedPlayCount = completedPlays[currentAssetKey ?? ""] ?? 0
        hasListened = completedPlayCount > 0
        let requestRevision = revision
        state = .loading
        do {
            let loaded = try await cache.load(service: service, attemptID: attemptID, questionID: questionID, assetID: assetID)
            guard revision == requestRevision, !Task.isCancelled else { return }
            data = loaded; state = .ready
        } catch {
            guard revision == requestRevision, !Task.isCancelled else { return }
            state = .failed
        }
    }

    func play(slow: Bool) {
        guard let data, state != .loading, canPlay else { return }
        stop()
        let requestRevision = revision
        state = .loading
        playTask = Task { [weak self] in
            guard let self else { return }
            await beforePlayback()
            guard revision == requestRevision, !Task.isCancelled else { return }
            do {
                try await playback.play(script: data, voice: ListeningVoicePolicy.voice(completedPlays: completedPlayCount), rate: slow ? 0.75 : 1, started: { [weak self] in
                    guard let self, revision == requestRevision else { return }
                    state = .playing
                    NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: playbackID)
                }) { [weak self] success in
                    guard let self, revision == requestRevision else { return }
                    revision = UUID()
                    if success {
                        completedPlayCount += 1; hasListened = true
                        if let currentAssetKey { completedPlays[currentAssetKey] = completedPlayCount }
                        state = .ready
                    } else { state = .failed }
                }
                guard revision == requestRevision, !Task.isCancelled else { return }
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

    func reset() { stop(); data = nil; hasListened = false; completedPlayCount = 0; state = .idle }
}

@MainActor
final class NativeLearningAudioPlayback: LearningAudioPlayback {
    private let player: ListeningSpeechPlayer
    init(session: AudioSessionCoordinator, speech: any SpeechService) { player = ListeningSpeechPlayer(speech: speech, session: session) }
    func play(script: LearningSpeechScript, voice: SupertonicVoice, rate: Float,
              started: @escaping @MainActor @Sendable () -> Void,
              completed: @escaping @MainActor @Sendable (Bool) -> Void) async throws {
        player.play(segments: script.segments.map { ListeningSpeechSegment(text: $0.text, pauseAfterMs: $0.pauseAfterMs) },
                    voice: voice, rate: rate, started: started, completed: completed)
    }
    func stop() { player.stop() }
}
