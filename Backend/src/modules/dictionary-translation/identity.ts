import { createHash } from "node:crypto";
import type {
  DictionaryExampleIdentity,
  DictionaryExampleRequest,
  DictionaryTranslationCacheIdentity,
} from "./types.js";

function hash(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function normalizedText(value: string): string {
  return value.normalize("NFKC").trim().replace(/\s+/gu, " ");
}

function normalizedLabel(value: string): string {
  return normalizedText(value).toLocaleLowerCase("en-US");
}

export function createDictionaryExampleIdentity(
  input: DictionaryExampleRequest,
): DictionaryExampleIdentity {
  const candidateMeaningsZhHans = [
    ...new Set(input.candidateMeaningsZhHans.map(normalizedText)),
  ];
  const stableSenseId =
    input.stableSenseId === undefined ? undefined : normalizedText(input.stableSenseId);
  const senseDefinitionEn =
    input.senseDefinitionEn === undefined
      ? undefined
      : normalizedText(input.senseDefinitionEn);
  const lemma = normalizedLabel(input.lemma);
  const partOfSpeech = normalizedLabel(input.partOfSpeech);
  const sentence = normalizedText(input.sentence);
  const dictionarySource = normalizedLabel(input.dictionary.source);
  const dictionaryVersion = normalizedText(input.dictionary.version);
  const senseFingerprint = hash({
    candidateMeaningsZhHans,
    senseDefinitionEn: senseDefinitionEn ?? null,
    stableSenseId: stableSenseId ?? null,
  });
  const exampleHash = hash(sentence);
  const sourceKey = hash({
    dictionarySource,
    dictionaryVersion,
    exampleHash,
    lemma,
    partOfSpeech,
    senseFingerprint,
  });

  return {
    candidateMeaningsZhHans,
    dictionarySource,
    dictionaryVersion,
    exampleHash,
    lemma,
    partOfSpeech,
    senseFingerprint,
    ...(senseDefinitionEn === undefined ? {} : { senseDefinitionEn }),
    sentence,
    sourceKey,
    ...(stableSenseId === undefined ? {} : { stableSenseId }),
  };
}

export function createDictionaryTranslationCacheIdentity(
  input: DictionaryExampleRequest,
  translationModelVersion: string,
  promptVersion: string,
): DictionaryTranslationCacheIdentity {
  const source = createDictionaryExampleIdentity(input);
  const normalizedModelVersion = normalizedText(translationModelVersion);
  const normalizedPromptVersion = normalizedText(promptVersion);
  return {
    ...source,
    cacheKey: hash({
      promptVersion: normalizedPromptVersion,
      sourceKey: source.sourceKey,
      translationModelVersion: normalizedModelVersion,
    }),
    promptVersion: normalizedPromptVersion,
    translationModelVersion: normalizedModelVersion,
  };
}
