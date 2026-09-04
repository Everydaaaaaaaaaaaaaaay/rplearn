export type DictionaryExampleRequest = Readonly<{
  candidateMeaningsZhHans: readonly string[];
  dictionary: Readonly<{
    source: string;
    version: string;
  }>;
  lemma: string;
  partOfSpeech: string;
  requestId?: string | undefined;
  senseDefinitionEn?: string | undefined;
  sentence: string;
  stableSenseId?: string | undefined;
}>;

export type DictionaryExampleIdentity = Readonly<{
  candidateMeaningsZhHans: readonly string[];
  dictionarySource: string;
  dictionaryVersion: string;
  exampleHash: string;
  lemma: string;
  partOfSpeech: string;
  senseFingerprint: string;
  senseDefinitionEn?: string | undefined;
  sentence: string;
  sourceKey: string;
  stableSenseId?: string | undefined;
}>;

export type DictionaryTranslationCacheIdentity = DictionaryExampleIdentity &
  Readonly<{
    cacheKey: string;
    promptVersion: string;
    translationModelVersion: string;
  }>;

export type DictionaryTranslationCacheMetadata = Readonly<{
  dictionarySource: string;
  dictionaryVersion: string;
  generatedAt?: string;
  promptVersion: string;
  translationModelVersion: string;
}>;

export type DictionaryTranslationResult = Readonly<{
  cache: DictionaryTranslationCacheMetadata;
  cacheKey: string;
  contextualMeaningZhHans?: string;
  requestId?: string;
  selectedMeaningIndex?: number;
  sentenceZhHans?: string;
  sourceKey: string;
  status: "missing" | "pending" | "ready";
}>;

export type GeneratedDictionaryTranslation = Readonly<{
  contextualMeaningZhHans: string;
  selectedMeaningIndex?: number | undefined;
  sentenceZhHans: string;
}>;

export type DictionaryTranslationJobPayload = Readonly<{
  attempt: number;
  cacheKey: string;
  userId: string;
}>;

export type TrustedDictionaryTranslationImport = DictionaryExampleRequest &
  GeneratedDictionaryTranslation &
  Readonly<{
    promptVersion: string;
    translationModelVersion: string;
  }>;
