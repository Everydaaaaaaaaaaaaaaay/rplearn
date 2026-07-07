import CoreKit
import Foundation
import LLMKit
import PersistenceKit

/// 分级记忆 v1：short 层压缩 + 注入 + 触发（plan.md §3.5）。
/// mid/long 层与订阅配额在 2.6 补齐。
public struct MemoryService: Sendable {
    public struct Config: Sendable {
        /// 未压缩消息达到该数触发压缩。
        public var compressionThresholdMessages: Int
        /// 每次压缩最旧的 N 条。
        public var compressionBatch: Int
        /// 上下文 token 预算（未压缩部分超过 70% 也触发）。
        public var tokenBudget: Int
        /// 注入 prompt 的 short 记忆条数上限。
        public var injectedShortLimit: Int

        public init(
            compressionThresholdMessages: Int = 24,
            compressionBatch: Int = 16,
            tokenBudget: Int = 4000,
            injectedShortLimit: Int = 12
        ) {
            self.compressionThresholdMessages = compressionThresholdMessages
            self.compressionBatch = compressionBatch
            self.tokenBudget = tokenBudget
            self.injectedShortLimit = injectedShortLimit
        }
    }

    private let llm: any LLMClient
    private let chatStore: ChatStore
    private let memoryStore: MemoryStore
    private let config: Config

    public init(llm: any LLMClient, chatStore: ChatStore, memoryStore: MemoryStore, config: Config = Config()) {
        self.llm = llm
        self.chatStore = chatStore
        self.memoryStore = memoryStore
        self.config = config
    }

    // MARK: - 注入

    /// PromptBuilder 的记忆段落（system 尾部）。
    public func memorySections(characterID: UUID) async -> [String] {
        guard let shorts = try? await memoryStore.memories(characterID: characterID, tier: .short),
              !shorts.isEmpty else {
            return []
        }
        let recent = shorts.suffix(config.injectedShortLimit)
        let lines = recent.map { "- \($0.content)" }
        return ["[Recent things you remember from your earlier chats]\n" + lines.joined(separator: "\n")]
    }

    // MARK: - 压缩

    /// 角色回复完成后调用：达到触发条件则把最旧一批未压缩消息压成 short 记忆。
    /// 成功才推进 lastSummarizedMessageIndex，失败下次重试（幂等）。
    public func compressIfNeeded(conversationID: UUID, characterName: String) async {
        guard let conversation = try? await chatStore.conversation(id: conversationID),
              let allMessages = try? await chatStore.messages(conversationID: conversationID) else {
            return
        }
        let unsummarized = allMessages.filter {
            $0.orderIndex >= conversation.lastSummarizedMessageIndex && $0.role != .coach
        }
        let unsummarizedTokens = unsummarized.reduce(0) {
            $0 + max($1.tokenEstimate, TokenEstimator.estimate($1.text))
        }
        let shouldCompress = unsummarized.count >= config.compressionThresholdMessages
            || unsummarizedTokens > Int(Double(config.tokenBudget) * 0.7)
        guard shouldCompress else { return }

        let batch = Array(unsummarized.prefix(config.compressionBatch))
        guard let last = batch.last else { return }

        do {
            let facts = try await summarize(batch: batch, characterName: characterName)
            let upToIndex = last.orderIndex + 1
            try await memoryStore.addMemories(
                characterID: conversation.characterID,
                tier: .short,
                facts: facts.map { MemoryStore.NewMemory(content: $0.content, importance: $0.importance) },
                sourceUpToIndex: upToIndex
            )
            try await chatStore.setLastSummarizedIndex(conversationID: conversationID, index: upToIndex)
            Log.app.info("记忆压缩：\(batch.count) 条消息 → \(facts.count) 条 short 记忆")
        } catch {
            // 失败不推进游标，下次回复完成后重试。
            Log.app.warning("记忆压缩失败（将重试）：\(error)")
        }
    }

    // MARK: - LLM 摘要

    struct Fact: Codable, Equatable {
        var content: String
        var importance: Int
    }

    private struct FactList: Codable {
        var memories: [Fact]
    }

    private func summarize(batch: [MessageDTO], characterName: String) async throws -> [Fact] {
        let transcript = batch.map { message in
            let speaker = message.role == .user ? "Friend" : characterName
            return "\(speaker): \(message.text)"
        }
        .joined(separator: "\n")

        let request = LLMRequest(
            tier: .fast,
            system: """
            You are the memory system of \(characterName), extracting durable memories from a chat excerpt \
            with their Chinese friend. Write 2-6 short factual notes from \(characterName)'s point of view, \
            in English, each a single sentence (who/what/plan/preference/event). Skip small talk with no \
            information. importance: 1 (trivial) to 5 (identity-level fact about the friend).
            Respond with JSON only.
            """,
            messages: [.user(transcript)],
            maxTokens: 500,
            temperature: 0.2,
            responseFormat: .jsonSchema(name: "memories", schema: Self.schema)
        )
        let output = try await llm.complete(request)
        guard let data = JSONExtractor.extractJSONData(from: output) else {
            throw LLMError.invalidResponse("记忆压缩输出无合法 JSON")
        }
        let list = try JSONDecoder().decode(FactList.self, from: data)
        return list.memories.filter { !$0.content.isEmpty }
    }

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "memories": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "content": ["type": "string"],
                        "importance": ["type": "integer", "enum": [1, 2, 3, 4, 5]],
                    ],
                    "required": ["content", "importance"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["memories"],
        "additionalProperties": false,
    ]
}
