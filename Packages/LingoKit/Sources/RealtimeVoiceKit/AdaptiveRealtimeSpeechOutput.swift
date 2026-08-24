import Foundation
import SpeechKit

/// 把任意 SpeechService 适配成可增量排队、可立即打断的实时输出。
/// AdaptiveSpeechService 会优先走已安装的 Pocket TTS，未准备好时无等待地回退 Apple TTS。
@MainActor
public final class AdaptiveRealtimeSpeechOutput: RealtimeSpeechOutput {
    public var heardText: String {
        let current = currentDidStart ? [currentSegment] : []
        return SpokenTextSanitizer.sanitize((completedSegments + current).joined(separator: " "))
    }

    private let speech: any SpeechService
    private var language = "en-US"
    private var voiceHint: SpeechVoiceHint?
    private var generation = UUID()
    private var tailTask: Task<Void, Never>?
    private var completedSegments: [String] = []
    private var currentSegment = ""
    private var currentDidStart = false
    private nonisolated(unsafe) var playbackObserver: NSObjectProtocol?

    public init(speech: any SpeechService) {
        self.speech = speech
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .speechPlaybackDidBegin,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.currentSegment.isEmpty else { return }
                self.currentDidStart = true
            }
        }
    }

    deinit {
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
        }
    }

    public func beginResponse(language: String, voiceHint: SpeechVoiceHint?) async {
        _ = await stop()
        self.language = language
        self.voiceHint = voiceHint
        completedSegments.removeAll(keepingCapacity: true)
    }

    public func enqueue(_ text: String) {
        let segment = SpokenTextSanitizer.sanitize(text)
        guard !segment.isEmpty else { return }

        let generation = generation
        let previous = tailTask
        let request = SpeechRequest(
            text: segment,
            language: language,
            purpose: .realtimeConversation,
            voiceHint: voiceHint
        )
        tailTask = Task { [weak self, speech] in
            await previous?.value
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.currentSegment = segment
            self.currentDidStart = false
            await speech.speakAndWait(request)
            guard !Task.isCancelled, self.generation == generation else { return }
            if self.currentDidStart {
                self.completedSegments.append(segment)
            }
            self.currentSegment = ""
            self.currentDidStart = false
        }
    }

    public func waitUntilFinished() async {
        await tailTask?.value
    }

    @discardableResult
    public func stop() async -> String {
        let spoken = heardText
        generation = UUID()
        let task = tailTask
        tailTask = nil
        task?.cancel()
        await speech.stopSpeaking()
        await task?.value
        currentSegment = ""
        currentDidStart = false
        return spoken
    }
}
