import { z } from "zod";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import type { ContentRecord } from "../content/types.js";
import { AppError } from "../../shared/errors.js";
import type { LearningContextReader } from "./context.js";
import { LearningSession } from "./engine-repository.js";
import {
  chatBodyFingerprint,
  learningMessageOriginSchema,
  type LearningChatContext,
  type LearningMessageOrigin,
} from "./chat-contract.js";

export interface LearningChatReader {
  message: (
    sql: TransactionSql,
    userId: string,
    id: string,
  ) => Promise<ContentRecord | undefined>;
  conversation: (
    sql: TransactionSql,
    userId: string,
    id: string,
  ) => Promise<ContentRecord | undefined>;
}
const messageSchema = z.object({
  role: z.enum(["user", "assistant", "coach"]),
  kind: z.enum(["text", "voice", "storyLine"]),
  text: z.string(),
  isInterrupted: z.boolean(),
  learningOrigin: learningMessageOriginSchema,
});
interface PendingMessage {
  message_id: string;
  conversation_id: string;
  character_id: string;
  origin: LearningMessageOrigin;
  body: string;
}
function invalid(): never {
  throw new AppError({
    code: "LEARNING_CHAT_CONTEXT_INVALID",
    message: "聊天关联尚未同步或已失效，请完成同步后重试。",
    statusCode: 409,
  });
}
async function lock(sql: TransactionSql, userId: string) {
  await sql`select pg_advisory_xact_lock(hashtextextended(${`learning:${userId}`},0))`;
}

export class LearningChatRepository {
  constructor(
    private readonly database: DatabaseResource,
    private readonly context: LearningContextReader,
    private readonly reader: LearningChatReader,
  ) {}

  /** Appointments accept only assistant bubbles matching a completed server chat receipt. */
  async verifiedAppointmentMessages(
    sql: TransactionSql,
    userId: string,
    characterId: string,
    conversationId: string,
    records: readonly ContentRecord[],
  ): Promise<ContentRecord[]> {
    const eligible = new Set<string>();
    const groups = new Map<
      string,
      {
        record: ContentRecord;
        origin: Extract<LearningMessageOrigin, { source: "assistant" }>;
        body: string;
      }[]
    >();
    for (const record of records) {
      const payload = record.payload as {
        role?: string;
        text?: string;
        learningOrigin?: unknown;
      };
      if (payload.role !== "assistant") {
        eligible.add(record.resourceId);
        continue;
      }
      const parsed = learningMessageOriginSchema.safeParse(payload.learningOrigin);
      if (
        !parsed.success ||
        parsed.data.source !== "assistant" ||
        typeof payload.text !== "string"
      )
        continue;
      const group = groups.get(parsed.data.operationId) ?? [];
      group.push({ record, origin: parsed.data, body: payload.text });
      groups.set(parsed.data.operationId, group);
    }
    for (const [operationId, group] of groups) {
      const [proof] = await sql<
        {
          body_fingerprint: string | null;
          user_message_id: string;
          conversation_id: string;
          character_id: string;
          cycle_id: string;
          preceding_user_message_id: string | null;
          current_user_text: string | null;
          user_body_fingerprint: string;
        }[]
      >`
       select o.body_fingerprint,t.user_message_id,t.conversation_id,t.character_id,t.cycle_id,
         u.payload->>'text' as current_user_text,original_user.body_fingerprint as user_body_fingerprint,
         (select candidate.resource_id from app.content_records candidate
          where candidate.user_id=t.user_id and candidate.resource_type='message' and candidate.parent_id=t.conversation_id::text
           and candidate.deleted_at is null and candidate.payload->>'role'='user'
           and candidate.created_at <= (select min(fragment.created_at) from app.content_records fragment
              where fragment.user_id=t.user_id and fragment.resource_type='message' and fragment.parent_id=t.conversation_id::text
                and fragment.resource_id=any(${group.map((fragment) => fragment.record.resourceId)}::text[]))
          order by candidate.created_at desc,candidate.resource_id desc limit 1) as preceding_user_message_id
       from app.learning_chat_operations o join app.learning_chat_turns t using(user_id,user_message_id)
       join app.content_records u on u.user_id=t.user_id and u.resource_type='message' and u.resource_id=t.user_message_id::text
         and u.parent_id=t.conversation_id::text and u.deleted_at is null and u.payload->>'role'='user'
         and coalesce((u.payload->>'isInterrupted')::boolean,false)=false
       join app.learning_chat_outbox original_user on original_user.user_id=t.user_id and original_user.message_id=t.user_message_id
       where o.user_id=${userId} and o.operation_id=${operationId} and o.completed_at is not null`;
      if (
        !proof?.body_fingerprint ||
        proof.preceding_user_message_id !== proof.user_message_id ||
        typeof proof.current_user_text !== "string" ||
        chatBodyFingerprint(proof.current_user_text) !== proof.user_body_fingerprint ||
        proof.character_id.toLowerCase() !== characterId.toLowerCase() ||
        proof.conversation_id.toLowerCase() !== conversationId.toLowerCase()
      )
        continue;
      group.sort((a, b) => a.origin.fragmentIndex - b.origin.fragmentIndex);
      if (
        group.length !== group[0]?.origin.fragmentCount ||
        group.some(
          (fragment, index) =>
            fragment.record.deletedAt !== null ||
            fragment.origin.fragmentIndex !== index ||
            fragment.origin.fragmentCount !== group.length ||
            fragment.origin.cycleId !== proof.cycle_id ||
            fragment.origin.userMessageId !== proof.user_message_id,
        ) ||
        chatBodyFingerprint(group.map((f) => f.body).join("")) !==
          proof.body_fingerprint
      )
        continue;
      for (const fragment of group) eligible.add(fragment.record.resourceId);
    }
    return records.filter((record) => eligible.has(record.resourceId));
  }

