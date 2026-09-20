import Foundation
import BackendKit
import DictKit

extension AppEnvironment {
    var exampleTranslationActions: DictExampleTranslationActions {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1",
           ProcessInfo.processInfo.environment["UI_TEST_DICTIONARY_EXAMPLES"] != "1" {
            return DictExampleTranslationActions { request in
                let samples = [
                    "a cozy nook near the fire": "炉火旁温暖舒适的小角落",
                    "snug in bed": "舒舒服服地窝在床上"
                ]
                guard let translation = samples[request.sentence] else { return nil }
                return DictExampleTranslation(sentenceZhHans: translation, contextualMeaningZhHans: "温暖舒适的")
            }
        }
        #endif
        return dictionaryExampleTranslations.dictionaryActions
    }
}

extension BackendDictionaryExampleTranslationResolver {
    var dictionaryActions: DictExampleTranslationActions {
        DictExampleTranslationActions(loadExamples: { lemma in
            guard let examples = try? await self.learnerExamples(for: lemma) else { return [] }
            return examples.map {
                DictSharedLearnerExample(rank: $0.rank, partOfSpeech: $0.partOfSpeech,
                    definition: $0.definition, sentence: $0.sentence,
                    translation: DictExampleTranslation(sentenceZhHans: $0.sentenceZhHans,
                        contextualMeaningZhHans: $0.contextualMeaningZhHans))
            }
        }) { request in await self.resolve(request) }
    }

    func resolve(_ request: DictExampleTranslationRequest) async -> DictExampleTranslation? {
        guard !request.lemma.isEmpty, !request.partOfSpeech.isEmpty,
              let translated = try? await resolve(
                BackendDictionaryExampleTranslationRequest(
                    candidateMeaningsZhHans: request.candidateMeaningsZhHans,
                    dictionary: BackendDictionaryDescriptor(source: request.dictionarySource, version: request.dictionaryVersion),
                    lemma: request.lemma,
                    partOfSpeech: request.partOfSpeech,
                    senseDefinitionEn: request.definitionEn,
                    sentence: request.sentence,
                    stableSenseId: request.stableSenseId
                )
              ) else { return nil }
        return DictExampleTranslation(sentenceZhHans: translated.sentenceZhHans,
                                      contextualMeaningZhHans: translated.contextualMeaningZhHans)
    }
}
