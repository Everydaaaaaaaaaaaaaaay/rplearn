import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import type { RuntimeConfig } from "../../../config/env.js";
import type { SealedProviderCredential } from "../repository.js";

export type CredentialSealer = Readonly<{
  open: (credential: SealedProviderCredential) => string;
  seal: (plaintext: string) => SealedProviderCredential;
}>;

export function createCredentialSealer(config: RuntimeConfig): CredentialSealer {
  if (
    config.appleCredentialEncryptionKeyBase64 === undefined ||
    config.appleCredentialKeyVersion === undefined
  ) {
    throw new Error("Apple credential encryption is not configured");
  }

  const key = Buffer.from(config.appleCredentialEncryptionKeyBase64, "base64");
  if (key.byteLength !== 32) {
    throw new Error("Apple credential encryption key is invalid");
  }
  const keyVersion = config.appleCredentialKeyVersion;

  return {
    open: (credential) => {
      if (credential.keyVersion !== keyVersion) {
        throw new Error(
          `Unsupported Apple credential key version: ${credential.keyVersion}`,
        );
      }
      const decipher = createDecipheriv("aes-256-gcm", key, credential.nonce);
      decipher.setAuthTag(credential.tag);
      return Buffer.concat([
        decipher.update(credential.ciphertext),
        decipher.final(),
      ]).toString("utf8");
    },
    seal: (plaintext) => {
      const nonce = randomBytes(12);
      const cipher = createCipheriv("aes-256-gcm", key, nonce);
      const ciphertext = Buffer.concat([
        cipher.update(plaintext, "utf8"),
        cipher.final(),
      ]);
      return {
        ciphertext,
        keyVersion,
        nonce,
        tag: cipher.getAuthTag(),
      };
    },
  };
}
