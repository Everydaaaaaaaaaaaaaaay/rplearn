import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { insertPreparedJob } from "../jobs/transactional-enqueue.js";
import type { PreparedJob } from "../jobs/types.js";
import type { AccountExport, AppleDeletionCredential, DeletionWork } from "./types.js";

type JsonRow = Record<string, unknown>;

type ScheduleDeletionParameters = Readonly<{
  cancellationTokenHash: string | null;
  job: PreparedJob;
  purgeAt: Date;
  requestId: string;
  userId: string;
  userReferenceHash: string;
}>;

export class AccountRepository {
  constructor(private readonly database: DatabaseResource) {}

  async exportData(userId: string, generatedAt: Date): Promise<AccountExport> {
    return this.database.sql.begin(
      "isolation level repeatable read read only",
      async (sql) => {
        const [account] = await sql<JsonRow[]>`
          select
            id::text as "userId",
            status,
            created_at as "createdAt",
            updated_at as "updatedAt",
            last_login_at as "lastLoginAt"
          from app.users
          where id = ${userId}
            and status = 'active'
        `;
        if (account === undefined) {
          throw new AppError({
            code: "ACCOUNT_UNAVAILABLE",
            message: "This account is not available.",
            statusCode: 409,
          });
        }

        const identities = await sql<JsonRow[]>`
          select
            provider,
            provider_subject as "providerSubject",
            email,
            email_verified_at as "emailVerifiedAt",
            created_at as "createdAt",
            updated_at as "updatedAt"
          from app.user_identities
          where user_id = ${userId}
          order by created_at
        `;
        const sessions = await sql<JsonRow[]>`
          select
            id::text,
            device_id as "deviceId",
            platform,
            device_name as "deviceName",
            app_version as "appVersion",
            status,
            created_at as "createdAt",
            last_seen_at as "lastSeenAt",
            revoked_at as "revokedAt",
            revoke_reason as "revokeReason"
          from app.device_sessions
          where user_id = ${userId}
          order by created_at
        `;
        const [profile] = await sql<JsonRow[]>`
          select
            display_name as "displayName",
            difficulty,
            current_region_id as "currentRegionId",
            game_level as "gameLevel",
            experience_points as "experiencePoints",
            coins,
            friend_slot_limit as "friendSlotLimit",
            quiz_globally_enabled as "quizGloballyEnabled",
            has_completed_onboarding as "hasCompletedOnboarding",
            starter_region_id as "starterRegionId",
            version,
            created_at as "createdAt",
            updated_at as "updatedAt"
          from app.user_profiles
          where user_id = ${userId}
        `;
        const coinLedger = await sql<JsonRow[]>`
          select
            id::text,
            delta,
            balance_after as "balanceAfter",
            reason,
            reference_type as "referenceType",
            reference_id as "referenceId",
            created_at as "createdAt"
          from app.coin_ledger
          where user_id = ${userId}
          order by created_at, id
        `;
        const tickets = await sql<JsonRow[]>`
          select
            id::text,
            type,
            country_code as "countryCode",
            source,
            source_reference_id as "sourceReferenceId",
            status,
            consumed_at as "consumedAt",
            consumed_for_region_id as "consumedForRegionId",
            created_at as "createdAt"
          from app.inventory_items
          where user_id = ${userId}
          order by created_at, id
        `;
        const unlockedRegions = await sql<JsonRow[]>`
          select
            region_id as "regionId",
            source,
            unlocked_at as "unlockedAt"
          from app.region_unlocks
          where user_id = ${userId}
          order by unlocked_at, region_id
        `;
        const travelRecords = await sql<JsonRow[]>`
          select
            id::text,
            from_region_id as "fromRegionId",
            to_region_id as "toRegionId",
            ticket_item_id::text as "ticketItemId",
            traveled_at as "traveledAt"
          from app.travel_records
          where user_id = ${userId}
          order by traveled_at, id
        `;
        const transactions = await sql<JsonRow[]>`
          select
            provider,
            environment,
            transaction_id as "transactionId",
            original_transaction_id as "originalTransactionId",
            product_id as "productId",
            plan_id as "planId",
            purchased_at as "purchasedAt",
            expires_at as "expiresAt",
            revoked_at as "revokedAt",
            ownership_type as "ownershipType",
            verified_at as "verifiedAt"
          from app.billing_transactions
          where user_id = ${userId}
          order by purchased_at
        `;
        const subscriptions = await sql<JsonRow[]>`
          select
            provider,
            environment,
            original_transaction_id as "originalTransactionId",
            product_id as "productId",
            plan_id as "planId",
            latest_transaction_id as "latestTransactionId",
            status,
            auto_renew_enabled as "autoRenewEnabled",
            expires_at as "expiresAt",
            grace_period_expires_at as "gracePeriodExpiresAt",
            updated_at as "updatedAt"
          from app.subscriptions
          where user_id = ${userId}
          order by updated_at
        `;
        const entitlements = await sql<JsonRow[]>`
          select
            entitlement_key as "entitlementKey",
            plan_id as "planId",
            source_provider as "sourceProvider",
            environment,
            source_reference_id as "sourceReferenceId",
            status,
            valid_until as "validUntil",
            created_at as "createdAt",
            updated_at as "updatedAt"
          from app.entitlement_grants
          where user_id = ${userId}
          order by created_at
        `;
        const aiRequests = await sql<JsonRow[]>`
          select
            id::text,
            task,
            provider,
            model,
            config_version as "configVersion",
            status,
            input_characters as "inputCharacters",
            input_tokens as "inputTokens",
            output_tokens as "outputTokens",
            latency_ms as "latencyMs",
            error_code as "errorCode",
            requested_at as "requestedAt",
            completed_at as "completedAt"
          from app.ai_requests
          where user_id = ${userId}
          order by requested_at
        `;
        const syncChanges = await sql<JsonRow[]>`
          select
            sequence::text,
            event_id::text as "eventId",
            command_id::text as "commandId",
            event_type as "eventType",
            payload,
            occurred_at as "occurredAt"
          from app.sync_changes
          where user_id = ${userId}
          order by sequence
        `;
        const contentRecords = await sql<JsonRow[]>`
          select
            resource_type as "resourceType",
            resource_id as "resourceId",
            parent_id as "parentId",
            payload,
            version,
            created_at as "createdAt",
            updated_at as "updatedAt",
            deleted_at as "deletedAt"
          from app.content_records
          where user_id = ${userId}
          order by resource_type, resource_id
        `;
        const mediaAssets = await sql<JsonRow[]>`
          select
            id::text,
            purpose,
            content_type as "contentType",
            byte_size::text as "byteSize",
            checksum_sha256 as "checksumSha256",
            status,
            created_at as "createdAt",
            ready_at as "readyAt",
            deleted_at as "deletedAt"
          from app.media_assets
          where user_id = ${userId}
          order by created_at, id
        `;
        const securityEvents = await sql<JsonRow[]>`
          select
            event_type as "eventType",
            created_at as "createdAt"
          from app.auth_security_events
          where user_id = ${userId}
          order by created_at
        `;
        const auditEvents = await sql<JsonRow[]>`
          select
            request_id as "requestId",
            action,
            target_type as "targetType",
            outcome,
            created_at as "createdAt"
          from app.audit_events
          where actor_user_id = ${userId}
          order by created_at
        `;
        const deletionRequests = await sql<JsonRow[]>`
          select
            id::text,
            status,
            purge_at as "purgeAt",
            created_at as "createdAt",
            cancelled_at as "cancelledAt",
            completed_at as "completedAt"
          from app.account_deletion_requests
          where user_id = ${userId}
          order by created_at
        `;

        return {
          account,
          aiRequests,
          auditEvents,
          billing: {
            entitlements,
            subscriptions,
            transactions,
          },
          contentRecords,
          economy: {
            coinLedger,
            tickets,
          },
          generatedAt: generatedAt.toISOString(),
          identities,
          mediaAssets,
          privacy: {
            deletionRequests,
          },
          profile: profile ?? null,
          schemaVersion: 3,
          securityEvents,
          sessions,
          syncChanges,
          travel: {
            records: travelRecords,
            unlockedRegions,
          },
        };
      },
    );
  }

