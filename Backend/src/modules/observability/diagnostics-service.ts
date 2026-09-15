import { AppError } from "../../shared/errors.js";

export interface DiagnosticRecord {
  time: string;
  service: string;
  level: "info" | "warn" | "error";
  event: string;
  requestId?: string;
  jobId?: string;
  jobType?: string;
  errorName?: string;
  result?: string;
  aiRequestId?: string;
  operationId?: string;
  providerRequestId?: string;
  errorCode?: string;
  route?: string;
  task?: string;
  model?: string;
  outcome?: string;
  statusCode?: number;
  durationMs?: number;
  firstDeltaMs?: number;
  outputCharacters?: number;
  deltaCount?: number;
  aborted?: boolean;
  slow?: boolean;
  usage?: Record<string, number>;
}
export interface DiagnosticQuery {
  hours: number;
  service: string;
  level: string;
  requestId: string;
  errorCode: string;
  offset: number;
  limit: number;
}

// 仅输出结构化白名单，不将原始 MESSAGE、异常正文、请求正文或头部送到浏览器。
export function parseJournal(line: string): DiagnosticRecord | null {
  try {
    const journal = JSON.parse(line) as Record<string, unknown>;
    if (typeof journal.MESSAGE !== "string") return null;
    const entry = JSON.parse(journal.MESSAGE) as Record<string, unknown>;
    if (
      typeof entry.res === "object" &&
      entry.res !== null &&
      entry.statusCode === undefined
    ) {
      entry.statusCode = (entry.res as Record<string, unknown>).statusCode;
    }
    if (typeof entry.err === "object" && entry.err !== null) {
      const error = entry.err as Record<string, unknown>;
      entry.errorCode ??= error.code;
      entry.errorName ??= error.type;
    }
    const service =
      journal._SYSTEMD_UNIT === "lingotrip-api.service"
        ? "api"
        : journal._SYSTEMD_UNIT === "lingotrip-worker.service"
          ? "worker"
          : null;
    if (service === null || typeof entry.level !== "number") return null;
    const micros = Number(journal.__REALTIME_TIMESTAMP);
    if (!Number.isFinite(micros) || micros <= 0) return null;
    const knownMessages: Record<string, string> = {
      "incoming request": "http.request.started",
      "request completed": "http.request.completed",
      "Job execution failed": "job.failed",
      "Job completed": "job.completed",
      "Job lease was lost before completion": "job.lease_lost",
      "Operational request failure": "http.operational_failure",
      "Unhandled request failure": "http.unhandled_failure",
    };
    const record: DiagnosticRecord = {
      time: new Date(micros / 1000).toISOString(),
      service,
      level: entry.level >= 50 ? "error" : entry.level >= 40 ? "warn" : "info",
      event:
        typeof entry.event === "string" && /^[a-zA-Z0-9._-]{1,100}$/.test(entry.event)
          ? entry.event
          : typeof entry.msg === "string"
            ? (knownMessages[entry.msg] ?? "service.log")
            : "service.log",
    };
    for (const key of [
      "jobId",
      "jobType",
      "errorName",
      "result",
      "requestId",
      "aiRequestId",
      "operationId",
      "providerRequestId",
      "errorCode",
      "task",
      "model",
      "outcome",
    ] as const) {
      const value = entry[key];
      if (typeof value === "string" && /^[a-zA-Z0-9._:/-]{1,200}$/.test(value))
        record[key] = value;
    }
    if (
      typeof entry.route === "string" &&
      /^\/[a-zA-Z0-9_:/.*-]{0,200}$/.test(entry.route)
    )
      record.route = entry.route;
    for (const key of [
      "statusCode",
      "durationMs",
      "firstDeltaMs",
      "outputCharacters",
      "deltaCount",
    ] as const) {
      const value = entry[key];
      if (typeof value === "number" && Number.isFinite(value) && value >= 0)
        record[key] = value;
    }
    for (const key of ["aborted", "slow"] as const)
      if (typeof entry[key] === "boolean") record[key] = entry[key];
    if (typeof entry.usage === "object" && entry.usage !== null) {
      const usage = entry.usage as Record<string, unknown>;
      record.usage = {};
      for (const key of [
        "inputTokens",
        "outputTokens",
        "totalTokens",
        "cacheHitTokens",
        "cacheMissTokens",
      ]) {
        const value = usage[key];
        if (typeof value === "number" && Number.isFinite(value) && value >= 0)
          record.usage[key] = value;
      }
    }
    return record;
  } catch {
    return null;
  }
}

