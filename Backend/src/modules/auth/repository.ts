import type { DatabaseResource } from "../../db/client.js";
import { newEntityId } from "../../shared/id.js";
import { insertPreparedJob } from "../jobs/transactional-enqueue.js";
import type { PreparedJob } from "../jobs/types.js";
import type {
  AuthActionType,
  SealedProviderCredential,
  SessionPlatform,
  SessionSummary,
} from "./types.js";
import type {
  ActionTokenParameters,
  CreateEmailAccountParameters,
  CreateSessionParameters,
  EmailAccount,
  FederatedAccount,
  FederatedIdentityProvider,
  RotateParameters,
  RotationResult,
} from "./repository-types.js";

function hasPostgresCode(error: unknown, code: string): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === code
  );
}

export class AuthRepository {
  constructor(private readonly resource: DatabaseResource) {}

  async isGuest(userId: string): Promise<boolean> {
    const [row] = await this.resource.sql<{ found: boolean }[]>`
      select exists(select 1 from app.guest_installations where user_id = ${userId}) as found
    `;
    return row?.found === true;
  }

  async findEmailAccount(email: string): Promise<EmailAccount | undefined> {
    const [row] = await this.resource.sql<
      {
        email: string;
        email_verified_at: string | null;
        password_hash: string | null;
        status: EmailAccount["status"];
        token_version: number;
        user_id: string;
      }[]
    >`
      select
        i.email,
        i.email_verified_at,
        i.password_hash,
        u.status,
        u.token_version,
        u.id::text as user_id
      from app.user_identities i
      join app.users u on u.id = i.user_id
      where i.provider = 'email'
        and i.provider_subject = ${email}
      limit 1
    `;

    if (row?.password_hash === null || row === undefined) {
      return undefined;
    }

    return {
      email: row.email,
      emailVerifiedAt:
        row.email_verified_at === null ? null : new Date(row.email_verified_at),
      passwordHash: row.password_hash,
      status: row.status,
      tokenVersion: row.token_version,
      userId: row.user_id,
    };
  }

  async createEmailAccount(
    parameters: CreateEmailAccountParameters,
  ): Promise<"created" | "exists"> {
    try {
      await this.resource.sql.begin(async (sql) => {
        await sql`
          insert into app.users (id)
          values (${parameters.userId})
        `;
        await sql`
          insert into app.user_identities (
            id,
            user_id,
            provider,
            provider_subject,
            email,
            password_hash
          )
          values (
            ${parameters.identityId},
            ${parameters.userId},
            'email',
            ${parameters.email},
            ${parameters.email},
            ${parameters.passwordHash}
          )
        `;
        await sql`
          insert into app.auth_action_tokens (
            id,
            user_id,
            type,
            token_hash,
            expires_at
          )
          values (
            ${parameters.actionToken.id},
            ${parameters.userId},
            'email_verification',
            ${parameters.actionToken.tokenHash},
            ${parameters.actionToken.expiresAt.toISOString()}
          )
        `;
        await insertPreparedJob(sql, parameters.notificationJob);
      });
      return "created";
    } catch (error) {
      if (hasPostgresCode(error, "23505")) {
        return "exists";
      }
      throw error;
    }
  }

  async issueActionTokenForEmail(
    email: string,
    type: AuthActionType,
    actionToken: ActionTokenParameters,
    notificationJob: PreparedJob,
  ): Promise<boolean> {
    return this.resource.sql.begin(async (sql) => {
      const [account] = await sql<
        {
          email: string;
          email_verified_at: string | null;
          status: EmailAccount["status"];
          user_id: string;
        }[]
      >`
        select
          i.email,
          i.email_verified_at,
          u.id::text as user_id,
          u.status
        from app.user_identities i
        join app.users u on u.id = i.user_id
        where i.provider = 'email'
          and i.provider_subject = ${email}
        for update of i, u
      `;

      if (
        account?.status !== "active" ||
        (type === "email_verification" && account.email_verified_at !== null) ||
        (type === "password_reset" && account.email_verified_at === null)
      ) {
        return false;
      }

      await sql`
        update app.auth_action_tokens
        set consumed_at = now()
        where user_id = ${account.user_id}
          and type = ${type}
          and consumed_at is null
      `;
      await sql`
        insert into app.auth_action_tokens (
          id,
          user_id,
          type,
          token_hash,
          expires_at
        )
        values (
          ${actionToken.id},
          ${account.user_id},
          ${type},
          ${actionToken.tokenHash},
          ${actionToken.expiresAt.toISOString()}
        )
      `;
      await insertPreparedJob(sql, {
        ...notificationJob,
        userId: account.user_id,
      });

      return true;
    });
  }

