import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { appendSyncChange } from "../sync/change-writer.js";
import type {
  ContentCommand,
  ContentDeleteCommand,
  ContentRecord,
  ContentResourceType,
  ContentUpsertCommand,
} from "./types.js";

type ContentRow = Readonly<{
  created_at: string;
  deleted_at: string | null;
  parent_id: string | null;
  payload_text: string;
  resource_id: string;
  resource_type: ContentResourceType;
  updated_at: string;
  version: number;
}>;

const RESOURCE_LIMITS: Readonly<Record<ContentResourceType, number>> = {
  character: 200,
  conversation: 2_000,
  favorite: 10_000,
  memory: 20_000,
  message: 100_000,
  quiz_record: 50_000,
  story_progress: 2_000,
};

const PARENT_TYPES: Readonly<
  Partial<Record<ContentResourceType, ContentResourceType>>
> = {
  conversation: "character",
  memory: "character",
  message: "conversation",
};

const DEPENDENT_TYPES: Readonly<
  Partial<Record<ContentResourceType, readonly ContentResourceType[]>>
> = {
  character: ["conversation", "memory"],
  conversation: ["message"],
};

function mapRecord(row: ContentRow): ContentRecord {
  return {
    createdAt: new Date(row.created_at).toISOString(),
    deletedAt: row.deleted_at === null ? null : new Date(row.deleted_at).toISOString(),
    parentId: row.parent_id,
    payload: JSON.parse(row.payload_text) as unknown,
    resourceId: row.resource_id,
    resourceType: row.resource_type,
    updatedAt: new Date(row.updated_at).toISOString(),
    version: row.version,
  };
}

function versionConflict(current: ContentRecord | undefined): AppError {
  return new AppError({
    code: "CONTENT_VERSION_CONFLICT",
    details: current === undefined ? { current: null } : { current },
    message: "This record changed on another device.",
    statusCode: 409,
  });
}

export class ContentRepository {
  constructor(private readonly database: DatabaseResource) {}

  async currentSequence(userId: string): Promise<string> {
    const [head] = await this.database.sql<{ sequence: string }[]>`
      select coalesce(
        (
          select last_sequence
          from app.sync_heads
          where user_id = ${userId}
        ),
        0
      )::text as sequence
    `;
    return head?.sequence ?? "0";
  }

  async page(
    userId: string,
    after:
      | Readonly<{
          resourceId: string;
          resourceType: ContentResourceType;
        }>
      | undefined,
    limit: number,
  ): Promise<readonly ContentRecord[]> {
    const afterType = after?.resourceType ?? "";
    const afterId = after?.resourceId ?? "";
    const rows = await this.database.sql<ContentRow[]>`
      select
        resource_type,
        resource_id,
        parent_id,
        payload::text as payload_text,
        version,
        created_at,
        updated_at,
        deleted_at
      from app.content_records
      where user_id = ${userId}
        and deleted_at is null
        and (
          ${after === undefined}
          or (resource_type::text, resource_id) > (${afterType}, ${afterId})
        )
      order by resource_type::text, resource_id
      limit ${limit}
    `;
    return rows.map(mapRecord);
  }

