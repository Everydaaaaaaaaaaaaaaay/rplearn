import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { newEntityId } from "../../shared/id.js";
import { appendSyncChange } from "../../infrastructure/sync-change-writer.js";
import {
  effectiveUntil,
  parseFeatureFlags,
  type AppliedState,
  type GrantRow,
  type PlanRow,
} from "./repository-helpers.js";
import {
  activeBillingUserExists,
  findUserForOriginalTransaction,
} from "./repository-queries.js";
import type {
  BillingProduct,
  EntitlementSnapshot,
  EntitlementStatus,
  StoreEnvironment,
  SubscriptionReconciliationClaim,
  SubscriptionTier,
  VerifiedRenewalInfo,
  VerifiedSubscriptionStatus,
  VerifiedStoreNotification,
  VerifiedStoreTransaction,
} from "./types.js";

export class BillingRepository {
  constructor(private readonly database: DatabaseResource) {}

  async listProducts(): Promise<readonly BillingProduct[]> {
    const rows = await this.database.sql<
      {
        feature_flags_text: string;
        plan_id: string;
        product_id: string;
        provider: "apple" | "google_play" | "stripe";
        tier: SubscriptionTier;
      }[]
    >`
      select
        p.id as plan_id,
        p.tier,
        p.feature_flags::text as feature_flags_text,
        sp.provider,
        sp.product_id
      from app.store_products sp
      join app.billing_plans p on p.id = sp.plan_id
      where sp.is_active = true
        and p.is_active = true
        and sp.provider <> 'manual'
      order by p.rank, sp.provider, sp.product_id
    `;
    return rows.map((row) => ({
      featureFlags: parseFeatureFlags(row.feature_flags_text),
      planId: row.plan_id,
      productId: row.product_id,
      provider: row.provider,
      tier: row.tier,
    }));
  }

  async entitlements(userId: string): Promise<EntitlementSnapshot> {
    const rows = await this.database.sql<(GrantRow & PlanRow)[]>`
      select
        g.entitlement_key,
        g.source_provider as provider,
        g.status,
        g.valid_until,
        p.id,
        p.rank,
        p.tier,
        p.feature_flags::text as feature_flags_text
      from app.entitlement_grants g
      join app.billing_plans p on p.id = g.plan_id
      where g.user_id = ${userId}
        and g.status in ('active', 'grace')
        and (g.valid_until is null or g.valid_until > now())
        and p.is_active = true
      order by p.rank desc, g.valid_until desc nulls first
    `;
    const [freePlan] = await this.database.sql<PlanRow[]>`
      select
        id,
        rank,
        tier,
        feature_flags::text as feature_flags_text
      from app.billing_plans
      where tier = 'free'
        and is_active = true
    `;
    if (freePlan === undefined) {
      throw new Error("The free billing plan is not configured");
    }
    const effectivePlan = rows[0] ?? freePlan;
    return {
      entitlements: rows.map((row) => ({
        entitlementKey: row.entitlement_key,
        provider: row.provider,
        status: row.status,
        validUntil:
          row.valid_until === null ? null : new Date(row.valid_until).toISOString(),
      })),
      featureFlags: parseFeatureFlags(effectivePlan.feature_flags_text),
      tier: effectivePlan.tier,
    };
  }

  async userForOriginalTransaction(
    environment: StoreEnvironment,
    originalTransactionId: string,
  ): Promise<string | undefined> {
    return findUserForOriginalTransaction(
      this.database,
      environment,
      originalTransactionId,
    );
  }

  async userExists(userId: string): Promise<boolean> {
    return activeBillingUserExists(this.database, userId);
  }

