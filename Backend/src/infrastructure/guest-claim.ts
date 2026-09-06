import { createHmac } from "node:crypto";
import type { DatabaseResource } from "../db/client.js";
import { AppError } from "../shared/errors.js";

/** Cross-module transaction: ownership moves together, or nothing moves. */
export function createGuestClaim(database: DatabaseResource, pepper: string) {
  return async (
    installationKey: string,
    accountId: string,
  ): Promise<{ claimed: boolean }> => {
    const hash = createHmac("sha256", pepper)
      .update(`guest-installation:${installationKey}`)
      .digest("hex");
    return database.sql.begin(async (sql) => {
      const [guest] = await sql<
        {
          user_id: string;
          claimed_by_user_id: string | null;
          claimed_at: string | null;
        }[]
      >`
        select user_id::text, claimed_by_user_id::text, claimed_at::text
        from app.guest_installations where installation_hash = ${hash} for update
      `;
      // A never-online local journey has no public ownership to transfer.
      if (!guest) return { claimed: false };
      if (guest.claimed_at !== null) {
        if (guest.claimed_by_user_id === accountId) return { claimed: true };
        throw new AppError({
          code: "GUEST_ALREADY_CLAIMED",
          message: "This journey belongs to another account.",
          statusCode: 409,
        });
      }
      if (guest.user_id === accountId)
        throw new AppError({
          code: "LOGIN_REQUIRED",
          message: "A registered account is required.",
          statusCode: 403,
        });
      // Same lock order as NPC assignment. No avatar may be allocated while ownership moves.
      for (const id of [guest.user_id, accountId].sort()) {
        await sql`select pg_advisory_xact_lock(hashtextextended(${`npc-viewer:${id}`}, 0))`;
      }
      await sql`
        insert into app.user_npc_relationships (user_id, npc_id, local_character_id, status, created_at)
        select ${accountId}, npc_id, local_character_id, status, created_at
        from app.user_npc_relationships where user_id = ${guest.user_id}
        on conflict (user_id, npc_id) do update set status = case
          when app.user_npc_relationships.status = 'friend' or excluded.status = 'friend' then 'friend'::app.npc_relationship_status
          else app.user_npc_relationships.status end, updated_at = now()
      `;
      await sql`update app.npc_pending_avatars set user_id = ${accountId} where user_id = ${guest.user_id}`;
      await sql`
        insert into app.npc_avatar_match_events (user_id, npc_id, requirements, reason, eligible_count, unseen_count, selected_avatar_id)
        select ${accountId}, npc_id, requirements, reason, eligible_count, unseen_count, selected_avatar_id
        from app.npc_avatar_match_events where user_id = ${guest.user_id}
        on conflict (user_id, npc_id) do nothing
      `;
      // Guest rows stay as an immutable history; the installation cannot spend or mint again.
      await sql`update app.guest_installations set claimed_by_user_id = ${accountId}, claimed_at = now() where user_id = ${guest.user_id}`;
      await sql`update app.users set token_version = token_version + 1 where id = ${guest.user_id}`;
      await sql`update app.device_sessions set status = 'revoked', revoked_at = now(), revoke_reason = 'guest_claimed' where user_id = ${guest.user_id} and status = 'active'`;
      return { claimed: true };
    });
  };
}
