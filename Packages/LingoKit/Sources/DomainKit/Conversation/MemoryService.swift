import CoreKit
import Foundation
import LLMKit
import PersistenceKit

/// 分级记忆：short 压缩 → mid 合并 → long 提炼，注入 + 触发 + 订阅配额。
public struct MemoryService: Sendable {
    public struct Config: Sendable {
        /// 未压缩消息达到该数触发压缩。
        public var compressionThresholdMessages: Int
        /// 每次压缩最旧的 N 条。
        public var compressionBatch: Int
        /// 上下文 token 预算（未压缩部分超过 70% 也触发）。
        public var tokenBudget: Int
        /// 注入 prompt 的近期（short+mid）记忆条数上限。
        public var injectedShortLimit: Int
        /// 溢出层合并/提炼的最小批量（少于此不值得再调 LLM）。
        public var tierMergeMinBatch: Int

        public init(
            compressionThresholdMessages: Int = 24,
            compressionBatch: Int = 16,
            tokenBudget: Int = 4000,
            injectedShortLimit: Int = 12,
            tierMergeMinBatch: Int = 3
        ) {
            self.compressionThresholdMessages = compressionThresholdMessages
            self.compressionBatch = compressionBatch
            self.tokenBudget = tokenBudget
            self.injectedShortLimit = injectedShortLimit
            self.tierMergeMinBatch = tierMergeMinBatch
        }
    }

    private let llm: any LLMClient
    private let chatStore: ChatStore
    private let memoryStore: MemoryStore
    /// 读订阅配额；nil 时退化为 Free 配额（供仅测短层的单测）。
    private let economyStore: EconomyStore?
    private let config: Config

    public init(
        llm: any LLMClient,
        chatStore: ChatStore,
        memoryStore: MemoryStore,
        economyStore: EconomyStore? = nil,
        config: Config = Config()
    ) {
        self.llm = llm
        self.chatStore = chatStore
        self.memoryStore = memoryStore
        self.economyStore = economyStore
        self.config = config
    }

    /// 当前订阅配额（无 economyStore 时按 Free）。
    public func quota() async -> MemoryQuota {
        guard let economyStore, let profile = try? await economyStore.profile() else {
            return EconomyService.memoryQuota(for: .free)
        }
        return EconomyService.memoryQuota(for: profile.subscriptionTier)
    }

    // MARK: - 注入

