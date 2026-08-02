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

    @Test("连续识别失败会退避恢复，不会同步重启卡死主线程")
    func backsOffRecognitionFailures() async throws {
        let input = MockSpeechInput()
        let session = makeSession(
            input: input,
            recognitionRecoveryPolicy: .init(
                retryDelays: [.milliseconds(10), .milliseconds(20)]
            )
        )

        await session.start()
        for _ in 0..<20 {
            input.emitFailure("识别服务暂时不可用")
        }
        #expect(input.restartCount == 0)

        try await Task.sleep(for: .milliseconds(30))
        #expect(input.restartCount == 1)

        input.emitFailure("识别服务仍不可用")
        try await Task.sleep(for: .milliseconds(40))
        #expect(input.restartCount == 2)

        input.emitFailure("识别服务仍不可用")
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.phase == .failed)
        #expect(input.stopCount == 1)
        await session.stop()
    }

    @Test("得到有效转写后会重置识别恢复次数")
    func resetsRecognitionRecoveryAfterTranscript() async throws {
        let input = MockSpeechInput()
        let session = makeSession(
            input: input,
            recognitionRecoveryPolicy: .init(retryDelays: [.milliseconds(10)])
        )

        await session.start()
        input.emitFailure("第一次失败")
        try await Task.sleep(for: .milliseconds(20))
        input.emitTranscript("Hello")
        input.emitFailure("第二次失败")
        try await Task.sleep(for: .milliseconds(20))

        #expect(input.restartCount == 2)
        #expect(session.phase == .listening)
        await session.stop()
    }

    private func makeSession(
        input: MockSpeechInput,
        recognitionRecoveryPolicy: SpeechRecognitionRecoveryPolicy
    ) -> RealtimeVoiceSession {
        RealtimeVoiceSession(
            input: input,
            output: MockSpeechOutput(),
            conversation: RealtimeVoiceConversationClient(
                replyStream: { _ in AsyncThrowingStream { $0.finish() } },
                saveAssistant: { _ in }
            ),
            localeIdentifier: "en-US",
            voiceLanguage: "en-US",
            contextualStrings: [],
            turnPolicy: .init(),
            recognitionRecoveryPolicy: recognitionRecoveryPolicy
        )
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
    var restartCount = 0
    var stopCount = 0

    func start(localeIdentifier: String, contextualStrings: [String]) async throws {}
    func restartRecognition() {
        restartCount += 1
        latestTranscript = ""
    }
    func setMuted(_ muted: Bool) {}
    func stop() async {
        stopCount += 1
    }

    func emitLevel(_ level: Double, at timestamp: TimeInterval) {
        onLevel?(level, timestamp)
    }

    func emitTranscript(_ text: String) {
        latestTranscript = text
        onTranscript?(text)
    }

    func emitFailure(_ message: String) {
        onFailure?(message)
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
