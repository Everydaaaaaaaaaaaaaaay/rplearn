import { describe, expect, it, vi } from "vitest";
import { buildApp } from "../../../src/app.js";
import { loadConfig } from "../../../src/config/env.js";
import { registerDictionaryExampleCatalogRoutes } from "../../../src/modules/dictionary-translation/catalog-routes.js";
import { createDictionaryExampleCatalogService } from "../../../src/modules/dictionary-translation/catalog-service.js";

describe("shared learner example catalog", () => {
  it("allows public reads, normalizes lemmas, and never caches an empty result", async () => {
    const find = vi
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          rank: -99,
          partOfSpeech: "n",
          definition: "a test",
          sentence: "This test is easy.",
          sentenceZhHans: "这项测试很简单。",
          contextualMeaningZhHans: "测试",
        },
      ]);
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), { logger: false });
    registerDictionaryExampleCatalogRoutes(
      app,
      createDictionaryExampleCatalogService({ find }),
    );
    const first = await app.inject({ url: "/v1/dictionary/learner-examples/Test" });
    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({ examples: [] });
    expect(first.headers["cache-control"]).toBe("no-store");
    const second = await app.inject({ url: "/v1/dictionary/learner-examples/Test" });
    expect(second.json<{ examples: unknown[] }>().examples).toHaveLength(1);
    expect(find).toHaveBeenNthCalledWith(2, "test");
    const invalid = await app.inject({ url: "/v1/dictionary/learner-examples/123" });
    expect(invalid.statusCode).toBe(400);
    expect(find).toHaveBeenCalledTimes(2);
    await app.close();
  });
});
