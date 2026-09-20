import { describe, expect, it, vi } from "vitest";
import {
  decodeGeneratedExamples,
  hasExampleTarget,
} from "../../../src/modules/dictionary-translation/generation-processor.js";
import { registerDictionaryExampleCatalogRoutes } from "../../../src/modules/dictionary-translation/catalog-routes.js";
import type { AuthService } from "../../../src/modules/auth/service.js";
import { buildApp } from "../../../src/app.js";
import { loadConfig } from "../../../src/config/env.js";
const baseline = {
  lemma: "just",
  forms: [],
  definition: "only",
  meaning: "仅仅",
  existingExamples: [],
};
const example = {
  partOfSpeech: "r",
  definition: "only",
  sentence: "I'm just looking, thank you.",
  sentenceZhHans: "我只是看看，谢谢。",
  contextualMeaningZhHans: "只是",
};

describe("runtime dictionary example validation", () => {
  it("rejects synonyms, duplicate output, wrong counts and multi-gloss annotations", () => {
    expect(
      decodeGeneratedExamples(JSON.stringify({ examples: [example] }), baseline, [], 1),
    ).toHaveLength(1);
    for (const examples of [
      [{ ...example, sentence: "I was merely asking." }],
      [example, example],
      [{ ...example, contextualMeaningZhHans: "刚刚；只是" }],
    ]) {
      expect(() =>
        decodeGeneratedExamples(JSON.stringify({ examples }), baseline, [], 1),
      ).toThrow();
    }
    expect(() =>
      decodeGeneratedExamples(
        JSON.stringify({ examples: [example] }),
        baseline,
        [example.sentence],
        1,
      ),
    ).toThrow();
  });
  it("accepts attested irregular forms and real contractions, but not substrings", () => {
    expect(
      hasExampleTarget("She went home.", { lemma: "go", forms: ["went", "gone"] }),
    ).toBe(true);
    expect(hasExampleTarget("I can't swim.", { lemma: "n't", forms: [] })).toBe(true);
    expect(hasExampleTarget("The window is open.", { lemma: "in", forms: [] })).toBe(
      false,
    );
  });
  it("requires an authenticated actor for generation and rejects client-supplied counts", async () => {
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), { logger: false });
    const resolve = vi.fn().mockResolvedValue({ examples: [], status: "pending" });
    const authenticate = vi.fn().mockResolvedValue({
      userId: "00000000-0000-4000-a000-000000000001",
      isGuest: true,
    });
    registerDictionaryExampleCatalogRoutes(
      app,
      { find: () => Promise.resolve([]) },
      { generation: { resolve }, auth: { authenticate } as unknown as AuthService },
    );
    expect(
      (
        await app.inject({
          method: "POST",
          url: "/v1/dictionary/learner-examples/resolve",
          payload: { lemma: "just", generateOnMiss: true },
        })
      ).statusCode,
    ).toBe(401);
    expect(
      (
        await app.inject({
          method: "POST",
          url: "/v1/dictionary/learner-examples/resolve",
          headers: { authorization: "Bearer guest-token" },
          payload: { lemma: "just", generateOnMiss: true, count: 2 },
        })
      ).statusCode,
    ).toBe(400);
    expect(resolve).not.toHaveBeenCalled();
    expect(
      (
        await app.inject({
          method: "POST",
          url: "/v1/dictionary/learner-examples/resolve",
          headers: { authorization: "Bearer guest-token" },
          payload: { lemma: "just", generateOnMiss: true },
        })
      ).statusCode,
    ).toBe(200);
    expect(resolve).toHaveBeenCalledWith(
      "just",
      "00000000-0000-4000-a000-000000000001",
    );
    await app.close();
  });
});
