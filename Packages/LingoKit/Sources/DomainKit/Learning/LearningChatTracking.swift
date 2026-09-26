import CoreKit
import Foundation
import PersistenceKit

/// 教程和纯本地预览不注入此依赖；后台主动消息也不调用它。
public protocol LearningChatTracking: Sendable {
    func refresh(characterID: UUID) async
    func userOrigin(characterID: UUID) async -> LearningChatOrigin?
    func prepareReply(conversationID: UUID, userMessage: MessageDTO) async throws -> LearningChatContext?
    func messageSaved(characterID: UUID) async
}
