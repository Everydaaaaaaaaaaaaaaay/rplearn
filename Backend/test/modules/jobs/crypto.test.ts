import { describe, expect, it } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import { createJobPayloadCipher } from "../../../src/modules/jobs/crypto.js";
import { AUTH_EMAIL_VERIFICATION_JOB } from "../../../src/modules/jobs/types.js";

describe("job payload encryption", () => {
  it("round trips sensitive payloads and authenticates ciphertext", () => {
    const cipher = createJobPayloadCipher(loadConfig({ NODE_ENV: "test" }));
    const job = cipher.prepare(AUTH_EMAIL_VERIFICATION_JOB, {
      email: "traveler@example.com",
      token: "a".repeat(64),
    });

    expect(job.payloadCiphertext.toString("utf8")).not.toContain(
      "traveler@example.com",
    );
    expect(cipher.open(job)).toEqual({
      email: "traveler@example.com",
      token: "a".repeat(64),
    });

    expect(() =>
      cipher.open({
        ...job,
        payloadCiphertext: Buffer.from(job.payloadCiphertext).fill(0, 0, 1),
      }),
    ).toThrow();
  });

  it("binds ciphertext to its job type", () => {
    const cipher = createJobPayloadCipher(loadConfig({ NODE_ENV: "test" }));
    const job = cipher.prepare(AUTH_EMAIL_VERIFICATION_JOB, {
      email: "traveler@example.com",
      token: "a".repeat(64),
    });

    expect(() =>
      cipher.open({
        ...job,
        type: "auth.password_reset",
      }),
    ).toThrow();
  });

  it("decrypts queued payloads after a key rotation", () => {
    const oldKey = Buffer.alloc(32, 1).toString("base64");
    const newKey = Buffer.alloc(32, 2).toString("base64");
    const oldCipher = createJobPayloadCipher(
      loadConfig({
        JOB_PAYLOAD_ENCRYPTION_KEY_BASE64: oldKey,
        JOB_PAYLOAD_KEY_VERSION: "jobs-v1",
        NODE_ENV: "test",
      }),
    );
    const job = oldCipher.prepare(AUTH_EMAIL_VERIFICATION_JOB, {
      email: "traveler@example.com",
      token: "a".repeat(64),
    });
    const rotatedCipher = createJobPayloadCipher(
      loadConfig({
        JOB_PAYLOAD_ENCRYPTION_KEY_BASE64: newKey,
        JOB_PAYLOAD_KEY_VERSION: "jobs-v2",
        JOB_PAYLOAD_PREVIOUS_KEYS: `jobs-v1=${oldKey}`,
        NODE_ENV: "test",
      }),
    );

    expect(rotatedCipher.open(job)).toEqual({
      email: "traveler@example.com",
      token: "a".repeat(64),
    });
  });
});
