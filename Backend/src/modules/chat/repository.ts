import { randomUUID } from "node:crypto";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { ContentCommand, ContentRecord } from "../content/types.js";
import type {
  ChatContentAccess,
  ChatGeneration,
  ChatGenerationInput,
  ChatState,
} from "./contracts.js";
import { conversationPrompt } from "./prompt.js";

type Payload = Record<string, unknown>;
interface Session {
  character_id: string;
  conversation_id: string;
  last_sequence: number;
  revision: string | number;
}
interface GenerationRow {
  id: string;
  user_id: string;
  conversation_id: string;
  status: ChatGeneration["status"];
  partial_text: string;
  input_message_ids: string[];
  error_code: string | null;
  fence_token: string | null;
  snapshot: ChatGenerationInput | null;
}
export interface ClaimedGeneration {
  input: ChatGenerationInput;
  fenceToken: string;
  recoverOnly?: boolean;
}

function missing(): never {
  throw new AppError({
    code: "CHAT_NOT_FOUND",
    message: "会话尚未同步，请重新打开聊天。",
    statusCode: 404,
  });
}
function generation(row: GenerationRow): ChatGeneration {
  return {
    id: row.id,
    status: row.status,
    partialText: row.partial_text,
    inputMessageIds: row.input_message_ids,
    errorCode: row.error_code,
  };
}
export class ChatRepository {
  static async sharedCoverage(
    sql: TransactionSql,
    userId: string,
    operationId: string,
    inputId: string,
    conversationId: string,
  ): Promise<boolean> {
    const rows =
      await sql`select 1 from app.chat_generations g join app.chat_messages m on m.user_id=g.user_id and m.answered_by=g.id
      where g.user_id=${userId} and g.id=${operationId} and g.conversation_id=${conversationId} and g.status='completed'
        and m.message_id=${inputId} and ${inputId}=any(g.input_message_ids)`;
    return rows.length > 0;
  }

  constructor(
    private readonly database: DatabaseResource,
    private readonly content: ChatContentAccess,
    private readonly coalesceMilliseconds: number,
    private readonly leaseMilliseconds: number,
  ) {}

  async lock(sql: TransactionSql, userId: string): Promise<void> {
    await sql`select pg_advisory_xact_lock(hashtextextended(${`${userId}:shared-chat`},0))`;
  }
  async beforeCommand(
    sql: TransactionSql,
    userId: string,
    command: ContentCommand,
  ): Promise<void> {
    await this.lock(sql, userId);
    if (command.operation !== "upsert" || command.resourceType !== "message") return;
    const payload = command.payload as Payload;
    if (!command.parentId) return;
    if (payload.role === "user" && typeof payload.sharedPredecessorId === "string") {
      const predecessor = await this.content.read(
        sql,
        userId,
        "message",
        payload.sharedPredecessorId,
      );
      if (!predecessor)
        throw new AppError({
          code: "CHAT_PREDECESSOR_PENDING",
          message: "正在同步前一条消息。",
          statusCode: 409,
        });
      if (predecessor.parentId !== command.parentId) {
        const aliases =
          await sql`select 1 from app.chat_aliases a join app.chat_aliases b on a.user_id=b.user_id and a.canonical_id=b.canonical_id
          where a.user_id=${userId} and a.conversation_id=${command.parentId} and b.conversation_id=${predecessor.parentId}`;
        if (!aliases.length)
          throw new AppError({
            code: "CHAT_PREDECESSOR_INVALID",
            message: "前一条消息不属于当前会话。",
            statusCode: 409,
          });
      }
    }
    if (payload.role !== "assistant") return;
    const managed =
      await sql`select 1 from app.chat_aliases where user_id=${userId} and conversation_id=${command.parentId}`;
    if (!managed.length) return;
    const exists =
      await sql`select 1 from app.chat_messages where user_id=${userId} and message_id=${command.resourceId}`;
    if (!exists.length && payload.deliveryOrigin === "proactive") {
      const pending =
        await sql`select 1 from app.chat_messages where user_id=${userId} and conversation_id in
        (select canonical_id from app.chat_aliases where user_id=${userId} and conversation_id=${command.parentId}) and role='user' and answered_by is null limit 1`;
      if (!pending.length) return;
    }
    if (!exists.length)
      throw new AppError({
        code: "CHAT_PROTOCOL_REQUIRED",
        message: "请更新应用后继续聊天。",
        statusCode: 409,
      });
  }
  async assertLegacyAllowed(userId: string): Promise<void> {
    const rows = await this.database
      .sql`select 1 from app.chat_sessions where user_id=${userId} limit 1`;
    if (rows.length)
      throw new AppError({
        code: "CHAT_PROTOCOL_REQUIRED",
        message: "请更新应用后继续聊天。",
        statusCode: 409,
      });
  }

