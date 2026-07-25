import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadBucketCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type { RuntimeConfig } from "../../config/env.js";

export type MediaObjectMetadata = Readonly<{
  byteSize: number;
  checksumSha256: string | undefined;
  contentType: string | undefined;
}>;

export type MediaObjectStore = Readonly<{
  createDownloadUrl: (objectKey: string, expiresInSeconds: number) => Promise<string>;
  createUploadUrl: (
    input: Readonly<{
      byteSize: number;
      checksumSha256: string;
      contentType: string;
      objectKey: string;
    }>,
    expiresInSeconds: number,
  ) => Promise<
    Readonly<{
      headers: Readonly<Record<string, string>>;
      url: string;
    }>
  >;
  deleteObjects: (objectKeys: readonly string[]) => Promise<void>;
  headObject: (objectKey: string) => Promise<MediaObjectMetadata | undefined>;
  ping: () => Promise<void>;
}>;

function isNotFound(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const candidate = error as {
    $metadata?: { httpStatusCode?: number };
    name?: string;
  };
  return (
    candidate.$metadata?.httpStatusCode === 404 ||
    candidate.name === "NoSuchKey" ||
    candidate.name === "NotFound"
  );
}

export function createMediaObjectStore(config: RuntimeConfig): MediaObjectStore {
  const client = new S3Client({
    ...(config.mediaS3AccessKeyId === undefined ||
    config.mediaS3SecretAccessKey === undefined
      ? {}
      : {
          credentials: {
            accessKeyId: config.mediaS3AccessKeyId,
            secretAccessKey: config.mediaS3SecretAccessKey,
          },
        }),
    ...(config.mediaS3Endpoint === undefined
      ? {}
      : { endpoint: config.mediaS3Endpoint }),
    forcePathStyle: config.mediaS3ForcePathStyle,
    region: config.mediaS3Region,
    requestChecksumCalculation: "WHEN_REQUIRED",
    responseChecksumValidation: "WHEN_REQUIRED",
  });
  const bucket = config.mediaS3Bucket;

  return {
    createDownloadUrl: (objectKey, expiresInSeconds) =>
      getSignedUrl(
        client,
        new GetObjectCommand({
          Bucket: bucket,
          Key: objectKey,
          ResponseCacheControl: "private, max-age=300",
        }),
        { expiresIn: expiresInSeconds },
      ),

    createUploadUrl: async (input, expiresInSeconds) => {
      const headers = {
        "content-length": input.byteSize.toString(),
        "content-type": input.contentType,
      };
      const url = await getSignedUrl(
        client,
        new PutObjectCommand({
          Bucket: bucket,
          ChecksumSHA256: input.checksumSha256,
          ContentLength: input.byteSize,
          ContentType: input.contentType,
          Key: input.objectKey,
          Metadata: {
            sha256: input.checksumSha256,
          },
        }),
        {
          expiresIn: expiresInSeconds,
          signableHeaders: new Set(Object.keys(headers)),
        },
      );
      return { headers, url };
    },

    deleteObjects: async (objectKeys) => {
      for (let index = 0; index < objectKeys.length; index += 1000) {
        const batch = objectKeys.slice(index, index + 1000);
        if (batch.length === 0) {
          continue;
        }
        const result = await client.send(
          new DeleteObjectsCommand({
            Bucket: bucket,
            Delete: {
              Objects: batch.map((Key) => ({ Key })),
              Quiet: true,
            },
          }),
        );
        if ((result.Errors?.length ?? 0) > 0) {
          throw new Error("MediaObjectDeletionFailed");
        }
      }
    },

    headObject: async (objectKey) => {
      try {
        const result = await client.send(
          new HeadObjectCommand({
            Bucket: bucket,
            ChecksumMode: "ENABLED",
            Key: objectKey,
          }),
        );
        if (result.ContentLength === undefined) {
          throw new Error("MediaObjectLengthUnavailable");
        }
        return {
          byteSize: result.ContentLength,
          checksumSha256: result.ChecksumSHA256 ?? result.Metadata?.sha256,
          contentType: result.ContentType,
        };
      } catch (error) {
        if (isNotFound(error)) {
          return undefined;
        }
        throw error;
      }
    },

    ping: async () => {
      await client.send(new HeadBucketCommand({ Bucket: bucket }));
    },
  };
}
