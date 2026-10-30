import Fastify from "fastify";
import { describe, expect, it, vi } from "vitest";
import { registerGrammarRoutes } from "../../../src/modules/grammar/routes.js";
import type { AuthService } from "../../../src/modules/auth/service.js";

describe("grammar HTTP contract", () => {
  it("catalog is a public read, while generation requires authentication and validated input", async () => {
    const app = Fastify();
    const authenticate = vi.fn(() =>
      Promise.resolve({
        userId: "019c0123-4567-789a-8bcd-ef01234567f0",
        isGuest: false,
      }),
    );
    const analyze = vi.fn(() =>
      Promise.resolve({
        analysis: { summaryZh: "说明", points: [] },
        learnedPoints: [],
      }),
    );
    const service = {
      catalog: () => Promise.resolve({ revision: "v1", points: [] }),
      analyze,
      curate: () => Promise.resolve(),
    };
    registerGrammarRoutes(app, { authenticate } as unknown as AuthService, service);
    expect((await app.inject({ url: "/v1/grammar/catalog" })).statusCode).toBe(200);
    expect(authenticate).not.toHaveBeenCalled();
    expect(
      (
        await app.inject({
          method: "POST",
          url: "/v1/grammar/analysis",
          payload: { sentence: "Hello" },
        })
      ).statusCode,
    ).toBe(401);
    expect(analyze).not.toHaveBeenCalled();
    const headers = { authorization: "Bearer test-only-token" };
    expect(
      (
        await app.inject({
          method: "POST",
          url: "/v1/grammar/analysis",
          headers,
          payload: { sentence: "Hello", learnerLevel: "B1", operationId: "bad" },
        })
      ).statusCode,
    ).toBe(400);
    expect(analyze).not.toHaveBeenCalled();
    const payload = {
      sentence: "I do like it.",
      learnerLevel: "B1",
      operationId: "019c0123-4567-789a-8bcd-ef01234567f1",
    };
    expect(
      (
        await app.inject({
          method: "POST",
          url: "/v1/grammar/analysis",
          headers,
          payload,
        })
      ).statusCode,
    ).toBe(200);
    expect(analyze).toHaveBeenCalledWith(
      "019c0123-4567-789a-8bcd-ef01234567f0",
      payload,
    );
    await app.close();
  });
});