  async open(userId: string, characterId: string): Promise<ChatState> {
    const id = await this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId);
      const existing = await sql<
        Session[]
      >`select * from app.chat_sessions where user_id=${userId} and character_id=${characterId}`;
      if (existing[0]) return existing[0].conversation_id;
      const character = await this.content.read(sql, userId, "character", characterId);
      if (!character) missing();
      const conversations = (
        await this.content.list(sql, userId, "conversation", characterId)
      )
        .filter((record) => !(record.payload as Payload).isArchived)
        .sort(
          (a, b) =>
            String((a.payload as Payload).createdAt).localeCompare(
              String((b.payload as Payload).createdAt),
            ) || a.resourceId.localeCompare(b.resourceId),
        );
      const now = new Date().toISOString();
      const canonical =
        conversations[0] ??
        (await this.content.write(
          sql,
          userId,
          "conversation",
          randomUUID(),
          characterId,
          {
            schemaVersion: 1,
            createdAt: now,
            lastMessageAt: now,
            isArchived: false,
            isEncounterSession: false,
            lastSummarizedMessageIndex: 0,
            turnCount: 0,
          },
        ));
      await sql`insert into app.chat_sessions(user_id,character_id,conversation_id) values(${userId},${characterId},${canonical.resourceId})`;
      const all: ContentRecord[] = [];
      for (const record of conversations.length ? conversations : [canonical]) {
        await this.content.onAdopt?.(
          sql,
          userId,
          record.resourceId,
          canonical.resourceId,
        );
        await sql`insert into app.chat_aliases(user_id,conversation_id,canonical_id) values(${userId},${record.resourceId},${canonical.resourceId})`;
        all.push(
          ...(await this.content.list(sql, userId, "message", record.resourceId)),
        );
        if (record.resourceId !== canonical.resourceId)
          await this.content.write(
            sql,
            userId,
            "conversation",
            record.resourceId,
            characterId,
            { ...(record.payload as Payload), isArchived: true },
          );
      }
      all.sort(
        (a, b) =>
          String((a.payload as Payload).createdAt).localeCompare(
            String((b.payload as Payload).createdAt),
          ) ||
          Number((a.payload as Payload).orderIndex) -
            Number((b.payload as Payload).orderIndex) ||
          a.resourceId.localeCompare(b.resourceId),
      );
      let sequence = 0;
      for (const record of all) {
        const payload: Payload = {
          ...(record.payload as Payload),
          orderIndex: ++sequence,
        };
        await this.content.write(
          sql,
          userId,
          "message",
          record.resourceId,
          canonical.resourceId,
          payload,
        );
        await sql`insert into app.chat_messages(user_id,message_id,conversation_id,sequence,role,protected_payload)
          values(${userId},${record.resourceId},${canonical.resourceId},${sequence},${String(payload.role)},${JSON.stringify(payload)}::jsonb)`;
      }
      // Historical user inputs preceding an assistant are already answered. A trailing
      // interrupted user burst remains eligible for one recovered server reply.
      const lastAssistant = all.findLastIndex(
        (record) => (record.payload as Payload).role === "assistant",
      );
      const oldIds = all
        .filter(
          (record, index) =>
            index <= lastAssistant && (record.payload as Payload).role === "user",
        )
        .map((r) => r.resourceId);
      if (oldIds.length) {
        const historicalId = randomUUID();
        await sql`insert into app.chat_generations(id,user_id,conversation_id,status,input_message_ids,created_at,completed_at)
          values(${historicalId},${userId},${canonical.resourceId},'completed',${oldIds}::uuid[],'epoch'::timestamptz,now())`;
        await sql`update app.chat_messages set answered_by=${historicalId} where user_id=${userId} and message_id=any(${oldIds}::uuid[])`;
      }
      await sql`update app.chat_sessions set last_sequence=${sequence} where user_id=${userId} and character_id=${characterId}`;
      await this.schedule(sql, userId, canonical.resourceId);
      return canonical.resourceId;
    });
    return this.state(userId, id);
  }

  async observe(
    sql: TransactionSql,
    userId: string,
    record: ContentRecord,
    previous?: ContentRecord,
  ): Promise<ContentRecord> {
    if (record.resourceType === "conversation" && record.deletedAt !== null) {
      await sql`update app.chat_generations set status='failed',fence_token=${randomUUID()},error_code='CHAT_ARCHIVED'
        where user_id=${userId} and conversation_id=${record.resourceId} and status in ('queued','dispatched','uncertain')`;
      await sql`delete from app.chat_sessions where user_id=${userId} and conversation_id=${record.resourceId}`;
      return record;
    }
    if (
      record.resourceType === "conversation" &&
      record.deletedAt === null &&
      record.parentId
    ) {
      const [session] = await sql<
        Session[]
      >`select * from app.chat_sessions where user_id=${userId} and character_id=${record.parentId}`;
      if (!session) return record;
      await sql`insert into app.chat_aliases(user_id,conversation_id,canonical_id)
        values(${userId},${record.resourceId},${session.conversation_id}) on conflict do nothing`;
      if (record.resourceId !== session.conversation_id)
        return this.content.rewrite(sql, userId, record, record.parentId, {
          ...(record.payload as Payload),
          isArchived: true,
        });
      const payload = record.payload as Payload;
      const prior = previous?.payload as Payload | undefined;
      if (payload.isArchived === true && prior?.isEncounterSession === true) {
        const character = await this.content.read(
          sql,
          userId,
          "character",
          record.parentId,
        );
        if ((character?.payload as Payload | undefined)?.isFriend !== true) {
          await sql`update app.chat_generations set status='failed',fence_token=${randomUUID()},error_code='CHAT_ARCHIVED'
            where user_id=${userId} and conversation_id=${record.resourceId} and status in ('queued','dispatched','uncertain')`;
          await sql`delete from app.chat_sessions where user_id=${userId} and conversation_id=${record.resourceId}`;
          return record;
        }
      }
      const remaining = await this.content.messages(
        sql,
        userId,
        record.resourceId,
        0,
        1,
      );
      return this.content.rewrite(sql, userId, record, record.parentId, {
        ...payload,
        isArchived: false,
        isEncounterSession: prior?.isEncounterSession ?? payload.isEncounterSession,
        turnCount: remaining.length ? (prior?.turnCount ?? payload.turnCount) : 0,
        lastMessageAt:
          remaining.length && typeof prior?.lastMessageAt === "string"
            ? [String(payload.lastMessageAt), prior.lastMessageAt].sort().at(-1)
            : payload.lastMessageAt,
      });
    }
    if (record.resourceType !== "message" || !record.parentId) return record;
    const [alias] = await sql<
      { canonical_id: string }[]
    >`select canonical_id from app.chat_aliases
      where user_id=${userId} and conversation_id=${record.parentId}`;
    if (!alias) return record;
    if (record.deletedAt !== null) {
      await sql`delete from app.chat_messages where user_id=${userId} and message_id=${record.resourceId}`;
      return record;
    }
    const [old] = await sql<
      { sequence: number; protected_payload: Payload; answered_by: string | null }[]
    >`
      select sequence,protected_payload,answered_by from app.chat_messages where user_id=${userId} and message_id=${record.resourceId}`;
    let payload = record.payload as Payload;
    if (old) {
      payload = {
        ...payload,
        text: old.protected_payload.text,
        role: old.protected_payload.role,
        kind: old.protected_payload.kind,
        createdAt: old.protected_payload.createdAt,
        learningOrigin: old.protected_payload.learningOrigin ?? null,
        sharedPredecessorId: old.protected_payload.sharedPredecessorId ?? null,
        sharedVoiceLeaseId: old.protected_payload.sharedVoiceLeaseId ?? null,
        deliveryOrigin: old.protected_payload.deliveryOrigin,
        orderIndex: old.sequence,
        isInterrupted:
          old.protected_payload.role === "user" ? old.answered_by === null : false,
      };
    } else {
      const [session] = await sql<
        Session[]
      >`update app.chat_sessions set last_sequence=last_sequence+1,revision=revision+1
        where user_id=${userId} and conversation_id=${alias.canonical_id} returning *`;
      const [archived] = session
        ? []
        : await sql<
            { sequence: number }[]
          >`select coalesce(max(sequence),0)+1 as sequence from app.chat_messages where user_id=${userId} and conversation_id=${alias.canonical_id}`;
      const sequence = session?.last_sequence ?? archived?.sequence;
      if (sequence === undefined) missing();
      payload = {
        ...payload,
        orderIndex: sequence,
        isInterrupted: payload.role === "user",
      };
      await sql`insert into app.chat_messages(user_id,message_id,conversation_id,sequence,role,protected_payload)
        values(${userId},${record.resourceId},${alias.canonical_id},${sequence},${String(payload.role)},${JSON.stringify(payload)}::jsonb)`;
    }
    const accepted = await this.content.rewrite(
      sql,
      userId,
      record,
      alias.canonical_id,
      payload,
    );
    if (payload.role === "user") {
      if (!old) {
        // A new user turn can continue a definitively failed reply. A failed call
        // resumes as ordinary text, without reusing a closed voice lease.
        await sql`update app.chat_messages set assigned_generation_id=null,protected_payload=protected_payload-'sharedVoiceLeaseId'
          where user_id=${userId} and conversation_id=${alias.canonical_id} and answered_by is null and assigned_generation_id in
            (select id from app.chat_generations where user_id=${userId} and conversation_id=${alias.canonical_id} and status='failed')`;
      }
      await this.schedule(sql, userId, alias.canonical_id);
    }
    return accepted;
  }

  private async schedule(
    sql: TransactionSql,
    userId: string,
    conversationId: string,
  ): Promise<void> {
    const pending =
      await sql`select 1 from app.chat_messages where user_id=${userId} and conversation_id=${conversationId}
      and role='user' and answered_by is null and assigned_generation_id is null limit 1`;
    if (!pending.length) return;
    const unresolved =
      await sql`select 1 from app.chat_generations where user_id=${userId} and conversation_id=${conversationId} and status='uncertain' limit 1`;
    if (unresolved.length) return;
    await sql`insert into app.chat_generations(id,user_id,conversation_id,status,available_at)
      select ${randomUUID()},${userId},${conversationId},'queued',now()+${this.coalesceMilliseconds}*interval '1 millisecond'
      where exists(select 1 from app.chat_sessions where user_id=${userId} and conversation_id=${conversationId})
      on conflict(user_id,conversation_id) where status in ('queued','dispatched') do nothing`;
  }

  async state(
    userId: string,
    conversationId: string,
    afterSequence = 0,
    inputMessageId?: string,
  ): Promise<ChatState> {
    return this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId);
      const [session] = await sql<
        Session[]
      >`select * from app.chat_sessions where user_id=${userId} and conversation_id=${conversationId}`;
      if (!session) missing();
      const [current] = await sql<GenerationRow[]>`select * from app.chat_generations
        where user_id=${userId} and conversation_id=${conversationId}
        and (${inputMessageId === undefined} or id=(select assigned_generation_id from app.chat_messages where user_id=${userId} and message_id=${inputMessageId ?? null} and conversation_id=${conversationId}))
        order by created_at desc,id desc limit 1`;
      const covered = await sql<
        { message_id: string }[]
      >`select message_id from app.chat_messages
        where user_id=${userId} and conversation_id=${conversationId} and answered_by is not null order by sequence desc limit 200`;
      const aliases = await sql<
        { conversation_id: string }[]
      >`select conversation_id from app.chat_aliases where user_id=${userId} and canonical_id=${conversationId}`;
      const conversations: ContentRecord[] = [];
      for (const alias of aliases) {
        const record = await this.content.read(
          sql,
          userId,
          "conversation",
          alias.conversation_id,
        );
        if (record) conversations.push(record);
      }
      const page = await this.content.messages(
        sql,
        userId,
        conversationId,
        afterSequence,
        201,
      );
      const records = page.slice(0, 200);
      const lastRecord = records.at(-1);
      const lastSequence = lastRecord
        ? Number((lastRecord.payload as Payload).orderIndex)
        : afterSequence;
      return {
        protocolVersion: 1,
        conversationId,
        revision: Number(session.revision),
        lastSequence,
        hasMore: page.length > 200,
        generation: current ? generation(current) : null,
        coveredMessageIds: covered.map((m) => m.message_id),
        records: [...conversations, ...records],
      };
    });
  }

  async claim(): Promise<ClaimedGeneration | undefined> {
    return this.database.sql.begin(async (sql) => {
      const [candidate] = await sql<GenerationRow[]>`select * from app.chat_generations
        where (status='queued' and available_at<=now()) or (status in ('dispatched','uncertain') and lease_until<=now())
        order by available_at,id limit 1`;
      if (!candidate) return undefined;
      await this.lock(sql, candidate.user_id);
      const [row] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where id=${candidate.id}
        and ((status='queued' and available_at<=now()) or (status in ('dispatched','uncertain') and lease_until<=now())) for update`;
      if (!row) return undefined;
      if (row.status === "dispatched" || row.status === "uncertain") {
        const fenceToken = randomUUID();
        await sql`update app.chat_generations set status='dispatched',fence_token=${fenceToken},lease_until=now()+${this.leaseMilliseconds}*interval '1 millisecond' where id=${row.id}`;
        return row.snapshot
          ? { input: row.snapshot, fenceToken, recoverOnly: true }
          : undefined;
      }
      const [session] = await sql<
        Session[]
      >`select * from app.chat_sessions where user_id=${row.user_id} and conversation_id=${row.conversation_id}`;
      if (!session) missing();
      const character = await this.content.read(
        sql,
        row.user_id,
        "character",
        session.character_id,
      );
      if (!character) {
        await sql`update app.chat_generations set status='failed',error_code='CHAT_CHARACTER_REMOVED' where id=${row.id}`;
        return undefined;
      }
      const pending = await sql<
        { message_id: string; text_length: number; voice_lease_id: string | null }[]
      >`select message_id,length(protected_payload->>'text') as text_length,protected_payload->>'sharedVoiceLeaseId' as voice_lease_id from app.chat_messages
        where user_id=${row.user_id} and conversation_id=${row.conversation_id} and role='user'
        and answered_by is null and assigned_generation_id is null order by sequence limit 20`;
      const ids: string[] = [];
      let pendingCharacters = 0;
      for (const message of pending) {
        if (
          ids.length > 0 &&
          (pendingCharacters + message.text_length > 40_000 ||
            message.voice_lease_id !== pending[0]?.voice_lease_id)
        )
          break;
        ids.push(message.message_id);
        pendingCharacters += message.text_length;
      }
      if (!ids.length) {
        await sql`update app.chat_generations set status='failed',error_code='CHAT_INPUT_REMOVED' where id=${row.id}`;
        return undefined;
      }
      const prior = await sql<
        { message_id: string }[]
      >`select message_id from app.chat_messages
        where user_id=${row.user_id} and conversation_id=${row.conversation_id} and (role='assistant' or answered_by is not null)
        order by sequence desc limit 24`;
      const history: ContentRecord[] = [];
      for (const id of [...prior.map((message) => message.message_id), ...ids]) {
        const record = await this.content.read(sql, row.user_id, "message", id);
        if (record) history.push(record);
      }
      history.sort(
        (a, b) =>
          Number((a.payload as Payload).orderIndex) -
          Number((b.payload as Payload).orderIndex),
      );
      const memories = await this.content.list(
        sql,
        row.user_id,
        "memory",
        session.character_id,
        200,
      );
      const profile = await this.content.learner?.(sql, row.user_id);
      const input: ChatGenerationInput = {
        userId: row.user_id,
        generationId: row.id,
        conversationId: row.conversation_id,
        characterId: session.character_id,
        inputMessageIds: ids,
        messages: conversationPrompt(character, memories, history, ids, profile ?? {}),
      };
      const voiceLeaseId = pending[0]?.voice_lease_id;
      if (voiceLeaseId) {
        input.voiceLeaseId = voiceLeaseId;
        input.messages = conversationPrompt(
          character,
          memories,
          history,
          ids,
          profile ?? {},
          true,
        );
      }
      const anchor = history.find((m) => m.resourceId === ids.at(-1));
      const origin = (
        anchor?.payload as
          { learningOrigin?: { source?: string; cycleId?: string } } | undefined
      )?.learningOrigin;
      if (origin?.source === "user" && origin.cycleId)
        input.learningChat = {
          conversationId: row.conversation_id,
          userMessageId: ids[ids.length - 1] ?? "",
          cycleId: origin.cycleId,
        };
      const fenceToken = randomUUID();
      await sql`update app.chat_generations set status='dispatched',fence_token=${fenceToken},
        lease_until=now()+${this.leaseMilliseconds}*interval '1 millisecond',input_message_ids=${ids}::uuid[],snapshot=${JSON.stringify(input)}::jsonb where id=${row.id}`;
      await sql`update app.chat_messages set assigned_generation_id=${row.id} where user_id=${row.user_id} and message_id=any(${ids}::uuid[])`;
      await sql`update app.chat_sessions set revision=revision+1 where user_id=${row.user_id} and conversation_id=${row.conversation_id}`;
      return { input, fenceToken };
    });
  }

  async partial(claim: ClaimedGeneration, text: string): Promise<void> {
    await this.database
      .sql`update app.chat_generations set partial_text=${text},lease_until=now()+${this.leaseMilliseconds}*interval '1 millisecond'
      where id=${claim.input.generationId} and fence_token=${claim.fenceToken} and status='dispatched'`;
  }
  async finish(claim: ClaimedGeneration, text: string): Promise<boolean> {
    const input = claim.input;
    return this.database.sql.begin(async (sql) => {
      await this.lock(sql, input.userId);
      const [row] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where id=${input.generationId}
        and fence_token=${claim.fenceToken} and status='dispatched' for update`;
      if (!row) return false;
      const available =
        await sql`select 1 from app.chat_messages where user_id=${input.userId} and message_id=any(${input.inputMessageIds}::uuid[])`;
      if (available.length !== input.inputMessageIds.length) {
        await sql`update app.chat_generations set status='failed',error_code='CHAT_INPUT_REMOVED' where id=${row.id}`;
        await sql`update app.chat_messages set assigned_generation_id=null where user_id=${input.userId} and assigned_generation_id=${row.id} and answered_by is null`;
        await this.schedule(sql, input.userId, input.conversationId);
        return false;
      }
      const now = new Date().toISOString();
      const lines = input.voiceLeaseId
        ? [text]
        : text
            .split(/\n+/)
            .map((line) => line.trim())
            .filter(Boolean);
      const fragments =
        lines.length > 8 ? [...lines.slice(0, 7), lines.slice(7).join(" ")] : lines;
      const [session] = await sql<
        Session[]
      >`update app.chat_sessions set last_sequence=last_sequence+${fragments.length},revision=revision+1
        where user_id=${input.userId} and conversation_id=${input.conversationId} returning *`;
      if (!session) missing();
      for (const [index, fragment] of fragments.entries()) {
        const id = randomUUID();
        const sequence = session.last_sequence - fragments.length + index + 1;
        const payload: Payload = {
          schemaVersion: 1,
          role: "assistant",
          kind: "text",
          text: fragment,
          createdAt: now,
          orderIndex: sequence,
          isInterrupted: false,
          tokenEstimate: Math.ceil(fragment.length / 4),
        };
        if (input.learningChat)
          payload.learningOrigin = {
            source: "assistant",
            cycleId: input.learningChat.cycleId,
            userMessageId: input.learningChat.userMessageId,
            operationId: input.generationId,
            fragmentIndex: index,
            fragmentCount: fragments.length,
          };
        const assistant = await this.content.write(
          sql,
          input.userId,
          "message",
          id,
          input.conversationId,
          payload,
        );
        await sql`insert into app.chat_messages(user_id,message_id,conversation_id,sequence,role,protected_payload)
          values(${input.userId},${id},${input.conversationId},${sequence},'assistant',${JSON.stringify(payload)}::jsonb)`;
        await this.content.onMessage?.(sql, input.userId, assistant);
      }
      await sql`update app.chat_messages set answered_by=${input.generationId} where user_id=${input.userId} and message_id=any(${input.inputMessageIds}::uuid[])`;
      for (const messageId of input.inputMessageIds) {
        const message = await this.content.read(
          sql,
          input.userId,
          "message",
          messageId,
        );
        if (message)
          await this.content.write(
            sql,
            input.userId,
            "message",
            messageId,
            input.conversationId,
            { ...(message.payload as Payload), isInterrupted: false },
          );
      }
      const conversation = await this.content.read(
        sql,
        input.userId,
        "conversation",
        input.conversationId,
      );
      if (conversation)
        await this.content.write(
          sql,
          input.userId,
          "conversation",
          input.conversationId,
          input.characterId,
          {
            ...(conversation.payload as Payload),
            lastMessageAt: now,
            turnCount: Number((conversation.payload as Payload).turnCount ?? 0) + 1,
          },
        );
      await sql`update app.chat_generations set status='completed',partial_text=${text},error_code=null,completed_at=now() where id=${row.id}`;
      await this.schedule(sql, input.userId, input.conversationId);
      return true;
    });
  }
  async uncertain(claim: ClaimedGeneration): Promise<void> {
    await this.database
      .sql`update app.chat_generations set status='uncertain',error_code='CHAT_DISPATCH_UNCERTAIN',lease_until=now()+interval '15 seconds'
      where id=${claim.input.generationId} and fence_token=${claim.fenceToken} and status='dispatched'`;
  }
  async fail(claim: ClaimedGeneration): Promise<void> {
    await this.database
      .sql`update app.chat_generations set status='failed',error_code='CHAT_REPLY_FAILED'
      where id=${claim.input.generationId} and fence_token=${claim.fenceToken} and status='dispatched'`;
  }
  async reclaim(
    userId: string,
    conversationId: string,
    generationId: string,
  ): Promise<ClaimedGeneration | undefined> {
    return this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId);
      const fenceToken = randomUUID();
      const [row] = await sql<
        GenerationRow[]
      >`update app.chat_generations set status='dispatched',fence_token=${fenceToken},lease_until=now()+${this.leaseMilliseconds}*interval '1 millisecond'
        where user_id=${userId} and conversation_id=${conversationId} and id=${generationId} and status='uncertain' returning *`;
      return row?.snapshot
        ? { input: row.snapshot, fenceToken, recoverOnly: true }
        : undefined;
    });
  }

  async retry(
    userId: string,
    conversationId: string,
    commandId: string,
  ): Promise<ChatState> {
    await this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId);
      const session =
        await sql`select 1 from app.chat_sessions where user_id=${userId} and conversation_id=${conversationId}`;
      if (!session.length) missing();
      const [receipt] = await sql<
        { conversation_id: string }[]
      >`select conversation_id from app.chat_retry_commands where user_id=${userId} and command_id=${commandId}`;
      if (receipt) {
        if (receipt.conversation_id !== conversationId)
          throw new AppError({
            code: "OPERATION_CONFLICT",
            message: "请求编号已用于其他会话。",
            statusCode: 409,
          });
        return;
      }
      const [failed] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where user_id=${userId} and conversation_id=${conversationId}
        order by created_at desc,id desc limit 1 for update`;
      if (!failed || (failed.status !== "failed" && failed.status !== "uncertain"))
        return;
      await sql`update app.chat_generations set status='failed',fence_token=${randomUUID()} where id=${failed.id}`;
      await sql`update app.chat_messages set assigned_generation_id=null,protected_payload=protected_payload-'sharedVoiceLeaseId' where user_id=${userId} and assigned_generation_id=${failed.id} and answered_by is null`;
      await this.schedule(sql, userId, conversationId);
      await sql`insert into app.chat_retry_commands(user_id,command_id,conversation_id,generation_id) values(${userId},${commandId},${conversationId},${failed.id})`;
    });
    return this.state(userId, conversationId);
  }
}
