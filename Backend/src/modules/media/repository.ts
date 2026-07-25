import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { insertPreparedJob } from "../jobs/repository.js";
import type { PreparedJob } from "../jobs/types.js";
import type { InternalMediaAsset, MediaPurpose, MediaStatus } from "./types.js";

type MediaRow = Readonly<{
  byte_size: string;
  checksum_sha256: string;
  content_type: string;
  created_at: string;
  deleted_at: string | null;
  id: string;
  object_key: string;
  pending_expires_at: string;
  purged_at: string | null;
  purpose: MediaPurpose;
  ready_at: string | null;
  status: MediaStatus;
  user_id: string;
}>;

type Reservation = Readonly<{
  byteSize: number;
  checksumSha256: string;
  contentType: string;
  id: string;
  objectKey: string;
  pendingExpiresAt: Date;
  purpose: MediaPurpose;
  userId: string;
}>;

function mapAsset(row: MediaRow): InternalMediaAsset {
  return {
    byteSize: Number(row.byte_size),
    checksumSha256: row.checksum_sha256,
    contentType: row.content_type,
    createdAt: new Date(row.created_at).toISOString(),
    deletedAt: row.deleted_at === null ? null : new Date(row.deleted_at).toISOString(),
    id: row.id,
    objectKey: row.object_key,
    pendingExpiresAt: new Date(row.pending_expires_at).toISOString(),
    purgedAt: row.purged_at === null ? null : new Date(row.purged_at).toISOString(),
    purpose: row.purpose,
    readyAt: row.ready_at === null ? null : new Date(row.ready_at).toISOString(),
    status: row.status,
    userId: row.user_id,
  };
}

function notFound(): AppError {
  return new AppError({
    code: "MEDIA_ASSET_NOT_FOUND",
    message: "The media asset was not found.",
    statusCode: 404,
  });
}

async function selectForUpdate(
  sql: TransactionSql,
  userId: string,
  assetId: string,
): Promise<InternalMediaAsset | undefined> {
  const rows = await sql<MediaRow[]>`
    select
      id::text,
      user_id::text,
      purpose,
      object_key,
      content_type,
      byte_size::text,
      checksum_sha256,
      status,
      pending_expires_at,
      ready_at,
      deleted_at,
      purged_at,
      created_at
    from app.media_assets
    where id = ${assetId}
      and user_id = ${userId}
    for update
  `;
  return rows[0] === undefined ? undefined : mapAsset(rows[0]);
}

export class MediaRepository {
  constructor(private readonly database: DatabaseResource) {}

  async reserve(
    input: Reservation,
    maximumAssetCount: number,
    maximumUserBytes: number,
  ): Promise<InternalMediaAsset> {
    return this.database.sql.begin(async (sql) => {
      const [user] = await sql<{ id: string }[]>`
        select id::text
        from app.users
        where id = ${input.userId}
          and status = 'active'
        for update
      `;
      if (user === undefined) {
        throw new AppError({
          code: "ACCOUNT_UNAVAILABLE",
          message: "This account is not available.",
          statusCode: 409,
        });
      }

      const existing = await selectForUpdate(sql, input.userId, input.id);
      if (existing !== undefined) {
        if (
          existing.contentType !== input.contentType ||
          existing.byteSize !== input.byteSize ||
          existing.checksumSha256 !== input.checksumSha256 ||
          existing.objectKey !== input.objectKey
        ) {
          throw new AppError({
            code: "MEDIA_ASSET_ID_CONFLICT",
            message: "This asset ID was already reserved with different metadata.",
            statusCode: 409,
          });
        }
        if (existing.status === "deleted") {
          throw new AppError({
            code: "MEDIA_ASSET_DELETED",
            message: "A deleted media asset ID cannot be reused.",
            statusCode: 409,
          });
        }
        return existing;
      }

      const [usage] = await sql<{ asset_count: number; used_bytes: string }[]>`
        select
          count(*)::int as asset_count,
          coalesce(sum(byte_size), 0)::text as used_bytes
        from app.media_assets
        where user_id = ${input.userId}
          and (
            status = 'ready'
            or (
              status = 'pending'
              and pending_expires_at > now()
            )
          )
      `;
      const usedBytes = Number(usage?.used_bytes ?? "0");
      if ((usage?.asset_count ?? 0) >= maximumAssetCount) {
        throw new AppError({
          code: "MEDIA_ASSET_LIMIT_EXCEEDED",
          message: "The account media asset limit has been reached.",
          statusCode: 403,
        });
      }
      if (usedBytes + input.byteSize > maximumUserBytes) {
        throw new AppError({
          code: "MEDIA_STORAGE_QUOTA_EXCEEDED",
          message: "The account media storage quota has been reached.",
          statusCode: 403,
        });
      }

      const [row] = await sql<MediaRow[]>`
        insert into app.media_assets (
          id,
          user_id,
          purpose,
          object_key,
          content_type,
          byte_size,
          checksum_sha256,
          pending_expires_at
        )
        values (
          ${input.id},
          ${input.userId},
          ${input.purpose},
          ${input.objectKey},
          ${input.contentType},
          ${input.byteSize},
          ${input.checksumSha256},
          ${input.pendingExpiresAt.toISOString()}
        )
        returning
          id::text,
          user_id::text,
          purpose,
          object_key,
          content_type,
          byte_size::text,
          checksum_sha256,
          status,
          pending_expires_at,
          ready_at,
          deleted_at,
          purged_at,
          created_at
      `;
      if (row === undefined) {
        throw new Error("MediaReservationFailed");
      }
      return mapAsset(row);
    });
  }

