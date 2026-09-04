import type { GeneratedDictionaryTranslation } from "./types.js";

const HAS_HAN_CHARACTER = /\p{Script=Han}/u;
const MEANING_SEPARATOR = /[,，;；、]/u;
const MEANING_COMPARISON_IGNORABLE = /[\p{P}\p{S}\s]/gu;

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function meaningComparisonKey(value: string): string {
  return value.normalize("NFKC").replace(MEANING_COMPARISON_IGNORABLE, "");
}

export function validatedGeneratedTranslation(
  value: unknown,
  candidateMeaningsZhHans: readonly string[],
): GeneratedDictionaryTranslation | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  const sentenceZhHans = value.sentenceZhHans;
  const contextualMeaningZhHans = value.contextualMeaningZhHans;
  const selectedMeaningIndex = value.selectedMeaningIndex;
  if (
    typeof sentenceZhHans !== "string" ||
    typeof contextualMeaningZhHans !== "string" ||
    (selectedMeaningIndex !== undefined &&
      selectedMeaningIndex !== null &&
      (typeof selectedMeaningIndex !== "number" ||
        !Number.isInteger(selectedMeaningIndex)))
  ) {
    return undefined;
  }
  const sentence = sentenceZhHans.normalize("NFKC").trim();
  const meaning = contextualMeaningZhHans.normalize("NFKC").trim();
  const selectedCandidate =
    typeof selectedMeaningIndex === "number"
      ? candidateMeaningsZhHans[selectedMeaningIndex]?.normalize("NFKC").trim()
      : undefined;
  if (
    sentence.length < 1 ||
    sentence.length > 1_000 ||
    meaning.length < 1 ||
    meaning.length > 80 ||
    !HAS_HAN_CHARACTER.test(sentence) ||
    !HAS_HAN_CHARACTER.test(meaning) ||
    MEANING_SEPARATOR.test(meaning) ||
    (typeof selectedMeaningIndex === "number" &&
      (selectedCandidate === undefined ||
        meaningComparisonKey(selectedCandidate) !== meaningComparisonKey(meaning)))
  ) {
    return undefined;
  }
  return {
    contextualMeaningZhHans: selectedCandidate ?? meaning,
    ...(typeof selectedMeaningIndex === "number" ? { selectedMeaningIndex } : {}),
    sentenceZhHans: sentence,
  };
}