    /// PromptBuilder 的记忆段落（system 尾部）：长期了解（long）+ 近期发生（short+mid）。
    public func memorySections(characterID: UUID) async -> [String] {
        let longs = (try? await memoryStore.memories(characterID: characterID, tier: .long)) ?? []
        let mids = (try? await memoryStore.memories(characterID: characterID, tier: .mid)) ?? []
        let shorts = (try? await memoryStore.memories(characterID: characterID, tier: .short)) ?? []

        var sections: [String] = []
        if !longs.isEmpty {
            let lines = longs.map { "- \($0.content)" }
            sections.append("[Long-term things you know about your friend]\n" + lines.joined(separator: "\n"))
        }
        // 近期 = mid + short，按时间取最新 N 条。
        let recent = (mids + shorts)
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(config.injectedShortLimit)
        if !recent.isEmpty {
            let lines = recent.map { "- \($0.content)" }
            sections.append("[Recent things you remember from your earlier chats]\n" + lines.joined(separator: "\n"))
        }
        return sections
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
            return
        }
        // 压缩成功后按配额做分层整理（short→mid→long）。
        await maintainTiers(characterID: conversation.characterID, characterName: characterName)
    }

    // MARK: - 分层整理（short → mid → long）

    /// 按订阅配额把溢出的 short 合并进 mid、溢出的 mid 提炼进 long，并裁剪 long。
    /// 每步独立幂等，任一步失败静默跳过（下次回复完成后重试）。
    public func maintainTiers(characterID: UUID, characterName: String) async {
        let quota = await quota()

        // 1) short 溢出 → mid
        if let shorts = try? await memoryStore.memories(characterID: characterID, tier: .short),
           shorts.count > quota.shortMid {
            let overflow = Array(shorts.prefix(shorts.count - quota.shortMid))
            if overflow.count >= config.tierMergeMinBatch {
                await consolidate(
                    overflow: overflow,
                    into: .mid,
                    characterID: characterID,
                    characterName: characterName,
                    existing: []
                )
            }
        }

        // 2) mid 溢出 → long（带既有 long 去重）
        if let mids = try? await memoryStore.memories(characterID: characterID, tier: .mid),
           mids.count > quota.shortMid {
            let overflow = Array(mids.prefix(mids.count - quota.shortMid))
            if overflow.count >= config.tierMergeMinBatch {
                let existingLongs = (try? await memoryStore.memories(characterID: characterID, tier: .long)) ?? []
                await consolidate(
                    overflow: overflow,
                    into: .long,
                    characterID: characterID,
                    characterName: characterName,
                    existing: existingLongs
                )
            }
        }

        // 3) long 超配额：按重要度（低→高）、同重要度按时间（旧→新）裁剪。
        if let longs = try? await memoryStore.memories(characterID: characterID, tier: .long),
           longs.count > quota.long {
            let ranked = longs.sorted {
                $0.importance != $1.importance ? $0.importance < $1.importance : $0.createdAt < $1.createdAt
            }
            let toDrop = ranked.prefix(longs.count - quota.long).map(\.id)
            try? await memoryStore.deleteMemories(ids: Array(toDrop))
        }
    }

    /// 把 overflow 一批记忆用 LLM 合并/提炼为目标层若干条，成功后删除来源并写入目标层。
    /// into == .long 时把 existing（既有 long）一并交给 LLM 去重整合，返回整合后的完整 long 集合。
    private func consolidate(
        overflow: [MemoryDTO],
        into targetTier: MemoryTier,
        characterID: UUID,
        characterName: String,
        existing: [MemoryDTO]
    ) async {
        do {
            let facts = try await mergeMemories(
                overflow: overflow,
                existing: existing,
                targetTier: targetTier,
                characterName: characterName
            )
            guard !facts.isEmpty else { return }
            // long 层为“整合替换”：先删旧 long 再写新集合；mid 层为追加。
            if targetTier == .long {
                try await memoryStore.deleteMemories(ids: existing.map(\.id))
            }
            let sourceUpTo = overflow.map(\.sourceUpToIndex).max() ?? 0
            try await memoryStore.addMemories(
                characterID: characterID,
                tier: targetTier,
                facts: facts.map { MemoryStore.NewMemory(content: $0.content, importance: $0.importance) },
                sourceUpToIndex: sourceUpTo
            )
            try await memoryStore.deleteMemories(ids: overflow.map(\.id))
            Log.app.info("记忆整理：\(overflow.count) 条 → \(facts.count) 条 \(targetTier.rawValue)")
        } catch {
            Log.app.warning("记忆整理失败（将重试）：\(error)")
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
            task: .memorySummary,
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

    /// 合并/提炼一批记忆到目标层。
    private func mergeMemories(
        overflow: [MemoryDTO],
        existing: [MemoryDTO],
        targetTier: MemoryTier,
        characterName: String
    ) async throws -> [Fact] {
        let overflowText = overflow.map { "- \($0.content)" }.joined(separator: "\n")
        let system: String
        var userText = "Notes to consolidate:\n\(overflowText)"
        switch targetTier {
        case .mid:
            system = """
            You are the memory system of \(characterName). Merge these short recent notes about their \
            Chinese friend into 1-3 higher-level "phase" summaries, in English, each a single sentence \
            capturing a theme or period (not every detail). Drop redundancy and pure small talk. \
            importance: 1 (trivial) to 5 (identity-level). Respond with JSON only.
            """
        case .long:
            let existingText = existing.map { "- \($0.content)" }.joined(separator: "\n")
            system = """
            You are the long-term memory of \(characterName) about their Chinese friend. You are given \
            EXISTING long-term facts and NEW notes to fold in. Return the UPDATED, de-duplicated set of \
            stable long-term facts (identity, relationships, lasting preferences, ongoing plans) in English, \
            one sentence each, prioritising durable facts about the friend over transient events. Merge \
            duplicates, keep the set concise. importance: 1 to 5. Respond with JSON only.
            """
            userText = "Existing long-term facts:\n\(existingText.isEmpty ? "(none)" : existingText)\n\nNew notes:\n\(overflowText)"
        case .short:
            system = "Summarise into JSON memories." // 不会走到
        }

        let request = LLMRequest(
            task: .memorySummary,
            tier: .fast,
            system: system,
            messages: [.user(userText)],
            maxTokens: 600,
            temperature: 0.2,
            responseFormat: .jsonSchema(name: "memories", schema: Self.schema)
        )
        let output = try await llm.complete(request)
        guard let data = JSONExtractor.extractJSONData(from: output) else {
            throw LLMError.invalidResponse("记忆整理输出无合法 JSON")
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
