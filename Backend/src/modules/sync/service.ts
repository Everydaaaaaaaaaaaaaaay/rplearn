import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { DomainService } from "../domain/service.js";
import type { DifficultyLevel, TicketType } from "../domain/types.js";
import type { SyncCursorCodec } from "./cursor.js";
import { SyncRepository } from "./repository.js";
import type { SyncPage, SyncSnapshot } from "./types.js";

export type SyncCommand =
  | Readonly<{
      commandId: string;
      payload: Readonly<{
        countryCode?: string;
        type: TicketType;
      }>;
      type: "economy.purchaseTicket";
    }>
  | Readonly<{
      commandId: string;
      payload: Readonly<{
        difficulty?: DifficultyLevel;
        displayName?: string;
        expectedVersion: number;
        hasCompletedOnboarding?: boolean;
        quizGloballyEnabled?: boolean;
      }>;
      type: "profile.update";
    }>
  | Readonly<{
      commandId: string;
      payload: Readonly<{
        targetRegionId: string;
        ticketId?: string;
      }>;
      type: "travel.go";
    }>;

export type SyncCommandResult =
  | Readonly<{
      commandId: string;
      result: unknown;
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

export type SyncService = Readonly<{
  executeCommands: (
    userId: string,
    commands: readonly SyncCommand[],
  ) => Promise<readonly SyncCommandResult[]>;
  getChanges: (
    userId: string,
    cursor: string | undefined,
    limit: number,
  ) => Promise<SyncPage>;
  getSnapshot: (userId: string) => Promise<SyncSnapshot>;
}>;

export function createSyncService(
  database: DatabaseResource,
  domainService: DomainService,
  cursorCodec: SyncCursorCodec,
): SyncService {
  const repository = new SyncRepository(database);

  return {
    executeCommands: async (userId, commands) => {
      const results: SyncCommandResult[] = [];
      for (const command of commands) {
        try {
          let result: unknown;
          switch (command.type) {
            case "economy.purchaseTicket":
              result = await domainService.purchaseTicket(
                userId,
                command.commandId,
                command.payload.type,
                command.payload.countryCode,
              );
              break;
            case "profile.update":
              result = await domainService.updateProfile(
                userId,
                command.commandId,
                command.payload,
              );
              break;
            case "travel.go":
              result = await domainService.travel(
                userId,
                command.commandId,
                command.payload.targetRegionId,
                command.payload.ticketId,
              );
              break;
          }
          results.push({
            commandId: command.commandId,
            result,
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
    getChanges: async (userId, cursor, limit) => {
      const sequence = cursor === undefined ? "0" : cursorCodec.decode(cursor, userId);
      const page = await repository.changesAfter(userId, sequence, limit);
      const nextSequence = page.changes.at(-1)?.sequence ?? sequence;
      return {
        changes: page.changes,
        hasMore: page.hasMore,
        nextCursor: cursorCodec.encode(userId, nextSequence),
      };
    },
    getSnapshot: async (userId) => {
      // Reading the head first may replay a later idempotent event over the
      // snapshot, but it can never make a client skip an event it still needs.
      const sequence = await repository.currentSequence(userId);
      const state = await domainService.getSnapshot(userId);
      return {
        cursor: cursorCodec.encode(userId, sequence),
        state,
      };
    },
  };
}