  async scheduleDeletion(parameters: ScheduleDeletionParameters): Promise<boolean> {
    return this.database.sql.begin(async (sql) => {
      const [user] = await sql<{ id: string }[]>`
        select id::text
        from app.users
        where id = ${parameters.userId}
          and status = 'active'
        for update
      `;
      if (user === undefined) {
        return false;
      }

      await sql`
        insert into app.account_deletion_requests (
          id,
          user_id,
          user_reference_hash,
          cancellation_token_hash,
          purge_at
        )
        values (
          ${parameters.requestId},
          ${parameters.userId},
          ${parameters.userReferenceHash},
          ${parameters.cancellationTokenHash},
          ${parameters.purgeAt.toISOString()}
        )
      `;
      await sql`
        update app.users
        set status = 'pending_deletion',
            token_version = token_version + 1,
            updated_at = now()
        where id = ${parameters.userId}
      `;
      await sql`
        update app.device_sessions
        set status = 'revoked',
            revoked_at = now(),
            revoke_reason = 'account_deletion',
            updated_at = now()
        where user_id = ${parameters.userId}
          and status = 'active'
      `;
      await sql`
        update app.refresh_tokens rt
        set revoked_at = now()
        from app.device_sessions ds
        where rt.session_id = ds.id
          and ds.user_id = ${parameters.userId}
          and rt.revoked_at is null
      `;
      await sql`
        update app.jobs
        set status = 'cancelled',
            completed_at = now(),
            updated_at = now()
        where user_id = ${parameters.userId}
          and status = 'pending'
          and type in ('auth.email_verification', 'auth.password_reset')
      `;
      await insertPreparedJob(sql, parameters.job);
      return true;
    });
  }

