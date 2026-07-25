import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { createJobPayloadCipher } from "../jobs/crypto.js";
import { MEDIA_DELETE_JOB } from "../jobs/types.js";
import type { MediaObjectStore } from "./object-store.js";
import { MediaRepository } from "./repository.js";
import type {
  InternalMediaAsset,
  MediaAsset,
  MediaDownload,
  MediaPurpose,
  MediaUploadReservation,
} from "./types.js";

const ALLOWED_CONTENT_TYPES = new Set([
  "audio/aac",
  "audio/caf",
  "audio/mp4",
  "audio/mpeg",
  "audio/wav",
  "audio/x-caf",
]);

export type MediaService = Readonly<{
  completeUpload: (userId: string, assetId: string) => Promise<MediaAsset>;
  createDownload: (userId: string, assetId: string) => Promise<MediaDownload>;
  deleteAsset: (userId: string, assetId: string) => Promise<void>;
  expirePendingUploads: (limit?: number) => Promise<number>;
  processDeletion: (
    payload: Readonly<{ assetId: string; objectKey: string }>,
  ) => Promise<void>;
  reserveUpload: (
    userId: string,
    input: Readonly<{
      assetId: string;
      byteSize: number;
      checksumSha256: string;
      contentType: string;
      purpose: MediaPurpose;
    }>,
  ) => Promise<MediaUploadReservation>;
}>;

function publicAsset(asset: InternalMediaAsset): MediaAsset {
  return {
    byteSize: asset.byteSize,
    checksumSha256: asset.checksumSha256,
    contentType: asset.contentType,
    createdAt: asset.createdAt,
    deletedAt: asset.deletedAt,
    id: asset.id,
    pendingExpiresAt: asset.pendingExpiresAt,
    purpose: asset.purpose,
    readyAt: asset.readyAt,
    status: asset.status,
  };
}

function addSeconds(date: Date, seconds: number): Date {
  return new Date(date.getTime() + seconds * 1000);
}

function addHours(date: Date, hours: number): Date {
  return addSeconds(date, hours * 3600);
}

function storageUnavailable(): AppError {
  return new AppError({
    code: "MEDIA_STORAGE_UNAVAILABLE",
    message: "Media storage is temporarily unavailable.",
    statusCode: 503,
  });
}

export function createMediaService(
  config: RuntimeConfig,
  database: DatabaseResource,
  objectStore: MediaObjectStore,
): MediaService {
  const repository = new MediaRepository(database);
  const cipher = createJobPayloadCipher(config);

  const deletionJob = (asset: InternalMediaAsset) =>
    cipher.prepare(
      MEDIA_DELETE_JOB,
      {
        assetId: asset.id,
        objectKey: asset.objectKey,
      },
      {
        maxAttempts: 12,
        uniqueKey: `media-delete:${asset.id}`,
        userId: asset.userId,
      },
    );

  const scheduleDeletion = async (asset: InternalMediaAsset): Promise<void> => {
    await repository.scheduleDeletion(
      asset.userId,
      asset.id,
      deletionJob(asset),
      new Date(),
    );
  };

  return {
    completeUpload: async (userId, assetId) => {
      const asset = await repository.find(userId, assetId);
      if (asset.status === "ready") {
        return publicAsset(asset);
      }
      if (
        asset.status !== "pending" ||
        new Date(asset.pendingExpiresAt).getTime() <= Date.now()
      ) {
        throw new AppError({
          code: "MEDIA_UPLOAD_EXPIRED",
          message: "The media upload reservation has expired.",
          statusCode: 409,
        });
      }

      let object;
      try {
        object = await objectStore.headObject(asset.objectKey);
      } catch {
        throw storageUnavailable();
      }
      if (object === undefined) {
        throw new AppError({
          code: "MEDIA_UPLOAD_NOT_FOUND",
          message: "Upload the media object before completing the reservation.",
          statusCode: 409,
        });
      }
      if (
        object.byteSize !== asset.byteSize ||
        object.contentType !== asset.contentType ||
        object.checksumSha256 !== asset.checksumSha256
      ) {
        await scheduleDeletion(asset);
        throw new AppError({
          code: "MEDIA_UPLOAD_MISMATCH",
          message: "The uploaded media does not match its reservation.",
          statusCode: 422,
        });
      }
      return publicAsset(await repository.markReady(userId, assetId, new Date()));
    },

    createDownload: async (userId, assetId) => {
      const asset = await repository.find(userId, assetId);
      if (asset.status !== "ready") {
        throw new AppError({
          code: "MEDIA_ASSET_NOT_READY",
          message: "The media asset is not available for download.",
          statusCode: 409,
        });
      }
      const now = new Date();
      try {
        return {
          asset: publicAsset(asset),
          download: {
            expiresAt: addSeconds(now, config.mediaDownloadUrlTtlSeconds).toISOString(),
            url: await objectStore.createDownloadUrl(
              asset.objectKey,
              config.mediaDownloadUrlTtlSeconds,
            ),
          },
        };
      } catch {
        throw storageUnavailable();
      }
    },

    deleteAsset: async (userId, assetId) => {
      const asset = await repository.find(userId, assetId);
      await repository.scheduleDeletion(
        userId,
        assetId,
        deletionJob(asset),
        new Date(),
      );
    },

    expirePendingUploads: async (limit = 500) => {
      const expired = await repository.expiredPending(limit, new Date());
      for (const asset of expired) {
        await scheduleDeletion(asset);
      }
      return expired.length;
    },

    processDeletion: async (payload) => {
      await objectStore.deleteObjects([payload.objectKey]);
      await repository.markPurged(payload.assetId, new Date());
    },

    reserveUpload: async (userId, input) => {
      if (!ALLOWED_CONTENT_TYPES.has(input.contentType)) {
        throw new AppError({
          code: "MEDIA_CONTENT_TYPE_UNSUPPORTED",
          message: "This media content type is not supported.",
          statusCode: 415,
        });
      }
      if (input.byteSize > config.mediaMaxVoiceBytes) {
        throw new AppError({
          code: "MEDIA_TOO_LARGE",
          message: "The media asset is too large.",
          statusCode: 413,
        });
      }
      const now = new Date();
      const asset = await repository.reserve(
        {
          byteSize: input.byteSize,
          checksumSha256: input.checksumSha256,
          contentType: input.contentType,
          id: input.assetId,
          objectKey: `${userId}/${input.assetId}`,
          pendingExpiresAt: addHours(now, config.mediaPendingTtlHours),
          purpose: input.purpose,
          userId,
        },
        config.mediaUserAssetLimit,
        config.mediaUserStorageBytes,
      );
      if (asset.status === "ready") {
        return {
          asset: publicAsset(asset),
          upload: null,
        };
      }
      try {
        const upload = await objectStore.createUploadUrl(
          {
            byteSize: asset.byteSize,
            checksumSha256: asset.checksumSha256,
            contentType: asset.contentType,
            objectKey: asset.objectKey,
          },
          config.mediaUploadUrlTtlSeconds,
        );
        return {
          asset: publicAsset(asset),
          upload: {
            expiresAt: addSeconds(now, config.mediaUploadUrlTtlSeconds).toISOString(),
            headers: upload.headers,
            method: "PUT",
            url: upload.url,
          },
        };
      } catch {
        throw storageUnavailable();
      }
    },
  };
}
