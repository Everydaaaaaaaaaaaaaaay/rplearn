import { claimDomainJourney } from "./guest-domain-claim.js";
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
      // Prevent in-flight domain operations racing ownership transfer.
      for (const id of [guest.user_id, accountId].sort()) {
        await sql`select pg_advisory_xact_lock(hashtextextended(${`domain:${id}`}, 0))`;
      }
      // Same lock order as NPC assignment. No avatar may be allocated while ownership moves.
      for (const id of [guest.user_id, accountId].sort()) {
        await sql`select pg_advisory_xact_lock(hashtextextended(${`npc-viewer:${id}`}, 0))`;
      }
      // Serialize the final claim marker with any last anonymous quota reservation.
      await sql`select pg_advisory_xact_lock(hashtextextended(${`usage:${guest.user_id}`}, 0))`;
      const [collision] = await sql`select 1 from app.user_npc_relationships g
        join app.public_npcs gn on gn.id=g.npc_id
        join app.user_npc_relationships a on a.user_id=${accountId} and a.npc_id<>g.npc_id
        join app.public_npcs an on an.id=a.npc_id and an.avatar_id=gn.avatar_id
        where g.user_id=${guest.user_id} limit 1`;
      if (collision)
        throw new AppError({
          code: "NPC_AVATAR_MERGE_CONFLICT",
          message:
            "两段旅程中有不同角色使用同一头像，尚未合并，原旅程已完整保留。请使用新账号认领。",
          statusCode: 409,
        });
      await claimDomainJourney(sql, guest.user_id, accountId);
      await sql`insert into app.npc_encounter_history(user_id,npc_id,last_seen_at,encounters)
        select ${accountId},npc_id,last_seen_at,encounters from app.npc_encounter_history where user_id=${guest.user_id}
        on conflict(user_id,npc_id) do update set last_seen_at=greatest(app.npc_encounter_history.last_seen_at,excluded.last_seen_at),
          encounters=app.npc_encounter_history.encounters+excluded.encounters`;
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