  async cancelDeletion(tokenHash: string, now: Date): Promise<boolean> {
    return this.database.sql.begin(async (sql) => {
      const [request] = await sql<{ id: string; user_id: string }[]>`
        select id::text, user_id::text
        from app.account_deletion_requests
        where cancellation_token_hash = ${tokenHash}
          and status = 'scheduled'
          and purge_at > ${now.toISOString()}
          and user_id is not null
        for update
      `;
      if (request === undefined) {
        return false;
      }
      const users = await sql<{ id: string }[]>`
        update app.users
        set status = 'active',
            updated_at = ${now.toISOString()}
        where id = ${request.user_id}
          and status = 'pending_deletion'
        returning id::text
      `;
      if (users.length !== 1) {
        return false;
      }
      await sql`
        update app.account_deletion_requests
        set status = 'cancelled',
            cancellation_token_hash = null,
            cancelled_at = ${now.toISOString()},
            updated_at = ${now.toISOString()}
        where id = ${request.id}
      `;
      await sql`
        update app.jobs
        set status = 'cancelled',
            completed_at = ${now.toISOString()},
            updated_at = ${now.toISOString()}
        where unique_key = ${`account-deletion:${request.id}`}
          and status = 'pending'
      `;
      return true;
    });
  }

  async beginDeletion(
    requestId: string,
    userId: string,
    now: Date,
  ): Promise<DeletionWork | undefined> {
    return this.database.sql.begin(async (sql) => {
      const [request] = await sql<{ id: string }[]>`
        select d.id::text
        from app.account_deletion_requests d
        join app.users u on u.id = d.user_id
        where d.id = ${requestId}
          and d.user_id = ${userId}
          and d.status in ('scheduled', 'processing')
          and d.purge_at <= ${now.toISOString()}
          and u.status = 'pending_deletion'
        for update of d, u
      `;
      if (request === undefined) {
        return undefined;
      }
      await sql`
        update app.account_deletion_requests
        set status = 'processing',
            cancellation_token_hash = null,
            updated_at = ${now.toISOString()}
        where id = ${requestId}
      `;
      const rows = await sql<
        {
          ciphertext: Buffer;
          key_version: string;
          nonce: Buffer;
          provider_client_id: string | null;
          tag: Buffer;
        }[]
      >`
        select
          c.ciphertext,
          c.nonce,
          c.tag,
          c.key_version,
          c.provider_client_id
        from app.identity_provider_credentials c
        join app.user_identities i on i.id = c.identity_id
        where i.user_id = ${userId}
          and i.provider = 'apple'
      `;
      const appleCredentials: AppleDeletionCredential[] = rows.map((row) => ({
        clientId: row.provider_client_id,
        credential: {
          ciphertext: row.ciphertext,
          keyVersion: row.key_version,
          nonce: row.nonce,
          tag: row.tag,
        },
      }));
      const mediaRows = await sql<{ object_key: string }[]>`
        select object_key
        from app.media_assets
        where user_id = ${userId}
          and purged_at is null
        order by id
      `;
      return {
        appleCredentials,
        mediaObjectKeys: mediaRows.map((row) => row.object_key),
        requestId,
        userId,
      };
    });
  }

  async finalizeDeletion(
    requestId: string,
    userId: string,
    now: Date,
  ): Promise<boolean> {
    return this.database.sql.begin(async (sql) => {
      const [request] = await sql<{ id: string }[]>`
        select id::text
        from app.account_deletion_requests
        where id = ${requestId}
          and user_id = ${userId}
          and status = 'processing'
        for update
      `;
      if (request === undefined) {
        return false;
      }

      await sql`
        update app.billing_transactions
        set app_account_token = null,
            raw_payload = '{"redacted":true}'::jsonb,
            updated_at = ${now.toISOString()}
        where user_id = ${userId}
      `;
      await sql`
        update app.billing_provider_events
        set decoded_payload = '{"redacted":true}'::jsonb,
            processing_error = null,
            user_id = null
        where user_id = ${userId}
      `;
      await sql`
        update app.auth_security_events
        set user_id = null,
            session_id = null,
            ip_hash = null,
            metadata = '{}'::jsonb
        where user_id = ${userId}
      `;
      await sql`
        update app.audit_events
        set actor_user_id = null,
            ip_hash = null,
            metadata = '{}'::jsonb,
            target_id = null
        where actor_user_id = ${userId}
      `;
      await sql`
        delete from app.jobs
        where user_id = ${userId}
          and unique_key is distinct from ${`account-deletion:${requestId}`}
      `;
      const deleted = await sql<{ id: string }[]>`
        delete from app.users
        where id = ${userId}
          and status = 'pending_deletion'
        returning id::text
      `;
      if (deleted.length !== 1) {
        return false;
      }
      await sql`
        update app.account_deletion_requests
        set status = 'completed',
            user_id = null,
            cancellation_token_hash = null,
            completed_at = ${now.toISOString()},
            updated_at = ${now.toISOString()}
        where id = ${requestId}
      `;
      return true;
    });
  }
}
