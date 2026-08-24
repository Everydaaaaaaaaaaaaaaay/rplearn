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
                && probe.assistants == [.init(text: "This is the first phrase", interrupted: true)]
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
    var heardText: String { enqueued.joined(separator: " ") }
    var enqueued: [String] = []
    var stopCount = 0

    func beginResponse(language: String, voiceHint: SpeechVoiceHint?) async {
        enqueued.removeAll()
    }

    func enqueue(_ text: String) { enqueued.append(text) }
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

    init(keepsStreamOpen: Bool = false) {
        self.keepsStreamOpen = keepsStreamOpen
    }

    func makeStream() -> AsyncThrowingStream<String, Error> {
        let keepsStreamOpen = keepsStreamOpen
        return AsyncThrowingStream { continuation in
            continuation.yield(keepsStreamOpen ? "This is the first phrase." : "Nice to meet you.")
            if !keepsStreamOpen { continuation.finish() }
        }
    }
}