  private async applyVerifiedState(
    sql: TransactionSql,
    userId: string,
    transaction: VerifiedStoreTransaction,
    renewal: VerifiedRenewalInfo | undefined,
    status: EntitlementStatus,
    providerStatus: number | undefined,
  ): Promise<AppliedState> {
    const [plan] = await sql<Pick<PlanRow, "id" | "tier">[]>`
      select p.id, p.tier
      from app.store_products sp
      join app.billing_plans p on p.id = sp.plan_id
      where sp.provider = 'apple'
        and sp.product_id = ${transaction.productId}
        and sp.is_active = true
        and p.is_active = true
    `;
    if (plan === undefined) {
      throw new AppError({
        code: "BILLING_PRODUCT_UNKNOWN",
        message: "The verified store product is not configured.",
        statusCode: 409,
      });
    }

    const [existingTransaction] = await sql<{ user_id: string | null }[]>`
      select user_id::text
      from app.billing_transactions
      where provider = 'apple'
        and environment = ${transaction.environment}::app.billing_environment
        and transaction_id = ${transaction.transactionId}
      for update
    `;
    if (existingTransaction !== undefined && existingTransaction.user_id !== userId) {
      throw new AppError({
        code: "BILLING_TRANSACTION_OWNERSHIP_CONFLICT",
        expose: false,
        message: "The transaction is already assigned to another account.",
        statusCode: 409,
      });
    }

    const [existingSubscription] = await sql<
      {
        provider_event_at: string;
        user_id: string | null;
      }[]
    >`
      select user_id::text, provider_event_at
      from app.subscriptions
      where provider = 'apple'
        and environment = ${transaction.environment}::app.billing_environment
        and original_transaction_id = ${transaction.originalTransactionId}
      for update
    `;
    if (existingSubscription !== undefined && existingSubscription.user_id !== userId) {
      throw new AppError({
        code: "BILLING_SUBSCRIPTION_OWNERSHIP_CONFLICT",
        expose: false,
        message: "The subscription is already assigned to another account.",
        statusCode: 409,
      });
    }

    await sql`
      insert into app.billing_transactions (
        id,
        provider,
        environment,
        transaction_id,
        original_transaction_id,
        user_id,
        app_account_token,
        product_id,
        plan_id,
        purchased_at,
        expires_at,
        revoked_at,
        signed_at,
        ownership_type,
        raw_payload
      )
      values (
        ${newEntityId()},
        'apple',
        ${transaction.environment}::app.billing_environment,
        ${transaction.transactionId},
        ${transaction.originalTransactionId},
        ${userId},
        ${transaction.appAccountToken ?? null},
        ${transaction.productId},
        ${plan.id},
        ${transaction.purchasedAt.toISOString()},
        ${transaction.expiresAt?.toISOString() ?? null},
        ${transaction.revokedAt?.toISOString() ?? null},
        ${transaction.signedAt.toISOString()},
        ${transaction.ownershipType ?? null},
        ${JSON.stringify(transaction.rawPayload)}::jsonb
      )
      on conflict (provider, environment, transaction_id) do update
      set product_id = excluded.product_id,
          plan_id = excluded.plan_id,
          expires_at = excluded.expires_at,
          revoked_at = excluded.revoked_at,
          signed_at = excluded.signed_at,
          ownership_type = excluded.ownership_type,
          raw_payload = excluded.raw_payload,
          verified_at = now(),
          updated_at = now()
      where app.billing_transactions.user_id = excluded.user_id
        and excluded.signed_at >= app.billing_transactions.signed_at
    `;

    const validUntil = effectiveUntil(transaction, renewal, status);
    const [subscription] = await sql<{ id: string }[]>`
      insert into app.subscriptions (
        id,
        provider,
        environment,
        original_transaction_id,
        user_id,
        product_id,
        plan_id,
        latest_transaction_id,
        status,
        provider_status,
        auto_renew_enabled,
        expires_at,
        grace_period_expires_at,
        provider_event_at
      )
      values (
        ${newEntityId()},
        'apple',
        ${transaction.environment}::app.billing_environment,
        ${transaction.originalTransactionId},
        ${userId},
        ${transaction.productId},
        ${plan.id},
        ${transaction.transactionId},
        ${status}::app.entitlement_status,
        ${providerStatus ?? null},
        ${renewal?.autoRenewEnabled ?? null},
        ${transaction.expiresAt?.toISOString() ?? null},
        ${renewal?.gracePeriodExpiresAt?.toISOString() ?? null},
        ${transaction.signedAt.toISOString()}
      )
      on conflict (provider, environment, original_transaction_id) do update
      set product_id = excluded.product_id,
          plan_id = excluded.plan_id,
          latest_transaction_id = excluded.latest_transaction_id,
          status = excluded.status,
          provider_status = excluded.provider_status,
          auto_renew_enabled = excluded.auto_renew_enabled,
          expires_at = excluded.expires_at,
          grace_period_expires_at = excluded.grace_period_expires_at,
          provider_event_at = excluded.provider_event_at,
          updated_at = now()
      where excluded.provider_event_at > app.subscriptions.provider_event_at
      returning id::text
    `;

    if (subscription !== undefined) {
      await sql`
        insert into app.entitlement_grants (
          id,
          user_id,
          entitlement_key,
          plan_id,
          source_provider,
          environment,
          source_reference_id,
          status,
          valid_until,
          provider_event_at
        )
        values (
          ${newEntityId()},
          ${userId},
          'subscription',
          ${plan.id},
          'apple',
          ${transaction.environment}::app.billing_environment,
          ${transaction.originalTransactionId},
          ${status}::app.entitlement_status,
          ${validUntil?.toISOString() ?? null},
          ${transaction.signedAt.toISOString()}
        )
        on conflict (
          source_provider,
          environment,
          source_reference_id,
          entitlement_key
        ) do update
        set plan_id = excluded.plan_id,
            status = excluded.status,
            valid_until = excluded.valid_until,
            provider_event_at = excluded.provider_event_at,
            updated_at = now()
        where excluded.provider_event_at >
          app.entitlement_grants.provider_event_at
      `;
    }

    return {
      changed: subscription !== undefined,
      planId: plan.id,
      status,
      tier: plan.tier,
      validUntil,
    };
  }

