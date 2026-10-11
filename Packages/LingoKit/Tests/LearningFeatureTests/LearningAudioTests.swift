import BackendKit
import Foundation
@testable import LearningFeature
import Testing

private actor AudioTestService: LearningServing {
    var fail = false
    var delayed = false
    var pending: [CheckedContinuation<Data, Error>] = []
    func setDelayed() { delayed = true }
    func failDownloads() { fail = true }
    func finishDownload() { if !pending.isEmpty { pending.removeFirst().resume(returning: Data([1, 2, 3])) } }
    func learningAudio(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data {
        if fail { throw BackendClientError.invalidResponse }
        if delayed { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return Data([1, 2, 3])
    }
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter { throw BackendClientError.invalidResponse }
    func learningJourney() async throws -> LearningJourney { throw BackendClientError.invalidResponse }
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory { throw BackendClientError.invalidResponse }
    func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart { throw BackendClientError.invalidResponse }
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt { throw BackendClientError.invalidResponse }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
}
@MainActor private final class TestAudioPlayback: LearningAudioPlayback {
    var rates: [Float] = []
    var completions: [@MainActor @Sendable (Bool) -> Void] = []
    func play(data: Data, rate: Float, completed: @escaping @MainActor @Sendable (Bool) -> Void) async throws {
        rates.append(rate); completions.append(completed)
    }
    func stop() {}
}

@Suite("学习听力的加载与中断") @MainActor
struct LearningAudioTests {
    private func question(_ id: String = "listening") throws -> LearningQuestion {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "type": "dictation", "goalId": "test.goal", "instruction": "听写", "prompt": "工程测试", "hint": "工程提示", "audio": ["assetId": "audio.test"]])
        return try JSONDecoder().decode(LearningQuestion.self, from: data)
    }
    private func waitForPlayback(_ model: LearningAudioModel) async throws {
        for _ in 0..<100 {
            if model.state == .playing { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("播放器没有进入播放状态。")
    }
    @Test("正常与慢速只有完整播放后解锁，中断和旧回调不能假报听完")
    func interruptionAndCompletion() async throws {
        let playback = TestAudioPlayback()
        let model = LearningAudioModel(service: AudioTestService(), playback: playback)
        await model.prepare(attemptID: UUID(), question: try question())
        #expect(model.state == .ready); #expect(!model.hasListened)
        model.play(slow: false); try await waitForPlayback(model)
        model.stop(interrupted: true)
        playback.completions[0](true)
        #expect(model.state == .interrupted); #expect(!model.hasListened)
        model.play(slow: true); try await waitForPlayback(model)
        playback.completions[1](true)
        #expect(model.state == .ready); #expect(model.hasListened)
        #expect(playback.rates == [1, 0.75])
        await model.prepare(attemptID: UUID(), question: try question("next"))
        playback.completions[1](true)
        #expect(!model.hasListened); #expect(model.state == .ready)
    }
    @Test("离开时废弃在途下载，迟到的音频不恢复界面或播放")
    func lateDownloadIsDiscarded() async throws {
        let service = AudioTestService(); await service.setDelayed()
        let playback = TestAudioPlayback()
        let model = LearningAudioModel(service: service, playback: playback)
        let q = try question()
        let loading = Task { await model.prepare(attemptID: UUID(), question: q) }
        for _ in 0..<100 { if await service.pending.count == 1 { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state == .loading)
        model.reset(); await service.finishDownload(); await loading.value
        #expect(model.state == .idle); #expect(!model.hasListened); #expect(playback.rates.isEmpty)
    }
    @Test("下载失败保持可重试状态，不能解锁听力作答")
    func failureKeepsListeningLocked() async throws {
        let service = AudioTestService(); await service.failDownloads()
        let model = LearningAudioModel(service: service, playback: TestAudioPlayback())
        await model.prepare(attemptID: UUID(), question: try question())
        #expect(model.state == .failed); #expect(!model.hasListened)
    }
    @Test("多声音题逐段听完才解锁，切换和迟到回调不伪造听完", arguments: ["audioChoice", "audioMatching"])
    func optionPlaybackIsolation(kind: String) async throws {
        let service = AudioTestService()
        var playbacks: [TestAudioPlayback] = []
        let model = LearningAudioOptionsModel {
            let playback = TestAudioPlayback(); playbacks.append(playback)
            return LearningAudioModel(service: service, playback: playback)
        }
        let data = Data(#"{"id":"sounds","type":"audioChoice","goalId":"test.goal","instruction":"选声音","prompt":"工程测试","hint":"工程提示","audioOptions":[{"id":"a","audio":{"assetId":"audio.a"}},{"id":"b","audio":{"assetId":"audio.b"}}]}"#.utf8)
        var publicQuestion = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        publicQuestion["type"] = kind
        let question = try JSONDecoder().decode(LearningQuestion.self, from: JSONSerialization.data(withJSONObject: publicQuestion))
        await model.prepare(attemptID: UUID(), question: question)
        let first = try #require(model.players["a"]), second = try #require(model.players["b"])
        #expect(!model.hasListenedToAll)
        model.play("a"); try await waitForPlayback(first)
        model.play("b"); try await waitForPlayback(second)
        playbacks[0].completions[0](true)
        #expect(!first.hasListened); #expect(second.state == .playing)
        playbacks[1].completions[0](true)
        #expect(second.hasListened); #expect(!model.hasListenedToAll)
        model.play("a", slow: true); try await waitForPlayback(first)
        playbacks[0].completions[1](true)
        #expect(model.hasListenedToAll); #expect(playbacks[0].rates == [1, 0.75])
        model.reset()
        playbacks[0].completions[1](true)
        #expect(model.players.isEmpty); #expect(!model.hasListenedToAll)
        await model.prepare(attemptID: UUID(), question: question)
        #expect(!model.hasListenedToAll)
    }

}
