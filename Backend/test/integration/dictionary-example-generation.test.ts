import { afterAll, beforeAll, describe, it, expect, vi } from "vitest";
import { integrationConfig } from "../helpers/integration.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { runMigrations } from "../../src/db/migrate.js";
import { newEntityId } from "../../src/shared/id.js";
import { DictionaryExampleGenerationRepository } from "../../src/modules/dictionary-translation/generation-repository.js";
import { createDictionaryExampleGenerationService } from "../../src/modules/dictionary-translation/generation-service.js";
import { createDictionaryExampleGenerationProcessor } from "../../src/modules/dictionary-translation/generation-processor.js";
import { createJobPayloadCipher } from "../../src/modules/jobs/crypto.js";
import { JobRepository } from "../../src/modules/jobs/repository.js";
import { JobWorker } from "../../src/modules/jobs/worker.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "persistent shared example generation",
  () => {
    let config: ReturnType<typeof integrationConfig>;
    let runtime: RuntimeDependencies;
    let initialized = false;
    let repository: DictionaryExampleGenerationRepository;
    const userId = newEntityId();
    const budget = vi.fn(() => Promise.resolve(1));
    const catalog = { find: () => Promise.resolve([]) };
    const complete = vi.fn(() =>
      Promise.resolve({
        content: JSON.stringify({
          examples: [
            {
              partOfSpeech: "a",
              definition: "very careful",
              sentence: "Her meticulous notes helped the whole team.",
              sentenceZhHans: "她细致的笔记帮助了整个团队。",
              contextualMeaningZhHans: "细致的",
            },
          ],
        }),
        model: "test",
      }),
    );
    let service: ReturnType<typeof createDictionaryExampleGenerationService>;
    let worker: JobWorker;
    beforeAll(async () => {
      config = integrationConfig({ JOB_RETRY_BASE_SECONDS: "1" });
      runtime = createRuntimeDependencies(config);
      initialized = true;
      await runMigrations(runtime.database);
      await runtime.start();
      await runtime.database.sql`insert into app.users(id) values(${userId})`;
      for (const lemma of [
        "meticulous",
        "quizzical",
        "plentiful",
        "forgotten",
        "ratecheck",
      ]) {
        const existing =
          lemma === "meticulous"
            ? ["He is meticulous about checking every detail."]
            : lemma === "plentiful"
              ? ["Food is plentiful here.", "The rains were plentiful."]
              : [];
        await runtime.database
          .sql`insert into app.dictionary_example_lexicon(lemma,definition,meaning,source_version,existing_examples) values(${lemma},'careful','细心的','test',${JSON.stringify(existing)}::jsonb)`;
      }
      repository = new DictionaryExampleGenerationRepository(runtime.database);
      service = createDictionaryExampleGenerationService(
        repository,
        catalog,
        createJobPayloadCipher(config),
        { consumeFixedWindow: budget },
      );
      worker = new JobWorker({
        config,
        cipher: createJobPayloadCipher(config),
        repository: new JobRepository(runtime.database),
        workerId: "example-test-worker",
        logger: {
          info: () => undefined,
          warn: () => undefined,
          error: () => undefined,
        },
        notifier: {
          sendEmailVerification: () => Promise.resolve(),
          sendPasswordReset: () => Promise.resolve(),
        },
        processDictionaryExamples: createDictionaryExampleGenerationProcessor(
          repository,
          catalog,
          complete,
        ).process,
      });
    });
    afterAll(async () => {
      if (initialized) {
        await runtime.database
          .sql`delete from app.dictionary_example_generations where lemma in ('meticulous','quizzical','plentiful','forgotten','ratecheck')`;
        await runtime.database.sql`delete from app.jobs where user_id=${userId}`;
        await runtime.database
          .sql`delete from app.dictionary_example_lexicon where source_version='test'`;
        await runtime.database.sql`delete from app.users where id=${userId}`;
        await runtime.close();
      }
    });
    it("enqueues one durable job under 20 concurrent requests and shares its one missing example", async () => {
      const responses = await Promise.all(
        Array.from({ length: 20 }, () => service.resolve("meticulous", userId)),
      );
      expect(responses.every((r) => r.status === "pending")).toBe(true);
      const jobs = await runtime.database
        .sql`select id from app.jobs where user_id=${userId}`;
      expect(jobs).toHaveLength(1);
      expect(budget).toHaveBeenCalledTimes(3);
      expect(await worker.runOnce()).toBe("succeeded");
      expect(complete).toHaveBeenCalledTimes(1);
      const again = await service.resolve("meticulous");
      expect(again.status).toBe("ready");
      expect(again.examples).toHaveLength(1);
      expect((await service.resolve("meticulous", newEntityId())).examples).toEqual(
        again.examples,
      );
      expect(complete).toHaveBeenCalledTimes(1);
      expect(budget).toHaveBeenCalledTimes(3);
    });
    it("keeps ready examples after completed job retention cleanup", async () => {
      await runtime.database
        .sql`delete from app.jobs where id=(select job_id from app.dictionary_example_generations where lemma='meticulous')`;
      const result = await service.resolve("meticulous", userId);
      expect(result.status).toBe("ready");
      expect(result.examples).toHaveLength(1);
      expect(complete).toHaveBeenCalledTimes(1);
    });

    it("does not generate for a full baseline or unknown word", async () => {
      expect((await service.resolve("plentiful", userId)).status).toBe("ready");
      expect((await service.resolve("notindictionary", userId)).status).toBe(
        "unavailable",
      );
      expect(budget).toHaveBeenCalledTimes(3);
    });
    it("retries invalid output at most three times, then persists cooldown across service instances", async () => {
      complete.mockResolvedValue({ content: '{"examples":[]}', model: "test" });
      await service.resolve("quizzical", userId);
      for (let i = 0; i < 3; i++)
        expect(await worker.runOnce(new Date(Date.now() + 10000))).toBe(
          i === 2 ? "dead" : "retry_scheduled",
        );
      const fresh = createDictionaryExampleGenerationService(
        new DictionaryExampleGenerationRepository(runtime.database),
        catalog,
        createJobPayloadCipher(config),
        { consumeFixedWindow: budget },
      );
      const result = await fresh.resolve("quizzical", userId);
      expect(result.status).toBe("failed");
      expect(result.examples).toEqual([]);
      expect(complete).toHaveBeenCalledTimes(4);
      expect((await repository.find("quizzical"))?.status).toBe("failed");
    });
    it("recovers dead jobs instead of leaving a word pending forever", async () => {
      await service.resolve("forgotten", userId);
      await runtime.database
        .sql`update app.jobs set status='dead',updated_at=now() where id=(select job_id from app.dictionary_example_generations where lemma='forgotten')`;
      expect((await service.resolve("forgotten", userId)).status).toBe("failed");
      await runtime.database
        .sql`update app.jobs set updated_at=now()-interval '2 hours' where id=(select job_id from app.dictionary_example_generations where lemma='forgotten')`;
      expect((await service.resolve("forgotten", userId)).status).toBe("pending");
      expect((await repository.find("forgotten"))?.revision).toBe(2);
    });
    it("blocked actors cannot consume the global budget or enqueue a job", async () => {
      const before = budget.mock.calls.length;
      budget.mockResolvedValueOnce(13);
      await expect(service.resolve("ratecheck", userId)).rejects.toMatchObject({
        statusCode: 429,
      });
      expect(budget.mock.calls.length - before).toBe(1);
      expect(await repository.find("ratecheck")).toBeUndefined();
    });
  },
);
