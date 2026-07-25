import type { SealedProviderCredential } from "../auth/repository.js";

export type AccountDeletionMode = "grace_period" | "immediate";

export type AppleDeletionCredential = Readonly<{
  clientId: string | null;
  credential: SealedProviderCredential;
}>;

export type AccountDeletionReceipt = Readonly<{
  cancellationToken: string | null;
  purgeAt: Date;
  requestId: string;
}>;

export type AccountExport = Readonly<{
  account: unknown;
  aiRequests: readonly unknown[];
  auditEvents: readonly unknown[];
  billing: Readonly<{
    entitlements: readonly unknown[];
    subscriptions: readonly unknown[];
    transactions: readonly unknown[];
  }>;
  economy: Readonly<{
    coinLedger: readonly unknown[];
    tickets: readonly unknown[];
  }>;
  generatedAt: string;
  identities: readonly unknown[];
  privacy: Readonly<{
    deletionRequests: readonly unknown[];
  }>;
  profile: unknown;
  schemaVersion: 1;
  securityEvents: readonly unknown[];
  sessions: readonly unknown[];
  syncChanges: readonly unknown[];
  travel: Readonly<{
    records: readonly unknown[];
    unlockedRegions: readonly unknown[];
  }>;
}>;

export type DeletionWork = Readonly<{
  appleCredentials: readonly AppleDeletionCredential[];
  requestId: string;
  userId: string;
}>;