  async verifyEmail(tokenHash: string, now: Date): Promise<boolean> {
    return this.resource.sql.begin(async (sql) => {
      const timestamp = now.toISOString();
      const [token] = await sql<{ id: string; user_id: string }[]>`
        select id::text, user_id::text
        from app.auth_action_tokens
        where token_hash = ${tokenHash}
          and type = 'email_verification'
          and consumed_at is null
          and expires_at > ${timestamp}
        for update
      `;
      if (token === undefined) {
        return false;
      }

      await sql`
        update app.user_identities
        set email_verified_at = coalesce(email_verified_at, ${timestamp}),
            updated_at = ${timestamp}
        where user_id = ${token.user_id}
          and provider = 'email'
      `;
      await sql`
        update app.auth_action_tokens
        set consumed_at = ${timestamp}
        where id = ${token.id}
      `;
      return true;
    });
  }

  async resetPassword(
    tokenHash: string,
    passwordHash: string,
    now: Date,
  ): Promise<boolean> {
    return this.resource.sql.begin(async (sql) => {
      const timestamp = now.toISOString();
      const [token] = await sql<{ id: string; user_id: string }[]>`
        select id::text, user_id::text
        from app.auth_action_tokens
        where token_hash = ${tokenHash}
          and type = 'password_reset'
          and consumed_at is null
          and expires_at > ${timestamp}
        for update
      `;
      if (token === undefined) {
        return false;
      }

      await sql`
        update app.user_identities
        set password_hash = ${passwordHash},
            updated_at = ${timestamp}
        where user_id = ${token.user_id}
          and provider = 'email'
      `;
      await sql`
        update app.users
        set token_version = token_version + 1,
            updated_at = ${timestamp}
        where id = ${token.user_id}
      `;
      await sql`
        update app.device_sessions
        set status = 'revoked',
            revoked_at = ${timestamp},
            revoke_reason = 'password_reset',
            updated_at = ${timestamp}
        where user_id = ${token.user_id}
          and status = 'active'
      `;
      await sql`
        update app.refresh_tokens rt
        set revoked_at = ${timestamp}
        from app.device_sessions ds
        where rt.session_id = ds.id
          and ds.user_id = ${token.user_id}
          and rt.revoked_at is null
      `;
      await sql`
        update app.auth_action_tokens
        set consumed_at = ${timestamp}
        where id = ${token.id}
      `;
      return true;
    });
  }

