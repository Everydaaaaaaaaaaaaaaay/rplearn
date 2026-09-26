import BackendKit
import Foundation
import UIKit
@testable import LearningFeature
import Testing

private actor ImageTestService: LearningServing {
    let data: Data
    init(data: Data) { self.data = data }
    var fail = false
    var delayed = false
    var pending: [CheckedContinuation<Data, Error>] = []
    func setDelayed() { delayed = true }
    func failDownloads(_ value: Bool) { fail = value }
    func finishDownload() { if !pending.isEmpty { pending.removeFirst().resume(returning: data) } }
    func learningImage(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data {
        if fail { throw BackendClientError.invalidResponse }
        if delayed { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return data
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

@Suite("学习图片的加载与换题") @MainActor
struct LearningImageTests {
    private func question(_ id: String = "image") throws -> LearningQuestion {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "type": "choice", "goalId": "test.goal", "instruction": "看图", "prompt": "工程测试", "hint": "工程提示", "options": [["id": "a", "text": "测试图片", "imageAssetId": "image.test"], ["id": "b", "text": "相同图片", "imageAssetId": "image.test"]]])
        return try JSONDecoder().decode(LearningQuestion.self, from: data)
    }
    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        }
    }
    @Test("失败后仍锁定，重试解码成功才允许当前题作答")
    func failureAndRetry() async throws {
        let service = ImageTestService(data: png()); await service.failDownloads(true)
        let model = LearningImageModel(service: service); let q = try question()
        await model.prepare(attemptID: UUID(), question: q)
        #expect(model.state == .failed); #expect(!model.isReady(for: q))
        await service.failDownloads(false)
        await model.prepare(attemptID: UUID(), question: q)
        #expect(model.state == .ready); #expect(model.isReady(for: q)); #expect(model.images.count == 1)
        #expect(!model.isReady(for: try question("next")))
    }
    @Test("离开时废弃在途图片，损坏的数据不解锁")
    func invalidAndLateData() async throws {
        let service = ImageTestService(data: png()); await service.setDelayed()
        let model = LearningImageModel(service: service); let q = try question()
        let loading = Task { await model.prepare(attemptID: UUID(), question: q) }
        for _ in 0..<100 { if await service.pending.count == 1 { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state == .loading)
        model.reset(); await service.finishDownload(); await loading.value
        #expect(model.state == .idle); #expect(model.images.isEmpty); #expect(!model.isReady(for: q))
        let broken = LearningImageModel(service: ImageTestService(data: Data([1, 2, 3])))
        await broken.prepare(attemptID: UUID(), question: q)
        #expect(broken.state == .failed); #expect(!broken.isReady(for: q))
    }
}
