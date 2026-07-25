import { randomBytes } from "node:crypto";
import { exportPKCS8, exportSPKI, generateKeyPair } from "jose";
import { newEntityId } from "../shared/id.js";

const keys = await generateKeyPair("EdDSA", { extractable: true });
const privateKey = await exportPKCS8(keys.privateKey);
const publicKey = await exportSPKI(keys.publicKey);

process.stdout.write(
  [
    `AUTH_JWT_KEY_ID=${newEntityId()}`,
    `AUTH_JWT_PRIVATE_KEY_BASE64=${Buffer.from(privateKey).toString("base64")}`,
    `AUTH_JWT_PUBLIC_KEY_BASE64=${Buffer.from(publicKey).toString("base64")}`,
    `AUTH_TOKEN_HASH_PEPPER=${randomBytes(48).toString("base64url")}`,
    "",
  ].join("\n"),
);
