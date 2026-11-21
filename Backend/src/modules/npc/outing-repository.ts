import { randomInt } from "node:crypto";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { loadAccessPolicy } from "../../infrastructure/access-policy.js";
import { AppError } from "../../shared/errors.js";
import {
  contentHash,
  requirePublishedWorld,
  type ActivityWorld,
} from "./activity-world-content.js";
import { encounterWeight } from "./encounter-weights.js";
import { NpcRepository } from "./repository.js";
import {
  advanceOuting,
  chooseOutingCandidate,
  outingConflict,
} from "./outing-state.js";
import type {
  OutingLocationReader,
  OutingOperation,
  OutingService,
  OutingSnapshot,
  OutingStart,
} from "./outing-types.js";

interface WorldRow {
  release_id: string;
  manifest_hash: string;
  manifest: ActivityWorld;
}
interface Candidate {
  id: string;
  traveler_id: string;
  avatar_id: string;
  avatar_url: string;
  created_at: string;
  known: boolean;
  encounters: number;
  days_since_seen: number;
}

export class OutingRepository implements OutingService {
  private readonly identities: NpcRepository;
  private readonly cache = new Map<string, ActivityWorld>();
  constructor(
    private readonly database: DatabaseResource,
    private readonly location: OutingLocationReader,
    private readonly roll: () => number = () =>
      randomInt(1_000_000_000) / 1_000_000_000,
  ) {
    this.identities = new NpcRepository(database);
  }

  private async lockActor(sql: TransactionSql, userId: string) {
    const location = await this.location.lock(sql, userId);
    await sql`select pg_advisory_xact_lock(hashtextextended(${`npc-viewer:${userId}`},0))`;
    const [claimed] =
      await sql`select 1 from app.guest_installations where user_id=${userId} and claimed_at is not null`;
    if (claimed)
      throw new AppError({
        code: "GUEST_ALREADY_CLAIMED",
        message: "请登录已认领此旅程的账号。",
        statusCode: 403,
      });
    const access = await loadAccessPolicy(sql, userId);
    if (access.isGuest && location.cityId !== location.starterCityId)
      throw new AppError({
        code: "LOGIN_REQUIRED",
        message: "游客只能在起始城市活动。",
        statusCode: 403,
      });
    return location;
  }

  private world(row: WorldRow) {
    const key = `${row.release_id}:${row.manifest_hash}`;
    const cached = this.cache.get(key);
    if (cached) return cached;
    const world = requirePublishedWorld(row.manifest);
    if (contentHash(world) !== row.manifest_hash)
      throw new Error("Stored activity world hash mismatch");
    this.cache.set(key, world);
    return world;
  }

  async catalog(userId: string, releaseId?: string) {
    return this.database.sql.begin(async (sql) => {
      const location = await this.lockActor(sql, userId);
      const [row] = await sql<
        WorldRow[]
      >`select release_id,manifest_hash,manifest from app.npc_activity_worlds
        where enabled and (${releaseId ?? null}::text is null or release_id=${releaseId ?? null})
        order by created_at desc,release_id desc limit 1`;
      if (!row) return null;
      const world = this.world(row);
      const places = world.places
        .filter((place) => place.cityId === location.cityId)
        .map((place) => {
          const photo = world.media.find((item) => item.id === place.mediaId);
          if (!photo) throw new Error("Missing published place photo");
          return {
            id: place.id,
            titleZh: place.titleZh,
            category: place.category,
            photo,
          };
        });
      return { releaseId: world.releaseId, cityId: location.cityId, places };
    });
  }

  async history(userId: string, before?: string) {
    return this.database.sql.begin(async (sql) => {
      await this.lockActor(sql, userId);
      const rows = await sql<{ run_id: string; snapshot: OutingSnapshot }[]>`
        select run_id::text,snapshot from app.npc_outings
        where user_id=${userId} and status in ('completed','abandoned')
          and (${before ?? null}::uuid is null or (created_at,run_id)<(
            select created_at,run_id from app.npc_outings where user_id=${userId} and run_id=${before ?? null}::uuid))
        order by created_at desc,run_id desc limit 50`;
      return {
        outings: rows.map((row) => row.snapshot),
        nextCursor: rows.length === 50 ? (rows.at(-1)?.run_id ?? null) : null,
      };
    });
  }

  async active(userId: string) {
    return this.database.sql.begin(async (sql) => {
      await this.lockActor(sql, userId);
      const [row] = await sql<
        { snapshot: OutingSnapshot }[]
      >`select snapshot from app.npc_outings
        where user_id=${userId} and status in ('reserved','opening_presented','in_progress')`;
      return row?.snapshot ?? null;
    });
  }

  async find(userId: string, runId: string) {
    return this.database.sql.begin(async (sql) => {
      await this.lockActor(sql, userId);
      return this.saved(sql, userId, runId);
    });
  }

