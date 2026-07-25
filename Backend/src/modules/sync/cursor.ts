import { createHmac, timingSafeEqual } from "node:crypto";
import { AppError } from "../../shared/errors.js";

type CursorPayload = Readonly<{
  sequence: string;
  userId: string;
  version: 1;
}>;

const SEQUENCE_PATTERN = /^(0|[1-9][0-9]*)$/;

function decodeCanonicalBase64Url(value: string): Buffer {
  const decoded = Buffer.from(value, "base64url");
  if (decoded.toString("base64url") !== value) {
    throw invalidCursor();
  }
  return decoded;
}

function invalidCursor(): AppError {
  return new AppError({
    code: "INVALID_SYNC_CURSOR",
    message: "The sync cursor is invalid or belongs to another user.",
    statusCode: 400,
  });
}

export type SyncCursorCodec = Readonly<{
  decode: (cursor: string, expectedUserId: string) => string;
  encode: (userId: string, sequence: string) => string;
}>;

export function createSyncCursorCodec(secret: string): SyncCursorCodec {
  const sign = (encodedPayload: string): Buffer =>
    createHmac("sha256", secret)
      .update(`lingotrip-sync-cursor-v1:${encodedPayload}`)
      .digest();

  return {
    decode: (cursor, expectedUserId) => {
      const [encodedPayload, encodedSignature, extra] = cursor.split(".");
      if (
        encodedPayload === undefined ||
        encodedSignature === undefined ||
        extra !== undefined
      ) {
        throw invalidCursor();
      }

      try {
        const suppliedSignature = decodeCanonicalBase64Url(encodedSignature);
        const expectedSignature = sign(encodedPayload);
        if (
          suppliedSignature.byteLength !== expectedSignature.byteLength ||
          !timingSafeEqual(suppliedSignature, expectedSignature)
        ) {
          throw invalidCursor();
        }

        const payload = JSON.parse(
          decodeCanonicalBase64Url(encodedPayload).toString("utf8"),
        ) as Partial<CursorPayload>;
        if (
          payload.version !== 1 ||
          payload.userId !== expectedUserId ||
          typeof payload.sequence !== "string" ||
          !SEQUENCE_PATTERN.test(payload.sequence)
        ) {
          throw invalidCursor();
        }
        return payload.sequence;
      } catch (error) {
        if (error instanceof AppError) {
          throw error;
        }
        throw invalidCursor();
      }
    },
    encode: (userId, sequence) => {
      if (!SEQUENCE_PATTERN.test(sequence)) {
        throw new Error("Cannot encode an invalid sync sequence");
      }
      const payload: CursorPayload = {
        sequence,
        userId,
        version: 1,
      };
      const encodedPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");
      return `${encodedPayload}.${sign(encodedPayload).toString("base64url")}`;
    },
  };
}
