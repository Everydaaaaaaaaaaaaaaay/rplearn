import { createHash } from "node:crypto";
import type { JobPayloadCipher } from "../jobs/crypto.js";
import type { GenerationRepository } from "./generation-repository.js";
import type { DictionaryExampleCatalogService } from "./catalog-service.js";
import type { RedisResource } from "../../infrastructure/redis/client.js";
import { AppError } from "../../shared/errors.js";

import { DICTIONARY_EXAMPLE_GENERATION_JOB } from "../jobs/types.js";
export type ExampleGenerationPayload = Readonly<{
  lemma: string;
  revision: number;
  userId: string;
}>;

export function createDictionaryExampleGenerationService(
  repository: GenerationRepository,
  catalog: DictionaryExampleCatalogService,
  cipher: JobPayloadCipher,
  redis: Pick<RedisResource, "consumeFixedWindow">,
) {
  const resolve = async (input: string, userId?: string) => {
    const lemma = input.trim().toLowerCase().replace(/\s+/g, " ");
    const [baseline, stored, seeded] = await Promise.all([
      repository.baseline(lemma),
      repository.find(lemma),
      catalog.find(lemma),
    ]);
    const examples = [...seeded, ...(stored?.examples ?? [])];
    const distinct = new Set(
      [...(baseline?.existingExamples ?? []), ...examples.map((e) => e.sentence)].map(
        (s) => s.trim().toLowerCase(),
      ),
    );
    if (distinct.size >= 2 || stored?.status === "ready")
      return { examples, status: "ready" as const };
    if (baseline === undefined) return { examples, status: "unavailable" as const };
    if (stored?.status === "pending") return { examples, status: "pending" as const };
    if (
      stored?.status === "failed" &&
      stored.retryAfter !== null &&
      Date.parse(stored.retryAfter) > Date.now()
    )
      return { examples, status: "failed" as const, retryAfter: stored.retryAfter };
    if (userId === undefined) return { examples, status: "missing" as const };
    const scheduled = await repository.schedule(lemma, async (revision) => {
      const reference = createHash("sha256").update(userId).digest("hex");
      // Executed once under the lemma lock; concurrent waiters consume no budget.
      const limited = () =>
        new AppError({
          code: "DICTIONARY_EXAMPLES_RATE_LIMIT",
          message: "Dictionary example generation limit reached.",
          statusCode: 429,
        });
      // Do not let an already-blocked actor consume the shared global budget.
      if (
        (await redis.consumeFixedWindow(
          `dictionary-examples:minute:${reference}`,
          60,
        )) > 12
      )
        throw limited();
      if (
        (await redis.consumeFixedWindow(
          `dictionary-examples:day:${reference}`,
          86400,
        )) > 200
      )
        throw limited();
      if (
        (await redis.consumeFixedWindow("dictionary-examples:global-day", 86400)) > 5000
      )
        throw limited();
      return cipher.prepare(
        DICTIONARY_EXAMPLE_GENERATION_JOB,
        { lemma, revision, userId } satisfies ExampleGenerationPayload,
        {
          maxAttempts: 3,
          uniqueKey: `dictionary-examples:${lemma}:${String(revision)}`,
          userId,
        },
      );
    });
    return {
      examples: [...seeded, ...scheduled.examples],
      status: scheduled.status,
      ...(scheduled.retryAfter === null ? {} : { retryAfter: scheduled.retryAfter }),
    };
  };
  return { resolve };
}
export type DictionaryExampleGenerationService = ReturnType<
  typeof createDictionaryExampleGenerationService
>;
