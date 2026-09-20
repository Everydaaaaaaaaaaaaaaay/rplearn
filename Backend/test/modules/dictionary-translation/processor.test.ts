import { describe, expect, it, vi } from "vitest";
import type { DatabaseResource } from "../../../src/db/client.js";
import {
  createDictionaryTranslationProcessor,
  type DictionaryTranslationCompletionClient,
} from "../../../src/modules/dictionary-translation/processor.js";
import type {
  DictionaryTranslationRepositoryContract,
  StoredDictionaryTranslation,
} from "../../../src/modules/dictionary-translation/repository.js";

function pendingRecord(): StoredDictionaryTranslation {
  return {
    attemptCount: 1,
    cacheKey: "a".repeat(64),
    candidateMeaningsZhHans: ["配偶", "对手", "助手", "(象棋)将死"],
    completedAt: null,
    contextualMeaningZhHans: null,
    dictionarySource: "ecdict",
    dictionaryVersion: "2026-09",
    exampleHash: "b".repeat(64),
    generationKind: "runtime",
    lemma: "mate",
    partOfSpeech: "noun",
    promptVersion: "dictionary-example-zh-hans-v1",
    selectedMeaningIndex: null,
    senseDefinitionEn: "a fellow member of a team",
    senseFingerprint: "c".repeat(64),
    sentence: "It was his first start against his former teammates.",
    sentenceZhHans: null,
    sourceKey: "d".repeat(64),
    stableSenseId: null,
    status: "pending",
    translationModelVersion: "deepseek-v4-flash@config-1",
  };
}

function repositoryFor(record: StoredDictionaryTranslation) {
  const complete = vi.fn<DictionaryTranslationRepositoryContract["complete"]>(() =>
    Promise.resolve(true),
  );
  const fail = vi.fn<DictionaryTranslationRepositoryContract["fail"]>(() =>
    Promise.resolve(),
  );
  const repository: DictionaryTranslationRepositoryContract = {
    complete,
    fail,
    findPreferred: () => Promise.resolve(undefined),
    importTrusted: () => Promise.reject(new Error("unused")),
    loadForProcessing: () => Promise.resolve(record),
    schedule: () => Promise.reject(new Error("unused")),
  };
  return { complete, fail, repository };
}

const database = {} as DatabaseResource;
const payload = {
  attempt: 1,
  cacheKey: "a".repeat(64),
  userId: "019c0123-4567-789a-8bcd-ef0123456789",
} as const;

