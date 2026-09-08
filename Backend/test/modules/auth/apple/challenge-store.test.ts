import { describe, expect, it } from "vitest";
import { loadConfig } from "../../../../src/config/env.js";
import type { RedisResource } from "../../../../src/infrastructure/redis/client.js";
import { createAppleChallengeStore } from "../../../../src/modules/auth/apple/challenge-store.js";

function createMemoryRedis(): RedisResource {
  const values = new Map<string, string>();
  return {
    close: () => Promise.resolve(),
    connect: () => Promise.resolve(),
    consumeFixedWindow: () => Promise.resolve(1),
    onError: () => undefined,
    ping: () => Promise.resolve(),
    putOneTime: (key, value) => {
      values.set(key, value);
      return Promise.resolve();
    },
    takeOneTime: (key) => {
      const value = values.get(key) ?? null;
      values.delete(key);
      return Promise.resolve(value);
    },
  };
}

describe("Apple challenge store", () => {
  it("accepts the uppercase UUID representation emitted by Swift", async () => {
    const store = createAppleChallengeStore(
      loadConfig({ NODE_ENV: "test" }),
      createMemoryRedis(),
    );
    const challenge = await store.create();

    await expect(store.consume(challenge.challengeId.toUpperCase())).resolves.toBe(
      challenge.nonce,
    );
    await expect(store.consume(challenge.challengeId)).resolves.toBeNull();
  });
});
