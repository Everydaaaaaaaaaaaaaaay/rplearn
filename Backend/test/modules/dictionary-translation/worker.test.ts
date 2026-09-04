import { describe, expect, it, vi } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import type { JobPayloadCipher } from "../../../src/modules/jobs/crypto.js";
import { JobWorker } from "../../../src/modules/jobs/worker.js";
import { DICTIONARY_EXAMPLE_TRANSLATION_JOB } from "../../../src/modules/jobs/types.js";

describe("dictionary translation job routing", () => {
  it("decrypts and dispatches the persistent job to the injected processor", async () => {
    const payload = {
      attempt: 1,
      cacheKey: "a".repeat(64),
      userId: "019c0123-4567-789a-8bcd-ef0123456789",
    };
    const processDictionaryTranslation = vi.fn(() => Promise.resolve());
    const complete = vi.fn(() => Promise.resolve(true));
    const fail = vi.fn(() => Promise.resolve("dead" as const));
    const cipher = {
      open: () => payload,
      prepare: () => {
        throw new Error("unused");
      },
    } satisfies JobPayloadCipher;
    let claimed = false;
    const worker = new JobWorker({
      cipher,
      config: loadConfig({ NODE_ENV: "test" }),
      logger: {
        error: () => undefined,
        info: () => undefined,
        warn: () => undefined,
      },
      notifier: {
        sendEmailVerification: () => Promise.resolve(),
        sendPasswordReset: () => Promise.resolve(),
      },
      processDictionaryTranslation,
      repository: {
        claim: () => {
          if (claimed) {
            return Promise.resolve(undefined);
          }
          claimed = true;
          return Promise.resolve({
            attempts: 1,
            id: "019c0123-4567-789a-8bcd-ef0123456788",
            keyVersion: "test-v1",
            maxAttempts: 1,
            nonce: Buffer.alloc(12),
            payloadCiphertext: Buffer.alloc(1),
            tag: Buffer.alloc(16),
            type: DICTIONARY_EXAMPLE_TRANSLATION_JOB,
          });
        },
        complete,
        fail,
      },
      workerId: "dictionary-worker-test",
    });

    expect(await worker.runOnce()).toBe("succeeded");
    expect(processDictionaryTranslation).toHaveBeenCalledWith(payload);
    expect(complete).toHaveBeenCalledTimes(1);
    expect(fail).not.toHaveBeenCalled();
  });
});
