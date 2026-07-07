/// 领域服务依赖的最小接口：可注入 MockLLMProvider 做零网络单测。
public protocol LLMClient: Sendable {
    func complete(_ request: LLMRequest) async throws -> String
    func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error>
}

/// 具体供应商实现的完整接口。
public protocol LLMProvider: LLMClient {
    func modelID(for tier: LLMTier) -> String
}
