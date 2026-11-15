import type { TransactionSql } from "postgres";
import type { ActivityWorld, PlaceEncounterStory } from "./activity-world-content.js";
import type { PublicNpc } from "./types.js";

export type OutingLocationReader = Readonly<{
  lock: (
    sql: TransactionSql,
    userId: string,
  ) => Promise<{ cityId: string; starterCityId: string }>;
}>;
export type OutingStart = Readonly<{
  runId: string;
  releaseId: string;
  placeId: string;
}>;
export interface OutingSnapshot {
  runId: string;
  releaseId: string;
  cityId: string;
  placeId: string;
  placeTitleZh: string;
  createdAt: string;
  status: "reserved" | "opening_presented" | "in_progress" | "completed" | "abandoned";
  revision: number;
  mode: "first_meeting" | "reunion" | "solitude";
  reason: "encounter" | "quiet_visit" | "empty_pool";
  npc: PublicNpc | null;
  story: Pick<PlaceEncounterStory, "id" | "titleZh" | "nodes" | "reunion"> | null;
  photo: ActivityWorld["media"][number];
  solitude: ActivityWorld["places"][number]["solitude"][number];
  nodeId: string;
  beatIndex: number;
  choices: string[];
}
export type OutingOperation = Readonly<
  {
    operationId: string;
    expectedRevision: number;
  } & (
    | { type: "read"; beatIndex: number }
    | { type: "presented" }
    | { type: "choice"; choiceId: string }
    | { type: "complete" }
    | { type: "abandon" }
  )
>;

export type OutingService = Readonly<{
  catalog: (
    userId: string,
    releaseId?: string,
  ) => Promise<{
    releaseId: string;
    cityId: string;
    places: {
      id: string;
      titleZh: string;
      category: string;
      photo: ActivityWorld["media"][number];
    }[];
  } | null>;
  start: (userId: string, input: OutingStart) => Promise<OutingSnapshot>;
  find: (userId: string, runId: string) => Promise<OutingSnapshot>;
  active: (userId: string) => Promise<OutingSnapshot | null>;
  history: (
    userId: string,
    before?: string,
  ) => Promise<{ outings: OutingSnapshot[]; nextCursor: string | null }>;
  apply: (
    userId: string,
    runId: string,
    operation: OutingOperation,
  ) => Promise<OutingSnapshot>;
}>;
