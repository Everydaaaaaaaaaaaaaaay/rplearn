import Foundation
import SpeechKit

/// One playing phrase plus one prepared phrase. No unbounded PCM queue, and only
/// fully played phrases are committed when interrupted (no guessed word timings).
@MainActor
public final class AdaptiveRealtimeSpeechOutput: RealtimeSpeechOutput {
    public var onPlaybackStarted: (@MainActor @Sendable () -> Void)?
    public var heardText: String {
        SpokenTextSanitizer.sanitize(completedSegments.joined(separator: " "))
    }

    private let speech: any SpeechService
    private var language = "en-US"
    private var voiceHint: SpeechVoiceHint?
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var preparation: Task<PreparedSpeech?, Never>?
    private var preparedRequest: SpeechRequest?
    private var pending: [SpeechRequest] = []
    private var completedSegments: [String] = []
    private var currentRequest: SpeechRequest?
    private var currentDidStart = false
    private nonisolated(unsafe) var playbackObserver: NSObjectProtocol?

    public init(speech: any SpeechService) {
        self.speech = speech
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .speechPlaybackDidBegin, object: nil, queue: .main
        ) { [weak self] note in
            let playbackID = note.object as? UUID
            MainActor.assumeIsolated {
                guard let self, let playbackID,
                      self.currentRequest?.playbackID == playbackID else { return }
                self.currentDidStart = true
                self.onPlaybackStarted?()
                self.prepareNextIfPossible()
            }
        }
    }

    deinit {
        if let playbackObserver { NotificationCenter.default.removeObserver(playbackObserver) }
    }

    public func beginResponse(language: String, voiceHint: SpeechVoiceHint?) async {
        _ = await stop()
        self.language = language
        self.voiceHint = voiceHint
        completedSegments.removeAll(keepingCapacity: true)
    }

    public func enqueue(_ text: String) {
        let text = SpokenTextSanitizer.sanitize(text)
        guard !text.isEmpty else { return }
        pending.append(SpeechRequest(
            text: text, language: language, purpose: .realtimeConversation, voiceHint: voiceHint,
            playbackID: UUID()
        ))
        prepareNextIfPossible()
        guard worker == nil else { return }
        let generation = generation
        worker = Task { [weak self] in await self?.drain(generation: generation) }
    }

    private func prepareNextIfPossible() {
        // Starting synthesis before actual playback could run two Core ML
        // inferences concurrently. A playback notification means synthesis ended.
        guard currentDidStart, preparation == nil, let next = pending.first else { return }
        preparedRequest = next
        preparation = Task { [speech] in
            guard !Task.isCancelled else { return nil }
            return await speech.prepareForPlayback(next)
        }
    }

    private func drain(generation: UUID) async {
        while !Task.isCancelled, self.generation == generation, !pending.isEmpty {
            let request = pending.removeFirst()
            let prepared = preparedRequest == request ? await preparation?.value : nil
            guard !Task.isCancelled, self.generation == generation else { return }
            preparation = nil
            preparedRequest = nil
            currentRequest = request
            currentDidStart = false
            await speech.speakAndWait(request, prepared: prepared)
            guard !Task.isCancelled, self.generation == generation else { return }
            if currentDidStart { completedSegments.append(request.text) }
            currentRequest = nil
            currentDidStart = false
        }
        if self.generation == generation { worker = nil }
    }

    public func waitUntilFinished() async { await worker?.value }

    @discardableResult
    public func stop() async -> String {
        let spoken = heardText
        generation = UUID()
        let worker = worker
        let preparation = preparation
        self.worker = nil
        self.preparation = nil
        preparedRequest = nil
        pending.removeAll()
        currentRequest = nil
        currentDidStart = false
        completedSegments.removeAll()
        worker?.cancel()
        preparation?.cancel()
        // Stop audible output before waiting for any in-flight local inference.
        await speech.stopSpeaking()
        _ = await preparation?.value
        await worker?.value
        return spoken
    }
}
