import type { FastifyInstance } from "fastify";

export function registerRequestDiagnostics(app: FastifyInstance): void {
  app.addHook("onRequest", (request, reply, done) => {
    const started = performance.now();
    let recorded = false;
    const record = (aborted: boolean): void => {
      if (recorded) return;
      recorded = true;
      const durationMs = Math.round((performance.now() - started) * 100) / 100;
      const fields = {
        event: "http.request.finished",
        method: request.method,
        // 未匹配的路径可能包含用户输入，只记录固定标签。
        route: request.routeOptions.url ?? "unmatched",
        statusCode: reply.raw.headersSent ? reply.raw.statusCode : null,
        durationMs,
        aborted,
        slow: durationMs >= 1000,
      };
      if (aborted || durationMs >= 1000 || reply.raw.statusCode >= 500) {
        request.log.warn(fields, "请求诊断");
      } else {
        request.log.info(fields, "请求诊断");
      }
    };
    reply.raw.once("finish", () => record(false));
    reply.raw.once("close", () => record(!reply.raw.writableFinished));
    done();
  });
}
