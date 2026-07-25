import { createHash } from "node:crypto";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { DomainRepository } from "./repository.js";
import type {
  CommandIdentity,
  ProfilePatch,
  Ticket,
  TicketSource,
  TicketType,
  TravelResult,
  UserProfile,
  UserSnapshot,
} from "./types.js";

export type DomainService = Readonly<{
  claimStarterTicket: (userId: string, commandId: string) => Promise<Ticket>;
  completeStory: (
    userId: string,
    commandId: string,
    storyId: string,
  ) => Promise<Readonly<{ coins: number; rewardCoins: number; storyId: string }>>;
  getSnapshot: (userId: string) => Promise<UserSnapshot>;
  grantCoins: (
    userId: string,
    commandId: string,
    amount: number,
    reason: string,
  ) => Promise<Readonly<{ coins: number }>>;
  grantTicket: (
    userId: string,
    commandId: string,
    type: TicketType,
    source: TicketSource,
    countryCode?: string,
  ) => Promise<Ticket>;
  purchaseTicket: (
    userId: string,
    commandId: string,
    type: TicketType,
    countryCode?: string,
  ) => Promise<Readonly<{ coins: number; ticket: Ticket }>>;
  travel: (
    userId: string,
    commandId: string,
    targetRegionId: string,
    ticketId?: string,
  ) => Promise<TravelResult>;
  updateProfile: (
    userId: string,
    commandId: string,
    patch: ProfilePatch,
  ) => Promise<UserProfile>;
}>;

const STORY_REWARDS = new Map<string, number>([
  ["mainline_london", 100],
  ["mainline_london_2", 120],
  ["mainline_melbourne", 100],
  ["mainline_melbourne_2", 120],
  ["mainline_newyork", 100],
  ["mainline_newyork_2", 120],
]);

function command(commandId: string, route: string, payload: unknown): CommandIdentity {
  return {
    commandId,
    requestHash: createHash("sha256").update(JSON.stringify(payload)).digest("hex"),
    route,
  };
}

export function createDomainService(database: DatabaseResource): DomainService {
  const repository = new DomainRepository(database);
  return {
    claimStarterTicket: (userId, commandId) =>
      repository.claimStarterTicket(
        userId,
        command(commandId, "progression.claimStarterTicket", {
          reward: "starter-ticket-v1",
        }),
      ),
    completeStory: (userId, commandId, storyId) => {
      const rewardCoins = STORY_REWARDS.get(storyId);
      if (rewardCoins === undefined) {
        return Promise.reject(
          new AppError({
            code: "STORY_NOT_FOUND",
            message: "This story does not exist.",
            statusCode: 404,
          }),
        );
      }
      return repository.completeStory(
        userId,
        command(commandId, "progression.completeStory", { storyId }),
        storyId,
        rewardCoins,
      );
    },
    getSnapshot: (userId) => repository.snapshot(userId),
    grantCoins: (userId, commandId, amount, reason) =>
      repository.grantCoins(
        userId,
        command(commandId, "debug.grantCoins", { amount, reason }),
        amount,
        reason,
      ),
    grantTicket: (userId, commandId, type, source, countryCode) =>
      repository.grantTicket(
        userId,
        command(commandId, "debug.grantTicket", {
          countryCode: countryCode ?? null,
          source,
          type,
        }),
        type,
        source,
        countryCode,
      ),
    purchaseTicket: (userId, commandId, type, countryCode) =>
      repository.purchaseTicket(
        userId,
        command(commandId, "economy.purchaseTicket", {
          countryCode: countryCode ?? null,
          type,
        }),
        type,
        countryCode,
      ),
    travel: (userId, commandId, targetRegionId, ticketId) =>
      repository.travel(
        userId,
        command(commandId, "travel.go", {
          targetRegionId,
          ticketId: ticketId ?? null,
        }),
        targetRegionId,
        ticketId,
      ),
    updateProfile: (userId, commandId, patch) =>
      repository.updateProfile(
        userId,
        command(commandId, "profile.update", patch),
        patch,
      ),
  };
}
