import Foundation
@testable import SpeechKit
import Testing
@testable import RealtimeVoiceKit

@Suite("实时语音播放流水线")
@MainActor
struct RealtimeSpeechOutputTests {
    @Test("开始播放后才预合成下一句，且只提前一句")
    func boundedLookaheadDuringPlayback() async {
        let speech = ControlledSpeechService()
        let output = AdaptiveRealtimeSpeechOutput(speech: speech)
        await output.beginResponse(language: "en-US", voiceHint: nil)
        output.enqueue("First phrase.")
        output.enqueue("Second phrase.")
        output.enqueue("Third phrase.")
        #expect(await eventually { speech.played.count == 1 })
        #expect(speech.prepared.isEmpty)
        speech.beginPlayback()
        #expect(await eventually { speech.prepared == ["Second phrase."] })
        #expect(output.heardText.isEmpty)
        speech.finishPlayback()
        #expect(await eventually { speech.played.count == 2 })
        #expect(output.heardText == "First phrase.")
        #expect(speech.usedPreparedAudio == [false, true])
        #expect(speech.prepared == ["Second phrase."])
        speech.beginPlayback()
        #expect(await eventually { speech.prepared.count == 2 })
        let heard = await output.stop()
        #expect(heard == "First phrase.")
        #expect(speech.played == ["First phrase.", "Second phrase."])
    }

    @Test("插话不把未播完和未开播的句子写入已听记录")
    func interruptedPhraseIsNotAssumedHeard() async {
        let speech = ControlledSpeechService()
        let output = AdaptiveRealtimeSpeechOutput(speech: speech)
        await output.beginResponse(language: "en-US", voiceHint: nil)
        output.enqueue("An unfinished phrase.")
        output.enqueue("Never played.")
        #expect(await eventually { speech.played.count == 1 })
        speech.beginPlayback()
        #expect(await output.stop() == "")
        #expect(speech.played == ["An unfinished phrase."])
        await output.beginResponse(language: "en-US", voiceHint: nil)
        output.enqueue("New response.")
        #expect(await eventually { speech.played.count == 2 })
        speech.beginPlayback()
        speech.finishPlayback()
        await output.waitUntilFinished()
        #expect(output.heardText == "New response.")
        _ = await output.stop()
    }

    @Test("其他页面或旧请求的播放通知不能启动预合成或污染已听记录")
    func unrelatedPlaybackIsIgnored() async {
        let speech = ControlledSpeechService()
        let output = AdaptiveRealtimeSpeechOutput(speech: speech)
        await output.beginResponse(language: "en-US", voiceHint: nil)
        output.enqueue("Waiting for synthesis.")
        output.enqueue("Next phrase.")
        #expect(await eventually { speech.played.count == 1 })
        NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: UUID())
        NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: nil)
        await Task.yield()
        #expect(speech.prepared.isEmpty)
        #expect(await output.stop() == "")
    }

    private func eventually(_ predicate: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<150 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }
}

@MainActor
private final class ControlledSpeechService: SpeechService {
    var played: [String] = []
    var prepared: [String] = []
    var usedPreparedAudio: [Bool] = []
    private var playbackID: UUID?
    private var completion: CheckedContinuation<Void, Never>?

    func speak(_ request: SpeechRequest) async { await speakAndWait(request) }
    func speakAndWait(_ request: SpeechRequest) async {
        await speakAndWait(request, prepared: nil)
    }
    func speakAndWait(_ request: SpeechRequest, prepared: PreparedSpeech?) async {
        usedPreparedAudio.append(prepared?.request == request && prepared?.samples == [0])
        played.append(request.text)
        playbackID = request.playbackID
        await withCheckedContinuation { completion = $0 }
    }
    func prepareForPlayback(_ request: SpeechRequest) async -> PreparedSpeech? {
        prepared.append(request.text)
        return PreparedSpeech(request: request, samples: [0])
    }
    func beginPlayback() {
        NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: playbackID)
    }
    func finishPlayback() {
        let waiter = completion
        completion = nil
        waiter?.resume()
    }
    func stopSpeaking() async { finishPlayback() }
}
