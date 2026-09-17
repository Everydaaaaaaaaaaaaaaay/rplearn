import Fastify, { type FastifyBaseLogger } from "fastify";
import pino from "pino";
import { describe, expect, it } from "vitest";
import { createLoggerOptions } from "../../src/app/logger.js";
import { registerRequestDiagnostics } from "../../src/app/request-diagnostics.js";
import { registerErrorHandling } from "../../src/app/error-handler.js";
import { registerAiRoutes } from "../../src/modules/ai/routes.js";
import type { AiService } from "../../src/modules/ai/service.js";
import type { AuthService } from "../../src/modules/auth/service.js";

function fixture() {
  const lines: string[] = [];
  const app = Fastify({
    // 限定日志接口，避免 Fastify 泛型推断为 Pino 专用实例。
    // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
    loggerInstance: pino(createLoggerOptions("info"), {
      write(chunk: string) {
        lines.push(chunk);
      },
    }) as FastifyBaseLogger,
  });
  registerRequestDiagnostics(app);
  registerErrorHandling(app);
  return {
    app,
    records: () =>
      lines.flatMap((line) =>
        line
          .trim()
          .split("\n")
          .map((value) => JSON.parse(value) as Record<string, unknown>),
      ),
  };
}

describe("请求诊断", () => {
  it("记录真实状态、耗时和路由模板，不记录查询与正文", async () => {
    const { app, records } = fixture();
    app.post("/items/:id", async (_request, reply) =>
      reply.code(201).send({ ok: true }),
    );
    await app.inject({
      method: "POST",
      url: "/items/private-id?token=secret-query",
      payload: { message: "secret-body" },
    });
    const summaries = records().filter(
      (item) => item.event === "http.request.finished",
    );
    expect(summaries).toHaveLength(1);
    expect(summaries[0]).toMatchObject({
      statusCode: 201,
      route: "/items/:id",
      aborted: false,
    });
    expect(summaries[0]?.durationMs).toEqual(expect.any(Number));
    expect(records().find((item) => item.msg === "request completed")?.res).toEqual({
      statusCode: 201,
    });
    expect(JSON.stringify(records())).not.toContain("secret-query");
    expect(JSON.stringify(records())).not.toContain("secret-body");
    await app.close();
  });

  it.each([false, true])(
    "流式响应能区分成功与 HTTP 200 内的失败：%s",
    async (failure) => {
      const { app, records } = fixture();
      registerAiRoutes(
        app,
        {} as AuthService,
        {
          resolveGuestUser: () => Promise.resolve("test-user"),
          stream: () =>
            Promise.resolve({
              requestId: "ai-test",
              events: (async function* () {
                await Promise.resolve();
                yield {
                  type: "metadata",
                  model: "test-model",
                  providerRequestId: "provider-test",
                };
                yield { type: "delta", text: "secret-output" };
                if (failure) throw new Error("secret-provider-error");
                yield {
                  type: "usage",
                  usage: { inputTokens: 2, outputTokens: 3, totalTokens: 5 },
                };
                yield { type: "done" };
              })(),
            }),
        } as unknown as AiService,
        { guestAccessEnabled: true },
      );
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/stream",
        headers: { "x-lingotrip-guest-id": "test-device" },
        payload: {
          task: "chat",
          messages: [{ role: "user", content: "secret-input" }],
        },
      });
      expect(response.statusCode).toBe(200);
      const summary = records().find((item) => item.event === "ai.stream.finished");
      expect(summary).toMatchObject({
        outcome: failure ? "error" : "completed",
        aiRequestId: "ai-test",
        deltaCount: 1,
        outputCharacters: 13,
      });
      expect(summary?.firstDeltaMs).toEqual(expect.any(Number));
      if (failure) expect(summary?.errorCode).toBe("AI_STREAM_FAILED");
      else
        expect(summary?.usage).toEqual({
          inputTokens: 2,
          outputTokens: 3,
          totalTokens: 5,
        });
      expect(
        records().filter((item) => item.event === "http.request.finished"),
      ).toHaveLength(1);
      for (const secret of ["secret-output", "secret-input", "secret-provider-error"])
        expect(JSON.stringify(records())).not.toContain(secret);
      await app.close();
    },
  );
});
