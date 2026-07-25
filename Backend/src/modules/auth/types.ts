export type AuthActionType = "email_verification" | "password_reset";

export type SessionPlatform = "ios" | "android" | "web" | "macos" | "unknown";

export type DeviceDescriptor = Readonly<{
  appVersion?: string;
  deviceId: string;
  deviceName?: string;
  platform: SessionPlatform;
}>;

export type RequestMetadata = Readonly<{
  ipHash?: string;
  userAgentHash?: string;
}>;

export type AccessIdentity = Readonly<{
  sessionId: string;
  tokenVersion: number;
  userId: string;
}>;

export type AuthTokenPair = Readonly<{
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  refreshTokenExpiresAt: Date;
  sessionId: string;
  tokenType: "Bearer";
  userId: string;
}>;

export type SessionSummary = Readonly<{
  appVersion: string | null;
  createdAt: Date;
  current: boolean;
  deviceId: string;
  deviceName: string | null;
  id: string;
  lastSeenAt: Date;
  platform: SessionPlatform;
}>;
