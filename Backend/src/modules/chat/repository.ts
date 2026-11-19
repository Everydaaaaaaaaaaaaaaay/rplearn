import { replyFragments } from "./reply-quality.js";
import { historyWindow } from "./context.js";
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
import {
  handoffAt,
  generationEligibleAt,
  quietWindow,
  replyPlan,
  typingDuration,
  visiblePhase,
  type ReplySimulation,
} from "./reply-timing.js";

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
  deliveryOnly?: boolean;
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
    ...(row.snapshot?.simulation && ["queued", "dispatched"].includes(row.status)
      ? {
          phase: visiblePhase(row.snapshot.simulation, row.status, Date.now()),
          replyPlan: row.snapshot.simulation.plan,
        }
      : {}),
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
      where g.user_id=${userId} and (g.id=${operationId} or g.snapshot->>'resultOperationId'=${operationId}) and g.conversation_id=${conversationId} and g.status='completed'
        and m.message_id=${inputId} and ${inputId}=any(g.input_message_ids)`;
    return rows.length > 0;
  }

  constructor(
    private readonly database: DatabaseResource,
    private readonly content: ChatContentAccess,
    private readonly coalesceMilliseconds: number,
    private readonly leaseMilliseconds: number,
    private readonly replyTimingScale = 1,
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
      const predecessorId = payload.sharedPredecessorId;
      const canonicalId = predecessorId.toLowerCase();
      // Swift encodes UUID payload fields in uppercase; content keys are case-sensitive.
      const predecessor =
        (await this.content.read(sql, userId, "message", predecessorId)) ??
        (canonicalId !== predecessorId
          ? await this.content.read(sql, userId, "message", canonicalId)
          : undefined);
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
    if (record.resourceType === "character" && record.deletedAt !== null) {
      await sql`delete from app.chat_followups where user_id=${userId} and character_id=${record.resourceId}`;
      await sql`update app.chat_generations set status='failed',fence_token=${randomUUID()},error_code='CHAT_CHARACTER_REMOVED'
        where user_id=${userId} and conversation_id in(select conversation_id from app.chat_sessions where user_id=${userId} and character_id=${record.resourceId})
          and (status in ('queued','dispatched','uncertain') or snapshot->>'awaitingVoiceReceipt'='true' or snapshot->>'voiceReceiptExpired'='true')`;
    }
    if (record.resourceType === "conversation" && record.deletedAt !== null) {
      await sql`delete from app.chat_followups where user_id=${userId} and conversation_id=${record.resourceId}`;
      await sql`delete from app.chat_voice_receipts r using app.chat_messages m where r.user_id=${userId} and m.user_id=r.user_id and m.message_id=r.message_id and m.conversation_id=${record.resourceId}`;
      await sql`update app.chat_generations set status='failed',fence_token=${randomUUID()},error_code='CHAT_ARCHIVED'
        where user_id=${userId} and conversation_id=${record.resourceId} and (status in ('queued','dispatched','uncertain') or snapshot->>'awaitingVoiceReceipt'='true' or snapshot->>'voiceReceiptExpired'='true')`;
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
      await sql`delete from app.chat_followups where user_id=${userId} and message_id=${record.resourceId}`;
      await sql`delete from app.chat_voice_receipts where user_id=${userId} and message_id=${record.resourceId}`;
      await sql`update app.chat_generations set status='failed',fence_token=${randomUUID()},error_code='CHAT_INPUT_REMOVED'
        where user_id=${userId} and ${record.resourceId}=any(input_message_ids)
          and (snapshot->>'awaitingVoiceReceipt'='true' or snapshot->>'voiceReceiptExpired'='true')`;
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
        voiceReceiptVersion: old.protected_payload.voiceReceiptVersion,
        contextMemoryIds: old.protected_payload.contextMemoryIds,
        userTimeZone: old.protected_payload.userTimeZone,
        deliveryOrigin: old.protected_payload.deliveryOrigin,
        replyToMessageIds: old.protected_payload.replyToMessageIds,
        orderIndex: old.sequence,
        isInterrupted:
          old.protected_payload.role === "user"
            ? old.answered_by === null
            : old.protected_payload.isInterrupted,
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
    const pending = await sql<{ message_id: string; protected_payload: Payload }[]>`
      select message_id,protected_payload from app.chat_messages where user_id=${userId} and conversation_id=${conversationId}
      and role='user' and answered_by is null and assigned_generation_id is null order by sequence desc limit 20`;
    if (!pending.length) return;
    const unresolved =
      await sql`select 1 from app.chat_generations where user_id=${userId} and conversation_id=${conversationId} and status='uncertain' limit 1`;
    if (unresolved.length) return;
    await sql`insert into app.chat_generations(id,user_id,conversation_id,status,available_at)
      select ${randomUUID()},${userId},${conversationId},'queued',now()+${this.coalesceMilliseconds}*interval '1 millisecond'
      where exists(select 1 from app.chat_sessions where user_id=${userId} and conversation_id=${conversationId})
      on conflict(user_id,conversation_id) where status in ('queued','dispatched') do nothing`;
    if (this.replyTimingScale === 0) return;
    const latest = pending[0];
    if (!latest) return;
    if (latest.protected_payload.sharedVoiceLeaseId) {
      // A phone call must not inherit a text chat's offline/typing wait.
      await sql`update app.chat_generations set snapshot=null,available_at=now()+${this.coalesceMilliseconds}*interval '1 millisecond'
        where user_id=${userId} and conversation_id=${conversationId} and status='queued'`;
      return;
    }
    const [current] = await sql<
      GenerationRow[]
    >`select * from app.chat_generations where user_id=${userId} and conversation_id=${conversationId} and status in ('queued','dispatched') for update`;
    if (!current || current.snapshot?.voiceLeaseId) return;
    if (current.snapshot?.simulation?.latestUserMessageId === latest.message_id) return;
    const [session] = await sql<
      Session[]
    >`select * from app.chat_sessions where user_id=${userId} and conversation_id=${conversationId}`;
    if (!session) return;
    const character = await this.content.read(
      sql,
      userId,
      "character",
      session.character_id,
    );
    if (!character) return;
    const history = await sql<{ message_id: string; protected_payload: Payload }[]>`
      select message_id,protected_payload from app.chat_messages where user_id=${userId} and conversation_id=${conversationId} order by sequence desc limit 24`;
    const now = Date.now();
    const plan = replyPlan(
      character,
      { resourceId: latest.message_id, payload: latest.protected_payload },
      history
        .toReversed()
        .map((m) => ({ resourceId: m.message_id, payload: m.protected_payload })),
      now,
    );
    const [priorGeneration] = current.snapshot?.simulation
      ? []
      : await sql<GenerationRow[]>`
      select * from app.chat_generations where user_id=${userId} and conversation_id=${conversationId}
      and id<>${current.id} order by created_at desc,id desc limit 1`;
    const previous = current.snapshot?.simulation;
    const quietUntil =
      Math.min(now, Date.parse(String(latest.protected_payload.createdAt))) +
      quietWindow(
        String(latest.protected_payload.text),
        pending.length,
        plan.continuingConversation,
      ) *
        this.replyTimingScale;
    const simulation: ReplySimulation = {
      ...(previous ?? {}),
      plan: current.status === "queued" ? plan : (previous?.plan ?? plan),
      latestUserMessageId: latest.message_id,
      quietUntil,
      composers:
        previous?.composers ?? priorGeneration?.snapshot?.simulation?.composers ?? {},
      resumeTypingAt: quietUntil,
    };
    const preparation = plan.continuingConversation
      ? 0
      : (2500 +
          Math.min(
            8000,
            String(latest.protected_payload.text).split(/\s+/).length * 200,
          )) *
        this.replyTimingScale;
    simulation.preparationMilliseconds = preparation;
    const availableAt =
      current.status === "queued" ? generationEligibleAt(simulation) : now;
    const snapshot: ChatGenerationInput = {
      userId,
      generationId: current.id,
      conversationId,
      characterId: session.character_id,
      inputMessageIds: [],
      messages: [],
      ...(current.snapshot ?? {}),
      simulation,
    };
    await sql`update app.chat_generations set snapshot=${JSON.stringify(snapshot)}::jsonb,
      available_at=case when status='queued' then ${new Date(availableAt).toISOString()} else available_at end where id=${current.id}`;
  }

  async composerActivity(
    userId: string,
    conversationId: string,
    event: {
      sessionId: string;
      sequence: number;
      activity: "edited" | "blurred" | "sent" | "inactive";
      remainingMilliseconds: number;
    },
  ): Promise<boolean> {
    return this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId);
      const [session] =
        await sql`select 1 from app.chat_sessions where user_id=${userId} and conversation_id=${conversationId}`;
      if (!session) missing();
      const [row] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where user_id=${userId} and conversation_id=${conversationId} and status in ('queued','dispatched') for update`;
      const simulation = row?.snapshot?.simulation;
      if (!row || !simulation || !row.snapshot) return false;
      const previous = simulation.composers[event.sessionId];
      if (previous && event.sequence <= previous.sequence) return true;
      const now = Date.now();
      const until =
        event.activity === "edited"
          ? now + Math.min(25_000, event.remainingMilliseconds)
          : event.activity === "blurred"
            ? Math.min(
                previous?.until ?? 0,
                now + Math.min(5000, event.remainingMilliseconds),
              )
            : 0;
      simulation.composers[event.sessionId] = { sequence: event.sequence, until };
      if (event.activity === "blurred") {
        simulation.quietUntil = Math.min(
          simulation.quietUntil,
          now + Math.min(5000, event.remainingMilliseconds),
        );
      }
      simulation.resumeTypingAt = handoffAt(simulation);
      const availableAt =
        row.status === "queued"
          ? Math.max(now, generationEligibleAt(simulation))
          : Math.max(now, handoffAt(simulation));
      await sql`update app.chat_generations set snapshot=${JSON.stringify(row.snapshot)}::jsonb,
        available_at=case when status='queued' or snapshot->'simulation'->>'preparedText' is not null then ${new Date(availableAt).toISOString()} else available_at end where id=${row.id}`;
      return true;
    });
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
        durableFollowups: true,
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
        where (status='queued' and available_at<=now()) or (status='dispatched' and snapshot->'simulation'->>'preparedText' is not null and available_at<=now()) or (status in ('dispatched','uncertain') and lease_until<=now())
        order by available_at,id limit 1`;
      if (!candidate) return undefined;
      await this.lock(sql, candidate.user_id);
      const [row] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where id=${candidate.id}
        and ((status='queued' and available_at<=now()) or (status='dispatched' and snapshot->'simulation'->>'preparedText' is not null and available_at<=now()) or (status in ('dispatched','uncertain') and lease_until<=now())) for update`;
      if (!row) return undefined;
      if (row.status === "dispatched" && row.snapshot?.simulation?.preparedText) {
        const fenceToken = randomUUID();
        await sql`update app.chat_generations set fence_token=${fenceToken},available_at=now()+${this.leaseMilliseconds}*interval '1 millisecond',lease_until=now()+${this.leaseMilliseconds}*interval '1 millisecond' where id=${row.id}`;
        return { input: row.snapshot, fenceToken, deliveryOnly: true };
      }
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
        {
          message_id: string;
          text_length: number;
          voice_lease_id: string | null;
          receipt_version: number | null;
        }[]
      >`select message_id,length(protected_payload->>'text') as text_length,protected_payload->>'sharedVoiceLeaseId' as voice_lease_id,(protected_payload->>'voiceReceiptVersion')::integer as receipt_version from app.chat_messages
        where user_id=${row.user_id} and conversation_id=${row.conversation_id} and role='user'
        and answered_by is null and assigned_generation_id is null order by sequence limit 20`;
      const ids: string[] = [];
      let pendingCharacters = 0;
      for (const message of pending) {
        if (
          ids.length > 0 &&
          (pending[0]?.receipt_version === 1 ||
            pendingCharacters + message.text_length > 40_000 ||
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
      const profile = {
        ...(await this.content.learner?.(sql, row.user_id)),
        subscriptionTier:
          (await this.content.subscriptionTier?.(sql, row.user_id)) ?? "free",
      };
      const window = historyWindow(
        profile.subscriptionTier,
        Boolean(pending[0]?.voice_lease_id),
      );
      const prior = await sql<
        { message_id: string }[]
      >`select message_id from app.chat_messages
        where user_id=${row.user_id} and conversation_id=${row.conversation_id} and (role='assistant' or answered_by is not null)
        order by sequence desc limit ${window}`;
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
      );
      const context = {
        stories: await this.content.list(sql, row.user_id, "story_progress", null),
        appointments:
          (await this.content.appointments?.(sql, row.user_id, session.character_id)) ??
          [],
      };
      const input: ChatGenerationInput = {
        userId: row.user_id,
        generationId: row.id,
        conversationId: row.conversation_id,
        characterId: session.character_id,
        inputMessageIds: ids,
        ...(row.snapshot?.simulation ? { simulation: row.snapshot.simulation } : {}),
        messages: conversationPrompt(
          character,
          memories,
          history,
          ids,
          profile,
          false,
          context,
        ),
      };
      const voiceLeaseId = pending[0]?.voice_lease_id;
      if (voiceLeaseId) {
        input.voiceLeaseId = voiceLeaseId;
        input.voiceReceiptRequired = pending[0]?.receipt_version === 1;
        input.messages = conversationPrompt(
          character,
          memories,
          history,
          ids,
          profile,
          true,
          context,
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
      if (input.simulation) {
        const now = Date.now();
        const until = generationEligibleAt(input.simulation);
        if (until > now) {
          await sql`update app.chat_generations set available_at=${new Date(until).toISOString()} where id=${row.id}`;
          return undefined;
        }
        input.simulation.resumeTypingAt = Math.max(
          input.simulation.plan.typingStartsAt,
          now,
        );
      }
      const fenceToken = randomUUID();
      await sql`update app.chat_generations set status='dispatched',fence_token=${fenceToken},
        lease_until=now()+${this.leaseMilliseconds}*interval '1 millisecond',input_message_ids=${ids}::uuid[],snapshot=${JSON.stringify(input)}::jsonb where id=${row.id}`;
      await sql`update app.chat_messages set assigned_generation_id=${row.id} where user_id=${row.user_id} and message_id=any(${ids}::uuid[])`;
      await sql`update app.chat_sessions set revision=revision+1 where user_id=${row.user_id} and conversation_id=${row.conversation_id}`;
      const [receipt] = input.voiceReceiptRequired
        ? await sql<{ heard_text: string; interrupted: boolean }[]>`
        select heard_text,interrupted from app.chat_voice_receipts where user_id=${row.user_id} and message_id=${ids[0] ?? ""}`
        : [];
      return {
        input,
        fenceToken,
        ...((receipt?.interrupted && !receipt.heard_text.trim()) ||
        !input.messages.some((m) => m.role === "user")
          ? { deliveryOnly: true }
          : {}),
      };
    });
  }

  async partial(claim: ClaimedGeneration, text: string): Promise<void> {
    await this.database
      .sql`update app.chat_generations set partial_text=${text},lease_until=now()+${this.leaseMilliseconds}*interval '1 millisecond'
      where id=${claim.input.generationId} and fence_token=${claim.fenceToken} and status='dispatched'`;
  }
  async prepare(claim: ClaimedGeneration, text: string): Promise<void> {
    if (
      claim.input.voiceLeaseId ||
      !claim.input.simulation ||
      this.replyTimingScale === 0
    ) {
      await this.finish(claim, text);
      return;
    }
    await this.database.sql.begin(async (sql) => {
      await this.lock(sql, claim.input.userId);
      const [row] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where id=${claim.input.generationId} and fence_token=${claim.fenceToken} and status='dispatched' for update`;
      const simulation = row?.snapshot?.simulation;
      if (!row?.snapshot || !simulation) return;
      if (claim.input.resultOperationId)
        row.snapshot.resultOperationId = claim.input.resultOperationId;
      row.snapshot.suppressLearning = claim.input.suppressLearning ?? false;
      simulation.fragments ??= replyFragments(text);
      simulation.preparedText ??= text;
      simulation.deliveredCount ??= 0;
      const now = Date.now();
      const start = Math.max(
        simulation.resumeTypingAt,
        simulation.plan.typingStartsAt,
        handoffAt(simulation),
      );
      simulation.nextDeliveryAt ??= now + 1000 * this.replyTimingScale;
      const due = Math.max(
        simulation.plan.firstBubbleAt,
        simulation.nextDeliveryAt,
        start +
          typingDuration(
            simulation.fragments[simulation.deliveredCount] ?? text,
            simulation.deliveredCount,
            row.id,
          ) *
            this.replyTimingScale,
      );
      await sql`update app.chat_generations set snapshot=${JSON.stringify(row.snapshot)}::jsonb,
        available_at=${new Date(due).toISOString()},lease_until=${new Date(due + this.leaseMilliseconds).toISOString()} where id=${row.id}`;
    });
  }

  async deliverPrepared(claim: ClaimedGeneration): Promise<void> {
    await this.finish(
      claim,
      claim.input.simulation?.preparedText ?? "",
      undefined,
      true,
    );
  }

  async finish(
    claim: ClaimedGeneration,
    text: string,
    retryCommandId?: string,
    paced = false,
  ): Promise<boolean> {
    const input = claim.input;
    return this.database.sql.begin(async (sql) => {
      await this.lock(sql, input.userId);
      const [row] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where id=${input.generationId}
        and fence_token=${claim.fenceToken} and (status='dispatched' or (status='completed' and (snapshot->>'awaitingVoiceReceipt'='true' or snapshot->>'voiceReceiptExpired'='true'))) for update`;
      if (!row) return false;
      if (retryCommandId) {
        const [receipt] = await sql<
          { conversation_id: string }[]
        >`select conversation_id from app.chat_retry_commands where user_id=${input.userId} and command_id=${retryCommandId}`;
        if (receipt && receipt.conversation_id !== input.conversationId)
          throw new AppError({
            code: "OPERATION_CONFLICT",
            message: "请求编号已用于其他会话。",
            statusCode: 409,
          });
        await sql`insert into app.chat_retry_commands(user_id,command_id,conversation_id,generation_id)
          values(${input.userId},${retryCommandId},${input.conversationId},${input.generationId}) on conflict do nothing`;
      }
      const available =
        await sql`select 1 from app.chat_messages where user_id=${input.userId} and message_id=any(${input.inputMessageIds}::uuid[])`;
      if (available.length !== input.inputMessageIds.length) {
        await sql`update app.chat_generations set status='failed',error_code='CHAT_INPUT_REMOVED' where id=${row.id}`;
        await sql`update app.chat_messages set assigned_generation_id=null where user_id=${input.userId} and assigned_generation_id=${row.id} and answered_by is null`;
        await this.schedule(sql, input.userId, input.conversationId);
        return false;
      }
      const simulation = paced ? row.snapshot?.simulation : undefined;
      const deliveredIndex = simulation?.deliveredCount ?? 0;
      if (simulation) {
        const now = Date.now();
        const start = Math.max(
          simulation.resumeTypingAt,
          simulation.plan.typingStartsAt,
          handoffAt(simulation),
        );
        const due = Math.max(
          simulation.plan.firstBubbleAt,
          simulation.nextDeliveryAt ?? 0,
          start +
            typingDuration(
              simulation.fragments?.[deliveredIndex] ?? text,
              deliveredIndex,
              row.id,
            ) *
              this.replyTimingScale,
        );
        if (due > now) {
          await sql`update app.chat_generations set available_at=${new Date(due).toISOString()},lease_until=${new Date(due + this.leaseMilliseconds).toISOString()} where id=${row.id}`;
          return false;
        }
      }
      const generatedText = text;
      let interrupted = false;
      if (input.voiceReceiptRequired) {
        const [receipt] = await sql<{ heard_text: string; interrupted: boolean }[]>`
          select heard_text,interrupted from app.chat_voice_receipts where user_id=${input.userId} and message_id=${input.inputMessageIds[0] ?? ""}`;
        if (!receipt && !input.voiceReceiptExpired) {
          input.awaitingVoiceReceipt = true;
          await sql`update app.chat_generations set status='completed',partial_text=${text},snapshot=${JSON.stringify(input)}::jsonb,
            completed_at=now(),lease_until=null where id=${row.id}`;
          return true;
        }
        text = receipt?.heard_text.trim() ?? "";
        interrupted =
          (receipt?.interrupted ?? true) ||
          text.replace(/\s+/g, " ") !== generatedText.trim().replace(/\s+/g, " ");
        input.suppressLearning = interrupted;
        input.awaitingVoiceReceipt = false;
        if (receipt) input.voiceReceiptExpired = false;
      }
      const now = new Date().toISOString();
      const allFragments =
        simulation?.fragments ??
        (input.voiceLeaseId ? (text ? [text] : []) : replyFragments(text));
      const fragments = simulation
        ? allFragments.slice(deliveredIndex, deliveredIndex + 1)
        : allFragments;
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
          isInterrupted: interrupted,
          replyToMessageIds: input.inputMessageIds,
          tokenEstimate: Math.ceil(fragment.length / 4),
        };
        if (input.learningChat && !input.suppressLearning)
          payload.learningOrigin = {
            source: "assistant",
            cycleId: input.learningChat.cycleId,
            userMessageId: input.learningChat.userMessageId,
            operationId: input.resultOperationId ?? input.generationId,
            fragmentIndex: simulation ? deliveredIndex : index,
            fragmentCount: allFragments.length,
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
      if (simulation && deliveredIndex + 1 < allFragments.length && row.snapshot) {
        simulation.deliveredCount = deliveredIndex + 1;
        simulation.resumeTypingAt = Date.now();
        simulation.nextDeliveryAt = simulation.resumeTypingAt;
        const due =
          simulation.resumeTypingAt +
          typingDuration(
            allFragments[deliveredIndex + 1] ?? "",
            deliveredIndex + 1,
            row.id,
          ) *
            this.replyTimingScale;
        await sql`update app.chat_generations set snapshot=${JSON.stringify(row.snapshot)}::jsonb,
          available_at=${new Date(due).toISOString()},lease_until=${new Date(due + this.leaseMilliseconds).toISOString()} where id=${row.id}`;
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
            { ...(conversation.payload as Payload), lastMessageAt: now },
          );
        return true;
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
      for (const messageId of input.inputMessageIds) {
        await sql`insert into app.chat_followups(user_id,message_id,conversation_id,character_id)
          values(${input.userId},${messageId},${input.conversationId},${input.characterId}) on conflict do nothing`;
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
            turnCount:
              Number((conversation.payload as Payload).turnCount ?? 0) +
              (fragments.length > 0 && !row.snapshot?.voiceTurnCounted ? 1 : 0),
          },
        );
      if (input.voiceReceiptRequired && fragments.length > 0)
        input.voiceTurnCounted = true;
      await sql`update app.chat_generations set status='completed',partial_text=${generatedText},snapshot=${JSON.stringify(input)}::jsonb,error_code=null,completed_at=now() where id=${row.id}`;
      await this.schedule(sql, input.userId, input.conversationId);
      return true;
    });
  }
  async expireVoiceReceipt(): Promise<boolean> {
    const [row] = await this.database.sql<
      GenerationRow[]
    >`select * from app.chat_generations
      where status='completed' and snapshot->>'awaitingVoiceReceipt'='true'
        and completed_at<now()-interval '5 minutes' order by completed_at limit 1`;
    if (!row?.snapshot || !row.fence_token) return false;
    const messageId = row.input_message_ids[0];
    if (!messageId) return false;
    // A killed playback process cannot attest that audio was heard. Keep generated output
    // in the generation ledger and close its conversational turn as an empty interruption.
    row.snapshot.voiceReceiptExpired = true;
    await this.finish(
      { input: row.snapshot, fenceToken: row.fence_token },
      row.partial_text,
    );
    return true;
  }
  async voiceReceipt(
    userId: string,
    conversationId: string,
    messageId: string,
    text: string,
    interrupted: boolean,
  ) {
    const claim = await this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId);
      const [message] = await sql<
        {
          assigned_generation_id: string | null;
          answered_by: string | null;
          protected_payload: Payload;
        }[]
      >`
        select assigned_generation_id,answered_by,protected_payload from app.chat_messages
        where user_id=${userId} and conversation_id=${conversationId} and message_id=${messageId} and role='user'`;
      if (
        message?.protected_payload.voiceReceiptVersion !== 1 ||
        !message.protected_payload.sharedVoiceLeaseId
      )
        missing();
      await sql`insert into app.chat_voice_receipts(user_id,message_id,heard_text,interrupted)
        values(${userId},${messageId},${text},${interrupted}) on conflict do nothing`;
      const id = message.assigned_generation_id ?? message.answered_by;
      if (!id) return undefined;
      const [row] = await sql<
        GenerationRow[]
      >`select * from app.chat_generations where user_id=${userId} and id=${id}`;
      return (row?.snapshot?.awaitingVoiceReceipt ||
        row?.snapshot?.voiceReceiptExpired) &&
        row.fence_token
        ? { input: row.snapshot, fenceToken: row.fence_token, text: row.partial_text }
        : undefined;
    });
    if (claim) await this.finish(claim, claim.text);
    return { accepted: true };
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
  async acknowledgeRetry(
    userId: string,
    conversationId: string,
    commandId: string,
    generationId: string,
  ): Promise<void> {
    await this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId);
      const [receipt] = await sql<
        { conversation_id: string }[]
      >`select conversation_id from app.chat_retry_commands where user_id=${userId} and command_id=${commandId}`;
      if (receipt && receipt.conversation_id !== conversationId)
        throw new AppError({
          code: "OPERATION_CONFLICT",
          message: "请求编号已用于其他会话。",
          statusCode: 409,
        });
      await sql`insert into app.chat_retry_commands(user_id,command_id,conversation_id,generation_id)
        values(${userId},${commandId},${conversationId},${generationId}) on conflict do nothing`;
    });
  }

  async retryWasApplied(
    userId: string,
    conversationId: string,
    commandId: string,
  ): Promise<boolean> {
    const [receipt] = await this.database.sql<
      { conversation_id: string }[]
    >`select conversation_id from app.chat_retry_commands where user_id=${userId} and command_id=${commandId}`;
    if (receipt && receipt.conversation_id !== conversationId)
      throw new AppError({
        code: "OPERATION_CONFLICT",
        message: "请求编号已用于其他会话。",
        statusCode: 409,
      });
    return receipt !== undefined;
  }

  async recoveryInput(
    userId: string,
    generationId: string,
  ): Promise<ChatGenerationInput | undefined> {
    const [row] = await this.database.sql<
      { snapshot: ChatGenerationInput | null }[]
    >`select snapshot from app.chat_generations where user_id=${userId} and id=${generationId} and status='uncertain'`;
    return row?.snapshot ?? undefined;
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
      if (!failed) return;
      if (failed.status !== "failed" && failed.status !== "uncertain") {
        await sql`insert into app.chat_retry_commands(user_id,command_id,conversation_id,generation_id)
          values(${userId},${commandId},${conversationId},${failed.id})`;
        return;
      }
      await sql`update app.chat_generations set status='failed',fence_token=${randomUUID()} where id=${failed.id}`;
      await sql`update app.chat_messages set assigned_generation_id=null,protected_payload=protected_payload-'sharedVoiceLeaseId' where user_id=${userId} and assigned_generation_id=${failed.id} and answered_by is null`;
      await this.schedule(sql, userId, conversationId);
      await sql`insert into app.chat_retry_commands(user_id,command_id,conversation_id,generation_id) values(${userId},${commandId},${conversationId},${failed.id})`;
    });
    return this.state(userId, conversationId);
  }
}
