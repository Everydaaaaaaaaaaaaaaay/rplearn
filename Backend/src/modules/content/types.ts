import type { TransactionSql } from "postgres";
export type ContentResourceType =
  "character" | "conversation" | "favorite" | "memory" | "message" | "story_progress";

export type ContentRecord = Readonly<{
  createdAt: string;
  deletedAt: string | null;
  parentId: string | null;
  payload: unknown;
  resourceId: string;
  resourceType: ContentResourceType;
  updatedAt: string;
  version: number;
}>;

export type ContentUpsertCommand = Readonly<{
  commandId: string;
  expectedVersion: number;
  operation: "upsert";
  parentId: string | null;
  payload: unknown;
  resourceId: string;
  resourceType: ContentResourceType;
}>;

export type ContentDeleteCommand = Readonly<{
  commandId: string;
  expectedVersion: number;
  operation: "delete";
  resourceId: string;
  resourceType: ContentResourceType;
}>;

export type ContentCommand = ContentUpsertCommand | ContentDeleteCommand;

export type ContentCommandResult =
  | Readonly<{
      commandId: string;
      record: ContentRecord;
      status: "applied";
    }>
  | Readonly<{
      commandId: string;
      error: Readonly<{
        code: string;
        details?: unknown;
        message: string;
      }>;
      status: "rejected";
    }>;

export type ContentPage = Readonly<{
  hasMore: boolean;
  nextCursor: string | null;
  records: readonly ContentRecord[];
  syncCursor: string;
}>;

/** 保存事务内的创建事件；失败随消息一起回滚。 */
export type ContentCommitObserver = (
  sql: TransactionSql,
  userId: string,
  record: ContentRecord,
) => Promise<void>;
