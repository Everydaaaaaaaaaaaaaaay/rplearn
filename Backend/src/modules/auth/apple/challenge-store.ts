import { randomBytes } from "node:crypto";
import type { RuntimeConfig } from "../../../config/env.js";
import type { RedisResource } from "../../../infrastructure/redis/client.js";
import { newEntityId } from "../../../shared/id.js";

export type AppleChallenge = Readonly<{
  challengeId: string;
  expiresIn: number;
  nonce: string;
}>;

export type AppleChallengeStore = Readonly<{
  consume: (challengeId: string) => Promise<string | null>;
  create: () => Promise<AppleChallenge>;
}>;

function challengeKey(challengeId: string): string {
  return `auth:apple:challenge:${challengeId.toLowerCase()}`;
}

export function createAppleChallengeStore(
  config: RuntimeConfig,
  redis: RedisResource,
): AppleChallengeStore {
  return {
    consume: (challengeId) => redis.takeOneTime(challengeKey(challengeId)),
    create: async () => {
      const challengeId = newEntityId();
      const nonce = randomBytes(32).toString("base64url");
      await redis.putOneTime(
        challengeKey(challengeId),
        nonce,
        config.appleChallengeTtlSeconds,
      );
      return {
        challengeId,
        expiresIn: config.appleChallengeTtlSeconds,
        nonce,
      };
    },
  };
}