  async createSession(parameters: CreateSessionParameters): Promise<void> {
    await this.resource.sql.begin(async (sql) => {
      const revokedSessions = await sql<{ id: string }[]>`
        update app.device_sessions
        set status = 'revoked',
            revoked_at = now(),
            revoke_reason = 'replaced_on_login',
            updated_at = now()
        where user_id = ${parameters.userId}
          and device_id = ${parameters.device.deviceId}
          and status = 'active'
        returning id::text
      `;
      const revokedSessionIds = revokedSessions.map((session) => session.id);
      if (revokedSessionIds.length > 0) {
        await sql`
          update app.refresh_tokens
          set revoked_at = now()
          where session_id in ${sql(revokedSessionIds)}
            and revoked_at is null
        `;
      }

      await sql`
        insert into app.device_sessions (
          id,
          user_id,
          token_family_id,
          device_id,
          platform,
          device_name,
          app_version,
          ip_hash,
          user_agent_hash
        )
        values (
          ${parameters.sessionId},
          ${parameters.userId},
          ${parameters.familyId},
          ${parameters.device.deviceId},
          ${parameters.device.platform},
          ${parameters.device.deviceName ?? null},
          ${parameters.device.appVersion ?? null},
          ${parameters.metadata.ipHash ?? null},
          ${parameters.metadata.userAgentHash ?? null}
        )
      `;
      await sql`
        insert into app.refresh_tokens (
          id,
          session_id,
          family_id,
          token_hash,
          expires_at
        )
        values (
          ${parameters.refreshToken.id},
          ${parameters.sessionId},
          ${parameters.familyId},
          ${parameters.refreshToken.hash},
          ${parameters.refreshToken.expiresAt.toISOString()}
        )
      `;
      await sql`
        update app.users
        set last_login_at = now(),
            updated_at = now()
        where id = ${parameters.userId}
      `;
    });
  }

  async rotateRefreshToken(parameters: RotateParameters): Promise<RotationResult> {
    return this.resource.sql.begin(async (sql) => {
      const timestamp = parameters.now.toISOString();
      const [token] = await sql<
        {
          expires_at: string;
          family_id: string;
          revoked_at: string | null;
          session_id: string;
          session_status: "active" | "revoked" | "compromised";
          token_version: number;
          used_at: string | null;
          user_id: string;
          user_status: EmailAccount["status"];
        }[]
      >`
        select
          rt.expires_at,
          rt.family_id::text,
          rt.revoked_at,
          rt.session_id::text,
          rt.used_at,
          ds.status as session_status,
          u.id::text as user_id,
          u.status as user_status,
          u.token_version
        from app.refresh_tokens rt
        join app.device_sessions ds on ds.id = rt.session_id
        join app.users u on u.id = ds.user_id
        where rt.token_hash = ${parameters.currentTokenHash}
        for update of rt, ds
      `;

      if (token === undefined) {
        return { status: "invalid" };
      }

      if (token.used_at !== null) {
        await sql`
          update app.refresh_tokens
          set revoked_at = coalesce(revoked_at, ${timestamp})
          where family_id = ${token.family_id}
        `;
        await sql`
          update app.device_sessions
          set status = 'compromised',
              revoked_at = coalesce(revoked_at, ${timestamp}),
              revoke_reason = 'refresh_token_reuse',
              updated_at = ${timestamp}
          where id = ${token.session_id}
        `;
        await sql`
          insert into app.auth_security_events (
            id,
            user_id,
            session_id,
            event_type,
            metadata
          )
          values (
            ${newEntityId()},
            ${token.user_id},
            ${token.session_id},
            'refresh_token_reuse',
            ${JSON.stringify({ familyId: token.family_id })}::jsonb
          )
        `;
        return { status: "reuse_detected" };
      }

      if (
        token.revoked_at !== null ||
        new Date(token.expires_at) <= parameters.now ||
        token.session_status !== "active" ||
        token.user_status !== "active"
      ) {
        return { status: "invalid" };
      }

      await sql`
        update app.refresh_tokens
        set used_at = ${timestamp},
            replaced_by_token_id = ${parameters.nextToken.id}
        where token_hash = ${parameters.currentTokenHash}
      `;
      await sql`
        insert into app.refresh_tokens (
          id,
          session_id,
          family_id,
          token_hash,
          expires_at
        )
        values (
          ${parameters.nextToken.id},
          ${token.session_id},
          ${token.family_id},
          ${parameters.nextToken.hash},
          ${parameters.nextToken.expiresAt.toISOString()}
        )
      `;
      await sql`
        update app.device_sessions
        set last_seen_at = ${timestamp},
            updated_at = ${timestamp}
        where id = ${token.session_id}
      `;

      return {
        sessionId: token.session_id,
        status: "rotated",
        tokenVersion: token.token_version,
        userId: token.user_id,
      };
    });
  }

