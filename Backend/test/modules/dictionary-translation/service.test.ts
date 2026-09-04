import { describe, expect, it } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import type { DatabaseResource } from "../../../src/db/client.js";
import type { RedisResource } from "../../../src/infrastructure/redis/client.js";
import type { JobPayloadCipher } from "../../../src/modules/jobs/crypto.js";
import {
  DICTIONARY_TRANSLATION_PROMPT_VERSION,
  createDictionaryTranslationService,
} from "../../../src/modules/dictionary-translation/service.js";
import type {
  DictionaryTranslationRepositoryContract,
  StoredDictionaryTranslation,
} from "../../../src/modules/dictionary-translation/repository.js";
import type {
  DictionaryTranslationCacheIdentity,
  GeneratedDictionaryTranslation,
} from "../../../src/modules/dictionary-translation/types.js";
import type { PreparedJob } from "../../../src/modules/jobs/types.js";

class FakeRedis implements RedisResource {
  count = 0;

  close(): Promise<void> {
    return Promise.resolve();
  }
  connect(): Promise<void> {
    return Promise.resolve();
  }
  consumeFixedWindow(): Promise<number> {
    this.count += 1;
    return Promise.resolve(this.count);
  }
  onError(listener: (error: Error) => void): void {
    void listener;
  }
  ping(): Promise<void> {
    return Promise.resolve();
  }
  putOneTime(): Promise<void> {
    return Promise.resolve();
  }
  takeOneTime(): Promise<null> {
    return Promise.resolve(null);
  }
}

function stored(
  identity: DictionaryTranslationCacheIdentity,
  status: StoredDictionaryTranslation["status"],
  translation?: GeneratedDictionaryTranslation,
  generationKind: StoredDictionaryTranslation["generationKind"] = "runtime",
): StoredDictionaryTranslation {
  return {
    attemptCount: 1,
    cacheKey: identity.cacheKey,
    candidateMeaningsZhHans: identity.candidateMeaningsZhHans,
    completedAt: translation === undefined ? null : "2026-09-03T00:00:00.000Z",
    contextualMeaningZhHans: translation?.contextualMeaningZhHans ?? null,
    dictionarySource: identity.dictionarySource,
    dictionaryVersion: identity.dictionaryVersion,
    exampleHash: identity.exampleHash,
    generationKind,
    lemma: identity.lemma,
    partOfSpeech: identity.partOfSpeech,
    promptVersion: identity.promptVersion,
    selectedMeaningIndex: translation?.selectedMeaningIndex ?? null,
    senseDefinitionEn: identity.senseDefinitionEn ?? null,
    senseFingerprint: identity.senseFingerprint,
    sentence: identity.sentence,
    sentenceZhHans: translation?.sentenceZhHans ?? null,
    sourceKey: identity.sourceKey,
    stableSenseId: identity.stableSenseId ?? null,
    status,
    translationModelVersion: identity.translationModelVersion,
  };
}

class FakeRepository implements DictionaryTranslationRepositoryContract {
  readonly records = new Map<string, StoredDictionaryTranslation>();
  scheduleCount = 0;

  complete(): Promise<boolean> {
    return Promise.resolve(true);
  }
  fail(): Promise<void> {
    return Promise.resolve();
  }
  findPreferred(
    sourceKey: string,
    currentCacheKey: string,
  ): Promise<StoredDictionaryTranslation | undefined> {
    return Promise.resolve(
      [...this.records.values()].find(
        (record) =>
          record.sourceKey === sourceKey &&
          ((record.generationKind === "trusted_precomputed" &&
            record.status === "ready") ||
            record.cacheKey === currentCacheKey),
      ),
    );
  }
  importTrusted(
    identity: DictionaryTranslationCacheIdentity,
    translation: GeneratedDictionaryTranslation,
  ): Promise<StoredDictionaryTranslation> {
    const record = stored(identity, "ready", translation, "trusted_precomputed");
    this.records.set(identity.cacheKey, record);
    return Promise.resolve(record);
  }
  loadForProcessing(): Promise<undefined> {
    return Promise.resolve(undefined);
  }
  schedule(
    identity: DictionaryTranslationCacheIdentity,
    _userId: string,
    prepareJob: (attempt: number) => PreparedJob,
  ): Promise<StoredDictionaryTranslation> {
    const existing = this.records.get(identity.cacheKey);
    if (existing !== undefined) {
      return Promise.resolve(existing);
    }
    this.scheduleCount += 1;
    void prepareJob(1);
    const record = stored(identity, "pending");
    this.records.set(identity.cacheKey, record);
    return Promise.resolve(record);
  }
}