  async ingestTransaction(
    userId: string,
    commandId: string,
    requestHash: string,
    transaction: VerifiedStoreTransaction,
    status: EntitlementStatus,
  ): Promise<EntitlementSnapshot> {
    const result = await this.database.sql.begin(async (sql) => {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`${userId}:${commandId}`}, 0)
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
          and command_id = ${commandId}
      `;
      if (receipt !== undefined) {
        if (
          receipt.request_hash !== requestHash ||
          receipt.route !== "billing.appleTransaction"
        ) {
          throw new AppError({
            code: "IDEMPOTENCY_KEY_CONFLICT",
            message: "This idempotency key was already used for a different request.",
            statusCode: 409,
          });
        }
        return JSON.parse(receipt.response_text) as EntitlementSnapshot;
      }

      const applied = await this.applyVerifiedState(
        sql,
        userId,
        transaction,
        undefined,
        status,
        undefined,
      );
      if (applied.changed) {
        await appendSyncChange(sql, {
          commandId,
          eventType: "billing.entitlementsUpdated",
          payload: {
            planId: applied.planId,
            status: applied.status,
            tier: applied.tier,
            validUntil: applied.validUntil?.toISOString() ?? null,
          },
          userId,
        });
      }
      const rows = await sql<(GrantRow & PlanRow)[]>`
        select
          g.entitlement_key,
          g.source_provider as provider,
          g.status,
          g.valid_until,
          p.id,
          p.rank,
          p.tier,
          p.feature_flags::text as feature_flags_text
        from app.entitlement_grants g
        join app.billing_plans p on p.id = g.plan_id
        where g.user_id = ${userId}
          and g.status in ('active', 'grace')
          and (g.valid_until is null or g.valid_until > now())
          and p.is_active = true
        order by p.rank desc, g.valid_until desc nulls first
      `;
      const [freePlan] = await sql<PlanRow[]>`
        select
          id,
          rank,
          tier,
          feature_flags::text as feature_flags_text
        from app.billing_plans
        where tier = 'free'
          and is_active = true
      `;
      if (freePlan === undefined) {
        throw new Error("The free billing plan is not configured");
      }
      const effectivePlan = rows[0] ?? freePlan;
      const response: EntitlementSnapshot = {
        entitlements: rows.map((row) => ({
          entitlementKey: row.entitlement_key,
          provider: row.provider,
          status: row.status,
          validUntil:
            row.valid_until === null ? null : new Date(row.valid_until).toISOString(),
        })),
        featureFlags: parseFeatureFlags(effectivePlan.feature_flags_text),
        tier: effectivePlan.tier,
      };
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
          ${commandId},
          'billing.appleTransaction',
          ${requestHash},
          ${JSON.stringify(response)}::jsonb
        )
      `;
      return response;
    });
    return result;
  }

  async ingestNotification(
    notification: VerifiedStoreNotification,
    userId: string | undefined,
    status: EntitlementStatus | undefined,
  ): Promise<void> {
    await this.database.sql.begin(async (sql) => {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(
            ${`apple:${notification.environment}:${notification.eventId}`},
            0
          )
        )
      `;
      const [existing] = await sql<{ payload_hash: string }[]>`
        select payload_hash
        from app.billing_provider_events
        where provider = 'apple'
          and environment =
            ${notification.environment}::app.billing_environment
          and event_id = ${notification.eventId}
      `;
      if (existing !== undefined) {
        if (existing.payload_hash !== notification.payloadHash) {
          throw new AppError({
            code: "BILLING_EVENT_ID_CONFLICT",
            expose: false,
            message: "A provider event ID was reused with another payload.",
            statusCode: 409,
          });
        }
        return;
      }

      await sql`
        insert into app.billing_provider_events (
          provider,
          environment,
          event_id,
          event_type,
          subtype,
          payload_hash,
          decoded_payload,
          signed_at,
          user_id
        )
        values (
          'apple',
          ${notification.environment}::app.billing_environment,
          ${notification.eventId},
          ${notification.eventType},
          ${notification.subtype ?? null},
          ${notification.payloadHash},
          ${JSON.stringify(notification.decodedPayload)}::jsonb,
          ${notification.signedAt.toISOString()},
          ${userId ?? null}
        )
      `;

      if (notification.transaction === undefined) {
        await sql`
          update app.billing_provider_events
          set processed_at = now(),
              processing_error = null
          where provider = 'apple'
            and environment =
              ${notification.environment}::app.billing_environment
            and event_id = ${notification.eventId}
        `;
        return;
      }

      if (userId === undefined || status === undefined) {
        await sql`
          update app.billing_provider_events
          set processing_error = 'UNBOUND_APP_ACCOUNT_TOKEN'
          where provider = 'apple'
            and environment =
              ${notification.environment}::app.billing_environment
            and event_id = ${notification.eventId}
        `;
        return;
      }

      try {
        const applied = await this.applyVerifiedState(
          sql,
          userId,
          notification.transaction,
          notification.renewal,
          status,
          notification.providerStatus,
        );
        if (applied.changed) {
          await appendSyncChange(sql, {
            commandId: newEntityId(),
            eventType: "billing.entitlementsUpdated",
            payload: {
              planId: applied.planId,
              status: applied.status,
              tier: applied.tier,
              validUntil: applied.validUntil?.toISOString() ?? null,
            },
            userId,
          });
        }
        await sql`
          update app.billing_provider_events
          set processed_at = now(),
              processing_error = null
          where provider = 'apple'
            and environment =
              ${notification.environment}::app.billing_environment
            and event_id = ${notification.eventId}
        `;
      } catch (error) {
        if (!(error instanceof AppError)) {
          throw error;
        }
        await sql`
          update app.billing_provider_events
          set processing_error = ${error.code}
          where provider = 'apple'
            and environment =
              ${notification.environment}::app.billing_environment
            and event_id = ${notification.eventId}
        `;
      }
    });
  }

  async claimSubscriptionsForReconciliation(
    limit: number,
    now: Date,
    leaseUntil: Date,
  ): Promise<readonly SubscriptionReconciliationClaim[]> {
    const rows = await this.database.sql<
      {
        environment: "production" | "sandbox";
        latest_transaction_id: string;
        original_transaction_id: string;
        reconciliation_attempts: number;
        status: EntitlementStatus;
        user_id: string;
      }[]
    >`
      with candidates as (
        select id
        from app.subscriptions
        where provider = 'apple'
          and environment in ('production', 'sandbox')
          and user_id is not null
          and reconcile_after <= ${now.toISOString()}
        order by reconcile_after asc, updated_at asc
        for update skip locked
        limit ${limit}
      )
      update app.subscriptions s
      set reconciliation_started_at = ${now.toISOString()},
          reconciliation_attempts = s.reconciliation_attempts + 1,
          reconcile_after = ${leaseUntil.toISOString()},
          updated_at = now()
      from candidates
      where s.id = candidates.id
      returning
        s.user_id::text,
        s.environment,
        s.original_transaction_id,
        s.latest_transaction_id,
        s.status,
        s.reconciliation_attempts
    `;
    return rows.map((row) => ({
      attempts: row.reconciliation_attempts,
      environment: row.environment,
      latestTransactionId: row.latest_transaction_id,
      originalTransactionId: row.original_transaction_id,
      startedAt: now,
      status: row.status,
      userId: row.user_id,
    }));
  }

  async completeSubscriptionReconciliation(
    claim: SubscriptionReconciliationClaim,
    verified: VerifiedSubscriptionStatus,
    status: EntitlementStatus,
    reconciledAt: Date,
    nextReconcileAt: Date,
  ): Promise<boolean> {
    return this.database.sql.begin(async (sql) => {
      const applied = await this.applyVerifiedState(
        sql,
        claim.userId,
        verified.transaction,
        verified.renewal,
        status,
        verified.providerStatus,
      );
      if (applied.changed) {
        await appendSyncChange(sql, {
          commandId: newEntityId(),
          eventType: "billing.entitlementsUpdated",
          payload: {
            planId: applied.planId,
            status: applied.status,
            tier: applied.tier,
            validUntil: applied.validUntil?.toISOString() ?? null,
          },
          userId: claim.userId,
        });
      }
      const rows = await sql<{ id: string }[]>`
        update app.subscriptions
        set last_reconciled_at = ${reconciledAt.toISOString()},
            reconciliation_started_at = null,
            reconciliation_attempts = 0,
            reconciliation_error = null,
            reconcile_after = ${nextReconcileAt.toISOString()},
            updated_at = now()
        where provider = 'apple'
          and environment =
            ${claim.environment}::app.billing_environment
          and original_transaction_id = ${claim.originalTransactionId}
          and user_id = ${claim.userId}
          and reconciliation_started_at = ${claim.startedAt.toISOString()}
        returning id::text
      `;
      return rows.length === 1;
    });
  }

  async failSubscriptionReconciliation(
    claim: SubscriptionReconciliationClaim,
    errorCode: string,
    retryAt: Date,
  ): Promise<boolean> {
    const rows = await this.database.sql<{ id: string }[]>`
      update app.subscriptions
      set reconciliation_started_at = null,
          reconciliation_error = ${errorCode.slice(0, 100)},
          reconcile_after = ${retryAt.toISOString()},
          updated_at = now()
      where provider = 'apple'
        and environment =
          ${claim.environment}::app.billing_environment
        and original_transaction_id = ${claim.originalTransactionId}
        and user_id = ${claim.userId}
        and reconciliation_started_at = ${claim.startedAt.toISOString()}
      returning id::text
    `;
    return rows.length === 1;
  }

  async grantDebugEntitlement(
    userId: string,
    commandId: string,
    tier: Exclude<SubscriptionTier, "free">,
    durationDays: number,
  ): Promise<EntitlementSnapshot> {
    await this.database.sql.begin(async (sql) => {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`debug-billing:${userId}:${commandId}`}, 0)
        )
      `;
      const [existing] = await sql<{ present: boolean }[]>`
        select exists (
          select 1
          from app.entitlement_grants
          where source_provider = 'manual'
            and environment = 'test'
            and source_reference_id = ${commandId}
            and entitlement_key = 'subscription'
        ) as present
      `;
      if (existing?.present === true) {
        return;
      }
      const [plan] = await sql<Pick<PlanRow, "id" | "tier">[]>`
        select id, tier
        from app.billing_plans
        where tier = ${tier}::app.subscription_tier
          and is_active = true
      `;
      if (plan === undefined) {
        throw new Error("The requested debug billing plan is not configured");
      }
      const validUntil = new Date(Date.now() + durationDays * 24 * 60 * 60 * 1000);
      await sql`
        insert into app.entitlement_grants (
          id,
          user_id,
          entitlement_key,
          plan_id,
          source_provider,
          environment,
          source_reference_id,
          status,
          valid_until,
          provider_event_at
        )
        values (
          ${newEntityId()},
          ${userId},
          'subscription',
          ${plan.id},
          'manual',
          'test',
          ${commandId},
          'active',
          ${validUntil.toISOString()},
          now()
        )
      `;
      await appendSyncChange(sql, {
        commandId,
        eventType: "billing.entitlementsUpdated",
        payload: {
          planId: plan.id,
          status: "active",
          tier: plan.tier,
          validUntil: validUntil.toISOString(),
        },
        userId,
      });
    });
    return this.entitlements(userId);
  }
}