  async assertAccessIdentity(
    userId: string,
    sessionId: string,
    tokenVersion: number,
  ): Promise<boolean> {
    const [row] = await this.resource.sql<{ valid: boolean }[]>`
      select exists (
        select 1
        from app.users u
        join app.device_sessions ds on ds.user_id = u.id
        where u.id = ${userId}
          and u.status = 'active'
          and u.token_version = ${tokenVersion}
          and ds.id = ${sessionId}
          and ds.status = 'active'
          and not exists (select 1 from app.guest_installations g where g.user_id = u.id and g.claimed_at is not null)
      ) as valid
    `;
    return row?.valid ?? false;
  }

  async listSessions(
    userId: string,
    currentSessionId: string,
  ): Promise<readonly SessionSummary[]> {
    const rows = await this.resource.sql<
      {
        app_version: string | null;
        created_at: string;
        device_id: string;
        device_name: string | null;
        id: string;
        last_seen_at: string;
        platform: SessionPlatform;
      }[]
    >`
      select
        id::text,
        device_id,
        platform,
        device_name,
        app_version,
        created_at,
        last_seen_at
      from app.device_sessions
      where user_id = ${userId}
        and status = 'active'
      order by last_seen_at desc
    `;

    return rows.map((row) => ({
      appVersion: row.app_version,
      createdAt: new Date(row.created_at),
      current: row.id === currentSessionId,
      deviceId: row.device_id,
      deviceName: row.device_name,
      id: row.id,
      lastSeenAt: new Date(row.last_seen_at),
      platform: row.platform,
    }));
  }

  async revokeSession(
    userId: string,
    sessionId: string,
    reason: string,
  ): Promise<boolean> {
    return this.resource.sql.begin(async (sql) => {
      const rows = await sql<{ id: string }[]>`
        update app.device_sessions
        set status = 'revoked',
            revoked_at = now(),
            revoke_reason = ${reason},
            updated_at = now()
        where id = ${sessionId}
          and user_id = ${userId}
          and status = 'active'
        returning id::text
      `;
      if (rows.length === 0) {
        return false;
      }
      await sql`
        update app.refresh_tokens
        set revoked_at = now()
        where session_id = ${sessionId}
          and revoked_at is null
      `;
      return true;
    });
  }

  async revokeAllSessions(userId: string, reason: string): Promise<void> {
    await this.resource.sql.begin(async (sql) => {
      await sql`
        update app.device_sessions
        set status = 'revoked',
            revoked_at = now(),
            revoke_reason = ${reason},
            updated_at = now()
        where user_id = ${userId}
          and status = 'active'
      `;
      await sql`
        update app.refresh_tokens rt
        set revoked_at = now()
        from app.device_sessions ds
        where rt.session_id = ds.id
          and ds.user_id = ${userId}
          and rt.revoked_at is null
      `;
      await sql`
        update app.users
        set token_version = token_version + 1,
            updated_at = now()
        where id = ${userId}
      `;
    });
  }

  async findFederatedAccount(
    provider: FederatedIdentityProvider,
    subject: string,
  ): Promise<FederatedAccount | undefined> {
    const [row] = await this.resource.sql<
      {
        identity_id: string;
        status: EmailAccount["status"];
        token_version: number;
        user_id: string;
      }[]
    >`
      select
        i.id::text as identity_id,
        u.id::text as user_id,
        u.status,
        u.token_version
      from app.user_identities i
      join app.users u on u.id = i.user_id
      where i.provider = ${provider}
        and i.provider_subject = ${subject}
      limit 1
    `;

    if (row === undefined) {
      return undefined;
    }
    return {
      identityId: row.identity_id,
      status: row.status,
      tokenVersion: row.token_version,
      userId: row.user_id,
    };
  }

