import Foundation

public struct BackendMainlineProgress: Codable, Sendable, Equatable {
    public struct Chapter: Codable, Sendable, Equatable, Identifiable {
        public let storyId: String
        public let regionId: String
        public let sequence: Int
        public let previousStoryId: String?
        public let state: String
        public let lockReason: String?
        public var id: String { storyId }
        public var canOpen: Bool { state == "available" || state == "completed" }
        public var statusText: String {
            if state == "completed" { return "已完成 · 可重温" }
            if state == "available" { return "已解锁 · 开启剧情" }
            switch lockReason {
            case "onboarding": return "先选择起始旅伴"
            case "login": return "登录后继续旅程"
            case "previousChapter": return "先完成前一章"
            default: return "暂未解锁"
            }
        }
    }
    public let chapters: [Chapter]
}
public protocol MainlineServing: Sendable {
    func mainlineProgress() async throws -> BackendMainlineProgress
}
extension BackendClient: MainlineServing {
    public func mainlineProgress() async throws -> BackendMainlineProgress {
        try await get("/v1/progression/mainline")
    }
}