  /** 在内容仓库拥有的保存事务中追加；不拿学习锁，避免与内容行锁逆序。 */
  async enqueue(sql: TransactionSql, userId: string, record: ContentRecord) {
    if (
      record.resourceType !== "message" ||
      record.version !== 1 ||
      record.deletedAt !== null ||
      record.parentId === null
    )
      return;
    const parsed = messageSchema.safeParse(record.payload);
    if (!parsed.success) return;
    const message = parsed.data;
    if (
      message.kind === "storyLine" ||
      message.role !== message.learningOrigin.source ||
      (message.role === "assistant" && message.isInterrupted)
    )
      return;
    const conversation = await this.reader.conversation(sql, userId, record.parentId);
    if (!conversation?.parentId || conversation.deletedAt !== null) return;
    await sql`insert into app.learning_chat_outbox(user_id,message_id,conversation_id,character_id,origin,body,body_fingerprint)
      values(${userId},${record.resourceId},${record.parentId},${conversation.parentId},${JSON.stringify(message.learningOrigin)}::jsonb,${message.text},${chatBodyFingerprint(message.text)})
      on conflict do nothing`;
  }

  /** 必须在模型调用前绑定已保存的用户正文，不能给翻译或主动问候补签收据。 */
  async begin(
    userId: string,
    operationId: string,
    chat: LearningChatContext,
    userText: string,
    requestFingerprint: string,
  ) {
    await this.database.sql.begin(async (sql) => {
      await lock(sql, userId);
      const record = await this.reader.message(sql, userId, chat.userMessageId);
      const message = messageSchema.safeParse(record?.payload);
      const conversation = await this.reader.conversation(
        sql,
        userId,
        chat.conversationId,
      );
      if (
        record?.parentId !== chat.conversationId ||
        !message.success ||
        message.data.role !== "user" ||
        message.data.kind === "storyLine" ||
        message.data.learningOrigin.source !== "user" ||
        message.data.learningOrigin.cycleId !== chat.cycleId ||
        chatBodyFingerprint(message.data.text) !== chatBodyFingerprint(userText) ||
        !conversation?.parentId
      )
        invalid();
      const [original] = await sql<
        {
          conversation_id: string;
          character_id: string;
          origin: LearningMessageOrigin;
          body_fingerprint: string;
        }[]
      >`select conversation_id,character_id,origin,body_fingerprint from app.learning_chat_outbox where user_id=${userId} and message_id=${chat.userMessageId}`;
      if (
        original?.origin.source !== "user" ||
        original.origin.cycleId !== chat.cycleId ||
        original.conversation_id !== chat.conversationId ||
        original.character_id !== conversation.parentId ||
        original.body_fingerprint !== chatBodyFingerprint(userText)
      )
        invalid();
      const session = new LearningSession(sql, userId, this.context);
      await session.resolveCharacter(conversation.parentId);
      // 周期必须由服务端实际签发；过去周期允许完成请求，但不会填入新的条。
      const issued =
        await sql`select 1 from app.learning_characters where user_id=${userId} and character_id=${conversation.parentId} and cycle_id=${chat.cycleId}
        union all select 1 from app.learning_attempts where user_id=${userId} and character_id=${conversation.parentId} and cycle_id=${chat.cycleId} limit 1`;
      if (!issued.length) invalid();
      await sql`insert into app.learning_chat_turns(user_id,user_message_id,conversation_id,character_id,cycle_id)
        values(${userId},${chat.userMessageId},${chat.conversationId},${conversation.parentId},${chat.cycleId}) on conflict do nothing`;
      const [turn] = await sql<
        { conversation_id: string; character_id: string; cycle_id: string }[]
      >`select conversation_id,character_id,cycle_id from app.learning_chat_turns where user_id=${userId} and user_message_id=${chat.userMessageId}`;
      if (
        turn?.conversation_id !== chat.conversationId ||
        turn.character_id !== conversation.parentId ||
        turn.cycle_id !== chat.cycleId
      )
        invalid();
      await sql`insert into app.learning_chat_operations(user_id,operation_id,user_message_id,request_fingerprint)
        values(${userId},${operationId},${chat.userMessageId},${requestFingerprint}) on conflict do nothing`;
      const [operation] = await sql<
        { user_message_id: string; request_fingerprint: string }[]
      >`select user_message_id,request_fingerprint from app.learning_chat_operations where user_id=${userId} and operation_id=${operationId}`;
      if (
        operation?.user_message_id !== chat.userMessageId ||
        operation.request_fingerprint !== requestFingerprint
      )
        invalid();
    });
  }

