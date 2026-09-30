import type { ContentCommand, ContentCommandResult, ContentRecord } from "./types.js";

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** 仅剥离已通过入口校验的废弃字段，保留普通聊天正文和全部现行字段。 */
export function stripLegacyContentCommand(command: ContentCommand): ContentCommand {
  if (command.operation !== "upsert" || !object(command.payload)) return command;
  const payload = { ...command.payload };
  if (command.resourceType === "conversation") {
    delete payload.quizOptOut;
    delete payload.turnsSinceQuiz;
  } else if (command.resourceType === "message") {
    delete payload.quizJson;
    delete payload.quizChosenIndex;
  } else {
    return command;
  }
  return { ...command, payload };
}

/** 临时保留旧版普通会话的必需字段，固定关闭小测；不修改存储或业务状态。 */
export function withLegacyContentRecord<T extends ContentRecord>(record: T): T {
  if (record.resourceType !== "conversation" || !object(record.payload)) return record;
  return {
    ...record,
    payload: { ...record.payload, quizOptOut: true, turnsSinceQuiz: 0 },
  };
}

/** 增量同步及冲突详情中的记录是 JSON，兼容只作用于普通会话记录。 */
export function withLegacyContentChange(value: unknown): unknown {
  if (
    !object(value) ||
    value.resourceType !== "conversation" ||
    !object(value.payload)
  ) {
    return value;
  }
  return {
    ...value,
    payload: { ...value.payload, quizOptOut: true, turnsSinceQuiz: 0 },
  };
}

export function withLegacyContentResult(
  result: ContentCommandResult,
): ContentCommandResult {
  if (result.status === "applied") {
    return { ...result, record: withLegacyContentRecord(result.record) };
  }
  const details = result.error.details;
  if (!object(details) || !("current" in details)) return result;
  return {
    ...result,
    error: {
      ...result.error,
      details: { ...details, current: withLegacyContentChange(details.current) },
    },
  };
}
