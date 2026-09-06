import { randomInt } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { loadAccessPolicy } from "../../infrastructure/access-policy.js";
import { AppError } from "../../shared/errors.js";
import type {
  LinkNpcRelationshipInput,
  NpcRelationshipStatus,
  PublicNpc,
  PublicNpcCard,
  RegisterPublicNpcInput,
  NpcEncounterContext,
  NpcEncounterSelection,
} from "./types.js";
import { travelerIdCheckDigit } from "./traveler-id.js";
import { chooseAvatar } from "./avatar-matcher.js";
import type { AvatarProfile, AvatarRequirements } from "./types.js";

type NpcRow = Readonly<{
  avatar_id: string | null;
  avatar_url: string | null;
  card_text: string;
  created_at: string;
  id: string;
  traveler_id: string;
}>;

type AvatarCandidateRow = Readonly<{
  id: string;
  image_url: string;
  tags_text: string;
  profile: AvatarProfile | null;
}>;

function mapNpc(row: NpcRow): PublicNpc {
  return {
    avatar:
      row.avatar_id === null || row.avatar_url === null
        ? null
        : { id: row.avatar_id, url: row.avatar_url },
    card: JSON.parse(row.card_text) as PublicNpcCard,
    createdAt: new Date(row.created_at).toISOString(),
    id: row.id,
    travelerId: row.traveler_id,
  };
}

function notFound(): AppError {
  return new AppError({
    code: "NPC_NOT_FOUND",
    message: "No public NPC has that traveler ID.",
    statusCode: 404,
  });
}

function makeTravelerId(): string {
  const body = randomInt(0, 10_000_000_000).toString().padStart(10, "0");
  return `${body}${String(travelerIdCheckDigit(body))}`;
}

export class NpcRepository {
  constructor(
    private readonly database: DatabaseResource,
    private readonly draw: (maximum: number) => number = randomInt,
  ) {}