function errorCodeFor(row: DiagnosticRecord): string | undefined {
  return (
    row.errorCode ??
    ((row.statusCode ?? 0) >= 400
      ? `HTTP_${String(row.statusCode)}`
      : row.level === "error" || row.outcome === "error" || row.outcome === "incomplete"
        ? "UNCLASSIFIED"
        : undefined)
  );
}

export class DiagnosticsService {
  private readonly cache = new Map<
    number,
    {
      expires: number;
      value: Promise<{
        records: DiagnosticRecord[];
        truncated: boolean;
        generatedAt: string;
      }>;
    }
  >();
  constructor(
    private readonly read: (hours: number) => Promise<string>,
    private readonly maxRecords = 20_000,
  ) {}

  async report(query: DiagnosticQuery) {
    let cached = this.cache.get(query.hours);
    if (cached === undefined || cached.expires < Date.now()) {
      const value = this.read(query.hours).then((text) => {
        const lines = text.trim().split("\n").filter(Boolean);
        return {
          records: lines
            .slice(-this.maxRecords)
            .map(parseJournal)
            .filter((row): row is DiagnosticRecord => row !== null)
            .reverse(),
          truncated: lines.length > this.maxRecords,
          generatedAt: new Date().toISOString(),
        };
      });
      cached = { expires: Date.now() + 10_000, value };
      this.cache.set(query.hours, cached);
    }
    let snapshot;
    try {
      snapshot = await cached.value;
    } catch {
      this.cache.delete(query.hours);
      throw new AppError({
        code: "DIAGNOSTICS_UNAVAILABLE",
        message: "日志暂不可用，请检查服务日志权限或稍后重试。",
        statusCode: 503,
      });
    }
    const records = snapshot.records.filter(
      (row) =>
        (query.service === "all" || row.service === query.service) &&
        (query.level === "all" || row.level === query.level) &&
        (!query.requestId ||
          [
            row.requestId,
            row.aiRequestId,
            row.operationId,
            row.providerRequestId,
            row.jobId,
          ].includes(query.requestId)) &&
        (!query.errorCode || errorCodeFor(row) === query.errorCode),
    );
    const failures = new Map<string, DiagnosticRecord>();
    const serverFailures = new Set<string>();
    records.forEach((row, index) => {
      if (
        row.level === "error" ||
        (row.statusCode ?? 0) >= 400 ||
        row.outcome === "error" ||
        row.outcome === "incomplete"
      ) {
        const key = row.requestId ?? row.aiRequestId ?? `${row.time}:${String(index)}`;
        if ((row.statusCode ?? 0) >= 500 || row.level === "error")
          serverFailures.add(key);
        const previous = failures.get(key);
        if (
          previous === undefined ||
          (previous.errorCode === undefined && row.errorCode !== undefined)
        )
          failures.set(key, row);
      }
    });
    const groups = new Map<string, { code: string; count: number; latest: string }>();
    for (const row of failures.values()) {
      const code = errorCodeFor(row) ?? "UNCLASSIFIED";
      const previous = groups.get(code);
      groups.set(code, {
        code,
        count: (previous?.count ?? 0) + 1,
        latest:
          previous === undefined || row.time > previous.latest
            ? row.time
            : previous.latest,
      });
    }
    return {
      generatedAt: snapshot.generatedAt,
      truncated: snapshot.truncated,
      scanned: snapshot.records.length,
      oldest: snapshot.records.at(-1)?.time ?? null,
      total: records.length,
      offset: query.offset,
      limit: query.limit,
      summary: {
        failures: failures.size,
        serverErrors: serverFailures.size,
        streamErrors: records.filter(
          (row) =>
            row.event === "ai.stream.finished" &&
            ["error", "incomplete"].includes(row.outcome ?? ""),
        ).length,
        disconnected: records.filter(
          (row) => row.event === "ai.stream.finished" && row.outcome === "disconnected",
        ).length,
      },
      errors: [...groups.values()].sort((a, b) => b.count - a.count),
      records: records.slice(query.offset, query.offset + query.limit),
    };
  }
}
