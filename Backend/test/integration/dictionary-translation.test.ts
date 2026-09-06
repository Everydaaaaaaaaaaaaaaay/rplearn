import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { buildApp } from "../../src/app.js";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { createDictionaryTranslationProcessor } from "../../src/modules/dictionary-translation/processor.js";
import { registerDictionaryTranslationRoutes } from "../../src/modules/dictionary-translation/routes.js";
import { createDictionaryTranslationService } from "../../src/modules/dictionary-translation/service.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

const example = {
  candidateMeaningsZhHans: ["配偶", "对手", "助手", "(象棋)将死"],
  dictionary: { source: "ecdict", version: "2026-09" },
  lemma: "mate",
  partOfSpeech: "noun",
  senseDefinitionEn: "a fellow member of a team",
  sentence: "It was his first start against his former teammates.",
  stableSenseId: `noun-1-${"definition-".repeat(58)}`,
};

describe.runIf(runIntegrationTests)("dictionary example translation cache", () => {
  let app: FastifyInstance | undefined;
  let dependencies: RuntimeDependencies | undefined;
  let jobWorker: ReturnType<typeof createTestJobWorker> | undefined;
  let accessToken: string;
  let userId: string;
  const email = `dictionary-${newEntityId()}@example.com`;
  const password = "Correct Horse Dictionary 1!";
  const verificationTokens = new Map<string, string>();
  const complete = vi.fn(() =>
    Promise.resolve({
      content: JSON.stringify({
        contextualMeaningZhHans: "队友",
        sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
      }),
      model: "deepseek-v4-flash",
    }),
  );

  beforeAll(async () => {
    const config = loadConfig({
      AI_USER_MINUTE_LIMIT: "20",
      NODE_ENV: "test",
    });
    const runtime = createRuntimeDependencies(config);
    dependencies = runtime;
    await runMigrations(runtime.database);
    await runtime.start();
    const notifier: AuthNotifier = {
      sendEmailVerification: (destination, token) => {
        verificationTokens.set(destination, token);
        return Promise.resolve();
      },
      sendPasswordReset: () => Promise.resolve(),
    };
    const authService = await createAuthService(config, runtime.database);
    const translationService = createDictionaryTranslationService(
      config,
      runtime.database,
      runtime.redis,
      {
        resolveRuntimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
    );
    const processor = createDictionaryTranslationProcessor(runtime.database, {
      completionClient: {
        complete: (_userId, messages) => {
          expect(messages[1]?.content).toContain("a fellow member of a team");
          return complete();
        },
        runtimeModelVersion: () => Promise.resolve("deepseek-v4-flash@config-1"),
      },
    });
    jobWorker = createTestJobWorker(config, runtime.database, notifier, {
      processDictionaryTranslation: processor.process,
    });
    const application = await buildApp(config, { logger: false });
    app = application;
    registerAuthRoutes(application, authService);
    registerDictionaryTranslationRoutes(application, authService, translationService);

    await application.inject({
      method: "POST",
      payload: { email, password },
      url: "/v1/auth/register",
    });
    expect(await jobWorker.runOnce()).toBe("succeeded");
    await application.inject({
      method: "POST",
      payload: { token: verificationTokens.get(email) },
      url: "/v1/auth/email/verify",
    });
    const login = await application.inject({
      method: "POST",
      payload: {
        device: { deviceId: "dictionary-test-device", platform: "ios" },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    const token = login.json<TokenResponse>();
    accessToken = token.accessToken;
    userId = token.userId;
  });

  afterAll(async () => {
    if (app === undefined || dependencies === undefined) {
      return;
    }
    await app.close();
    await dependencies.database.sql`
      delete from app.dictionary_example_translations
      where requested_by_user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.jobs
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.auth_security_events
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.users
      where id = ${userId}
    `;
    await dependencies.close();
  });

  it("reads anonymously, enqueues once, and exposes only validated worker output", async () => {
    if (app === undefined || dependencies === undefined || jobWorker === undefined) {
      throw new Error("DictionaryTranslationIntegrationSetupIncomplete");
    }
    const initial = await app.inject({
      method: "POST",
      payload: { generateOnMiss: false, requests: [example] },
      url: "/v1/dictionary/example-translations/resolve",
    });
    expect(initial.statusCode).toBe(200);
    expect(
      initial.json<{ results: readonly { status: string }[] }>().results[0],
    ).toMatchObject({ status: "missing" });

    const authorization = { authorization: `Bearer ${accessToken}` };
    const pending = await app.inject({
      headers: authorization,
      method: "POST",
      payload: { generateOnMiss: true, requests: [example] },
      url: "/v1/dictionary/example-translations/resolve",
    });
    expect(pending.statusCode).toBe(200);
    const pendingResult = pending.json<{
      results: readonly { cacheKey: string; status: string }[];
    }>().results[0];
    expect(pendingResult).toMatchObject({ status: "pending" });

    const replay = await app.inject({
      headers: authorization,
      method: "POST",
      payload: { generateOnMiss: true, requests: [example] },
      url: "/v1/dictionary/example-translations/resolve",
    });
    expect(
      replay.json<{ results: readonly { cacheKey: string }[] }>().results[0],
    ).toMatchObject({ cacheKey: pendingResult?.cacheKey });
    const [counts] = await dependencies.database.sql<
      { cache_count: number; job_count: number }[]
    >`
      select
        (select count(*)::int from app.dictionary_example_translations
          where requested_by_user_id = ${userId}) as cache_count,
        (select count(*)::int from app.jobs
          where user_id = ${userId}
            and type = 'dictionary.example_translation') as job_count
    `;
    expect(counts).toEqual({ cache_count: 1, job_count: 1 });

    expect(await jobWorker.runOnce()).toBe("succeeded");
    expect(complete).toHaveBeenCalledTimes(1);

    const ready = await app.inject({
      method: "POST",
      payload: { generateOnMiss: false, requests: [example] },
      url: "/v1/dictionary/example-translations/resolve",
    });
    expect(ready.json<{ results: readonly unknown[] }>().results[0]).toMatchObject({
      contextualMeaningZhHans: "队友",
      sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
      status: "ready",
    });
  });
});