  async find(userId: string, assetId: string): Promise<InternalMediaAsset> {
    const rows = await this.database.sql<MediaRow[]>`
      select
        id::text,
        user_id::text,
        purpose,
        object_key,
        content_type,
        byte_size::text,
        checksum_sha256,
        status,
        pending_expires_at,
        ready_at,
        deleted_at,
        purged_at,
        created_at
      from app.media_assets
      where id = ${assetId}
        and user_id = ${userId}
    `;
    if (rows[0] === undefined) {
      throw notFound();
    }
    return mapAsset(rows[0]);
  }

  async markReady(
    userId: string,
    assetId: string,
    now: Date,
  ): Promise<InternalMediaAsset> {
    return this.database.sql.begin(async (sql) => {
      const asset = await selectForUpdate(sql, userId, assetId);
      if (asset === undefined) {
        throw notFound();
      }
      if (asset.status === "ready") {
        return asset;
      }
      if (
        asset.status !== "pending" ||
        new Date(asset.pendingExpiresAt).getTime() <= now.getTime()
      ) {
        throw new AppError({
          code: "MEDIA_UPLOAD_EXPIRED",
          message: "The media upload reservation has expired.",
          statusCode: 409,
        });
      }
      const [row] = await sql<MediaRow[]>`
        update app.media_assets
        set status = 'ready',
            ready_at = ${now.toISOString()},
            updated_at = ${now.toISOString()}
        where id = ${assetId}
          and user_id = ${userId}
          and status = 'pending'
        returning
          id::text,
          user_id::text,
          purpose,
          object_key,
          content_type,
          byte_size::text,
          checksum_sha256,
          status,
          pending_expires_at,
          ready_at,
          deleted_at,
          purged_at,
          created_at
      `;
      if (row === undefined) {
        throw new Error("MediaCompletionFailed");
      }
      return mapAsset(row);
    });
  }

  async scheduleDeletion(
    userId: string,
    assetId: string,
    job: PreparedJob,
    now: Date,
  ): Promise<InternalMediaAsset> {
    return this.database.sql.begin(async (sql) => {
      const asset = await selectForUpdate(sql, userId, assetId);
      if (asset === undefined) {
        throw notFound();
      }
      if (asset.status === "deleted") {
        return asset;
      }
      if (asset.status === "ready") {
        const [reference] = await sql<{ resource_id: string }[]>`
          select resource_id
          from app.content_records
          where user_id = ${userId}
            and resource_type = 'message'
            and deleted_at is null
            and payload ->> 'audioAssetId' = ${assetId}
          limit 1
        `;
        if (reference !== undefined) {
          throw new AppError({
            code: "MEDIA_ASSET_IN_USE",
            message: "Delete the message that uses this media asset first.",
            statusCode: 409,
          });
        }
      }
      const [row] = await sql<MediaRow[]>`
        update app.media_assets
        set status = 'deleted',
            deleted_at = ${now.toISOString()},
            updated_at = ${now.toISOString()}
        where id = ${assetId}
          and user_id = ${userId}
        returning
          id::text,
          user_id::text,
          purpose,
          object_key,
          content_type,
          byte_size::text,
          checksum_sha256,
          status,
          pending_expires_at,
          ready_at,
          deleted_at,
          purged_at,
          created_at
      `;
      if (row === undefined) {
        throw new Error("MediaDeletionSchedulingFailed");
      }
      await insertPreparedJob(sql, job);
      return mapAsset(row);
    });
  }

  async expiredPending(
    limit: number,
    now: Date,
  ): Promise<readonly InternalMediaAsset[]> {
    const rows = await this.database.sql<MediaRow[]>`
      select
        id::text,
        user_id::text,
        purpose,
        object_key,
        content_type,
        byte_size::text,
        checksum_sha256,
        status,
        pending_expires_at,
        ready_at,
        deleted_at,
        purged_at,
        created_at
      from app.media_assets
      where status = 'pending'
        and pending_expires_at <= ${now.toISOString()}
      order by pending_expires_at, id
      limit ${limit}
    `;
    return rows.map(mapAsset);
  }

  async markPurged(assetId: string, now: Date): Promise<void> {
    await this.database.sql`
      update app.media_assets
      set purged_at = coalesce(purged_at, ${now.toISOString()}),
          updated_at = ${now.toISOString()}
      where id = ${assetId}
        and status = 'deleted'
    `;
  }
}
