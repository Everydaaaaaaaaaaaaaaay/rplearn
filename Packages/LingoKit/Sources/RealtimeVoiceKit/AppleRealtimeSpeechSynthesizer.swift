import AVFoundation
import Foundation
import SpeechKit

private enum RealtimeSpeechOutputEvent: Sendable {
    case started
    case progressed(String, Int)
    case finished(String)
    case cancelled
}

private final class RealtimeSpeechOutputDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let generation: UUID
    private let report: @Sendable (UUID, RealtimeSpeechOutputEvent) -> Void

    init(
        generation: UUID,
        report: @escaping @Sendable (UUID, RealtimeSpeechOutputEvent) -> Void
    ) {
        self.generation = generation
        self.report = report
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        report(generation, .started)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        report(
            generation,
            .progressed(utterance.speechString, NSMaxRange(characterRange))
        )
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        report(generation, .finished(utterance.speechString))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        report(generation, .cancelled)
    }
}

/// 可增量排队、可立即打断，并记录用户实际听到文本的 Apple 本地 TTS。
@MainActor
public final class AppleRealtimeSpeechSynthesizer: RealtimeSpeechOutput {
    public var heardText: String {
        SpokenTextSanitizer.sanitize((completedSegments + [currentPrefix]).joined(separator: " "))
    }

    private var synthesizer: AVSpeechSynthesizer?
    private var delegate: RealtimeSpeechOutputDelegate?
    private var generation: UUID?
    private var language = "en-US"
    private var pendingCount = 0
    private var completedSegments: [String] = []
    private var currentPrefix = ""
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func beginResponse(language: String) {
        _ = stop()
        self.language = language
        completedSegments = []
        currentPrefix = ""

        let generation = UUID()
        let delegate = RealtimeSpeechOutputDelegate(generation: generation) { [weak self] generation, event in
            Task { @MainActor [weak self] in
                self?.handle(event, generation: generation)
            }
        }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = delegate
        self.generation = generation
        self.delegate = delegate
        self.synthesizer = synthesizer
    }

    public func enqueue(_ text: String) {
        let spoken = SpokenTextSanitizer.sanitize(text)
        guard !spoken.isEmpty, let synthesizer, generation != nil else { return }

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = AppleTTSService.selectBestVoice(
            from: AVSpeechSynthesisVoice.speechVoices(),
            language: language
        )
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.preUtteranceDelay = pendingCount == 0 ? 0 : 0.03
        utterance.postUtteranceDelay = 0.04
        pendingCount += 1
        synthesizer.speak(utterance)
    }

    public func waitUntilFinished() async {
        guard pendingCount > 0 else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    @discardableResult
    public func stop() -> String {
        let spoken = heardText
        generation = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer?.delegate = nil
        synthesizer = nil
        delegate = nil
        pendingCount = 0
        resumeWaiters()
        return spoken
    }

    private func handle(_ event: RealtimeSpeechOutputEvent, generation: UUID) {
        guard generation == self.generation else { return }
        switch event {
        case .started:
            break
        case .progressed(let text, let utf16End):
            let clampedEnd = min(max(0, utf16End), text.utf16.count)
            let end = String.Index(utf16Offset: clampedEnd, in: text)
            currentPrefix = String(text[..<end])
        case .finished(let text):
            completedSegments.append(text)
            currentPrefix = ""
            pendingCount = max(0, pendingCount - 1)
            if pendingCount == 0 {
                resumeWaiters()
            }
        case .cancelled:
            pendingCount = 0
            resumeWaiters()
        }
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
