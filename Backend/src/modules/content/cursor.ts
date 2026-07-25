import { createHmac, timingSafeEqual } from "node:crypto";
import { AppError } from "../../shared/errors.js";
import type { ContentResourceType } from "./types.js";

type ContentCursorPayload = Readonly<{
  lastId: string;
  lastType: ContentResourceType;
  snapshotSequence: string;
  userId: string;
  version: 1;
}>;

const SEQUENCE_PATTERN = /^(0|[1-9][0-9]*)$/;
const RESOURCE_TYPES = new Set<ContentResourceType>([
  "character",
  "conversation",
  "favorite",
  "memory",
  "message",
  "quiz_record",
  "story_progress",
]);

function invalidCursor(): AppError {
  return new AppError({
    code: "INVALID_CONTENT_CURSOR",
    message: "The content cursor is invalid or belongs to another user.",
    statusCode: 400,
  });
}

function decodeCanonicalBase64Url(value: string): Buffer {
  const decoded = Buffer.from(value, "base64url");
  if (decoded.toString("base64url") !== value) {
    throw invalidCursor();
  }
  return decoded;
}

export type ContentCursorCodec = Readonly<{
  decode: (cursor: string, expectedUserId: string) => ContentCursorPayload;
  encode: (payload: Omit<ContentCursorPayload, "version">) => string;
}>;

export function createContentCursorCodec(secret: string): ContentCursorCodec {
  const sign = (encodedPayload: string): Buffer =>
    createHmac("sha256", secret)
      .update(`lingotrip-content-cursor-v1:${encodedPayload}`)
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
        const supplied = decodeCanonicalBase64Url(encodedSignature);
        const expected = sign(encodedPayload);
        if (
          supplied.byteLength !== expected.byteLength ||
          !timingSafeEqual(supplied, expected)
        ) {
          throw invalidCursor();
        }
        const payload = JSON.parse(
          decodeCanonicalBase64Url(encodedPayload).toString("utf8"),
        ) as Partial<ContentCursorPayload>;
        if (
          payload.version !== 1 ||
          payload.userId !== expectedUserId ||
          typeof payload.lastId !== "string" ||
          payload.lastId.length < 1 ||
          payload.lastId.length > 128 ||
          typeof payload.lastType !== "string" ||
          !RESOURCE_TYPES.has(payload.lastType) ||
          typeof payload.snapshotSequence !== "string" ||
          !SEQUENCE_PATTERN.test(payload.snapshotSequence)
        ) {
          throw invalidCursor();
        }
        return payload as ContentCursorPayload;
      } catch (error) {
        if (error instanceof AppError) {
          throw error;
        }
        throw invalidCursor();
      }
    },
    encode: (payload) => {
      if (!SEQUENCE_PATTERN.test(payload.snapshotSequence)) {
        throw new Error("Cannot encode an invalid content sequence");
      }
      const encodedPayload = Buffer.from(
        JSON.stringify({ ...payload, version: 1 }),
      ).toString("base64url");
      return `${encodedPayload}.${sign(encodedPayload).toString("base64url")}`;
    },
  };
}
