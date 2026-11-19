import BackendKit
import CoreKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit

/// Server leases and a frozen, replayable model request survive process and device changes.
public struct SharedChatFollowupCoordinator: Sendable {
  public let backend: BackendClient
  public let chatStore: ChatStore
  public let rosterStore: RosterStore
  public let memoryStore: MemoryStore
  public let economyStore: EconomyStore
  public let llm: any LLMClient
  private let afterReply: @Sendable (CharacterDTO, UUID) async throws -> Void

  public init(
    backend: BackendClient, chatStore: ChatStore, rosterStore: RosterStore,
    memoryStore: MemoryStore, economyStore: EconomyStore, llm: any LLMClient,
    afterReply: @escaping @Sendable (CharacterDTO, UUID) async throws -> Void = { _, _ in }
  ) {
    self.backend = backend
    self.chatStore = chatStore
    self.rosterStore = rosterStore
    self.memoryStore = memoryStore
    self.economyStore = economyStore
    self.llm = llm
    self.afterReply = afterReply
  }
  private struct Job: Decodable, Sendable {
    let messageId: UUID
    let conversationId: UUID
    let characterId: UUID
  }
  private struct Pending: Decodable { let jobs: [Job] }
  private struct Claim: Decodable {
    let operationId: UUID
    let token: UUID
    let request: RelationshipService.ReviewRequest
  }
  private struct Claimed: Decodable { let claim: Claim? }
  private struct ClaimBody: Encodable { let review: RelationshipService.ReviewRequest }
  private struct Completion: Encodable { let token: UUID }
  private struct Completed: Decodable { let completed: Bool }

  public func process(synchronize: @Sendable () async throws -> Void) async throws {
    try Task.checkCancellation()
    let pending: Pending = try await backend.get("/v1/chat/followups")
    for job in pending.jobs {
      try Task.checkCancellation()
      guard let character = try await rosterStore.character(id: job.characterId) else { continue }
      let all = try await chatStore.messages(conversationID: job.conversationId)
      guard let message = all.first(where: { $0.id == job.messageId }) else { continue }
      let reply = try await chatStore.replyText(after: message, conversationID: job.conversationId)
      if let mood = ChatTimelineEvidence.mood(reply: reply) {
        try await chatStore.addTimelineEvents(messageID: message.id, events: [mood])
      }
      let cutoff = try await memoryStore.extractionCutoff(characterID: character.id)
      let history = all.filter {
        $0.orderIndex <= message.orderIndex && (cutoff == nil || $0.createdAt > cutoff!)
      }
      let extract =
        MemoryFact.shouldExtract(message.text) && (cutoff == nil || message.createdAt > cutoff!)
      let memories =
        extract
        ? try await memoryStore.memories(
          characterID: character.id, tier: .long, includingArchived: true) : []
      let context = memories.filter { $0.record?.edited != true }.suffix(4).compactMap {
        $0.record.map { $0.key + ": " + String($0.text.prefix(90)) }
      }.joined(separator: "\n")
      let request = RelationshipService.reviewRequest(
        character: character, history: history,
        userMessage: message, memoryContext: context, extractMemory: extract)
      let claimed: Claimed = try await backend.send(
        path: "/v1/chat/followups/\(message.id.uuidString.lowercased())/claim", method: "POST",
        body: ClaimBody(review: request))
      guard let claim = claimed.claim else { continue }
      let service = RelationshipService(llm: llm, rosterStore: rosterStore)
      // Every new job writes a review receipt, including error-free messages.
      // Existing reviewed messages can be acknowledged without another provider call.
      if message.coachReviewJSON == nil
        || !RelationshipEngine.hasEvaluated(messageID: message.id, in: character.relationship)
      {
        var events: [ChatMessageTimelineEvent] = []
        let review = try await service.evaluate(
          claim.request, operationID: claim.operationId, userText: message.text)
        try Task.checkCancellation()
        let relationship = try await service.apply(
          review: review, character: character, history: history, userMessage: message,
          source: message.kind == .voice ? .voiceChat : .textChat, at: message.createdAt)
        let latestCutoff = try await memoryStore.extractionCutoff(characterID: character.id)
        if extract && (latestCutoff == nil || message.createdAt > latestCutoff!) {
          let facts = (review.memoryFacts ?? []).compactMap { $0.record(from: message) }
          let changes = try await memoryStore.applyFacts(
            characterID: character.id, records: facts, sourceIndex: message.orderIndex + 1)
          if let first = changes.first { events.append(ChatTimelineEvidence.memory(first)) }
        }
        if !events.contains(where: { $0.kind == .memory }), ChatTimelineEvidence.hasRecallCue(reply),
           let recall = ChatTimelineEvidence.recalledMemory(
             reply: reply, userMessage: message,
             memories: try await memoryStore.memories(characterID: character.id, tier: .long)) {
          events.append(recall)
        }
        if let relationship {
          // A version conflict can replay the turn onto a newer relationship.
          // Read the accepted receipt before describing its change in chat.
          try await synchronize()
          if let snapshot = try await rosterStore.character(id: character.id)?.relationship,
             let receipt = snapshot.recentEvents.last(where: { $0.id == message.id }) {
            if snapshot == relationship.snapshot {
              events.append(relationship.event)
            } else if abs(receipt.delta) >= 0.15 {
              events.append(.init(kind: .relationship, state: "affinity", delta: receipt.delta))
            }
          }
        }
        try await chatStore.addTimelineEvents(messageID: message.id, events: events)
        if let json = CoachService.encode(review.coachReview) {
          try await chatStore.setCoachReview(messageID: message.id, json: json)
        }
      }
      let memory = MemoryService(
        llm: llm, chatStore: chatStore, memoryStore: memoryStore, economyStore: economyStore)
      let compressed = await memory.compressIfNeeded(
        conversationID: job.conversationId, characterName: character.card.name,
        characterRegionID: character.card.regionID)
      guard compressed else { throw AppError.storage("记忆整理等待重试") }
      try Task.checkCancellation()
      try await afterReply(character, job.conversationId)
      try await synchronize()
      try Task.checkCancellation()
      let _: Completed = try await backend.send(
        path: "/v1/chat/followups/\(message.id.uuidString.lowercased())/complete", method: "POST",
        body: Completion(token: claim.token))
    }
  }
}
