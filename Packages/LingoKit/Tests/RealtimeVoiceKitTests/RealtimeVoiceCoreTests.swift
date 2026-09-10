import Foundation
import SpeechKit
import Testing
@testable import RealtimeVoiceKit

@Suite("实时语音分句")
struct StreamingSpeechSegmenterTests {
    @Test("标点到达时立即交付完整短句")
    func punctuationFlushesImmediately() {
        var segmenter = StreamingSpeechSegmenter()
        #expect(segmenter.append("Hello there") == [])
        #expect(segmenter.append("! How are") == ["Hello there!"])
        #expect(segmenter.finish() == ["How are"])
    }

    @Test("无标点回复会按短词组开播")
    func longTextStartsBeforeCompletion() {
        var segmenter = StreamingSpeechSegmenter(maximumWordsWithoutPunctuation: 5)
        let segments = segmenter.append("one two three four five six ")
        #expect(segments == ["one two three four five"])
        #expect(segmenter.finish() == ["six"])
    }
    @Test("跨 token 的小数和称谓不被拆开朗读")
    func decimalsAndAbbreviationsSurviveChunking() {
        var segmenter = StreamingSpeechSegmenter()
        #expect(segmenter.append("Ask Dr.") == [])
        #expect(segmenter.append(" Lee for 3.") == [])
        #expect(segmenter.append("5 dollars. ") == ["Ask Dr. Lee for 3.5 dollars."])
    }

    @Test("首句快速开播，后续允许较长词组以保持韵律")
    func laterPhrasesHaveMoreContext() {
        var segmenter = StreamingSpeechSegmenter()
        #expect(segmenter.append("one two three four five six seven ") == ["one two three four five six seven"])
        #expect(segmenter.append("eight nine ten eleven twelve thirteen fourteen ") == [])
        #expect(segmenter.finish() == ["eight nine ten eleven twelve thirteen fourteen"])
    }

}

