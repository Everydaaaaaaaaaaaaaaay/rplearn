import Fastify from "fastify";
import { describe, expect, it, vi } from "vitest";
import { createAdminAuthenticator } from "../../../src/modules/admin/http.js";
import { registerErrorHandling } from "../../../src/app/error-handler.js";
import {
  DiagnosticsService,
  parseJournal,
  type DiagnosticQuery,
} from "../../../src/modules/observability/diagnostics-service.js";
import { registerDiagnosticsRoutes } from "../../../src/modules/observability/diagnostics-routes.js";

const query: DiagnosticQuery = {
  hours: 24,
  service: "all",
  level: "all",
  requestId: "",
  errorCode: "",
  offset: 0,
  limit: 50,
};
const line = (entry: object, unit = "lingotrip-api.service") =>
  JSON.stringify({
    _SYSTEMD_UNIT: unit,
    __REALTIME_TIMESTAMP: "1789458973691000",
    MESSAGE: JSON.stringify({ level: 30, ...entry }),
  });

describe("管理后台诊断", () => {
  it("只保留诊断白名单，丢弃凭证、正文、错误原文和其他服务", () => {
    const result = parseJournal(
      line({
        event: "ai.stream.finished",
        requestId: "trace-1",
        password: "secret",
        msg: "private text",
        err: { message: "private error" },
        usage: { inputTokens: 4, prompt: "private input" },
      }),
    );
    expect(result).toMatchObject({
      event: "ai.stream.finished",
      requestId: "trace-1",
      usage: { inputTokens: 4 },
    });
    expect(JSON.stringify(result)).not.toMatch(/secret|private/);
    expect(parseJournal(line({}, "ssh.service"))).toBeNull();
    expect(parseJournal("not json")).toBeNull();
  });
  it("合并请求报错，识别 200 内流式失败，支持关联查询和分页", async () => {
    const read = vi.fn().mockResolvedValue(
      [
        line({
          event: "http.request.error",
          requestId: "r1",
          errorCode: "UPSTREAM_FAILED",
          statusCode: 502,
          level: 50,
        }),
        line({ event: "http.request.finished", requestId: "r1", statusCode: 502 }),
        line({
          event: "ai.stream.finished",
          requestId: "r2",
          aiRequestId: "ai2",
          outcome: "error",
          errorCode: "AI_STREAM_FAILED",
          level: 40,
        }),
        line({
          event: "ai.stream.finished",
          requestId: "r3",
          outcome: "disconnected",
          level: 40,
        }),
        line(
          {
            msg: "Job execution failed",
            jobId: "j1",
            errorName: "TimeoutError",
            level: 50,
          },
          "lingotrip-worker.service",
        ),
      ].join("\n"),
    );
    const service = new DiagnosticsService(read);
    const report = await service.report({ ...query, limit: 2 });
    expect(report.summary).toEqual({
      failures: 3,
      serverErrors: 2,
      streamErrors: 1,
      disconnected: 1,
    });
    expect(report.records).toHaveLength(2);
    expect(report.total).toBe(5);
    expect((await service.report({ ...query, requestId: "r1" })).total).toBe(2);
    expect((await service.report({ ...query, requestId: "ai2" })).total).toBe(1);
    expect(
      (await service.report({ ...query, requestId: "j1" })).records[0]?.event,
    ).toBe("job.failed");
    expect((await service.report({ ...query, service: "worker" })).total).toBe(1);
    expect(
      (await service.report({ ...query, errorCode: "AI_STREAM_FAILED" })).total,
    ).toBe(1);
    expect(read).toHaveBeenCalledTimes(1);
  });
  it("同一请求的流式警告不会掩盖先前服务端错误，兼容原始完成日志", async () => {
    const service = new DiagnosticsService(() =>
      Promise.resolve(
        [
          line({
            requestId: "r1",
            level: 50,
            errorCode: "UPSTREAM_FAILED",
            statusCode: 502,
          }),
          line({
            requestId: "r1",
            level: 40,
            event: "ai.stream.finished",
            outcome: "error",
            errorCode: "UPSTREAM_FAILED",
          }),
          line({ requestId: "r2", msg: "request completed", res: { statusCode: 401 } }),
        ].join("\n"),
      ),
    );
    expect((await service.report(query)).summary).toMatchObject({
      failures: 2,
      serverErrors: 1,
    });
    expect((await service.report({ ...query, errorCode: "HTTP_401" })).total).toBe(1);
  });
  it("超限明确标记，读取异常返回不可用而非空统计", async () => {
    const service = new DiagnosticsService(
      () => Promise.resolve([line({}), line({}), line({})].join("\n")),
      2,
    );
    expect(await service.report(query)).toMatchObject({ truncated: true, scanned: 2 });
    const failed = new DiagnosticsService(() =>
      Promise.reject(new Error("sensitive filesystem details")),
    );
    await expect(failed.report(query)).rejects.toMatchObject({
      code: "DIAGNOSTICS_UNAVAILABLE",
      statusCode: 503,
    });
  });
  it("必须通过管理鉴权，拒绝非法参数和不受限查询", async () => {
    const app = Fastify();
    registerErrorHandling(app);
    const read = vi.fn().mockResolvedValue("");
    registerDiagnosticsRoutes(
      app,
      createAdminAuthenticator([{ keyId: "test", token: "test-token" }]),
      new DiagnosticsService(read),
    );
    expect((await app.inject("/internal/admin/ai/diagnostics")).statusCode).toBe(401);
    expect(read).not.toHaveBeenCalled();
    const headers = { authorization: "Bearer test-token" };
    for (const suffix of [
      "hours=999",
      "service=ssh",
      "limit=100000",
      "requestId=%3Bpwd",
      "offset=-1",
    ]) {
      expect(
        (await app.inject({ url: "/internal/admin/ai/diagnostics?" + suffix, headers }))
          .statusCode,
      ).toBe(400);
    }
    const response = await app.inject({
      url: "/internal/admin/ai/diagnostics",
      headers,
    });
    expect(response.statusCode).toBe(200);
    expect(response.headers["cache-control"]).toBe("no-store");
    await app.close();
  });
});
