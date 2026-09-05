import { randomInt } from "node:crypto";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type {
  LinkNpcRelationshipInput,
  NpcRelationshipStatus,
  PublicNpc,
  PublicNpcCard,
  RegisterPublicNpcInput,
} from "./types.js";
import { travelerIdCheckDigit } from "./traveler-id.js";

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

function avatarTags(card: PublicNpcCard): ReadonlySet<string> {
  const ageBand = card.age < 25 ? "young" : card.age < 45 ? "adult" : "mature";
  // Deliberately excludes nationality/ethnicity: geography must not mechanically infer looks.
  return new Set([`gender:${card.gender}`, `age:${ageBand}`]);
}

function selectAvatar(
  rows: readonly AvatarCandidateRow[],
  card: PublicNpcCard,
): AvatarCandidateRow | undefined {
  const desired = avatarTags(card);
  return rows
    .map((row) => {
      const tags = JSON.parse(row.tags_text) as readonly string[];
      return {
        row,
        score: tags.reduce((sum, tag) => sum + (desired.has(tag) ? 1 : 0), 0),
      };
    })
    .sort((left, right) => right.score - left.score)[0]?.row;
}

export class NpcRepository {
  constructor(private readonly database: DatabaseResource) {}

  async register(
    userId: string,
    input: RegisterPublicNpcInput,
    cardHash: string,
  ): Promise<PublicNpc> {
    return this.database.sql.begin(async (sql) => {
      const existing = await this.findById(sql, input.id, true);
      if (existing !== undefined) {
        const [hashRow] = await sql<{ card_hash: string }[]>`
          select card_hash
          from app.public_npcs
          where id = ${input.id}
        `;
        if (hashRow?.card_hash !== cardHash) {
          throw new AppError({
            code: "NPC_IDENTITY_CONFLICT",
            message: "This NPC identity was already registered with different data.",
            statusCode: 409,
          });
        }
        await this.linkWithinTransaction(sql, userId, existing.id, {
          localCharacterId: input.id,
          status: "candidate",
        });
        return existing;
      }

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

      const avatarRows = await sql<AvatarCandidateRow[]>`
        select
          avatar.id::text as id,
          avatar.image_url,
          avatar.tags::text as tags_text
        from app.npc_avatars avatar
        where avatar.enabled = true
          and not exists (
            select 1 from app.public_npcs npc where npc.avatar_id = avatar.id
          )
        order by avatar.created_at, avatar.id
        for update of avatar skip locked
        limit 64
      `;
      const avatar = selectAvatar(avatarRows, input.card);
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
          ${JSON.stringify(input.card)}::jsonb,
          ${cardHash},
          ${avatar?.id ?? null},
          ${userId}
        )
        returning
          id::text,
          traveler_id,
          card::text as card_text,
          avatar_id::text,
          ${avatar?.image_url ?? null}::text as avatar_url,
          created_at::text
      `;
      if (created === undefined) throw new Error("NPC registration returned no row");
      const result = mapNpc(created);
      await this.linkWithinTransaction(sql, userId, result.id, {
        localCharacterId: input.id,
        status: "candidate",
      });
      return result;
    });
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
  ): Promise<void> {
    await sql`
      insert into app.user_npc_relationships (
        user_id,
        npc_id,
        local_character_id,
        status
      )
      values (${userId}, ${npcId}, ${input.localCharacterId}, ${input.status})
      on conflict (user_id, npc_id) do update
      set local_character_id = excluded.local_character_id,
          status = excluded.status,
          updated_at = now()
    `;
  }
}
