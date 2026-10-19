import BackendKit
import Foundation
@testable import LearningFeature
import Testing

private actor AudioTestService: LearningServing {
    var fail = false
    var delayed = false
    var pending: [CheckedContinuation<Data, Error>] = []
    private(set) var downloadCount = 0
    private(set) var maximumPending = 0
    func setDelayed() { delayed = true }
    func failDownloads() { fail = true }
    func resumeDownloads() { fail = false; delayed = false }
    func finishDownload() { if !pending.isEmpty { pending.removeFirst().resume(returning: Data([1, 2, 3])) } }
    func learningAudio(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data {
        downloadCount += 1
        if fail { throw BackendClientError.invalidResponse }
        if delayed { return try await withCheckedThrowingContinuation {
            pending.append($0); maximumPending = max(maximumPending, pending.count)
        } }
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
    private func question(_ id: String = "listening", kind: String = "dictation") throws -> LearningQuestion {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "type": kind, "goalId": "test.goal", "instruction": "听力", "prompt": "工程测试", "hint": "工程提示", "wordLimit": 2, "audio": ["assetId": "audio.test"]])
        return try JSONDecoder().decode(LearningQuestion.self, from: data)
    }
    private func waitForPlayback(_ model: LearningAudioModel) async throws {
        for _ in 0..<100 {
            if model.state == .playing { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("播放器没有进入播放状态。")
    }
    @Test("正常与慢速只有完整播放后解锁，中断和旧回调不能假报听完", arguments: ["dictation", "listeningCompletion"])
    func interruptionAndCompletion(kind: String) async throws {
        let playback = TestAudioPlayback()
        let model = LearningAudioModel(service: AudioTestService(), playback: playback)
        await model.prepare(attemptID: UUID(), question: try question(kind: kind))
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
    @Test("下载失败保持可重试状态，不能解锁听力作答", arguments: ["dictation", "listeningCompletion"])
    func failureKeepsListeningLocked(kind: String) async throws {
        let service = AudioTestService(); await service.failDownloads()
        let model = LearningAudioModel(service: service, playback: TestAudioPlayback())
        await model.prepare(attemptID: UUID(), question: try question(kind: kind))
        #expect(model.state == .failed); #expect(!model.hasListened)
    }
    @Test("多声音题逐段听完才解锁，切换和迟到回调不伪造听完", arguments: ["audioChoice", "audioMatching"])
    func optionPlaybackIsolation(kind: String) async throws {
        let service = AudioTestService()
        var playbacks: [TestAudioPlayback] = []
        let model = LearningAudioOptionsModel { cache in
            let playback = TestAudioPlayback(); playbacks.append(playback)
            return LearningAudioModel(service: service, playback: playback, cache: cache)
        }
        let data = Data(#"{"id":"sounds","type":"audioChoice","goalId":"test.goal","instruction":"选声音","prompt":"工程测试","hint":"工程提示","audioOptions":[{"id":"a","audio":{"assetId":"audio.a"}},{"id":"b","audio":{"assetId":"audio.b"}}]}"#.utf8)
        var publicQuestion = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        publicQuestion["type"] = kind
        let question = try JSONDecoder().decode(LearningQuestion.self, from: JSONSerialization.data(withJSONObject: publicQuestion))
        let attemptID = UUID()
        await model.prepare(attemptID: attemptID, question: question)
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
        await model.prepare(attemptID: attemptID, question: question)
        #expect(!model.hasListenedToAll)
        #expect(await service.downloadCount == 2)
        await model.prepare(attemptID: UUID(), question: question)
        #expect(await service.downloadCount == 4)
    }

    @Test("声音选项最多三路并发，完成一路后补位")
    func optionDownloadsAreBoundedAndConcurrent() async throws {
        let service = AudioTestService(); await service.setDelayed()
        let model = LearningAudioOptionsModel { cache in
            LearningAudioModel(service: service, playback: TestAudioPlayback(), cache: cache)
        }
        let options = (0..<5).map { ["id": "option.\($0)", "audio": ["assetId": "audio.\($0)"]] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["id": "sounds", "type": "audioChoice",
            "goalId": "test.goal", "instruction": "选声音", "prompt": "工程测试", "hint": "工程提示", "audioOptions": options])
        let question = try JSONDecoder().decode(LearningQuestion.self, from: data)
        let loading = Task { await model.prepare(attemptID: UUID(), question: question) }
        for _ in 0..<100 {
            if await service.pending.count == 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await service.downloadCount == 3)
        await service.finishDownload()
        for _ in 0..<100 {
            if await service.downloadCount == 4 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await service.downloadCount == 4)
        // 切题后不再启动排队请求，迟到下载也不能复活播放器。
        model.reset()
        for _ in 0..<3 { await service.finishDownload() }
        await loading.value
        #expect(await service.downloadCount == 4)
        #expect(await service.maximumPending == 3)
        #expect(model.players.isEmpty)
    }

    @Test("音频缓存按字节淘汰，同挑战同素材复用，跨挑战隔离")
    func audioCacheEvictsAndScopesDownloads() async throws {
        let service = AudioTestService()
        let cache = LearningAudioCache(byteLimit: 6)
        let attempt = UUID()
        func load(_ asset: String, question: String = "q", attemptID: UUID? = nil) async throws {
            _ = try await cache.load(service: service, attemptID: attemptID ?? attempt, questionID: question, assetID: asset)
        }
        try await load("a"); try await load("b"); try await load("a")
        #expect(await service.downloadCount == 2)
        try await load("c"); try await load("b")
        #expect(await service.downloadCount == 4)
        try await load("b", question: "other"); try await load("b", attemptID: UUID())
        #expect(await service.downloadCount == 5)
    }

    @Test("下载失败或取消后可重新下载，不缓存失败结果")
    func audioCacheDoesNotRetainFailuresOrCancellation() async throws {
        let service = AudioTestService()
        let cache = LearningAudioCache()
        let attempt = UUID()
        await service.failDownloads()
        await #expect(throws: BackendClientError.self) {
            _ = try await cache.load(service: service, attemptID: attempt, questionID: "q", assetID: "a")
        }
        await service.resumeDownloads(); await service.setDelayed()
        let loading = Task { try await cache.load(service: service, attemptID: attempt, questionID: "q", assetID: "a") }
        for _ in 0..<100 {
            if await service.pending.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        loading.cancel(); await service.finishDownload()
        await #expect(throws: CancellationError.self) { _ = try await loading.value }
        await service.resumeDownloads()
        let data = try await cache.load(service: service, attemptID: attempt, questionID: "q", assetID: "a")
        #expect(data == Data([1, 2, 3]))
        #expect(await service.downloadCount == 3)
    }

    @Test("完整题组共用音轨只需听完一次，跨挑战重新解锁")
    func sharedGroupTrack() async throws {
        let service = AudioTestService(); let playback = TestAudioPlayback()
        let model = LearningAudioModel(service: service, playback: playback)
        let attempt = UUID()
        await model.prepare(attemptID: attempt, question: try question("q1"))
        model.play(slow: false); try await waitForPlayback(model)
        playback.completions[0](true)
        await model.prepare(attemptID: attempt, question: try question("q2"))
        #expect(model.hasListened)
        #expect(await service.downloadCount == 1)
        await model.prepare(attemptID: UUID(), question: try question("q2"))
        #expect(!model.hasListened)
        #expect(await service.downloadCount == 2)
    }

}