  /** 只有完整模型结果可到达此入口；保存指纹，不复制模型正文。重放可修复完成前故障。 */
  async complete(userId: string, operationId: string, body: string) {
    const fingerprint = chatBodyFingerprint(body);
    await this.database.sql.begin(async (sql) => {
      await lock(sql, userId);
      const rows =
        await sql`update app.learning_chat_operations set body_fingerprint=${fingerprint},completed_at=coalesce(completed_at,now())
        where user_id=${userId} and operation_id=${operationId} and (body_fingerprint is null or body_fingerprint=${fingerprint}) returning operation_id`;
      if (!rows.length) invalid();
    });
  }

  async drain(userId: string) {
    return this.database.sql.begin(async (sql) => {
      await lock(sql, userId);
      const session = new LearningSession(sql, userId, this.context);
      const rows = await sql<
        PendingMessage[]
      >`select message_id,conversation_id,character_id,origin,body from app.learning_chat_outbox
        where user_id=${userId} and processed_at is null order by checked_at,created_at,message_id limit 200`;
      if (rows.length)
        await sql`update app.learning_chat_outbox set checked_at=now() where user_id=${userId} and message_id=any(${rows.map((row) => row.message_id)}::uuid[])`;
      let processed = 0;
      const handled = new Set<string>();
      const settle = async (ids: string[], outcome: string) => {
        await sql`update app.learning_chat_outbox set body=null,processed_at=now(),outcome=${outcome} where user_id=${userId} and message_id=any(${ids}::uuid[]) and processed_at is null`;
        processed += ids.length;
        ids.forEach((id) => handled.add(id));
      };
      for (const row of rows) {
        if (handled.has(row.message_id)) continue;
        try {
          await session.resolveCharacter(row.character_id);
        } catch (error) {
          if (!(error instanceof AppError) || error.statusCode !== 404) throw error;
          await settle([row.message_id], "ignored");
          continue;
        }
        if (row.origin.source === "user") {
          const before = await session.character(row.character_id);
          const after = await session.recordMessage({
            characterId: row.character_id,
            cycleId: row.origin.cycleId,
            messageId: row.message_id,
            text: row.body,
          });
          await settle(
            [row.message_id],
            after.characters > before.characters ? "counted" : "ignored",
          );
          continue;
        }
        const origin = row.origin;
        const [proof] = await sql<
          {
            body_fingerprint: string | null;
            user_message_id: string;
            conversation_id: string;
            character_id: string;
            cycle_id: string;
            reply_event_id: string;
          }[]
        >`
          select o.body_fingerprint,t.user_message_id,t.conversation_id,t.character_id,t.cycle_id,t.reply_event_id
          from app.learning_chat_operations o join app.learning_chat_turns t using(user_id,user_message_id)
          where o.user_id=${userId} and o.operation_id=${origin.operationId}`;
        if (!proof?.body_fingerprint) continue;
        const fragments = await sql<
          PendingMessage[]
        >`select message_id,conversation_id,character_id,origin,body from app.learning_chat_outbox
          where user_id=${userId} and processed_at is null and origin->>'operationId'=${origin.operationId} order by (origin->>'fragmentIndex')::integer,message_id`;
        if (fragments.length < origin.fragmentCount) continue;
        const valid =
          fragments.length === origin.fragmentCount &&
          fragments.every(
            (fragment, index) =>
              fragment.origin.source === "assistant" &&
              fragment.origin.fragmentCount === origin.fragmentCount &&
              fragment.origin.fragmentIndex === index &&
              fragment.origin.cycleId === proof.cycle_id &&
              fragment.origin.userMessageId === proof.user_message_id &&
              fragment.character_id === proof.character_id &&
              fragment.conversation_id === proof.conversation_id,
          ) &&
          chatBodyFingerprint(fragments.map((fragment) => fragment.body).join("")) ===
            proof.body_fingerprint;
        if (!valid) {
          await settle(
            fragments.map((fragment) => fragment.message_id),
            "invalid",
          );
          continue;
        }
        const before = await session.character(proof.character_id);
        const after = await session.recordMessage({
          characterId: proof.character_id,
          cycleId: proof.cycle_id,
          messageId: proof.reply_event_id,
          text: fragments.map((fragment) => fragment.body).join(""),
        });
        await settle(
          fragments.map((fragment) => fragment.message_id),
          after.characters > before.characters ? "counted" : "ignored",
        );
      }
      // 不完整/失效候选不永久保存正文，也不阻塞其他消息。
      await sql`update app.learning_chat_outbox set body=null,processed_at=now(),outcome='expired' where user_id=${userId} and processed_at is null and created_at<now()-interval '7 days'`;
      return processed;
    });
  }

  async pendingUsers(limit: number) {
    return this.database.sql<
      { user_id: string }[]
    >`select user_id from app.learning_chat_outbox where processed_at is null group by user_id order by min(checked_at),min(created_at) limit ${limit}`;
  }
}
