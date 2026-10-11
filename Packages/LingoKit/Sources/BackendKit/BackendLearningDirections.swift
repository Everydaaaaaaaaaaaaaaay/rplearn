import Foundation

/// 方向及可用状态由服务端维护；保留未知值以支持新版方向在旧客户端展示。
public struct LearningDirectionOption: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: String

    public var isAvailable: Bool { status == "available" }

    public init(id: String, title: String, status: String) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// 备考方向与基础英语水平独立；revision用于检测其他设备的并发选择。
public struct LearningDirections: Codable, Sendable, Equatable {
    public let selectedDirection: String
    public let revision: Int
    public let directions: [LearningDirectionOption]

    public init(selectedDirection: String, revision: Int, directions: [LearningDirectionOption]) {
        self.selectedDirection = selectedDirection
        self.revision = revision
        self.directions = directions
    }
}

public protocol LearningDirectionServing: Sendable {
    func learningDirections() async throws -> LearningDirections
    func selectLearningDirection(_ direction: String, requestID: UUID, expectedRevision: Int) async throws -> LearningDirections
}

extension BackendClient: LearningDirectionServing {
    private struct DirectionSelection: Encodable, Sendable {
        let direction: String
        let requestId: UUID
        let expectedRevision: Int
    }

    public func learningDirections() async throws -> LearningDirections {
        try await get("/v1/learning/directions")
    }

    /// 调用方保留同次选择的requestID用于重试；冲突与失败原样上抛，不改选通用英语。
    public func selectLearningDirection(_ direction: String, requestID: UUID, expectedRevision: Int) async throws -> LearningDirections {
        try await send(
            path: "/v1/learning/directions",
            method: "POST",
            body: DirectionSelection(direction: direction, requestId: requestID, expectedRevision: expectedRevision)
        )
    }
}