describe("dictionary translation processor", () => {
  it("accepts one selected contextual meaning and a Chinese sentence", async () => {
    const record = pendingRecord();
    const state = repositoryFor(record);
    const completionClient: DictionaryTranslationCompletionClient = {
      complete: () =>
        Promise.resolve({
          content: JSON.stringify({
            contextualMeaningZhHans: "助手",
            selectedMeaningIndex: 2,
            sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
          }),
          model: "deepseek-v4-flash",
        }),
      runtimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
    };
    const processor = createDictionaryTranslationProcessor(database, {
      completionClient,
      repository: state.repository,
    });
    await processor.process(payload);
    expect(state.complete).toHaveBeenCalledWith(
      record.cacheKey,
      1,
      {
        contextualMeaningZhHans: "助手",
        selectedMeaningIndex: 2,
        sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
      },
      expect.any(Date),
    );
    expect(state.fail).not.toHaveBeenCalled();
  });

  it("accepts canonical provider model names without losing valid translations", async () => {
    const record = pendingRecord();
    const state = repositoryFor(record);
    const processor = createDictionaryTranslationProcessor(database, {
      repository: state.repository,
      completionClient: {
        runtimeModelVersion: () => Promise.resolve(record.translationModelVersion),
        complete: () =>
          Promise.resolve({
            model: "deepseek-v4-flash-canonical-revision",
            content: JSON.stringify({
              sentenceZhHans: "他与昔日队友交手。",
              contextualMeaningZhHans: "队友",
            }),
          }),
      },
    });
    await processor.process(payload);
    expect(state.complete).toHaveBeenCalledOnce();
    expect(state.fail).not.toHaveBeenCalled();
  });

  it("rejects a route revision change during generation", async () => {
    const record = pendingRecord();
    const state = repositoryFor(record);
    let calls = 0;
    const processor = createDictionaryTranslationProcessor(database, {
      repository: state.repository,
      completionClient: {
        runtimeModelVersion: () =>
          Promise.resolve(
            ++calls === 1 ? record.translationModelVersion : "new-model@config-2",
          ),
        complete: () =>
          Promise.resolve({
            model: "deepseek-v4-flash",
            content: JSON.stringify({
              sentenceZhHans: "他与昔日队友交手。",
              contextualMeaningZhHans: "队友",
            }),
          }),
      },
    });
    await expect(processor.process(payload)).rejects.toMatchObject({
      code: "DICTIONARY_TRANSLATION_MODEL_VERSION_STALE",
    });
    expect(state.complete).not.toHaveBeenCalled();
    expect(state.fail).toHaveBeenCalledOnce();
  });

  it("ignores harmless input fields echoed by the model", async () => {
    const record = pendingRecord();
    const state = repositoryFor(record);
    const processor = createDictionaryTranslationProcessor(database, {
      completionClient: {
        complete: () =>
          Promise.resolve({
            content: JSON.stringify({
              candidateMeaningsZhHans: record.candidateMeaningsZhHans,
              contextualMeaningZhHans: "助手",
              lemma: record.lemma,
              partOfSpeech: record.partOfSpeech,
              selectedMeaningIndex: 2,
              sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
            }),
            model: "deepseek-v4-flash",
          }),
        runtimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
      repository: state.repository,
    });

    await processor.process(payload);

    expect(state.complete).toHaveBeenCalledWith(
      record.cacheKey,
      1,
      {
        contextualMeaningZhHans: "助手",
        selectedMeaningIndex: 2,
        sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
      },
      expect.any(Date),
    );
    expect(state.fail).not.toHaveBeenCalled();
  });

  it("canonicalizes harmless punctuation differences in a selected meaning", async () => {
    const record = {
      ...pendingRecord(),
      candidateMeaningsZhHans: ["在...之前"],
      lemma: "before",
      partOfSpeech: "介词",
      senseDefinitionEn: null,
      sentence: "Fancy a coffee before the rain hits?",
    };
    const state = repositoryFor(record);
    const processor = createDictionaryTranslationProcessor(database, {
      completionClient: {
        complete: () =>
          Promise.resolve({
            content: JSON.stringify({
              contextualMeaningZhHans: "在…之前",
              selectedMeaningIndex: 0,
              sentenceZhHans: "趁还没下雨，想喝杯咖啡吗？",
            }),
            model: "deepseek-v4-flash",
          }),
        runtimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
      repository: state.repository,
    });

    await processor.process(payload);

    expect(state.complete).toHaveBeenCalledWith(
      record.cacheKey,
      1,
      {
        contextualMeaningZhHans: "在...之前",
        selectedMeaningIndex: 0,
        sentenceZhHans: "趁还没下雨,想喝杯咖啡吗?",
      },
      expect.any(Date),
    );
  });

  it("rejects multi-meaning or non-Chinese model output before cache write", async () => {
    const state = repositoryFor(pendingRecord());
    const processor = createDictionaryTranslationProcessor(database, {
      completionClient: {
        complete: () =>
          Promise.resolve({
            content: JSON.stringify({
              contextualMeaningZhHans: "配偶，对手，助手",
              selectedMeaningIndex: 0,
              sentenceZhHans: "It was a sentence.",
            }),
            model: "deepseek-v4-flash",
          }),
        runtimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
      repository: state.repository,
    });
    await expect(processor.process(payload)).rejects.toMatchObject({
      code: "DICTIONARY_TRANSLATION_INVALID_MODEL_OUTPUT",
    });
    expect(state.complete).not.toHaveBeenCalled();
    expect(state.fail).toHaveBeenCalledWith(
      payload.cacheKey,
      1,
      "DICTIONARY_TRANSLATION_INVALID_MODEL_OUTPUT",
      expect.any(Date),
    );
  });

  it("allows a refined meaning without an index when Chinese candidates are empty", async () => {
    const record = {
      ...pendingRecord(),
      candidateMeaningsZhHans: [],
      senseDefinitionEn: "a close friend or companion",
    };
    const state = repositoryFor(record);
    const processor = createDictionaryTranslationProcessor(database, {
      completionClient: {
        complete: () =>
          Promise.resolve({
            content: JSON.stringify({
              contextualMeaningZhHans: "好友",
              sentenceZhHans: "他是我最好的朋友。",
            }),
            model: "deepseek-v4-flash",
          }),
        runtimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
      repository: state.repository,
    });
    await processor.process(payload);
    expect(state.complete).toHaveBeenCalledWith(
      record.cacheKey,
      1,
      {
        contextualMeaningZhHans: "好友",
        sentenceZhHans: "他是我最好的朋友。",
      },
      expect.any(Date),
    );
  });

  it("allows a refined meaning without falsely selecting an inexact candidate", async () => {
    const record = pendingRecord();
    const state = repositoryFor(record);
    const processor = createDictionaryTranslationProcessor(database, {
      completionClient: {
        complete: () =>
          Promise.resolve({
            content: JSON.stringify({
              contextualMeaningZhHans: "队友",
              sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
            }),
            model: "deepseek-v4-flash",
          }),
        runtimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
      repository: state.repository,
    });
    await processor.process(payload);
    expect(state.complete).toHaveBeenCalledWith(
      record.cacheKey,
      1,
      {
        contextualMeaningZhHans: "队友",
        sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
      },
      expect.any(Date),
    );
  });
});
