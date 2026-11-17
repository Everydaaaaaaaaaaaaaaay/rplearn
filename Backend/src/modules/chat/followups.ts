import { randomUUID } from "node:crypto";
import type { ChatContentAccess } from "./contracts.js";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";

interface Followup {
  message_id: string;
  conversation_id: string;
  character_id: string;
  operation_id: string;
  request: unknown;
  lease_token: string | null;
}
export class ChatFollowupRepository {
  constructor(
    private database: DatabaseResource,
    private content: ChatContentAccess,
  ) {}
  private async recover(userId: string) {
    await this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended(${`${userId}:shared-chat`},0))`;
      const rows = await sql<
        { message_id: string; conversation_id: string; character_id: string }[]
      >`
        select m.message_id,m.conversation_id,s.character_id from app.chat_messages m
        join app.chat_generations g on g.id=m.answered_by and g.user_id=m.user_id
        join app.chat_sessions s on s.user_id=m.user_id and s.conversation_id=m.conversation_id
        where m.user_id=${userId} and m.role='user' and g.status='completed' and g.created_at>'epoch'::timestamptz
          and not exists(select 1 from app.chat_followups f where f.user_id=m.user_id and f.message_id=m.message_id)
        order by m.sequence limit 500`;
      for (const row of rows) {
        const message = await this.content.read(sql, userId, "message", row.message_id);
        const character = await this.content.read(
          sql,
          userId,
          "character",
          row.character_id,
        );
        if (!message || !character) {
          await sql`insert into app.chat_followups(user_id,message_id,conversation_id,character_id,completed_at)
            values(${userId},${row.message_id},${row.conversation_id},${row.character_id},now()) on conflict do nothing`;
          continue;
        }
        const payload = message.payload as {
          coachReviewJson?: string;
          createdAt?: string;
        };
        const relationship = (
          character.payload as {
            relationship?: {
              lastEvaluatedMessageAt?: string;
              lastEvaluatedMessageID?: string;
              recentEvaluatedMessageIDs?: string[];
            };
          }
        ).relationship;
        const evaluated = Boolean(
          Boolean(payload.coachReviewJson) ||
          relationship?.lastEvaluatedMessageID?.toLowerCase() === row.message_id ||
          (relationship?.recentEvaluatedMessageIDs?.some(
            (id) => id.toLowerCase() === row.message_id,
          ) ??
            false) ||
          (relationship?.lastEvaluatedMessageAt &&
            payload.createdAt &&
            Date.parse(relationship.lastEvaluatedMessageAt) >=
              Date.parse(payload.createdAt)),
        );
        await sql`insert into app.chat_followups(user_id,message_id,conversation_id,character_id,completed_at)
          values(${userId},${row.message_id},${row.conversation_id},${row.character_id},${evaluated ? new Date().toISOString() : null}) on conflict do nothing`;
      }
    });
  }
  async pending(userId: string) {
    await this.recover(userId);
    const jobs = await this.database.sql<Followup[]>`
      select f.* from app.chat_followups f join app.chat_messages m on m.user_id=f.user_id and m.message_id=f.message_id
      where f.user_id=${userId} and f.completed_at is null and (f.lease_until is null or f.lease_until<now())
      order by f.created_at,f.message_id limit 50`;
    return {
      jobs: jobs.map((j) => ({
        messageId: j.message_id,
        conversationId: j.conversation_id,
        characterId: j.character_id,
      })),
    };
  }
  async claim(userId: string, messageId: string, request: unknown) {
    const token = randomUUID();
    const [job] = await this.database.sql<Followup[]>`
      update app.chat_followups set request=coalesce(request,${JSON.stringify(request)}::jsonb),
        lease_token=${token},lease_until=now()+interval '5 minutes'
      where user_id=${userId} and message_id=${messageId} and completed_at is null
        and (lease_until is null or lease_until<now()) returning *`;
    return {
      claim: job
        ? { operationId: job.operation_id, token, request: job.request }
        : null,
    };
  }
  async complete(userId: string, messageId: string, token: string) {
    const rows = await this.database
      .sql`update app.chat_followups set completed_at=now(),lease_until=null
      where user_id=${userId} and message_id=${messageId} and lease_token=${token}`;
    if (!rows.count)
      throw new AppError({
        code: "CHAT_REVIEW_LEASE_EXPIRED",
        message: "辅助处理已由其他设备接续。",
        statusCode: 409,
      });
    return { completed: true };
  }
}