  async execute(
    userId: string,
    command: ContentCommand,
    requestHash: string,
  ): Promise<ContentRecord> {
    return this.database.sql.begin(async (sql) => {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`${userId}:${command.commandId}`}, 0)
        )
      `;
      const [receipt] = await sql<
        {
          request_hash: string;
          response_text: string;
          route: string;
        }[]
      >`
        select
          request_hash,
          route,
          response::text as response_text
        from app.command_receipts
        where user_id = ${userId}
          and command_id = ${command.commandId}
      `;
      if (receipt !== undefined) {
        if (
          receipt.request_hash !== requestHash ||
          receipt.route !== "content.command"
        ) {
          throw new AppError({
            code: "IDEMPOTENCY_KEY_CONFLICT",
            message: "This command ID was already used for another request.",
            statusCode: 409,
          });
        }
        return JSON.parse(receipt.response_text) as ContentRecord;
      }

      const record =
        command.operation === "upsert"
          ? await this.upsert(sql, userId, command)
          : await this.delete(sql, userId, command);
      await appendSyncChange(sql, {
        commandId: command.commandId,
        eventType: `content.${command.resourceType}.${command.operation}`,
        payload: record,
        userId,
      });
      await sql`
        insert into app.command_receipts (
          user_id,
          command_id,
          route,
          request_hash,
          response
        )
        values (
          ${userId},
          ${command.commandId},
          'content.command',
          ${requestHash},
          ${JSON.stringify(record)}::jsonb
        )
      `;
      return record;
    });
  }

  private async upsert(
    sql: TransactionSql,
    userId: string,
    command: ContentUpsertCommand,
  ): Promise<ContentRecord> {
    const existing = await this.lockRecord(
      sql,
      userId,
      command.resourceType,
      command.resourceId,
    );
    if (
      (existing === undefined && command.expectedVersion !== 0) ||
      (existing !== undefined && existing.version !== command.expectedVersion)
    ) {
      throw versionConflict(existing);
    }
    await this.requireParent(sql, userId, command.resourceType, command.parentId);
    await this.requireReadyMediaAsset(sql, userId, command);
    if (existing?.deletedAt !== null) {
      await this.requireCapacity(sql, userId, command.resourceType);
    }

    const [row] =
      existing === undefined
        ? await sql<ContentRow[]>`
            insert into app.content_records (
              user_id,
              resource_type,
              resource_id,
              parent_id,
              payload
            )
            values (
              ${userId},
              ${command.resourceType}::app.content_resource_type,
              ${command.resourceId},
              ${command.parentId},
              ${JSON.stringify(command.payload)}::jsonb
            )
            returning
              resource_type,
              resource_id,
              parent_id,
              payload::text as payload_text,
              version,
              created_at,
              updated_at,
              deleted_at
          `
        : await sql<ContentRow[]>`
            update app.content_records
            set parent_id = ${command.parentId},
                payload = ${JSON.stringify(command.payload)}::jsonb,
                version = version + 1,
                deleted_at = null,
                updated_at = now()
            where user_id = ${userId}
              and resource_type = ${command.resourceType}::app.content_resource_type
              and resource_id = ${command.resourceId}
            returning
              resource_type,
              resource_id,
              parent_id,
              payload::text as payload_text,
              version,
              created_at,
              updated_at,
              deleted_at
          `;
    if (row === undefined) {
      throw new Error("Content upsert did not return a row");
    }
    return mapRecord(row);
  }

  private async delete(
    sql: TransactionSql,
    userId: string,
    command: ContentDeleteCommand,
  ): Promise<ContentRecord> {
    const existing = await this.lockRecord(
      sql,
      userId,
      command.resourceType,
      command.resourceId,
    );
    if (existing?.version !== command.expectedVersion || existing.deletedAt !== null) {
      throw versionConflict(existing);
    }
    await this.requireNoDependents(
      sql,
      userId,
      command.resourceType,
      command.resourceId,
    );
    const [row] = await sql<ContentRow[]>`
      update app.content_records
      set version = version + 1,
          deleted_at = now(),
          updated_at = now()
      where user_id = ${userId}
        and resource_type = ${command.resourceType}::app.content_resource_type
        and resource_id = ${command.resourceId}
      returning
        resource_type,
        resource_id,
        parent_id,
        payload::text as payload_text,
        version,
        created_at,
        updated_at,
        deleted_at
    `;
    if (row === undefined) {
      throw new Error("Content deletion did not return a row");
    }
    return mapRecord(row);
  }

  private async lockRecord(
    sql: TransactionSql,
    userId: string,
    resourceType: ContentResourceType,
    resourceId: string,
  ): Promise<ContentRecord | undefined> {
    const [row] = await sql<ContentRow[]>`
      select
        resource_type,
        resource_id,
        parent_id,
        payload::text as payload_text,
        version,
        created_at,
        updated_at,
        deleted_at
      from app.content_records
      where user_id = ${userId}
        and resource_type = ${resourceType}::app.content_resource_type
        and resource_id = ${resourceId}
      for update
    `;
    return row === undefined ? undefined : mapRecord(row);
  }

  private async requireParent(
    sql: TransactionSql,
    userId: string,
    resourceType: ContentResourceType,
    parentId: string | null,
  ): Promise<void> {
    const requiredType = PARENT_TYPES[resourceType];
    if (requiredType === undefined) {
      if (parentId !== null) {
        throw new AppError({
          code: "CONTENT_PARENT_NOT_ALLOWED",
          message: "This resource type cannot have a parent.",
          statusCode: 400,
        });
      }
      return;
    }
    if (parentId === null) {
      throw new AppError({
        code: "CONTENT_PARENT_REQUIRED",
        message: "This resource requires a parent.",
        statusCode: 400,
      });
    }
    const [parent] = await sql<{ exists: boolean }[]>`
      select true as exists
      from app.content_records
      where user_id = ${userId}
        and resource_type = ${requiredType}::app.content_resource_type
        and resource_id = ${parentId}
        and deleted_at is null
    `;
    if (parent === undefined) {
      throw new AppError({
        code: "CONTENT_PARENT_NOT_FOUND",
        message: "The parent record does not exist.",
        statusCode: 409,
      });
    }
  }

  private async requireReadyMediaAsset(
    sql: TransactionSql,
    userId: string,
    command: ContentUpsertCommand,
  ): Promise<void> {
    if (
      command.resourceType !== "message" ||
      typeof command.payload !== "object" ||
      command.payload === null
    ) {
      return;
    }
    const audioAssetId = (command.payload as { audioAssetId?: unknown }).audioAssetId;
    if (typeof audioAssetId !== "string") {
      return;
    }
    const [asset] = await sql<{ id: string }[]>`
      select id::text
      from app.media_assets
      where id = ${audioAssetId}
        and user_id = ${userId}
        and purpose = 'voice_message'
        and status = 'ready'
    `;
    if (asset === undefined) {
      throw new AppError({
        code: "MEDIA_ASSET_NOT_READY",
        message: "The referenced media asset is not ready for this account.",
        statusCode: 409,
      });
    }
  }

  private async requireCapacity(
    sql: TransactionSql,
    userId: string,
    resourceType: ContentResourceType,
  ): Promise<void> {
    const [row] = await sql<{ count: string }[]>`
      select count(*)::text as count
      from app.content_records
      where user_id = ${userId}
        and resource_type = ${resourceType}::app.content_resource_type
        and deleted_at is null
    `;
    if (Number(row?.count ?? "0") >= RESOURCE_LIMITS[resourceType]) {
      throw new AppError({
        code: "CONTENT_RESOURCE_LIMIT_REACHED",
        details: {
          limit: RESOURCE_LIMITS[resourceType],
          resourceType,
        },
        message: "The account storage limit for this resource was reached.",
        statusCode: 409,
      });
    }
  }

  private async requireNoDependents(
    sql: TransactionSql,
    userId: string,
    resourceType: ContentResourceType,
    resourceId: string,
  ): Promise<void> {
    const dependentTypes = DEPENDENT_TYPES[resourceType];
    if (dependentTypes === undefined) {
      return;
    }
    const [dependent] = await sql<{ exists: boolean }[]>`
      select true as exists
      from app.content_records
      where user_id = ${userId}
        and parent_id = ${resourceId}
        and resource_type in ${sql(dependentTypes)}
        and deleted_at is null
      limit 1
    `;
    if (dependent !== undefined) {
      throw new AppError({
        code: "CONTENT_HAS_DEPENDENTS",
        message: "Delete child records before deleting this record.",
        statusCode: 409,
      });
    }
  }
}
