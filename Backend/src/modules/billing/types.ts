export type StoreEnvironment = "production" | "sandbox" | "test";
export type SubscriptionTier = "free" | "plus" | "pro";
export type EntitlementStatus =
  "active" | "grace" | "billing_retry" | "expired" | "revoked";

export type VerifiedStoreTransaction = Readonly<{
  appAccountToken?: string;
  environment: StoreEnvironment;
  expiresAt?: Date;
  originalTransactionId: string;
  ownershipType?: string;
  productId: string;
  purchasedAt: Date;
  rawPayload: unknown;
  revokedAt?: Date;
  signedAt: Date;
  transactionId: string;
}>;

export type VerifiedRenewalInfo = Readonly<{
  appAccountToken?: string;
  autoRenewEnabled?: boolean;
  gracePeriodExpiresAt?: Date;
  originalTransactionId?: string;
  productId?: string;
  rawPayload: unknown;
  signedAt?: Date;
}>;

export type VerifiedStoreNotification = Readonly<{
  decodedPayload: unknown;
  environment: StoreEnvironment;
  eventId: string;
  eventType: string;
  payloadHash: string;
  providerStatus?: number;
  renewal?: VerifiedRenewalInfo;
  signedAt: Date;
  subtype?: string;
  transaction?: VerifiedStoreTransaction;
}>;

export type BillingProduct = Readonly<{
  featureFlags: Readonly<Record<string, boolean | number | string>>;
  planId: string;
  productId: string;
  provider: "apple" | "google_play" | "stripe";
  tier: SubscriptionTier;
}>;

export type EntitlementSnapshot = Readonly<{
  entitlements: readonly Readonly<{
    entitlementKey: string;
    provider: "apple" | "google_play" | "stripe" | "manual";
    status: EntitlementStatus;
    validUntil: string | null;
  }>[];
  featureFlags: Readonly<Record<string, boolean | number | string>>;
  tier: SubscriptionTier;
}>;
