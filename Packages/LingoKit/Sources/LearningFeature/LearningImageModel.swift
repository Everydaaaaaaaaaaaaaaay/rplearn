import BackendKit
import Foundation
import ImageIO
import Observation
import UIKit

/// 一道题内的图片全部可解码后才能作答；切题或退出时废弃旧请求结果。
@MainActor @Observable
final class LearningImageModel {
    enum State: Equatable { case idle, loading, ready, failed }
    private(set) var state: State = .idle
    private(set) var images: [String: UIImage] = [:]
    private(set) var questionID: String?
    @ObservationIgnored private let service: any LearningServing
    @ObservationIgnored private var revision = UUID()

    init(service: any LearningServing) { self.service = service }

    func isReady(for question: LearningQuestion?) -> Bool {
        guard let question, !question.imageAssetIDs.isEmpty else { return true }
        return questionID == question.id && state == .ready
    }

    func prepare(attemptID: UUID, question: LearningQuestion?) async {
        reset()
        guard let question else { return }
        questionID = question.id
        let ids = question.imageAssetIDs
        guard !ids.isEmpty else { state = .ready; return }
        let requestRevision = revision
        state = .loading
        do {
            let service = service
            let loaded = try await withThrowingTaskGroup(of: (String, Data).self) { group in
                for id in ids {
                    group.addTask { (id, try await service.learningImage(attemptID, questionID: question.id, assetID: id)) }
                }
                var result: [String: Data] = [:]
                for try await (id, data) in group { result[id] = data }
                return result
            }
            guard revision == requestRevision else { return }
            try Task.checkCancellation()
            var decoded: [String: UIImage] = [:]
            for (id, data) in loaded {
                guard data.count <= 2_000_000,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceGetType(source) as String? == "public.png",
                      CGImageSourceGetCount(source) == 1,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      (128...1024).contains(width), (128...1024).contains(height),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                    throw BackendClientError.invalidResponse
                }
                decoded[id] = UIImage(cgImage: image)
            }
            images = decoded; state = .ready
        } catch {
            guard revision == requestRevision else { return }
            images = [:]; state = Task.isCancelled ? .idle : .failed
        }
    }

    func reset() { revision = UUID(); images = [:]; questionID = nil; state = .idle }
}
