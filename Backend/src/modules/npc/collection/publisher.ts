import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { PreparedCollection } from "./review.js";

export type AvatarPublisher = Readonly<{
  put: (file: PreparedCollection["files"][number]) => Promise<void>;
}>;
export function createAvatarPublisher(options: {
  bucket: string;
  prefix: string;
  region: string;
  endpoint?: string;
}): AvatarPublisher {
  if (
    !/^[a-zA-Z0-9][a-zA-Z0-9._-]{1,254}$/u.test(options.bucket) ||
    !/^[a-zA-Z0-9/_-]*$/u.test(options.prefix)
  )
    throw new Error("Invalid bucket or key prefix");
  if (options.endpoint) {
    const url = new URL(options.endpoint);
    if (url.protocol !== "https:" || url.username || url.password)
      throw new Error("S3 endpoint must be HTTPS");
  }
  const client = new S3Client({
    region: options.region,
    ...(options.endpoint ? { endpoint: options.endpoint, forcePathStyle: true } : {}),
  });
  return {
    put: async (file) => {
      const content = await readFile(file.path);
      if (
        content.length !== file.byteLength ||
        createHash("sha256").update(content).digest("hex") !== file.sha256
      ) {
        throw new Error(`Reviewed file changed before upload: ${file.path}`);
      }
      const key = `${options.prefix.replace(/\/$/u, "")}${options.prefix ? "/" : ""}${file.key}`;
      try {
        await client.send(
          new PutObjectCommand({
            Bucket: options.bucket,
            Key: key,
            Body: content,
            ContentType: file.contentType,
            CacheControl: "public, max-age=31536000, immutable",
            IfNoneMatch: "*",
            ChecksumSHA256: Buffer.from(file.sha256, "hex").toString("base64"),
            Metadata: { sha256: file.sha256 },
          }),
        );
      } catch (error) {
        const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata
          ?.httpStatusCode;
        if (status !== 412) throw error;
        // A retry may find a prior successful upload. Verify the object; never overwrite it.
        const existing = await client.send(
          new GetObjectCommand({ Bucket: options.bucket, Key: key }),
        );
        if (existing.ContentLength !== file.byteLength)
          throw new Error(`Existing object differs: ${key}`, { cause: error });
        const bytes = await existing.Body?.transformToByteArray();
        if (!bytes || createHash("sha256").update(bytes).digest("hex") !== file.sha256)
          throw new Error(`Existing object differs: ${key}`, { cause: error });
      }
    },
  };
}
export async function publishCollection(
  prepared: PreparedCollection,
  publisher: AvatarPublisher,
): Promise<void> {
  for (const file of prepared.files) await publisher.put(file);
}
