import Foundation
import Testing
@testable import RealtimeVoiceKit

@Suite("RealtimeVoiceCore")
struct RealtimeVoiceCoreTests {
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

    @Test("逐字符输入只扫描增量并保持切句结果")
    func segmentsCharacterStreamIncrementally() {
        var segmenter = StreamingSpeechSegmenter(maximumWordsWithoutPunctuation: 4)
        var segments: [String] = []

        for character in "one two three four five six seven eight " {
            segments.append(contentsOf: segmenter.append(String(character)))
        }

        #expect(segments == ["one two three four", "five six seven eight"])
        #expect(segmenter.finish().isEmpty)
    }

    @Test("同一增量内标点优先形成自然句子")
    func punctuationTakesPriorityWithinDelta() {
        var segmenter = StreamingSpeechSegmenter(maximumWordsWithoutPunctuation: 4)

        #expect(segmenter.append("one two three four five! six") == [
            "one two three four five!",
        ])
        #expect(segmenter.finish() == ["six"])
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
            turnPolicy: VoiceTurnPolicy(endOfTurnDelay: .milliseconds(80))
        )

        await session.start()
        input.emitTranscription("Hello there", isFinal: true)
        let completed = await eventually {
            probe.assistantTexts == ["Nice to meet you!"]
        }

        #expect(completed)
        #expect(probe.userTexts == ["Hello there"])
        #expect(probe.assistantTexts == ["Nice to meet you!"])
        #expect(session.phase == .listening)
        #expect(session.assistantTranscript == "Nice to meet you!")
        await session.stop()
    }

    @Test("部分转写在无新增后提交，并以最新文本延长等待")
    func debouncesPartialTranscriptions() async throws {
        let input = MockSpeechInput()
        let probe = ConversationProbe()
        let session = makeSession(
            input: input,
            probe: probe,
            turnPolicy: VoiceTurnPolicy(endOfTurnDelay: .milliseconds(80))
        )

        await session.start()
        input.emitTranscription("How are", isFinal: false)
        try await Task.sleep(for: .milliseconds(50))
        input.emitTranscription("How are you", isFinal: false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(probe.userTexts.isEmpty)

        let completed = await eventually { probe.userTexts == ["How are you"] }
        #expect(completed)
        #expect(input.restartCount == 1)
        await session.stop()
    }

    @Test("系统最终转写无需等待静音防抖")
    func commitsFinalTranscriptionImmediately() async {
        let input = MockSpeechInput()
        let probe = ConversationProbe()
        let session = makeSession(
            input: input,
            probe: probe,
            turnPolicy: VoiceTurnPolicy(endOfTurnDelay: .seconds(5))
        )

        await session.start()
        input.emitTranscription("Ready to go", isFinal: true)
        let completed = await eventually { probe.userTexts == ["Ready to go"] }

        #expect(completed)
        #expect(input.restartCount == 1)
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

        let firstRecovery = await eventually { input.restartCount == 1 }
        #expect(firstRecovery)

        input.emitFailure("识别服务仍不可用")
        let secondRecovery = await eventually { input.restartCount == 2 }
        #expect(secondRecovery)

        input.emitFailure("识别服务仍不可用")
        let stopped = await eventually { session.phase == .failed && input.stopCount == 1 }
        #expect(stopped)
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
        let firstRecovery = await eventually { input.restartCount == 1 }
        #expect(firstRecovery)
        input.emitTranscription("Hello", isFinal: false)
        input.emitFailure("第二次失败")
        let secondRecovery = await eventually { input.restartCount == 2 }

        #expect(secondRecovery)
        #expect(session.phase == .listening)
        await session.stop()
    }

    private func makeSession(
        input: MockSpeechInput,
        probe: ConversationProbe = ConversationProbe(),
        turnPolicy: VoiceTurnPolicy = .init(),
        recognitionRecoveryPolicy: SpeechRecognitionRecoveryPolicy = .init()
    ) -> RealtimeVoiceSession {
        RealtimeVoiceSession(
            input: input,
            output: MockSpeechOutput(),
            conversation: RealtimeVoiceConversationClient(
                replyStream: { text in
                    probe.userTexts.append(text)
                    return AsyncThrowingStream { $0.finish() }
                },
                saveAssistant: { _ in }
            ),
            localeIdentifier: "en-US",
            voiceLanguage: "en-US",
            contextualStrings: [],
            turnPolicy: turnPolicy,
            recognitionRecoveryPolicy: recognitionRecoveryPolicy
        )
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

@MainActor
private final class ConversationProbe {
    var userTexts: [String] = []
    var assistantTexts: [String] = []
}

@MainActor
private final class MockSpeechInput: RealtimeSpeechInput {
    var onLevel: (@MainActor @Sendable (Double) -> Void)?
    var onTranscription: (@MainActor @Sendable (RealtimeTranscription) -> Void)?
    var onFailure: (@MainActor @Sendable (String) -> Void)?
    var restartCount = 0
    var stopCount = 0

    func start(localeIdentifier: String, contextualStrings: [String]) async throws {}
    func restartRecognition() {
        restartCount += 1
    }
    func setMuted(_ muted: Bool) {}
    func stop() async {
        stopCount += 1
    }

    func emitLevel(_ level: Double) {
        onLevel?(level)
    }

    func emitTranscription(_ text: String, isFinal: Bool) {
        onTranscription?(RealtimeTranscription(text: text, isFinal: isFinal))
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
