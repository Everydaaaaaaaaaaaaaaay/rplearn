import type {
  EntitlementStatus,
  SubscriptionTier,
  VerifiedRenewalInfo,
  VerifiedStoreTransaction,
} from "./types.js";

export type PlanRow = Readonly<{
  feature_flags_text: string;
  id: string;
  rank: number;
  tier: SubscriptionTier;
}>;

export type GrantRow = Readonly<{
  entitlement_key: string;
  provider: "apple" | "google_play" | "stripe" | "manual";
  status: EntitlementStatus;
  valid_until: string | null;
}>;

export type AppliedState = Readonly<{
  changed: boolean;
  planId: string;
  status: EntitlementStatus;
  tier: SubscriptionTier;
  validUntil: Date | null;
}>;

export function parseFeatureFlags(
  value: string,
): Readonly<Record<string, boolean | number | string>> {
  return JSON.parse(value) as Readonly<Record<string, boolean | number | string>>;
}

export function effectiveUntil(
  transaction: VerifiedStoreTransaction,
  renewal: VerifiedRenewalInfo | undefined,
  status: EntitlementStatus,
): Date | null {
  if (status === "grace" && renewal?.gracePeriodExpiresAt !== undefined) {
    return renewal.gracePeriodExpiresAt;
  }
  return transaction.expiresAt ?? null;
}
