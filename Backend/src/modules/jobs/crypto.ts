import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import { newEntityId } from "../../shared/id.js";
import type { PreparedJob } from "./types.js";

const ALGORITHM = "aes-256-gcm";
const NONCE_LENGTH = 12;

type SealedPayload = Readonly<{
  keyVersion: string;
  nonce: Buffer;
  payloadCiphertext: Buffer;
  tag: Buffer;
}>;

export type JobPayloadCipher = Readonly<{
  open: (job: SealedPayload & Readonly<{ type: string }>) => unknown;
  prepare: (
    type: string,
    payload: unknown,
    options?: Readonly<{
      availableAt?: Date;
      maxAttempts?: number;
      uniqueKey?: string;
      userId?: string;
    }>,
  ) => PreparedJob;
}>;

function additionalData(type: string, keyVersion: string): Buffer {
  return Buffer.from(`lingotrip-job:v1:${type}:${keyVersion}`, "utf8");
}

export function createJobPayloadCipher(config: RuntimeConfig): JobPayloadCipher {
  const encryptionKey = Buffer.from(config.jobPayloadEncryptionKeyBase64, "base64");
  if (encryptionKey.byteLength !== 32) {
    throw new Error("Job payload encryption key must be 32 bytes");
  }
  const decryptionKeys = new Map<string, Buffer>([
    [config.jobPayloadKeyVersion, encryptionKey],
    ...config.jobPayloadPreviousKeys.map(
      (entry) => [entry.keyVersion, Buffer.from(entry.keyBase64, "base64")] as const,
    ),
  ]);

  return {
    open: (job) => {
      const key = decryptionKeys.get(job.keyVersion);
      if (key === undefined) {
        throw new Error(`Unsupported job payload key version: ${job.keyVersion}`);
      }
      const decipher = createDecipheriv(ALGORITHM, key, job.nonce);
      decipher.setAAD(additionalData(job.type, job.keyVersion));
      decipher.setAuthTag(job.tag);
      const plaintext = Buffer.concat([
        decipher.update(job.payloadCiphertext),
        decipher.final(),
      ]);
      return JSON.parse(plaintext.toString("utf8")) as unknown;
    },
    prepare: (type, payload, options = {}) => {
      const nonce = randomBytes(NONCE_LENGTH);
      const cipher = createCipheriv(ALGORITHM, encryptionKey, nonce);
      cipher.setAAD(additionalData(type, config.jobPayloadKeyVersion));
      const payloadCiphertext = Buffer.concat([
        cipher.update(JSON.stringify(payload), "utf8"),
        cipher.final(),
      ]);

      return {
        availableAt: options.availableAt ?? new Date(),
        id: newEntityId(),
        keyVersion: config.jobPayloadKeyVersion,
        maxAttempts: options.maxAttempts ?? 8,
        nonce,
        payloadCiphertext,
        tag: cipher.getAuthTag(),
        type,
        ...(options.uniqueKey === undefined ? {} : { uniqueKey: options.uniqueKey }),
        ...(options.userId === undefined ? {} : { userId: options.userId }),
      };
    },
  };
}
