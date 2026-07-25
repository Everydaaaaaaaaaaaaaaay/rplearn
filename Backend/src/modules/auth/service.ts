import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { newEntityId } from "../../shared/id.js";
import { createJobPayloadCipher } from "../jobs/crypto.js";
import {
  AUTH_EMAIL_VERIFICATION_JOB,
  AUTH_PASSWORD_RESET_JOB,
  type AuthEmailJobType,
} from "../jobs/types.js";
import { createPasswordHasher, type PasswordHasher } from "./password.js";
import {
  AuthRepository,
  type EmailAccount,
  type RotationResult,
} from "./repository.js";
import { createAuthTokenService } from "./token-service.js";
import type {
  AccessIdentity,
  AuthActionType,
  AuthTokenPair,
  DeviceDescriptor,
  RequestMetadata,
  SessionSummary,
} from "./types.js";

export type AuthService = Readonly<{
  authenticate: (accessToken: string) => Promise<AccessIdentity>;
  createRequestMetadata: (
    ipAddress: string | undefined,
    userAgent: string | undefined,
  ) => RequestMetadata;
  forgotPassword: (email: string) => Promise<void>;
  listSessions: (identity: AccessIdentity) => Promise<readonly SessionSummary[]>;
  loginFederated: (
    userId: string,
    tokenVersion: number,
    device: DeviceDescriptor,
    metadata: RequestMetadata,
  ) => Promise<AuthTokenPair>;
  login: (
    email: string,
    password: string,
    device: DeviceDescriptor,
    metadata: RequestMetadata,
  ) => Promise<AuthTokenPair>;
  refresh: (refreshToken: string) => Promise<AuthTokenPair>;
  register: (email: string, password: string) => Promise<void>;
  requestEmailVerification: (email: string) => Promise<void>;
  resetPassword: (token: string, newPassword: string) => Promise<void>;
  revokeAllSessions: (identity: AccessIdentity) => Promise<void>;
  revokeSession: (identity: AccessIdentity, sessionId: string) => Promise<void>;
  verifyEmail: (token: string) => Promise<void>;
}>;

type AuthServiceDependencies = Readonly<{
  passwordHasher?: PasswordHasher;
}>;

function normalizeEmail(email: string): string {
  return email.trim().normalize("NFKC").toLowerCase();
}

function addSeconds(date: Date, seconds: number): Date {
  return new Date(date.getTime() + seconds * 1000);
}

function addDays(date: Date, days: number): Date {
  return addSeconds(date, days * 24 * 60 * 60);
}

function invalidCredentials(): AppError {
  return new AppError({
    code: "INVALID_CREDENTIALS",
    message: "The email or password is incorrect.",
    statusCode: 401,
  });
}

function invalidRefreshToken(result: RotationResult): AppError {
  if (result.status === "reuse_detected") {
    return new AppError({
      code: "REFRESH_TOKEN_REUSE_DETECTED",
      message: "This session has been revoked for security.",
      statusCode: 401,
    });
  }

  return new AppError({
    code: "INVALID_REFRESH_TOKEN",
    message: "The refresh token is invalid or expired.",
    statusCode: 401,
  });
}

