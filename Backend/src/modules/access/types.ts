import type { CreditSnapshot } from "./credit-service.js";
import type { ActorAccessPolicy } from "../../infrastructure/access-policy.js";
export type UsageKind = "chat" | "advanced" | "auxiliary" | "voice";
export type AccessSnapshot = Readonly<{
  credits?: CreditSnapshot;
  policy: ActorAccessPolicy;
  resetsAt: string | null;
  balances: Record<
    UsageKind,
    { limit: number; used: number; reserved: number; remaining: number }
  >;
}>;
export type UsageReservation = Readonly<{
  operationId: string;
  amount: number;
  expiresAt: string;
  replay: boolean;
  result: unknown;
}>;