  private async saved(sql: TransactionSql, userId: string, runId: string) {
    const [row] = await sql<
      { snapshot: OutingSnapshot }[]
    >`select snapshot from app.npc_outings
      where user_id=${userId} and run_id=${runId} for update`;
    if (!row)
      throw new AppError({
        code: "OUTING_NOT_FOUND",
        message: "没有找到这次外出。",
        statusCode: 404,
      });
    return row.snapshot;
  }

  async start(userId: string, input: OutingStart) {
    return this.database.sql.begin(async (sql) => {
      const location = await this.lockActor(sql, userId);
      const requestHash = contentHash(input);
      const [previous] = await sql<
        { request_hash: string; snapshot: OutingSnapshot }[]
      >`
        select request_hash,snapshot from app.npc_outings where user_id=${userId} and run_id=${input.runId}`;
      if (previous) {
        if (previous.request_hash !== requestHash)
          outingConflict("同一次外出的地点或版本不能更改。");
        return previous.snapshot;
      }
      const [active] = await sql<
        { run_id: string }[]
      >`select run_id::text from app.npc_outings
        where user_id=${userId} and status in ('reserved','opening_presented','in_progress')`;
      if (active)
        throw new AppError({
          code: "OUTING_ALREADY_ACTIVE",
          message: "还有一次外出可以继续。",
          statusCode: 409,
          details: { runId: active.run_id },
        });
      const [row] = await sql<
        WorldRow[]
      >`select release_id,manifest_hash,manifest from app.npc_activity_worlds
        where release_id=${input.releaseId} and enabled`;
      if (!row)
        throw new AppError({
          code: "ACTIVITY_WORLD_UNAVAILABLE",
          message: "这版城市地点暂未开放，请稍后重试。",
          statusCode: 503,
        });
      const world = this.world(row);
      const place = world.places.find((item) => item.id === input.placeId);
      if (place?.cityId !== location.cityId)
        throw new AppError({
          code: "OUTING_WRONG_CITY",
          message: "请先前往这个地点所在的城市。",
          statusCode: 409,
        });
      const bindings = world.characters.filter(
        (person) =>
          person.assignment?.placeId === place.id &&
          person.assignment.cityId === place.cityId,
      );
      const candidates = await sql<Candidate[]>`
        select n.id::text,n.traveler_id,n.avatar_id::text,a.image_url as avatar_url,n.created_at::text,
          (h.npc_id is not null or r.npc_id is not null) as known,
          coalesce(h.encounters,0)::int as encounters,
          coalesce(extract(epoch from (now()-h.last_seen_at))/86400,30)::float as days_since_seen
        from app.public_npcs n join app.npc_avatars a on a.id=n.avatar_id and a.enabled
        left join app.user_npc_relationships r on r.user_id=${userId} and r.npc_id=n.id
        left join app.npc_encounter_history h on h.user_id=${userId} and h.npc_id=n.id
        where n.id=any(${bindings.map((person) => person.id)}::uuid[])
          and (r.status is null or r.status <> 'removed')
          and not exists(select 1 from app.user_npc_relationships prior
            join app.public_npcs seen on seen.id=prior.npc_id
            where prior.user_id=${userId} and seen.avatar_id=n.avatar_id and seen.id<>n.id)
        order by n.id`;
      const eligible = candidates
        .filter((candidate) =>
          bindings.some(
            (person) =>
              person.id === candidate.id &&
              person.avatarId === candidate.avatar_id &&
              person.travelerId === candidate.traveler_id &&
              person.assignment?.card.languages.some(
                (language) => language.toLowerCase() === "english",
              ),
          ),
        )
        .map((candidate) => ({
          ...candidate,
          weight: encounterWeight(candidate.encounters, candidate.days_since_seen),
        }));
      const [progress] = await sql<{ quiet_streak: number; familiar_streak: number }[]>`
        select quiet_streak,familiar_streak from app.npc_outing_city_progress where user_id=${userId} and city_id=${place.cityId}`;
      const selected = chooseOutingCandidate(
        eligible,
        progress?.quiet_streak ?? 0,
        progress?.familiar_streak ?? 0,
        this.roll(),
        this.roll(),
        this.roll(),
      );
      const binding = selected
        ? bindings.find((person) => person.id === selected.id)?.assignment
        : undefined;
      const story = binding
        ? world.stories.find((item) => item.id === binding.storyId)
        : undefined;
      const photo = world.media.find((image) => image.id === place.mediaId);
      const [count] = await sql<
        { total: number }[]
      >`select count(*)::int as total from app.npc_outings
        where user_id=${userId} and place_id=${place.id} and snapshot->>'mode'='solitude'
        and status in ('opening_presented','completed')`;
      const solitude = place.solitude[(count?.total ?? 0) % place.solitude.length];
      if (!photo || !solitude || (selected && (!binding || !story)))
        throw new Error("Published outing content is incomplete");
      const snapshot: OutingSnapshot = {
        runId: input.runId,
        releaseId: world.releaseId,
        cityId: place.cityId,
        placeId: place.id,
        placeTitleZh: place.titleZh,
        createdAt: new Date().toISOString(),
        status: "reserved",
        revision: 0,
        mode: selected ? (selected.known ? "reunion" : "first_meeting") : "solitude",
        reason: selected ? "encounter" : eligible.length ? "quiet_visit" : "empty_pool",
        npc:
          selected && binding
            ? {
                id: selected.id,
                travelerId: selected.traveler_id,
                avatar: { id: selected.avatar_id, url: selected.avatar_url },
                card: binding.card,
                createdAt: selected.created_at,
              }
            : null,
        story: story
          ? {
              id: story.id,
              titleZh: story.titleZh,
              nodes: story.nodes,
              reunion: story.reunion,
            }
          : null,
        photo,
        solitude,
        nodeId: "start",
        beatIndex: -1,
        choices: [],
      };
      await sql`insert into app.npc_outings(user_id,run_id,request_hash,release_id,city_id,place_id,status,snapshot)
        values(${userId},${input.runId},${requestHash},${world.releaseId},${place.cityId},${place.id},'reserved',${JSON.stringify(snapshot)}::jsonb)`;
      return snapshot;
    });
  }