  async selectEncounter(
    userId: string,
    context: NpcEncounterContext,
  ): Promise<NpcEncounterSelection> {
    return this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended(${`npc-viewer:${userId}`}, 0))`;
      const [claimed] =
        await sql`select 1 from app.guest_installations where user_id=${userId} and claimed_at is not null`;
      if (claimed)
        throw new AppError({
          code: "GUEST_ALREADY_CLAIMED",
          message: "请登录已认领此旅程的账号。",
          statusCode: 403,
        });
      const policy = await loadAccessPolicy(sql, userId);
      if (policy.isGuest) {
        const [journey] = await sql<
          { starter_region_id: string | null }[]
        >`select starter_region_id from app.user_profiles where user_id=${userId}`;
        if (journey?.starter_region_id !== context.regionId)
          throw new AppError({
            code: "LOGIN_REQUIRED",
            message: "游客只能在起始城市活动。",
            statusCode: 403,
          });
      }
      const candidates = await sql<NpcRow[]>`
        select n.id::text, n.traveler_id, n.card::text as card_text, n.created_at::text,
          n.avatar_id::text, a.image_url as avatar_url
        from app.public_npcs n join app.npc_scene_affinities scene on scene.npc_id = n.id
        join app.npc_avatars a on a.id = n.avatar_id and a.enabled
        left join app.npc_encounter_history h on h.npc_id = n.id and h.user_id = ${userId}
        where scene.region_id = ${context.regionId} and scene.activity_id = ${context.activityId}
          and scene.category = ${context.category} and lower(scene.language) = lower(${context.language})
          and n.card->>'regionId' = ${context.regionId}
          and exists(select 1 from jsonb_array_elements_text(n.card->'languages') lang where lower(lang) = lower(${context.language}))
          and (h.last_seen_at is null or h.last_seen_at < now() - interval '24 hours')
          and not exists (
            select 1 from app.user_npc_relationships r join app.public_npcs seen on seen.id = r.npc_id
            where r.user_id = ${userId} and seen.avatar_id = n.avatar_id and seen.id <> n.id
          )
          and not exists(select 1 from app.user_npc_relationships r where r.user_id = ${userId} and r.npc_id = n.id and r.status = 'removed')
        order by coalesce(h.encounters, 0), h.last_seen_at nulls first, n.id
        limit 200
      `;
      // Reuse rises as a scene gains supply. Randomization is only within the eligible pool.
      const reuse =
        candidates.length > 0 && this.draw(100) < (candidates.length >= 12 ? 95 : 75);
      const selected = reuse
        ? candidates[this.draw(Math.min(candidates.length, 20))]
        : undefined;
      const npc = selected ? mapNpc(selected) : null;
      if (npc) {
        await this.linkWithinTransaction(
          sql,
          userId,
          npc.id,
          { localCharacterId: npc.id, status: "candidate" },
          true,
        );
        await sql`insert into app.npc_encounter_history (user_id, npc_id) values (${userId}, ${npc.id})
          on conflict (user_id, npc_id) do update set last_seen_at = now(), encounters = app.npc_encounter_history.encounters + 1`;
      }
      await sql`insert into app.npc_scene_supply (region_id, activity_id, language, selections, reuses, gaps, candidate_count)
        values (${context.regionId}, ${context.activityId}, ${context.language}, 1, ${npc ? 1 : 0}, ${candidates.length === 0 ? 1 : 0}, ${candidates.length})
        on conflict (region_id, activity_id, language) do update set selections = app.npc_scene_supply.selections + 1,
          reuses = app.npc_scene_supply.reuses + excluded.reuses, gaps = app.npc_scene_supply.gaps + excluded.gaps,
          candidate_count = excluded.candidate_count, updated_at = now()`;
      return {
        npc,
        candidateCount: candidates.length,
        reason: npc ? "reuse" : candidates.length ? "diversity" : "coverage_gap",
      };
    });
  }

  async register(
    userId: string,
    input: RegisterPublicNpcInput,
    cardHash: string,
  ): Promise<PublicNpc> {
    if (
      input.encounterContext &&
      input.encounterContext.regionId !== input.card.regionId
    ) {
      throw new AppError({
        code: "NPC_CONTEXT_CONFLICT",
        message: "The character must belong to the encounter region.",
        statusCode: 400,
      });
    }
    const result = await this.database.sql.begin(async (sql) => {
      // Serialize assignments per viewer and registration per identity, including first insert.
      await sql`select pg_advisory_xact_lock(hashtextextended(${`npc-viewer:${userId}`}, 0))`;
      const [claimed] =
        await sql`select 1 from app.guest_installations where user_id=${userId} and claimed_at is not null`;
      if (claimed)
        throw new AppError({
          code: "GUEST_ALREADY_CLAIMED",
          message: "请登录已认领此旅程的账号。",
          statusCode: 403,
        });
      await sql`select pg_advisory_xact_lock(hashtextextended(${`npc-identity:${input.id}`}, 0))`;
      const existing = await this.findById(sql, input.id, true);
      if (existing !== undefined) {
        const [hashRow] = await sql<{ card_hash: string }[]>`
          select card_hash
          from app.public_npcs
          where id = ${input.id}
        `;
        const [event] = await sql<{ requirements: AvatarRequirements }[]>`
          select requirements from app.npc_avatar_match_events
          where npc_id = ${input.id} and selected_avatar_id is not null
          order by updated_at limit 1
        `;
        // The iOS client retries with the finalized server card after its first registration.
        const canonicalReplay =
          isDeepStrictEqual(input.card, existing.card) &&
          isDeepStrictEqual(
            [...new Set(input.requiredAvatarTags ?? [])].sort(),
            event?.requirements.requiredTags ?? [],
          );
        if (hashRow?.card_hash !== cardHash && !canonicalReplay) {
          throw new AppError({
            code: "NPC_IDENTITY_CONFLICT",
            message: "This NPC identity was already registered with different data.",
            statusCode: 409,
          });
        }
        await this.linkWithinTransaction(
          sql,
          userId,
          existing.id,
          {
            localCharacterId: input.id,
            status: "candidate",
          },
          true,
        );
        return existing;
      }

      const policy = await loadAccessPolicy(sql, userId);
      const [supply] = await sql<
        { count: number }[]
      >`select count(*)::int as count from (
        select npc_id from app.user_npc_relationships where user_id=${userId}
          and (${policy.isGuest} or created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc')
        union select npc_id from app.npc_pending_avatars where user_id=${userId} and npc_id<>${input.id}
      ) seen`;
      const [pending] = await sql<
        { user_id: string; card_hash: string; input: string }[]
      >`
        select user_id::text, card_hash, input::text from app.npc_pending_avatars where npc_id = ${input.id}
      `;
      if (pending && (pending.user_id !== userId || pending.card_hash !== cardHash)) {
        throw new AppError({
          code: "NPC_IDENTITY_CONFLICT",
          statusCode: 409,
          message:
            "This pending NPC identity already has a different owner or narrative.",
        });
      }

      if (
        !pending &&
        (supply?.count ?? 0) >= (policy.isGuest ? 30 : 90)
      )
        throw new AppError({
          code: "NPC_REGISTRATION_LIMIT",
          message: "本周期的新角色登记已达上限，已有角色会保留。",
          statusCode: 429,
        });
      // The short critical section makes random allocation collision-free without exposing a
      // guessable sequence. Public lookup still requires the final checksum digit.
      await sql`select pg_advisory_xact_lock(hashtextextended('public-npc-traveler-id', 0))`;
      let travelerId = makeTravelerId();
      for (let attempt = 0; attempt < 32; attempt += 1) {
        const [collision] = await sql<{ exists: boolean }[]>`
          select true as exists from app.public_npcs where traveler_id = ${travelerId}
        `;
        if (collision === undefined) break;
        travelerId = makeTravelerId();
        if (attempt === 31) {
          throw new Error("Unable to allocate a unique traveler ID");
        }
      }

      // Import holds the exclusive counterpart, protecting reviewed pixels/profile during binding.
      await sql`select pg_advisory_xact_lock_shared(hashtextextended('npc-avatar-library', 0))`;
      const avatarRows = await sql<AvatarCandidateRow[]>`
        select
          avatar.id::text as id,
          avatar.image_url,
          avatar.tags::text as tags_text,
          avatar.profile
        from app.npc_avatars avatar
        where avatar.enabled = true
        order by avatar.created_at, avatar.id
        for share of avatar
      `;
      const seenRows = await sql<{ avatar_id: string }[]>`
        select npc.avatar_id::text from app.user_npc_relationships relation
        join app.public_npcs npc on npc.id = relation.npc_id
        where relation.user_id = ${userId} and npc.avatar_id is not null
      `;
      const requirements: AvatarRequirements = {
        age: input.card.age,
        gender: input.card.gender,
        requiredTags: [...new Set(input.requiredAvatarTags ?? [])].sort(),
      };
      const match = chooseAvatar(
        avatarRows.map((row) => ({
          id: row.id,
          imageUrl: row.image_url,
          tags: JSON.parse(row.tags_text) as string[],
          profile: row.profile,
        })),
        requirements,
        new Set(seenRows.map((row) => row.avatar_id)),
      );
      const avatar = match.avatar;
      await sql`
        insert into app.npc_avatar_match_events (user_id, npc_id, requirements, reason, eligible_count, unseen_count, selected_avatar_id)
        values (${userId}, ${input.id}, ${JSON.stringify(requirements)}::jsonb, ${match.reason}, ${match.eligibleCount}, ${match.unseenCount}, ${avatar?.id ?? null})
        on conflict (user_id, npc_id) do update set requirements = excluded.requirements, reason = excluded.reason,
          eligible_count = excluded.eligible_count, unseen_count = excluded.unseen_count,
          selected_avatar_id = excluded.selected_avatar_id, updated_at = now()
      `;
      if (avatar === undefined) {
        await sql`
          insert into app.npc_pending_avatars (npc_id, user_id, input, card_hash, next_attempt_at)
          values (${input.id}, ${userId}, ${JSON.stringify(input)}::jsonb, ${cardHash}, now() + interval '5 minutes')
          on conflict (npc_id) do nothing
        `;
        return { gap: match.reason, eligibleCount: match.eligibleCount };
      }
      // Narrative identity stays intact. Only external appearance is finalized from reviewed art.
      const finalCard =
        avatar.profile === null
          ? input.card
          : { ...input.card, appearance: avatar.profile.appearance };
      const [created] = await sql<NpcRow[]>`
        insert into app.public_npcs (
          id,
          traveler_id,
          card,
          card_hash,
          avatar_id,
          created_by_user_id
        )
        values (
          ${input.id},
          ${travelerId},
          ${JSON.stringify(finalCard)}::jsonb,
          ${cardHash},
          ${avatar.id},
          ${userId}
        )
        returning
          id::text,
          traveler_id,
          card::text as card_text,
          avatar_id::text,
          ${avatar.imageUrl}::text as avatar_url,
          created_at::text
      `;
      if (created === undefined) throw new Error("NPC registration returned no row");
      const result = mapNpc(created);
      const context =
        (pending
          ? (JSON.parse(pending.input) as RegisterPublicNpcInput).encounterContext
          : undefined) ?? input.encounterContext;
      if (context) {
        await sql`insert into app.npc_scene_affinities (npc_id, region_id, activity_id, category, language)
          values (${result.id}, ${context.regionId}, ${context.activityId}, ${context.category}, ${context.language}) on conflict do nothing`;
        await sql`insert into app.npc_encounter_history (user_id, npc_id) values (${userId}, ${result.id}) on conflict do nothing`;
      }
      await this.linkWithinTransaction(sql, userId, result.id, {
        localCharacterId: input.id,
        status: "candidate",
      });
      await sql`delete from app.npc_pending_avatars where npc_id = ${input.id}`;
      return result;
    });
    if ("gap" in result)
      throw new AppError({
        code: "NPC_AVATAR_COVERAGE_GAP",
        message:
          "No compatible unseen portrait is available. The original registration is saved for automatic retry after replenishment.",
        statusCode: 409,
        details: { reason: result.gap, eligibleCount: result.eligibleCount },
      });
    return result;
  }

  async retryPendingAvatars(
    limit = 20,
  ): Promise<{ attempted: number; matched: number }> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100)
      throw new Error("Invalid retry batch size");
    // Reserve before work; never hold a queue-row lock while acquiring registration locks.
    const requests = await this.database.sql<
      {
        user_id: string;
        input: string;
        card_hash: string;
      }[]
    >`
      with due as (
        select pending.npc_id from app.npc_pending_avatars pending
        join app.users owner on owner.id = pending.user_id and owner.status = 'active'
        where pending.next_attempt_at <= now()
        order by pending.next_attempt_at, pending.created_at, pending.npc_id
        for update of pending skip locked limit ${limit}
      )
      update app.npc_pending_avatars pending set next_attempt_at = now() + interval '5 minutes'
      from due where pending.npc_id = due.npc_id
      returning pending.user_id::text, pending.input::text, pending.card_hash
    `;
    let matched = 0;
    for (const request of requests) {
      try {
        await this.register(
          request.user_id,
          JSON.parse(request.input) as RegisterPublicNpcInput,
          request.card_hash,
        );
        matched += 1;
      } catch (error) {
        if (
          !(error instanceof AppError) ||
          !["NPC_AVATAR_COVERAGE_GAP", "GUEST_ALREADY_CLAIMED"].includes(error.code)
        )
          throw error;
      }
    }
    return { attempted: requests.length, matched };
  }

  async find(travelerId: string): Promise<PublicNpc> {
    const [row] = await this.database.sql<NpcRow[]>`
      select
        npc.id::text,
        npc.traveler_id,
        npc.card::text as card_text,
        npc.avatar_id::text,
        avatar.image_url as avatar_url,
        npc.created_at::text
      from app.public_npcs npc
      left join app.npc_avatars avatar on avatar.id = npc.avatar_id
      where npc.traveler_id = ${travelerId}
    `;
    if (row === undefined) throw notFound();
    return mapNpc(row);
  }

  async link(
    userId: string,
    npcId: string,
    input: LinkNpcRelationshipInput,
  ): Promise<void> {
    await this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended(${`npc-viewer:${userId}`}, 0))`;
      const [claimed] =
        await sql`select 1 from app.guest_installations where user_id=${userId} and claimed_at is not null`;
      if (claimed)
        throw new AppError({
          code: "GUEST_ALREADY_CLAIMED",
          message: "请登录已认领此旅程的账号。",
          statusCode: 403,
        });
      const npc = await this.findById(sql, npcId, false);
      if (npc === undefined) throw notFound();
      await this.linkWithinTransaction(sql, userId, npcId, input);
    });
  }

  private async findById(
    sql: TransactionSql,
    id: string,
    lock: boolean,
  ): Promise<PublicNpc | undefined> {
    const rows = lock
      ? await sql<NpcRow[]>`
          select
            npc.id::text,
            npc.traveler_id,
            npc.card::text as card_text,
            npc.avatar_id::text,
            avatar.image_url as avatar_url,
            npc.created_at::text
          from app.public_npcs npc
          left join app.npc_avatars avatar on avatar.id = npc.avatar_id
          where npc.id = ${id}
          for update of npc
        `
      : await sql<NpcRow[]>`
          select
            npc.id::text,
            npc.traveler_id,
            npc.card::text as card_text,
            npc.avatar_id::text,
            avatar.image_url as avatar_url,
            npc.created_at::text
          from app.public_npcs npc
          left join app.npc_avatars avatar on avatar.id = npc.avatar_id
          where npc.id = ${id}
        `;
    return rows[0] === undefined ? undefined : mapNpc(rows[0]);
  }

  private async linkWithinTransaction(
    sql: TransactionSql,
    userId: string,
    npcId: string,
    input: Readonly<{ localCharacterId: string; status: NpcRelationshipStatus }>,
    preserveStatus = false,
  ): Promise<void> {
    const [relationship] = await sql<
      { status: string }[]
    >`select status from app.user_npc_relationships where user_id = ${userId} and npc_id = ${npcId}`;
    if (!relationship) {
      const [conflict] = await sql<{ found: boolean }[]>`
        select exists(select 1 from app.user_npc_relationships r
          join app.public_npcs seen on seen.id = r.npc_id
          join app.public_npcs target on target.id = ${npcId} and target.avatar_id = seen.avatar_id
          where r.user_id = ${userId} and r.npc_id <> ${npcId}) as found
      `;
      if (conflict?.found)
        throw new AppError({
          code: "NPC_AVATAR_ALREADY_SEEN",
          message:
            "This portrait is already bound to another character in your journey.",
          statusCode: 409,
        });
    }
    if (input.status === "friend" && !preserveStatus) {
      if (relationship?.status !== "friend") {
        const policy = await loadAccessPolicy(sql, userId);
        const [count] = await sql<
          { occupied: number }[]
        >`select count(*)::integer as occupied from app.user_npc_relationships where user_id = ${userId} and status = 'friend'`;
        if ((count?.occupied ?? 0) >= policy.friendSlotLimit)
          throw new AppError({
            code: "FRIEND_SLOTS_FULL",
            message: policy.isGuest
              ? "Sign in to unlock more friend slots."
              : "All friend slots are occupied.",
            statusCode: 409,
            details: { limit: policy.friendSlotLimit, loginRequired: policy.isGuest },
          });
      }
    }
    await sql`
      insert into app.user_npc_relationships (
        user_id,
        npc_id,
        local_character_id,
        status
      )
      values (${userId}, ${npcId}, ${input.localCharacterId}, ${input.status})
      on conflict (user_id, npc_id) do update
      set local_character_id = case when ${preserveStatus} then app.user_npc_relationships.local_character_id else excluded.local_character_id end,
          status = case when ${preserveStatus} then app.user_npc_relationships.status else excluded.status end,
          updated_at = now()
    `;
  }
}
