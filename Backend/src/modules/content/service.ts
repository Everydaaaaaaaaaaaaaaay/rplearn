import type { TransactionSql } from "postgres";
import { createHash } from "node:crypto";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { SyncCursorCodec } from "../sync/cursor.js";
import type { ContentCursorCodec } from "./cursor.js";
import { ContentRepository } from "./repository.js";
import type { ContentCommand, ContentCommandResult, ContentPage } from "./types.js";

export type ContentService = Readonly<{
  executeCommands: (
    userId: string,
    commands: readonly ContentCommand[],
  ) => Promise<readonly ContentCommandResult[]>;
  getPage: (
    userId: string,
    cursor: string | undefined,
    limit: number,
  ) => Promise<ContentPage>;
}>;

export function createContentService(
  database: DatabaseResource,
  contentCursor: ContentCursorCodec,
  syncCursor: SyncCursorCodec,
): ContentService {
  const repository = new ContentRepository(database);
  return {
    executeCommands: async (userId, commands) => {
      const results: ContentCommandResult[] = [];
      for (const command of commands) {
        try {
          const requestHash = createHash("sha256")
            .update(JSON.stringify(command))
            .digest("hex");
          results.push({
            commandId: command.commandId,
            record: await repository.execute(userId, command, requestHash),
            status: "applied",
          });
        } catch (error) {
          if (!(error instanceof AppError) || !error.expose) {
            throw error;
          }
          results.push({
            commandId: command.commandId,
            error: {
              code: error.code,
              ...(error.details === undefined ? {} : { details: error.details }),
              message: error.message,
            },
            status: "rejected",
          });
        }
      }
      return results;
    },
    getPage: async (userId, cursor, limit) => {
      const decoded =
        cursor === undefined ? undefined : contentCursor.decode(cursor, userId);
      const snapshotSequence =
        decoded?.snapshotSequence ?? (await repository.currentSequence(userId));
      const rows = await repository.page(
        userId,
        decoded === undefined
          ? undefined
          : {
              resourceId: decoded.lastId,
              resourceType: decoded.lastType,
            },
        limit + 1,
      );
      const hasMore = rows.length > limit;
      const records = rows.slice(0, limit);
      const last = records.at(-1);
      return {
        hasMore,
        nextCursor:
          hasMore && last !== undefined
            ? contentCursor.encode({
                lastId: last.resourceId,
                lastType: last.resourceType,
                snapshotSequence,
                userId,
              })
            : null,
        records,
        syncCursor: syncCursor.encode(userId, snapshotSequence),
      };
    },
  };
}

/** 供组装层在同一业务事务内校验资源归属。 */
export function createContentReadService(database: DatabaseResource) {
  const repository = new ContentRepository(database);
  return {
    character: (sql: TransactionSql, userId: string, id: string) =>
      repository.readRecord(sql, userId, "character", id),
    conversation: (sql: TransactionSql, userId: string, id: string) =>
      repository.readRecord(sql, userId, "conversation", id),
  };
}
