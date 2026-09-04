import { createHmac } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import type { RedisResource } from "../../infrastructure/redis/client.js";
import { AppError } from "../../shared/errors.js";
import { createJobPayloadCipher, type JobPayloadCipher } from "../jobs/crypto.js";
import { DICTIONARY_EXAMPLE_TRANSLATION_JOB } from "../jobs/types.js";
import { createDictionaryTranslationCacheIdentity } from "./identity.js";
import {
  DictionaryTranslationRepository,
  type DictionaryTranslationRepositoryContract,
  type StoredDictionaryTranslation,
} from "./repository.js";
import type {
  DictionaryExampleRequest,
  DictionaryTranslationCacheIdentity,
  DictionaryTranslationResult,
  TrustedDictionaryTranslationImport,
} from "./types.js";
import { validatedGeneratedTranslation } from "./validation.js";

export const DICTIONARY_TRANSLATION_PROMPT_VERSION = "dictionary-example-zh-hans-v2";

export type DictionaryTranslationService = Readonly<{
  importTrusted: (
    items: readonly TrustedDictionaryTranslationImport[],
  ) => Promise<readonly DictionaryTranslationResult[]>;
  resolve: (
    requests: readonly DictionaryExampleRequest[],
    options: Readonly<{
      generateOnMiss: boolean;
      userId?: string;
    }>,
  ) => Promise<readonly DictionaryTranslationResult[]>;
}>;

type ServiceDependencies = Readonly<{
  cipher?: JobPayloadCipher;
  now?: () => Date;
  repository?: DictionaryTranslationRepositoryContract;
  resolveRuntimeModelVersion: () => Promise<string>;
}>;

function publicResult(
  request: DictionaryExampleRequest,
  identity: DictionaryTranslationCacheIdentity,
  stored: StoredDictionaryTranslation | undefined,
): DictionaryTranslationResult {
  const status =
    stored?.status === "ready"
      ? "ready"
      : stored?.status === "pending"
        ? "pending"
        : "missing";
  return {
    cache: {
      dictionarySource: stored?.dictionarySource ?? identity.dictionarySource,
      dictionaryVersion: stored?.dictionaryVersion ?? identity.dictionaryVersion,
      ...(stored?.completedAt === null || stored?.completedAt === undefined
        ? {}
        : { generatedAt: stored.completedAt }),
      promptVersion: stored?.promptVersion ?? identity.promptVersion,
      translationModelVersion:
        stored?.translationModelVersion ?? identity.translationModelVersion,
    },
    cacheKey: stored?.cacheKey ?? identity.cacheKey,
    ...(status === "ready" && stored?.contextualMeaningZhHans != null
      ? { contextualMeaningZhHans: stored.contextualMeaningZhHans }
      : {}),
    ...(request.requestId === undefined ? {} : { requestId: request.requestId }),
    ...(status === "ready" && stored?.selectedMeaningIndex != null
      ? { selectedMeaningIndex: stored.selectedMeaningIndex }
      : {}),
    ...(status === "ready" && stored?.sentenceZhHans != null
      ? { sentenceZhHans: stored.sentenceZhHans }
      : {}),
    sourceKey: identity.sourceKey,
    status,
  };
}

function generationUnavailable(cause: unknown): AppError {
  return new AppError({
    cause,
    code: "DICTIONARY_TRANSLATION_PROTECTION_UNAVAILABLE",
    message: "Dictionary translation generation is temporarily unavailable.",
    statusCode: 503,
  });
}

export function createDictionaryTranslationService(
  config: RuntimeConfig,
  database: DatabaseResource,
  redis: RedisResource,
  dependencies: ServiceDependencies,
): DictionaryTranslationService {
  const repository =
    dependencies.repository ?? new DictionaryTranslationRepository(database);
  const cipher = dependencies.cipher ?? createJobPayloadCipher(config);
  const now = dependencies.now ?? (() => new Date());
  const userReference = (userId: string): string =>
    createHmac("sha256", config.authTokenHashPepper)
      .update(`dictionary-translation-user:${userId}`)
      .digest("hex");

  const currentEntries = async (requests: readonly DictionaryExampleRequest[]) => {
    const modelVersion = await dependencies.resolveRuntimeModelVersion();
    return requests.map((request) => ({
      identity: createDictionaryTranslationCacheIdentity(
        request,
        modelVersion,
        DICTIONARY_TRANSLATION_PROMPT_VERSION,
      ),
      request,
    }));
  };

  return {
    resolve: async (requests, options) => {
      const entries = await currentEntries(requests);
      const stored = await Promise.all(
        entries.map(({ identity }) =>
          repository.findPreferred(identity.sourceKey, identity.cacheKey),
        ),
      );
      const generationUserId = options.userId;
      if (!options.generateOnMiss || generationUserId === undefined) {
        return entries.map(({ identity, request }, index) =>
          publicResult(request, identity, stored[index]),
        );
      }

      const misses = new Map<string, DictionaryTranslationCacheIdentity>();
      for (const [index, { identity }] of entries.entries()) {
        const record = stored[index];
        if (record?.status !== "ready" && record?.status !== "pending") {
          misses.set(identity.cacheKey, identity);
        }
      }
      if (misses.size > 0) {
        let counts: readonly number[];
        try {
          counts = await Promise.all(
            [...misses].map(() =>
              redis.consumeFixedWindow(
                `dictionary-translation:minute:${userReference(generationUserId)}`,
                60,
              ),
            ),
          );
        } catch (error) {
          throw generationUnavailable(error);
        }
        if (counts.some((count) => count > config.aiUserMinuteLimit)) {
          throw new AppError({
            code: "DICTIONARY_TRANSLATION_RATE_LIMIT_EXCEEDED",
            details: {
              limit: config.aiUserMinuteLimit,
              windowSeconds: 60,
            },
            message: "Too many dictionary translations were requested.",
            statusCode: 429,
          });
        }
      }

      const scheduled = new Map<string, StoredDictionaryTranslation>();
      await Promise.all(
        [...misses.values()].map(async (identity) => {
          const result = await repository.schedule(
            identity,
            generationUserId,
            (attempt) =>
              cipher.prepare(
                DICTIONARY_EXAMPLE_TRANSLATION_JOB,
                {
                  attempt,
                  cacheKey: identity.cacheKey,
                  userId: generationUserId,
                },
                {
                  maxAttempts: 1,
                  uniqueKey: `dictionary-translation:${identity.cacheKey}:${String(attempt)}`,
                  userId: generationUserId,
                },
              ),
          );
          scheduled.set(identity.cacheKey, result);
        }),
      );

      return entries.map(({ identity, request }, index) => {
        return publicResult(
          request,
          identity,
          scheduled.get(identity.cacheKey) ?? stored[index],
        );
      });
    },

    importTrusted: async (items) =>
      Promise.all(
        items.map(async (item) => {
          const identity = createDictionaryTranslationCacheIdentity(
            item,
            item.translationModelVersion,
            item.promptVersion,
          );
          const translation = validatedGeneratedTranslation(
            {
              contextualMeaningZhHans: item.contextualMeaningZhHans,
              selectedMeaningIndex: item.selectedMeaningIndex,
              sentenceZhHans: item.sentenceZhHans,
            },
            identity.candidateMeaningsZhHans,
          );
          if (translation === undefined) {
            throw new AppError({
              code: "INVALID_DICTIONARY_TRANSLATION",
              message: "The trusted dictionary translation is invalid.",
              statusCode: 400,
            });
          }
          const stored = await repository.importTrusted(identity, translation, now());
          return publicResult(item, identity, stored);
        }),
      ),
  };
}
