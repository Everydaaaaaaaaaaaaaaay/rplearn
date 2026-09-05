import { randomInt } from "node:crypto";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { avatarMetadataSchema } from "./avatar-catalog.js";
import {
  avatarPreference,
  chooseAvatar,
  type AvatarCandidate,
} from "./avatar-matching.js";
import type {
  LinkNpcRelationshipInput,
  PublicNpc,
  PublicNpcCard,
  RegisterPublicNpcInput,
} from "./types.js";
import { travelerIdCheckDigit } from "./traveler-id.js";

type NpcRow = Readonly<{
  id: string;
  traveler_id: string;
  card_text: string;
  card_hash: string;
  created_at: string;
}>;
type AvatarRow = Readonly<{
  id: string;
  family_id: string;
  image_url: string;
  metadata_text: string | null;
  withdrawn: boolean;
}>;

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
  constructor(private readonly database: DatabaseResource) {}

  async register(
    userId: string,
    input: RegisterPublicNpcInput,
    cardHash: string,
  ): Promise<PublicNpc> {
    return this.database.sql.begin(async (sql) => {
      // Lock before checking existence: simultaneous retries must see the winner's identity.
      await sql`select pg_advisory_xact_lock(hashtextextended('public-npc-traveler-id', 0))`;
      await this.lockUser(sql, userId);
      let [npc] = await sql<NpcRow[]>`
        select id::text, traveler_id, card::text as card_text, card_hash, created_at::text
        from app.public_npcs where id = ${input.id}
      `;
      if (npc && npc.card_hash !== cardHash) {
        throw new AppError({
          code: "NPC_IDENTITY_CONFLICT",
          message: "This NPC identity was already registered with different data.",
          statusCode: 409,
        });
      }
      if (!npc) {
        let travelerId: string | undefined;
        for (let attempt = 0; attempt < 32; attempt += 1) {
          const candidate = makeTravelerId();
          const [collision] =
            await sql`select 1 from app.public_npcs where traveler_id = ${candidate}`;
          if (!collision) {
            travelerId = candidate;
            break;
          }
        }
        if (!travelerId) throw new Error("Unable to allocate a unique traveler ID");
        [npc] = await sql<NpcRow[]>`
          insert into app.public_npcs (id, traveler_id, card, card_hash, created_by_user_id)
          values (${input.id}, ${travelerId}, ${JSON.stringify(input.card)}::jsonb, ${cardHash}, ${userId})
          returning id::text, traveler_id, card::text as card_text, card_hash, created_at::text
        `;
      }
      if (!npc) throw new Error("NPC registration returned no row");
      const result = await this.present(sql, userId, npc);
      // Registration retries must not undo friendship/removal or a pre-existing local mapping.
      await sql`
        insert into app.user_npc_relationships (user_id, npc_id, local_character_id, status)
        values (${userId}, ${npc.id}, ${input.id}, 'candidate')
        on conflict (user_id, npc_id) do nothing
      `;
      return result;
    });
  }

  async find(userId: string, travelerId: string): Promise<PublicNpc> {
    return this.database.sql.begin(async (sql) => {
      await this.lockUser(sql, userId);
      const [npc] = await sql<NpcRow[]>`
        select id::text, traveler_id, card::text as card_text, card_hash, created_at::text
        from app.public_npcs where traveler_id = ${travelerId}
      `;
      if (!npc) throw notFound();
      // Lookup is an encounter even if the user never adds this NPC as a friend.
      return this.present(sql, userId, npc);
    });
  }

  async link(
    userId: string,
    npcId: string,
    input: LinkNpcRelationshipInput,
  ): Promise<void> {
    await this.database.sql.begin(async (sql) => {
      await this.lockUser(sql, userId);
      const [npc] = await sql<NpcRow[]>`
        select id::text, traveler_id, card::text as card_text, card_hash, created_at::text
        from app.public_npcs where id = ${npcId}
      `;
      if (!npc) throw notFound();
      await this.present(sql, userId, npc);
      await sql`
        insert into app.user_npc_relationships (user_id, npc_id, local_character_id, status)
        values (${userId}, ${npcId}, ${input.localCharacterId}, ${input.status})
        on conflict (user_id, npc_id) do update
        set local_character_id = excluded.local_character_id, status = excluded.status, updated_at = now()
      `;
    });
  }

  private async lockUser(sql: TransactionSql, userId: string): Promise<void> {
    await sql`select pg_advisory_xact_lock(hashtextextended(${"npc-avatar-user:" + userId}, 0))`;
  }

  private async present(
    sql: TransactionSql,
    userId: string,
    npc: NpcRow,
  ): Promise<PublicNpc> {
    const card = JSON.parse(npc.card_text) as PublicNpcCard;
    let [avatar] = await sql<AvatarRow[]>`
      select asset.id::text, asset.family_id::text, asset.image_url,
        asset.metadata::text as metadata_text, asset.withdrawn
      from app.user_npc_avatars binding
      join app.npc_avatars asset on asset.id = binding.avatar_id
      where binding.user_id = ${userId} and binding.npc_id = ${npc.id}
    `;
    if (!avatar) {
      // All eligible inventory participates; never LIMIT before relevance ranking.
      const rows = await sql<AvatarRow[]>`
        select asset.id::text, asset.family_id::text, asset.image_url,
          asset.metadata::text as metadata_text, asset.withdrawn
        from app.npc_avatars asset
        where asset.enabled and not asset.reserved and not asset.withdrawn
          and asset.metadata is not null
          and not exists (
            select 1 from app.user_npc_avatars used
            where used.user_id = ${userId} and used.family_id = asset.family_id
          )
        order by asset.id
        for share of asset
      `;
      const candidates: AvatarCandidate[] = [];
      for (const row of rows) {
        const parsed = avatarMetadataSchema.safeParse(
          JSON.parse(row.metadata_text ?? "null") as unknown,
        );
        if (parsed.success)
          candidates.push({
            id: row.id,
            familyId: row.family_id,
            metadata: parsed.data,
          });
      }
      const preference = avatarPreference(card);
      const selected = chooseAvatar(candidates, preference, `${userId}:${npc.id}`);
      if (!selected) {
        // Never bind a random unrelated image or recycle a previous encounter's identity.
        throw new AppError({
          code: "NPC_AVATAR_UNAVAILABLE",
          message: "No suitable unused avatar is available yet.",
          statusCode: 503,
        });
      }
      avatar = rows.find((row) => row.id === selected.avatar.id);
      await sql`
        insert into app.user_npc_avatars (user_id, npc_id, avatar_id, family_id, reason)
        values (${userId}, ${npc.id}, ${selected.avatar.id}, ${selected.avatar.familyId},
          ${JSON.stringify({ version: 1, preference, interests: selected.matchedInterests, expressions: selected.matchedExpressions, score: selected.score })}::jsonb)
      `;
    }
    const metadata = avatarMetadataSchema.safeParse(
      JSON.parse(avatar?.metadata_text ?? "null") as unknown,
    );
    return {
      avatar:
        !avatar || avatar.withdrawn
          ? null
          : {
              id: avatar.id,
              url: avatar.image_url,
              attribution: metadata.success ? metadata.data.source.attribution : "",
              sourceUrl: metadata.success ? metadata.data.source.pageUrl : null,
            },
      card,
      id: npc.id,
      travelerId: npc.traveler_id,
      createdAt: new Date(npc.created_at).toISOString(),
    };
  }
}
