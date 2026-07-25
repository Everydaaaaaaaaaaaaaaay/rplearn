import type { UserSnapshot } from "../domain/types.js";

export type SyncChange = Readonly<{
  commandId: string;
  eventId: string;
  eventType: string;
  occurredAt: string;
  payload: unknown;
  sequence: string;
}>;

export type SyncPage = Readonly<{
  changes: readonly SyncChange[];
  hasMore: boolean;
  nextCursor: string;
}>;

export type SyncSnapshot = Readonly<{
  cursor: string;
  state: UserSnapshot;
}>;
