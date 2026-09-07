import type { SealedProviderCredential } from "../auth/types.js";

export type AccountDeletionMode = "grace_period" | "immediate";

export type AppleDeletionCredential = Readonly<{
  clientId: string | null;
  credential: SealedProviderCredential;
}>;

export type LinkedIdentity = Readonly<{
  createdAt: Date;
  displayName: string | null;
  email: string | null;
  emailVerified: boolean;
  id: string;
  provider: "email" | "apple" | "google";
  updatedAt: Date;
}>;

export type IdentityUnlinkCandidate = Readonly<{
  credential?: AppleDeletionCredential["credential"];
  clientId?: string | null;
  id: string;
  provider: LinkedIdentity["provider"];
}>;

export type IdentityUnlinkPreparation =
  | Readonly<{ status: "last_identity" | "not_found" | "reauthentication_required" }>
  | Readonly<{ candidate: IdentityUnlinkCandidate; status: "ready" }>;

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
  contentRecords: readonly unknown[];
  economy: Readonly<{
    coinLedger: readonly unknown[];
    tickets: readonly unknown[];
  }>;
  generatedAt: string;
  identities: readonly unknown[];
  mediaAssets: readonly unknown[];
  privacy: Readonly<{
    deletionRequests: readonly unknown[];
  }>;
  profile: unknown;
  schemaVersion: 3;
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
  mediaObjectKeys: readonly string[];
  requestId: string;
  userId: string;
}>;
