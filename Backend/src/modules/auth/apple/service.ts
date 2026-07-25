import type { RuntimeConfig } from "../../../config/env.js";
import type { DatabaseResource } from "../../../db/client.js";
import type { RedisResource } from "../../../infrastructure/redis/client.js";
import { AppError } from "../../../shared/errors.js";
import { AuthRepository } from "../repository.js";
import type { AuthService } from "../service.js";
import type {
  AccessIdentity,
  AuthTokenPair,
  DeviceDescriptor,
  RequestMetadata,
} from "../types.js";
import {
  createAppleChallengeStore,
  type AppleChallenge,
  type AppleChallengeStore,
} from "./challenge-store.js";
import { createAppleCodeExchanger, type AppleCodeExchanger } from "./code-exchanger.js";
import { createCredentialSealer, type CredentialSealer } from "./credential-crypto.js";
import {
  createAppleIdentityVerifier,
  type AppleIdentity,
  type AppleIdentityVerifier,
} from "./identity-verifier.js";

export type AppleAuthentication = Readonly<{
  authorizationCode: string;
  challengeId: string;
  identityToken: string;
}>;

export type AppleAuthService = Readonly<{
  createChallenge: () => Promise<AppleChallenge>;
  link: (
    identity: AccessIdentity,
    authentication: AppleAuthentication,
  ) => Promise<void>;
  login: (
    authentication: AppleAuthentication,
    device: DeviceDescriptor,
    metadata: RequestMetadata,
  ) => Promise<AuthTokenPair>;
}>;

type AppleAuthDependencies = Readonly<{
  challengeStore?: AppleChallengeStore;
  codeExchanger?: AppleCodeExchanger;
  credentialSealer?: CredentialSealer;
  identityVerifier?: AppleIdentityVerifier;
}>;

function assertAccountAvailable(status: string): void {
  if (status !== "active") {
    throw new AppError({
      code: "ACCOUNT_UNAVAILABLE",
      message: "This account is not available.",
      statusCode: 403,
    });
  }
}

export async function createAppleAuthService(
  config: RuntimeConfig,
  database: DatabaseResource,
  redis: RedisResource,
  authService: AuthService,
  dependencies: AppleAuthDependencies = {},
): Promise<AppleAuthService> {
  if (!config.appleAuthEnabled && dependencies.identityVerifier === undefined) {
    throw new Error("Sign in with Apple is disabled");
  }

  const repository = new AuthRepository(database);
  const challengeStore =
    dependencies.challengeStore ?? createAppleChallengeStore(config, redis);
  const verifier = dependencies.identityVerifier ?? createAppleIdentityVerifier(config);
  const exchanger =
    dependencies.codeExchanger ?? (await createAppleCodeExchanger(config));
  const credentialSealer =
    dependencies.credentialSealer ?? createCredentialSealer(config);

  const verifyAuthentication = async (
    authentication: AppleAuthentication,
  ): Promise<Readonly<{ identity: AppleIdentity; refreshToken: string }>> => {
    const expectedNonce = await challengeStore.consume(authentication.challengeId);
    if (expectedNonce === null) {
      throw new AppError({
        code: "APPLE_CHALLENGE_INVALID",
        message: "The Apple authentication challenge is invalid or expired.",
        statusCode: 401,
      });
    }

    let identity: AppleIdentity;
    try {
      identity = await verifier.verify(authentication.identityToken, expectedNonce);
    } catch {
      throw new AppError({
        code: "APPLE_IDENTITY_INVALID",
        message: "The Apple identity token is invalid or expired.",
        statusCode: 401,
      });
    }

    const exchange = await exchanger.exchange(
      authentication.authorizationCode,
      identity.audience,
    );
    let exchangedIdentity: AppleIdentity;
    try {
      exchangedIdentity = await verifier.verify(exchange.idToken);
    } catch {
      throw new AppError({
        code: "APPLE_IDENTITY_INVALID",
        message: "Apple returned an invalid identity token.",
        statusCode: 401,
      });
    }
    if (
      exchangedIdentity.subject !== identity.subject ||
      exchangedIdentity.audience !== identity.audience
    ) {
      throw new AppError({
        code: "APPLE_IDENTITY_MISMATCH",
        message: "The Apple authorization does not match the identity token.",
        statusCode: 401,
      });
    }

    return {
      identity,
      refreshToken: exchange.refreshToken,
    };
  };

  return {
    createChallenge: challengeStore.create,

    link: async (accessIdentity, authentication) => {
      const verified = await verifyAuthentication(authentication);
      const linked = await repository.linkAppleIdentity({
        ...(verified.identity.email === undefined
          ? {}
          : { email: verified.identity.email }),
        emailVerified: verified.identity.emailVerified,
        subject: verified.identity.subject,
        userId: accessIdentity.userId,
      });
      if (linked.status === "conflict") {
        throw new AppError({
          code: "IDENTITY_ALREADY_LINKED",
          message: "This Apple identity belongs to another account.",
          statusCode: 409,
        });
      }
      await repository.saveProviderCredential(
        linked.identityId,
        verified.identity.audience,
        credentialSealer.seal(verified.refreshToken),
      );
    },

    login: async (authentication, device, metadata) => {
      const verified = await verifyAuthentication(authentication);
      const account = await repository.findOrCreateAppleAccount({
        ...(verified.identity.email === undefined
          ? {}
          : { email: verified.identity.email }),
        emailVerified: verified.identity.emailVerified,
        subject: verified.identity.subject,
      });
      assertAccountAvailable(account.status);
      await repository.saveProviderCredential(
        account.identityId,
        verified.identity.audience,
        credentialSealer.seal(verified.refreshToken),
      );
      return authService.loginFederated(
        account.userId,
        account.tokenVersion,
        device,
        metadata,
      );
    },
  };
}
