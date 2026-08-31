import type { PreparedJob } from "../jobs/types.js";
import type { DeviceDescriptor, RequestMetadata } from "./types.js";

export type EmailAccount = Readonly<{
  email: string;
  emailVerifiedAt: Date | null;
  passwordHash: string;
  status: "active" | "locked" | "pending_deletion";
  tokenVersion: number;
  userId: string;
}>;

export type FederatedAccount = Readonly<{
  identityId: string;
  status: EmailAccount["status"];
  tokenVersion: number;
  userId: string;
}>;

export type ActionTokenParameters = Readonly<{
  expiresAt: Date;
  id: string;
  tokenHash: string;
}>;

export type CreateEmailAccountParameters = Readonly<{
  actionToken: ActionTokenParameters;
  email: string;
  identityId: string;
  notificationJob: PreparedJob;
  passwordHash: string;
  userId: string;
}>;

export type CreateSessionParameters = Readonly<{
  device: DeviceDescriptor;
  familyId: string;
  metadata: RequestMetadata;
  refreshToken: Readonly<{
    expiresAt: Date;
    hash: string;
    id: string;
  }>;
  sessionId: string;
  userId: string;
}>;

export type RotateParameters = Readonly<{
  currentTokenHash: string;
  nextToken: Readonly<{
    expiresAt: Date;
    hash: string;
    id: string;
  }>;
  now: Date;
}>;

export type RotationResult =
  | Readonly<{ status: "invalid" }>
  | Readonly<{ status: "reuse_detected" }>
  | Readonly<{
      sessionId: string;
      status: "rotated";
      tokenVersion: number;
      userId: string;
    }>;