const fakeDatabase = {} as DatabaseResource;
const fakeCipher: JobPayloadCipher = {
  open: () => ({}),
  prepare: (type, _payload, options = {}) => ({
    availableAt: new Date(0),
    id: "019c0123-4567-789a-8bcd-ef0123456789",
    keyVersion: "test",
    maxAttempts: options.maxAttempts ?? 1,
    nonce: Buffer.alloc(12),
    payloadCiphertext: Buffer.alloc(1),
    tag: Buffer.alloc(16),
    type,
    ...(options.uniqueKey === undefined ? {} : { uniqueKey: options.uniqueKey }),
    ...(options.userId === undefined ? {} : { userId: options.userId }),
  }),
};
const mateRequest = {
  candidateMeaningsZhHans: ["配偶", "对手", "助手", "(象棋)将死"],
  dictionary: { source: "ecdict", version: "2026-09" },
  lemma: "mate",
  partOfSpeech: "noun",
  requestId: "mate-example-1",
  sentence: "It was his first start against his former teammates.",
  senseDefinitionEn: "a fellow member of a team",
} as const;

describe("dictionary translation service", () => {
  it("returns a trusted shared hit without authentication", async () => {
    const repository = new FakeRepository();
    const redis = new FakeRedis();
    const service = createDictionaryTranslationService(
      loadConfig({ NODE_ENV: "test" }),
      fakeDatabase,
      redis,
      {
        cipher: fakeCipher,
        repository,
        resolveRuntimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
    );
    const imported = await service.importTrusted([
      {
        ...mateRequest,
        contextualMeaningZhHans: "队友",
        promptVersion: DICTIONARY_TRANSLATION_PROMPT_VERSION,
        sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
        translationModelVersion: "gpt-5.6-luna@2026-09-03",
      },
    ]);
    expect(imported[0]?.status).toBe("ready");

    const [result] = await service.resolve([mateRequest], {
      generateOnMiss: false,
    });
    expect(result).toMatchObject({
      contextualMeaningZhHans: "队友",
      sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
      status: "ready",
    });
    expect(repository.scheduleCount).toBe(0);
    expect(redis.count).toBe(0);
  });

  it("deduplicates identical misses and returns pending immediately", async () => {
    const repository = new FakeRepository();
    const redis = new FakeRedis();
    const service = createDictionaryTranslationService(
      loadConfig({ NODE_ENV: "test" }),
      fakeDatabase,
      redis,
      {
        cipher: fakeCipher,
        repository,
        resolveRuntimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
    );
    const results = await service.resolve([mateRequest, mateRequest], {
      generateOnMiss: true,
      userId: "019c0123-4567-789a-8bcd-ef0123456789",
    });
    expect(results.map((result) => result.status)).toEqual(["pending", "pending"]);
    expect(repository.scheduleCount).toBe(1);
    expect(redis.count).toBe(1);

    await service.resolve([mateRequest], {
      generateOnMiss: true,
      userId: "019c0123-4567-789a-8bcd-ef0123456789",
    });
    expect(repository.scheduleCount).toBe(1);
    expect(redis.count).toBe(1);
  });

  it("fails closed before enqueue when the generation limit is exceeded", async () => {
    const repository = new FakeRepository();
    const service = createDictionaryTranslationService(
      loadConfig({ AI_USER_MINUTE_LIMIT: "1", NODE_ENV: "test" }),
      fakeDatabase,
      new FakeRedis(),
      {
        cipher: fakeCipher,
        repository,
        resolveRuntimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
    );
    await expect(
      service.resolve(
        [mateRequest, { ...mateRequest, sentence: "He is my best mate." }],
        {
          generateOnMiss: true,
          userId: "019c0123-4567-789a-8bcd-ef0123456789",
        },
      ),
    ).rejects.toMatchObject({
      code: "DICTIONARY_TRANSLATION_RATE_LIMIT_EXCEEDED",
    });
    expect(repository.scheduleCount).toBe(0);
  });
});
