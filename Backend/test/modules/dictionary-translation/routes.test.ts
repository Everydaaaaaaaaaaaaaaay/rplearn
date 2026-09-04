import { describe, expect, it, vi } from "vitest";
import { buildApp } from "../../../src/app.js";
import { loadConfig } from "../../../src/config/env.js";
import { createAdminAuthenticator } from "../../../src/modules/admin/http.js";
import type { AuthService } from "../../../src/modules/auth/service.js";
import { registerDictionaryTranslationAdminRoutes } from "../../../src/modules/dictionary-translation/admin-routes.js";
import { registerDictionaryTranslationRoutes } from "../../../src/modules/dictionary-translation/routes.js";
import type { DictionaryTranslationService } from "../../../src/modules/dictionary-translation/service.js";

const request = {
  candidateMeaningsZhHans: ["配偶", "对手", "助手", "(象棋)将死"],
  dictionary: { source: "ecdict", version: "2026-09" },
  lemma: "mate",
  partOfSpeech: "noun",
  sentence: "It was his first start against his former teammates.",
};

function authService(): AuthService {
  return {
    authenticate: (token) =>
      token === "valid-access-token"
        ? Promise.resolve({
            sessionId: "019c0123-4567-789a-8bcd-ef0123456788",
            tokenVersion: 0,
            userId: "019c0123-4567-789a-8bcd-ef0123456789",
          })
        : Promise.reject(new Error("invalid token")),
  } as AuthService;
}

function service() {
  const resolve = vi.fn<DictionaryTranslationService["resolve"]>(() =>
    Promise.resolve([
      {
        cache: {
          dictionarySource: "ecdict",
          dictionaryVersion: "2026-09",
          promptVersion: "dictionary-example-zh-hans-v1",
          translationModelVersion: "gpt-5.6-luna@2026-09-03",
        },
        cacheKey: "a".repeat(64),
        contextualMeaningZhHans: "队友",
        selectedMeaningIndex: 2,
        sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
        sourceKey: "b".repeat(64),
        status: "ready",
      },
    ]),
  );
  const importTrusted = vi.fn<DictionaryTranslationService["importTrusted"]>(() =>
    Promise.resolve([]),
  );
  return {
    implementation: { importTrusted, resolve } satisfies DictionaryTranslationService,
    importTrusted,
    resolve,
  };
}

describe("dictionary translation routes", () => {
  it("allows anonymous shared-cache reads and authenticates generation", async () => {
    const config = loadConfig({ NODE_ENV: "test" });
    const fake = service();
    const app = await buildApp(config, { logger: false });
    registerDictionaryTranslationRoutes(app, authService(), fake.implementation);

    const publicHit = await app.inject({
      method: "POST",
      payload: { generateOnMiss: false, requests: [request] },
      url: "/v1/dictionary/example-translations/resolve",
    });
    expect(publicHit.statusCode).toBe(200);
    expect(
      publicHit.json<{ results: readonly { status: string }[] }>().results[0],
    ).toMatchObject({ status: "ready" });
    expect(fake.resolve).toHaveBeenNthCalledWith(1, [request], {
      generateOnMiss: false,
    });

    const generation = await app.inject({
      headers: { authorization: "Bearer valid-access-token" },
      method: "POST",
      payload: { generateOnMiss: true, requests: [request] },
      url: "/v1/dictionary/example-translations/resolve",
    });
    expect(generation.statusCode).toBe(200);
    expect(fake.resolve).toHaveBeenNthCalledWith(2, [request], {
      generateOnMiss: true,
      userId: "019c0123-4567-789a-8bcd-ef0123456789",
    });
    await app.close();
  });

  it("rejects client-supplied translations instead of silently stripping them", async () => {
    const fake = service();
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), {
      logger: false,
    });
    registerDictionaryTranslationRoutes(app, authService(), fake.implementation);
    const response = await app.inject({
      method: "POST",
      payload: {
        generateOnMiss: true,
        requests: [
          {
            ...request,
            sentenceZhHans: "攻击者提交的公共译文",
          },
        ],
      },
      url: "/v1/dictionary/example-translations/resolve",
    });
    expect(response.statusCode).toBe(400);
    expect(response.json<{ code: string }>().code).toBe("INVALID_REQUEST");
    expect(fake.resolve).not.toHaveBeenCalled();
    await app.close();
  });

  it("protects trusted precomputed imports with an operator credential", async () => {
    const token = "operator-token-with-at-least-thirty-two-characters";
    const fake = service();
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), {
      logger: false,
    });
    registerDictionaryTranslationAdminRoutes(
      app,
      createAdminAuthenticator([{ keyId: "primary", token }]),
      fake.implementation,
    );
    const payload = {
      items: [
        {
          ...request,
          contextualMeaningZhHans: "队友",
          promptVersion: "dictionary-example-zh-hans-v1",
          selectedMeaningIndex: 2,
          sentenceZhHans: "这是他第一次作为首发对阵以前的队友。",
          translationModelVersion: "gpt-5.6-luna@2026-09-03",
        },
      ],
    };
    const unauthorized = await app.inject({
      method: "POST",
      payload,
      url: "/internal/admin/dictionary/example-translations/import",
    });
    expect(unauthorized.statusCode).toBe(401);
    expect(fake.importTrusted).not.toHaveBeenCalled();

    const imported = await app.inject({
      headers: { authorization: `Bearer ${token}` },
      method: "POST",
      payload,
      url: "/internal/admin/dictionary/example-translations/import",
    });
    expect(imported.statusCode).toBe(200);
    expect(fake.importTrusted).toHaveBeenCalledTimes(1);
    await app.close();
  });
});
