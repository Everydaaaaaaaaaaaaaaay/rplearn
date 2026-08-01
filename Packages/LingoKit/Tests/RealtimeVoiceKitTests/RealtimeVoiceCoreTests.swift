import Foundation
import Testing
@testable import RealtimeVoiceKit

@Suite("RealtimeVoiceCore")
struct RealtimeVoiceCoreTests {
    @Test("持续说话可触发插话，并在静音后结束回合")
    func detectsInterruptionAndTurnEnd() {
        var detector = ClientVoiceTurnDetector(
            policy: VoiceTurnDetectionPolicy(
                activationLevel: 0.1,
                releaseLevel: 0.05,
                minimumSpeechDuration: 0.15,
                interruptionDuration: 0.2,
                endOfTurnSilence: 0.5
            )
        )

        #expect(detector.ingest(level: 0.2, at: 1.0, agentIsBusy: true) == [.speechStarted])
        #expect(detector.ingest(level: 0.2, at: 1.25, agentIsBusy: true) == [.interruption])
        #expect(detector.ingest(level: 0.01, at: 1.4, agentIsBusy: false).isEmpty)
        #expect(detector.ingest(level: 0.01, at: 1.95, agentIsBusy: false) == [.speechEnded])
    }

    @Test("短噪声不会提交为用户回合")
    func rejectsBriefNoise() {
        var detector = ClientVoiceTurnDetector(
            policy: VoiceTurnDetectionPolicy(
                activationLevel: 0.1,
                releaseLevel: 0.05,
                minimumSpeechDuration: 0.3,
                interruptionDuration: 0.2,
                endOfTurnSilence: 0.2
            )
        )

        #expect(detector.ingest(level: 0.2, at: 1.0, agentIsBusy: false) == [.speechStarted])
        _ = detector.ingest(level: 0.01, at: 1.05, agentIsBusy: false)
        #expect(detector.ingest(level: 0.01, at: 1.3, agentIsBusy: false).isEmpty)
    }

    @Test("模型文本按标点增量切句")
    func segmentsStreamingTextAtPunctuation() {
        var segmenter = StreamingSpeechSegmenter()

        #expect(segmenter.append("That sounds great! What do ") == ["That sounds great!"])
        #expect(segmenter.append("you think?") == ["What do you think?"])
        #expect(segmenter.finish().isEmpty)
    }

    @Test("无标点长回复会在完整单词后提前播报")
    func segmentsLongUnpunctuatedText() {
        var segmenter = StreamingSpeechSegmenter(maximumWordsWithoutPunctuation: 4)

        #expect(segmenter.append("one two three four ") == ["one two three four"])
        #expect(segmenter.append("five six") == [])
        #expect(segmenter.finish() == ["five six"])
    }

    @Test("播报文本移除表情和 Markdown 符号")
    func sanitizesSpokenText() {
        #expect(SpokenTextSanitizer.sanitize("**Hi** 😊  there!") == "Hi there!")
    }
}

@Suite("RealtimeVoiceSession")
@MainActor
struct RealtimeVoiceSessionTests {
    @Test("识别到完整回合后流式播报并保存实际听到的文本")
    func completesClientSideConversationLoop() async throws {
        let input = MockSpeechInput()
        let output = MockSpeechOutput()
        let probe = ConversationProbe()
        let client = RealtimeVoiceConversationClient(
            replyStream: { text in
                probe.userTexts.append(text)
                return AsyncThrowingStream { continuation in
                    continuation.yield("Nice to meet you!")
                    continuation.finish()
                }
            },
            saveAssistant: { text in
                probe.assistantTexts.append(text)
            }
        )
        let session = RealtimeVoiceSession(
            input: input,
            output: output,
            conversation: client,
            localeIdentifier: "en-US",
            voiceLanguage: "en-GB",
            contextualStrings: [],
            turnPolicy: VoiceTurnDetectionPolicy(
                activationLevel: 0.1,
                releaseLevel: 0.05,
                minimumSpeechDuration: 0.1,
                interruptionDuration: 0.2,
                endOfTurnSilence: 0.2
            )
        )

        await session.start()
        input.emitLevel(0.2, at: 1.0)
        input.emitTranscript("Hello there")
        input.emitLevel(0.01, at: 1.3)
        input.emitLevel(0.01, at: 1.55)
        try await Task.sleep(for: .milliseconds(300))

        #expect(probe.userTexts == ["Hello there"])
        #expect(probe.assistantTexts == ["Nice to meet you!"])
        #expect(session.phase == .listening)
        #expect(session.assistantTranscript == "Nice to meet you!")
        await session.stop()
    }
}

@MainActor
private final class ConversationProbe {
    var userTexts: [String] = []
    var assistantTexts: [String] = []
}

@MainActor
private final class MockSpeechInput: RealtimeSpeechInput {
    var latestTranscript = ""
    var onLevel: (@MainActor @Sendable (Double, TimeInterval) -> Void)?
    var onTranscript: (@MainActor @Sendable (String) -> Void)?
    var onFailure: (@MainActor @Sendable (String) -> Void)?

    func start(localeIdentifier: String, contextualStrings: [String]) async throws {}
    func restartRecognition() {
        latestTranscript = ""
    }
    func setMuted(_ muted: Bool) {}
    func stop() async {}

    func emitLevel(_ level: Double, at timestamp: TimeInterval) {
        onLevel?(level, timestamp)
    }

    func emitTranscript(_ text: String) {
        latestTranscript = text
        onTranscript?(text)
    }
}

@MainActor
private final class MockSpeechOutput: RealtimeSpeechOutput {
    var heardText = ""

    func beginResponse(language: String) {
        heardText = ""
    }

    func enqueue(_ text: String) {
        heardText = [heardText, text].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func waitUntilFinished() async {}

    func stop() -> String {
        heardText
    }
}