export async function createAuthService(
  config: RuntimeConfig,
  database: DatabaseResource,
  dependencies: AuthServiceDependencies = {},
): Promise<AuthService> {
  const repository = new AuthRepository(database);
  const passwordHasher = dependencies.passwordHasher ?? createPasswordHasher();
  const jobPayloadCipher = createJobPayloadCipher(config);
  const tokenService = await createAuthTokenService(config);
  const dummyPasswordHash = await passwordHasher.hash(tokenService.createOpaqueToken());

  const createActionToken = (
    now: Date,
  ): Readonly<{
    expiresAt: Date;
    hash: string;
    id: string;
    raw: string;
  }> => {
    const raw = tokenService.createOpaqueToken();
    return {
      expiresAt: addSeconds(now, config.authActionTokenTtlSeconds),
      hash: tokenService.hashOpaqueValue(raw),
      id: newEntityId(),
      raw,
    };
  };

  const issueActionForEmail = async (
    rawEmail: string,
    type: AuthActionType,
  ): Promise<void> => {
    const email = normalizeEmail(rawEmail);
    const action = createActionToken(new Date());
    const jobType: AuthEmailJobType =
      type === "email_verification"
        ? AUTH_EMAIL_VERIFICATION_JOB
        : AUTH_PASSWORD_RESET_JOB;
    await repository.issueActionTokenForEmail(
      email,
      type,
      {
        expiresAt: action.expiresAt,
        id: action.id,
        tokenHash: action.hash,
      },
      jobPayloadCipher.prepare(
        jobType,
        {
          email,
          token: action.raw,
        },
        {
          uniqueKey: `auth-action:${action.id}`,
        },
      ),
    );
  };

  const issueTokenPair = async (
    identity: AccessIdentity,
    refreshToken: string,
    refreshTokenExpiresAt: Date,
  ): Promise<AuthTokenPair> => ({
    accessToken: await tokenService.createAccessToken(identity),
    accessTokenExpiresIn: tokenService.accessTokenTtlSeconds,
    refreshToken,
    refreshTokenExpiresAt,
    sessionId: identity.sessionId,
    tokenType: "Bearer",
    userId: identity.userId,
  });

  const ensureAccountCanLogin = (account: EmailAccount): void => {
    if (account.status !== "active") {
      throw new AppError({
        code: "ACCOUNT_UNAVAILABLE",
        message: "This account is not available.",
        statusCode: 403,
      });
    }
    if (account.emailVerifiedAt === null) {
      throw new AppError({
        code: "EMAIL_NOT_VERIFIED",
        message: "Verify the email before signing in.",
        statusCode: 403,
      });
    }
  };

  const createSessionForUser = async (
    userId: string,
    tokenVersion: number,
    device: DeviceDescriptor,
    metadata: RequestMetadata,
  ): Promise<AuthTokenPair> => {
    const now = new Date();
    const rawRefreshToken = tokenService.createOpaqueToken();
    const refreshTokenExpiresAt = addDays(now, config.authRefreshTokenTtlDays);
    const identity: AccessIdentity = {
      sessionId: newEntityId(),
      tokenVersion,
      userId,
    };

    await repository.createSession({
      device,
      familyId: newEntityId(),
      metadata,
      refreshToken: {
        expiresAt: refreshTokenExpiresAt,
        hash: tokenService.hashOpaqueValue(rawRefreshToken),
        id: newEntityId(),
      },
      sessionId: identity.sessionId,
      userId: identity.userId,
    });

    return issueTokenPair(identity, rawRefreshToken, refreshTokenExpiresAt);
  };

  return {
    authenticate: async (accessToken) => {
      let identity: AccessIdentity;
      try {
        identity = await tokenService.verifyAccessToken(accessToken);
      } catch {
        throw new AppError({
          code: "UNAUTHORIZED",
          message: "A valid access token is required.",
          statusCode: 401,
        });
      }

      const valid = await repository.assertAccessIdentity(
        identity.userId,
        identity.sessionId,
        identity.tokenVersion,
      );
      if (!valid) {
        throw new AppError({
          code: "SESSION_REVOKED",
          message: "The session is no longer active.",
          statusCode: 401,
        });
      }
      return identity;
    },

    createRequestMetadata: (ipAddress, userAgent) => ({
      ...(ipAddress === undefined
        ? {}
        : { ipHash: tokenService.hashOpaqueValue(`ip:${ipAddress}`) }),
      ...(userAgent === undefined
        ? {}
        : {
            userAgentHash: tokenService.hashOpaqueValue(`user-agent:${userAgent}`),
          }),
    }),

    forgotPassword: async (email) => {
      await issueActionForEmail(email, "password_reset");
    },

    listSessions: async (identity) =>
      repository.listSessions(identity.userId, identity.sessionId),

    loginFederated: createSessionForUser,

    login: async (rawEmail, password, device, metadata) => {
      const email = normalizeEmail(rawEmail);
      const account = await repository.findEmailAccount(email);

      if (account === undefined) {
        await passwordHasher.verify(dummyPasswordHash, password);
        throw invalidCredentials();
      }

      const passwordMatches = await passwordHasher.verify(
        account.passwordHash,
        password,
      );
      if (!passwordMatches) {
        throw invalidCredentials();
      }
      ensureAccountCanLogin(account);

      return createSessionForUser(
        account.userId,
        account.tokenVersion,
        device,
        metadata,
      );
    },

    refresh: async (refreshToken) => {
      const now = new Date();
      const nextRawToken = tokenService.createOpaqueToken();
      const nextExpiresAt = addDays(now, config.authRefreshTokenTtlDays);
      const result = await repository.rotateRefreshToken({
        currentTokenHash: tokenService.hashOpaqueValue(refreshToken),
        nextToken: {
          expiresAt: nextExpiresAt,
          hash: tokenService.hashOpaqueValue(nextRawToken),
          id: newEntityId(),
        },
        now,
      });

      if (result.status !== "rotated") {
        throw invalidRefreshToken(result);
      }

      return issueTokenPair(
        {
          sessionId: result.sessionId,
          tokenVersion: result.tokenVersion,
          userId: result.userId,
        },
        nextRawToken,
        nextExpiresAt,
      );
    },

    register: async (rawEmail, password) => {
      const email = normalizeEmail(rawEmail);
      const passwordHash = await passwordHasher.hash(password);
      const action = createActionToken(new Date());
      const userId = newEntityId();
      const result = await repository.createEmailAccount({
        actionToken: {
          expiresAt: action.expiresAt,
          id: action.id,
          tokenHash: action.hash,
        },
        email,
        identityId: newEntityId(),
        notificationJob: jobPayloadCipher.prepare(
          AUTH_EMAIL_VERIFICATION_JOB,
          {
            email,
            token: action.raw,
          },
          {
            uniqueKey: `auth-action:${action.id}`,
            userId,
          },
        ),
        passwordHash,
        userId,
      });

      if (result === "created") {
        return;
      }

      await issueActionForEmail(email, "email_verification");
    },

    requestEmailVerification: async (email) => {
      await issueActionForEmail(email, "email_verification");
    },

    resetPassword: async (token, newPassword) => {
      const passwordHash = await passwordHasher.hash(newPassword);
      const reset = await repository.resetPassword(
        tokenService.hashOpaqueValue(token),
        passwordHash,
        new Date(),
      );
      if (!reset) {
        throw new AppError({
          code: "INVALID_ACTION_TOKEN",
          message: "The password reset token is invalid or expired.",
          statusCode: 400,
        });
      }
    },

    revokeAllSessions: async (identity) => {
      await repository.revokeAllSessions(identity.userId, "user_logout_all");
    },

    revokeSession: async (identity, sessionId) => {
      const revoked = await repository.revokeSession(
        identity.userId,
        sessionId,
        "user_revoked",
      );
      if (!revoked) {
        throw new AppError({
          code: "SESSION_NOT_FOUND",
          message: "The session does not exist or is already revoked.",
          statusCode: 404,
        });
      }
    },

    verifyEmail: async (token) => {
      const verified = await repository.verifyEmail(
        tokenService.hashOpaqueValue(token),
        new Date(),
      );
      if (!verified) {
        throw new AppError({
          code: "INVALID_ACTION_TOKEN",
          message: "The verification token is invalid or expired.",
          statusCode: 400,
        });
      }
    },
  };
}