  async apply(userId: string, runId: string, operation: OutingOperation) {
    return this.database.sql.begin(async (sql) => {
      await this.lockActor(sql, userId);
      const snapshot = await this.saved(sql, userId, runId);
      const requestHash = contentHash(operation);
      const [previous] = await sql<
        { request_hash: string; response: OutingSnapshot }[]
      >`
        select request_hash,response from app.npc_outing_operations
        where user_id=${userId} and run_id=${runId} and operation_id=${operation.operationId}`;
      if (previous) {
        if (previous.request_hash !== requestHash)
          outingConflict("这次操作已经提交，参数不能更改。");
        return previous.response;
      }
      const next = advanceOuting(snapshot, operation);
      if (operation.type === "presented") {
        if (snapshot.npc) {
          const [removed] = await sql`select 1 from app.user_npc_relationships
            where user_id=${userId} and npc_id=${snapshot.npc.id} and status='removed'`;
          if (removed) outingConflict("这个角色已被移除，不会重新加入联系人。");
          await this.identities.recordOutingEncounter(sql, userId, snapshot.npc.id);
        }
        if (snapshot.reason !== "empty_pool")
          await sql`insert into app.npc_outing_city_progress(user_id,city_id,quiet_streak,familiar_streak)
            values(${userId},${snapshot.cityId},${snapshot.mode === "solitude" ? 1 : 0},${snapshot.mode === "reunion" ? 1 : 0})
            on conflict(user_id,city_id) do update set
              quiet_streak=case when ${snapshot.mode === "solitude"} then app.npc_outing_city_progress.quiet_streak+1 else 0 end,
              familiar_streak=case when ${snapshot.mode === "reunion"} then app.npc_outing_city_progress.familiar_streak+1
                when ${snapshot.mode === "first_meeting"} then 0 else app.npc_outing_city_progress.familiar_streak end`;
      }
      await sql`update app.npc_outings set snapshot=${JSON.stringify(next)}::jsonb,status=${next.status},updated_at=now()
        where user_id=${userId} and run_id=${runId}`;
      await sql`insert into app.npc_outing_operations(user_id,run_id,operation_id,request_hash,response)
        values(${userId},${runId},${operation.operationId},${requestHash},${JSON.stringify(next)}::jsonb)`;
      return next;
    });
  }
}

/** Version-scoped import; old pools, people, portraits and private relationships stay intact. */
export async function importActivityWorld(
  database: DatabaseResource,
  input: unknown,
  enabled = false,
) {
  const world = requirePublishedWorld(input);
  const manifestHash = contentHash(world);
  return database.sql.begin(async (sql) => {
    await sql`select pg_advisory_xact_lock(hashtextextended('npc-avatar-library',0))`;
    const identities = await sql<
      { id: string; traveler_id: string; avatar_id: string; card: unknown }[]
    >`
      select id::text,traveler_id,avatar_id::text,card from app.public_npcs where id=any(${world.characters.map((person) => person.id)}::uuid[])`;
    for (const person of world.characters) {
      const original = identities.find((item) => item.id === person.id);
      if (
        original?.traveler_id !== person.travelerId ||
        original.avatar_id !== person.avatarId ||
        contentHash(original.card) !== person.sourceCardHash
      )
        throw new Error(`Existing identity/baseline mismatch: ${person.id}`);
    }
    const rows =
      await sql`insert into app.npc_activity_worlds(release_id,manifest_hash,manifest,enabled)
      values(${world.releaseId},${manifestHash},${JSON.stringify(world)}::jsonb,${enabled})
      on conflict(release_id) do update set enabled=excluded.enabled
      where app.npc_activity_worlds.manifest_hash=excluded.manifest_hash returning release_id`;
    if (rows.length !== 1)
      throw new Error("Activity world versions are immutable; create a new release");
    return { releaseId: world.releaseId, manifestHash, enabled };
  });
}