@Suite("低成本实时语音状态机")
@MainActor
struct RealtimeVoiceSessionTests {
    @Test("端侧终稿驱动流式回复、短句播报和持久化")
    func streamsReplyAndPersistsHeardText() async {
        let input = MockSpeechInput()
        let output = MockSpeechOutput()
        let probe = ConversationProbe()
        let session = makeSession(input: input, output: output, probe: probe)

        await session.start()
        #expect(session.phase == .listening)
        input.emitSpeechStarted()
        input.emit(.init(text: "Hello", isFinal: false))
        #expect(session.phase == .userSpeaking)
        #expect(session.liveTranscript == "Hello")
        input.emit(.init(text: "Hello there", isFinal: true))

        #expect(await eventually {
            probe.replyInputs == ["Hello there"]
                && output.enqueued == ["Nice to meet you."]
                && probe.assistants == [.init(text: "Nice to meet you.", interrupted: false)]
        })
        #expect(session.phase == .listening)
        #expect(session.userTranscript == "Hello there")
        await session.stop()
        #expect(probe.assistants.count == 1)
    }

    @Test("用户开口会立即取消模型和 TTS，并保存已听片段")
    func bargeInInterruptsImmediately() async {
        let input = MockSpeechInput()
        let output = MockSpeechOutput()
        let probe = ConversationProbe(keepsStreamOpen: true)
        let session = makeSession(input: input, output: output, probe: probe)

        await session.start()
        input.emit(.init(text: "Tell me something", isFinal: true))
        #expect(await eventually { session.phase == .speaking })

        input.emitSpeechStarted()
        #expect(await eventually {
            session.phase == .userSpeaking
                && output.stopCount >= 1
                && probe.assistants == [.init(text: "This is the first phrase.", interrupted: true)]
        })
        await session.stop()
    }

    @Test("语义端点漏报时会请求输入引擎强制定稿")
    func partialTranscriptHasFallbackEndpoint() async {
        let input = MockSpeechInput()
        let output = MockSpeechOutput()
        let probe = ConversationProbe()
        let session = makeSession(
            input: input,
            output: output,
            probe: probe,
            turnPolicy: .init(fallbackEndOfTurnDelay: .milliseconds(20))
        )

        await session.start()
        input.emit(.init(text: "A partial sentence", isFinal: false))
        #expect(await eventually { input.finishTurnCount == 1 })
        await session.stop()
    }

    @Test("静音直接传递给端侧输入且清空实时字幕")
    func muteControlsInput() async {
        let input = MockSpeechInput()
        let session = makeSession(
            input: input,
            output: MockSpeechOutput(),
            probe: ConversationProbe()
        )
        await session.start()
        input.emit(.init(text: "unfinished", isFinal: false))
        session.toggleMuted()
        #expect(session.isMuted)
        #expect(session.liveTranscript.isEmpty)
        #expect(input.muteStates.last == true)
        session.toggleMuted()
        #expect(input.muteStates.last == false)
        await session.stop()
    }

    @Test("终稿排队后立即挂断不会再发起付费请求")
    func hangupRejectsQueuedFinal() async {
        let input = MockSpeechInput()
        let probe = ConversationProbe()
        let session = makeSession(input: input, output: MockSpeechOutput(), probe: probe)
        await session.start()
        input.emit(.init(text: "Do not send this after hangup", isFinal: true))
        await session.stop()
        await Task.yield()
        #expect(probe.replyInputs.isEmpty)
        #expect(session.phase == .idle)
    }

    @Test("文字不变但仍有说话声时不强制定稿")
    func ongoingSpeechDefersEndpoint() async {
        let input = MockSpeechInput()
        let session = makeSession(input: input, output: MockSpeechOutput(), probe: ConversationProbe(),
                                  turnPolicy: .init(fallbackEndOfTurnDelay: .milliseconds(60)))
        await session.start()
        input.emit(.init(text: "I would like", isFinal: false))
        for _ in 0..<10 {
            input.onLevel?(0.2)
            try? await Task.sleep(for: .milliseconds(15))
        }
        #expect(input.finishTurnCount == 0)
        #expect(await eventually { input.finishTurnCount == 1 })
        await session.stop()
    }

    @Test("重复 partial 不会无限延长静音兜底")
    func repeatedPartialDoesNotResetSilence() async {
        let input = MockSpeechInput()
        let session = makeSession(input: input, output: MockSpeechOutput(), probe: ConversationProbe(),
                                  turnPolicy: .init(fallbackEndOfTurnDelay: .milliseconds(30)))
        await session.start()
        for _ in 0..<8 {
            input.emit(.init(text: "A table please", isFinal: false))
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(input.finishTurnCount == 1)
        await session.stop()
    }

    @Test("能量门漏报开口时 partial 仍会打断旧回复")
    func partialAlsoInterruptsResponse() async {
        let input = MockSpeechInput()
        let output = MockSpeechOutput()
        let probe = ConversationProbe(keepsStreamOpen: true)
        let session = makeSession(input: input, output: output, probe: probe)
        await session.start()
        input.emit(.init(text: "Tell me something", isFinal: true))
        #expect(await eventually { session.phase == .speaking })
        input.emit(.init(text: "Wait", isFinal: false))
        #expect(await eventually { probe.assistants.count == 1 })
        #expect(session.liveTranscript == "Wait")
        #expect(session.phase == .userSpeaking)
        await session.stop()
        #expect(probe.assistants.count == 1)
    }

    @Test("额度失效时等已开始的回复完整结束，且拒绝下一轮")
    func finishAdmittedResponseBeforeEnding() async {
        let input = MockSpeechInput()
        let output = MockSpeechOutput()
        let probe = ConversationProbe(keepsStreamOpen: true)
        let session = makeSession(input: input, output: output, probe: probe)
        await session.start()
        input.emit(.init(text: "One last question", isFinal: true))
        #expect(await eventually { session.phase == .speaking })
        let ending = Task { await session.finishSpeakingAndStop() }
        #expect(await eventually { session.isEnding })
        #expect(session.phase == .speaking)
        input.emit(.init(text: "Must not send another request", isFinal: true))
        probe.finishStream()
        await ending.value
        #expect(probe.replyInputs == ["One last question"])
        #expect(probe.assistants == [.init(text: "This is the first phrase.", interrupted: false)])
        #expect(session.phase == .idle)
    }

    @Test("上游自行取消时释放当前回合，不永久停在思考状态")
    func upstreamCancellationReleasesTurn() async {
        let input = MockSpeechInput()
        let session = RealtimeVoiceSession(input: input, output: MockSpeechOutput(), conversation: .init(
            replyStream: { _ in AsyncThrowingStream { $0.finish(throwing: CancellationError()) } },
            saveAssistant: { _, _ in }
        ))
        await session.start()
        input.emit(.init(text: "Hello", isFinal: true))
        await Task.yield()
        #expect(await eventually { session.phase == .listening })
        await session.finishSpeakingAndStop()
        #expect(session.phase == .idle)
    }

    private func makeSession(
        input: MockSpeechInput,
        output: MockSpeechOutput,
        probe: ConversationProbe,
        turnPolicy: VoiceTurnPolicy = .init()
    ) -> RealtimeVoiceSession {
        RealtimeVoiceSession(
            input: input,
            output: output,
            conversation: RealtimeVoiceConversationClient(
                replyStream: { text in
                    probe.replyInputs.append(text)
                    return probe.makeStream()
                },
                saveAssistant: { text, interrupted in
                    probe.assistants.append(.init(text: text, interrupted: interrupted))
                }
            ),
            turnPolicy: turnPolicy
        )
    }

    private func eventually(
        timeout: Int = 150,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<timeout {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

@MainActor
private final class MockSpeechInput: RealtimeSpeechInput {
    var onLevel: (@MainActor @Sendable (Double) -> Void)?
    var onSpeechStarted: (@MainActor @Sendable () -> Void)?
    var onTranscription: (@MainActor @Sendable (RealtimeTranscription) -> Void)?
    var onFailure: (@MainActor @Sendable (String) -> Void)?

    var startCount = 0
    var stopCount = 0
    var finishTurnCount = 0
    var muteStates: [Bool] = []

    func start() async throws {
        startCount += 1
    }

    func finishCurrentTurn() async { finishTurnCount += 1 }
    func setMuted(_ muted: Bool) { muteStates.append(muted) }
    func stop() async { stopCount += 1 }

    func emitSpeechStarted() { onSpeechStarted?() }
    func emit(_ transcription: RealtimeTranscription) { onTranscription?(transcription) }
}

@MainActor
private final class MockSpeechOutput: RealtimeSpeechOutput {
    var onPlaybackStarted: (@MainActor @Sendable () -> Void)?
    var heardText: String { enqueued.joined(separator: " ") }
    var enqueued: [String] = []
    var stopCount = 0

    func beginResponse(language: String, voiceHint: SpeechVoiceHint?) async {
        enqueued.removeAll()
    }

    func enqueue(_ text: String) { enqueued.append(text); onPlaybackStarted?() }
    func waitUntilFinished() async {}

    func stop() async -> String {
        stopCount += 1
        return heardText
    }
}

@MainActor
private final class ConversationProbe {
    struct Assistant: Equatable {
        let text: String
        let interrupted: Bool
    }

    var replyInputs: [String] = []
    var assistants: [Assistant] = []
    private let keepsStreamOpen: Bool
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    func finishStream() { continuation?.finish() }

    init(keepsStreamOpen: Bool = false) {
        self.keepsStreamOpen = keepsStreamOpen
    }

    func makeStream() -> AsyncThrowingStream<String, Error> {
        let keepsStreamOpen = keepsStreamOpen
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(keepsStreamOpen ? "This is the first phrase. " : "Nice to meet you.")
            if !keepsStreamOpen { continuation.finish() }
        }
    }
}
