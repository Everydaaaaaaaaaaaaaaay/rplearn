import Foundation
import DictKit
import LLMKit
import PersistenceKit
import SpeechKit

extension ChatDependencies {
    @MainActor
    func speakLookupWord(_ word: String) {
        let speech = speech
        Task {
            await speech.speak(
                SpeechRequest(text: word, language: "en-US", purpose: .pronunciation)
            )
        }
    }

    var lookupWordFavoriteActions: WordFavoriteActions {
        lookupWordFavoriteActions(sourceMessageID: nil)
    }

    func lookupWordFavoriteActions(sourceMessageID: UUID?) -> WordFavoriteActions {
        let favorites = favorites
        return WordFavoriteActions(
            contains: { word in
                (try? await favorites.isWordFavorited(word)) ?? false
            },
            toggle: { word, translationZh in
                (try? await favorites.toggleWord(word, translationZh: translationZh, sourceMessageID: sourceMessageID)) ?? false
            }
        )
    }

    var lookupAIWordFallback: @Sendable (String) async -> String? {
        let llm = llm
        return { word in
            let request = LLMRequest(
                task: .dictionaryExplain,
                tier: .fast,
                system: "你是一个简明的英汉词典助手。用中文简要解释用户给出的英文词，格式：词性. 释义（不超过 3 条）；如是俚语/缩写/网络用语请注明。总长不超过 80 字。",
                messages: [.user(word)],
                maxTokens: 200,
                temperature: 0.2
            )
            return try? await llm.complete(request)
        }
    }
}