  async findOrCreateFederatedAccount(parameters: {
    displayName?: string;
    email?: string;
    emailVerified: boolean;
    provider: FederatedIdentityProvider;
    subject: string;
  }): Promise<FederatedAccount> {
    const existing = await this.findFederatedAccount(
      parameters.provider,
      parameters.subject,
    );
    if (existing !== undefined) {
      await this.resource.sql`
        update app.user_identities
        set email = coalesce(${parameters.email ?? null}, email),
            email_verified_at = case
              when ${parameters.emailVerified} then coalesce(email_verified_at, now())
              else email_verified_at
            end,
            display_name = coalesce(${parameters.displayName ?? null}, display_name),
            updated_at = now()
        where id = ${existing.identityId}
      `;
      return existing;
    }

    const userId = newEntityId();
    const identityId = newEntityId();
    const verifiedAt = parameters.emailVerified ? new Date().toISOString() : null;
    try {
      await this.resource.sql.begin(async (sql) => {
        await sql`
          insert into app.users (id)
          values (${userId})
        `;
        await sql`
          insert into app.user_identities (
            id,
            user_id,
            provider,
            provider_subject,
            email,
            email_verified_at,
            display_name
          )
          values (
            ${identityId},
            ${userId},
            ${parameters.provider},
            ${parameters.subject},
            ${parameters.email ?? null},
            ${verifiedAt},
            ${parameters.displayName ?? null}
          )
        `;
      });
      return {
        identityId,
        status: "active",
        tokenVersion: 0,
        userId,
      };
    } catch (error) {
      if (!hasPostgresCode(error, "23505")) {
        throw error;
      }
      const racedAccount = await this.findFederatedAccount(
        parameters.provider,
        parameters.subject,
      );
      if (racedAccount === undefined) {
        throw error;
      }
      return racedAccount;
    }
  }

  async linkFederatedIdentity(parameters: {
    displayName?: string;
    email?: string;
    emailVerified: boolean;
    provider: FederatedIdentityProvider;
    subject: string;
    userId: string;
  }): Promise<
    | Readonly<{ identityId: string; status: "linked" }>
    | Readonly<{ status: "conflict" }>
  > {
    const existing = await this.findFederatedAccount(
      parameters.provider,
      parameters.subject,
    );
    if (existing !== undefined) {
      return existing.userId === parameters.userId
        ? { identityId: existing.identityId, status: "linked" }
        : { status: "conflict" };
    }

    const identityId = newEntityId();
    const verifiedAt = parameters.emailVerified ? new Date().toISOString() : null;
    try {
      const rows = await this.resource.sql<{ id: string }[]>`
        insert into app.user_identities (
          id,
          user_id,
          provider,
          provider_subject,
          email,
          email_verified_at,
          display_name
        )
        select
          ${identityId},
          u.id,
          ${parameters.provider},
          ${parameters.subject},
          ${parameters.email ?? null},
          ${verifiedAt},
          ${parameters.displayName ?? null}
        from app.users u
        where u.id = ${parameters.userId}
          and u.status = 'active'
        returning id::text
      `;
      if (rows.length === 0) {
        return { status: "conflict" };
      }
      return { identityId, status: "linked" };
    } catch (error) {
      if (!hasPostgresCode(error, "23505")) {
        throw error;
      }
      const racedAccount = await this.findFederatedAccount(
        parameters.provider,
        parameters.subject,
      );
      return racedAccount?.userId === parameters.userId
        ? { identityId: racedAccount.identityId, status: "linked" }
        : { status: "conflict" };
    }
  }

  async saveProviderCredential(
    identityId: string,
    providerClientId: string,
    credential: SealedProviderCredential,
  ): Promise<void> {
    await this.resource.sql`
      insert into app.identity_provider_credentials (
        identity_id,
        ciphertext,
        nonce,
        tag,
        key_version,
        provider_client_id
      )
      values (
        ${identityId},
        ${credential.ciphertext},
        ${credential.nonce},
        ${credential.tag},
        ${credential.keyVersion},
        ${providerClientId}
      )
      on conflict (identity_id) do update
      set ciphertext = excluded.ciphertext,
          nonce = excluded.nonce,
          tag = excluded.tag,
          key_version = excluded.key_version,
          provider_client_id = excluded.provider_client_id,
          updated_at = now()
    `;
  }
}
