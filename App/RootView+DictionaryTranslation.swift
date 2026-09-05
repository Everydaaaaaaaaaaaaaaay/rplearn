import BackendKit
import DictKit

extension RootView {
    var exampleTranslationActions: DictExampleTranslationActions {
        let resolver = environment.dictionaryExampleTranslations
        return DictExampleTranslationActions { request in
            guard !request.lemma.isEmpty,
                  !request.partOfSpeech.isEmpty,
                  let translated = try? await resolver.resolve(
                    BackendDictionaryExampleTranslationRequest(
                        candidateMeaningsZhHans: request.candidateMeaningsZhHans,
                        dictionary: BackendDictionaryDescriptor(
                            source: request.dictionarySource,
                            version: request.dictionaryVersion
                        ),
                        lemma: request.lemma,
                        partOfSpeech: request.partOfSpeech,
                        senseDefinitionEn: request.definitionEn,
                        sentence: request.sentence,
                        stableSenseId: request.stableSenseId
                    )
                  )
            else { return nil }
            return DictExampleTranslation(
                sentenceZhHans: translated.sentenceZhHans,
                contextualMeaningZhHans: translated.contextualMeaningZhHans
            )
        }
    }
}
