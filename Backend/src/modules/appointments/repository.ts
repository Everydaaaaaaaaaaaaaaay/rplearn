import { currentAppointmentMemory } from "./memory-state.js";
import { AppError } from "../../shared/errors.js";
import { createHash, randomUUID } from "node:crypto";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import type {
  Appointment,
  AppointmentBlock,
  AppointmentMessage,
  AppointmentChoice,
  AppointmentCommand,
  AppointmentContextReader,
  AppointmentDetail,
  AppointmentGenerationContext,
  AppointmentNarrative,
  AppointmentReview,
  AppointmentSession,
  AppointmentSettlementWriter,
  AppointmentSummary,
} from "./contracts.js";
import {
  appointmentError,
  appointmentMessageFacts,
  assertEntry,
  resolveAction,
  resolveAppointmentTime,
  validateEvidence,
} from "./state.js";
const json = (value: unknown) => JSON.stringify(value);
const hash = (value: unknown) => createHash("sha256").update(json(value)).digest("hex");
interface Row {
  snapshot: Appointment;
  session: AppointmentSession | null;
  summary: AppointmentSummary | null;
  conversation_id: string;
  evidence: unknown;
}
interface Operation {
  recoverable: boolean;
  request_hash: string;
  status: string;
  lease_token: string;
  lease_until: Date | null;
  context: AppointmentGenerationContext;
  draft: { block: AppointmentBlock; outcome: string } | null;
  response: AppointmentDetail | null;
}
export class AppointmentRepository {
  constructor(
    private database: DatabaseResource,
    private context: AppointmentContextReader,
    private narrative: AppointmentNarrative,
    private settlement: AppointmentSettlementWriter,
    private now: () => Date = () => new Date(),
  ) {}
  static async chatContext(sql: TransactionSql, userId: string, characterId: string) {
    const rows = await sql<Row[]>`select snapshot,summary from app.appointments
      where user_id=${userId} and character_id=${characterId} order by created_at desc limit 20`;
    return rows.map(({ snapshot, summary }) => ({
      ...snapshot,
      status:
        snapshot.status === "confirmed" &&
        Date.parse(snapshot.windowClosesAt) < Date.now()
          ? "expired"
          : snapshot.status,
      ...(snapshot.status === "completed" && summary
        ? { memories: summary.memories }
        : {}),
    }));
  }
  private async lock(sql: TransactionSql, userId: string, id: string) {
    await sql`select pg_advisory_xact_lock(hashtextextended(${`appointment:${userId}:${id}`},0))`;
  }
  private async saved(sql: TransactionSql, userId: string, id: string): Promise<Row> {
    const [row] = await sql<
      Row[]
    >`select snapshot,session,summary,conversation_id,evidence from app.appointments where id=${id} and user_id=${userId} for update`;
    if (!row) appointmentError("APPOINTMENT_NOT_FOUND", "找不到这次约定。", 404);
    return row;
  }
  private detailRow(row: Row): AppointmentDetail {
    const appointment = { ...row.snapshot };
    if (
      appointment.status === "confirmed" &&
      this.now().getTime() > Date.parse(appointment.windowClosesAt)
    )
      appointment.status = "expired";
    return {
      appointment,
      session: row.session,
      summary: row.summary,
      serverNow: this.now().toISOString(),
    };
  }
  private async projectDetail(
    sql: TransactionSql,
    userId: string,
    detail: AppointmentDetail,
  ): Promise<AppointmentDetail> {
    const readMemory = this.settlement.readMemory?.bind(this.settlement);
    if (!readMemory || !detail.summary?.memories.length) return detail;
    const memories: AppointmentSummary["memories"] = [];
    for (const memory of detail.summary.memories)
      memories.push(
        currentAppointmentMemory(memory, await readMemory(sql, userId, memory.id)),
      );
    return { ...detail, summary: { ...detail.summary, memories } };
  }
  async list(userId: string) {
    const rows = await this.database.sql<
      Row[]
    >`select snapshot,session,summary,conversation_id,evidence from app.appointments where user_id=${userId} order by created_at desc limit 200`;
    return {
      appointments: rows.map((r) => this.detailRow(r).appointment),
      serverNow: this.now().toISOString(),
    };
  }
  async detail(userId: string, id: string) {
    const row = await this.database.sql.begin(async (sql) =>
      this.saved(sql, userId, id),
    );
    if (
      row.snapshot.status === "completed" &&
      row.summary?.affinity.status === "pending"
    )
      await this.ensureReview(userId, id).catch(() => undefined);
    return this.database.sql.begin(async (sql) =>
      this.projectDetail(
        sql,
        userId,
        this.detailRow(await this.saved(sql, userId, id)),
      ),
    );
  }
  async detect(userId: string, input: { characterId: string; conversationId: string }) {
    const source = await this.database.sql.begin(async (sql) => ({
      character: await this.context.character(sql, userId, input.characterId),
      messages: await this.context.messages(
        sql,
        userId,
        input.characterId,
        input.conversationId,
      ),
    }));
    if (
      !source.messages.some((m) => m.role === "user") ||
      !source.messages.some((m) => m.role === "assistant")
    )
      return await this.list(userId);
    const digest = hash(appointmentMessageFacts(source.messages));
    // Stable message facts reuse the same AI receipt even if annotations advance resource revisions.
    const operationId = stableId(
      `detect:${userId}:${input.characterId}:${input.conversationId}:${digest}`,
    );
    const existing = (await this.list(userId)).appointments.filter(
      (a) => a.characterId === input.characterId,
    );
    const token = randomUUID();
    const prepared = await this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId, operationId);
      const [previous] = await sql<
        {
          status: string;
          lease_until: string | null;
          context: Parameters<AppointmentNarrative["detect"]>[0];
        }[]
      >`select status,lease_until::text,context from app.appointment_operations where user_id=${userId} and command_id=${operationId} for update`;
      if (previous?.status === "completed") return { done: true as const };
      if (
        previous?.status === "running" &&
        previous.lease_until &&
        Date.parse(previous.lease_until) > this.now().getTime()
      )
        appointmentError("APPOINTMENT_OPERATION_PENDING", "正在确认约定，请稍后刷新。");
      let context = previous?.context ?? {
        userId,
        operationId,
        ...source,
        serverNow: this.now().toISOString(),
        existing,
      };
      if (previous?.status === "failed")
        context = {
          ...context,
          operationId: stableId(`detect-retry:${context.operationId}`),
        };
      await sql`insert into app.appointment_operations(user_id,command_id,kind,request_hash,status,lease_token,lease_until,context)
       values(${userId},${operationId},'detect',${digest},'running',${token},${new Date(this.now().getTime() + 15 * 60_000).toISOString()}::timestamptz,${json(context)}::jsonb)
       on conflict(user_id,command_id) do update set status='running',lease_token=excluded.lease_token,lease_until=excluded.lease_until,context=excluded.context`;
      return { done: false as const, context };
    });
    if (prepared.done) return await this.list(userId);
    try {
      const detected = await this.narrative.detect(prepared.context);
      if (!detected) {
        await this.database
          .sql`update app.appointment_operations set status='completed',lease_until=null where user_id=${userId} and command_id=${operationId} and lease_token=${token}`;
        return await this.list(userId);
      }
      validateEvidence(detected.evidence, prepared.context.messages);
      if (
        detected.cityId !== source.character.cityId ||
        detected.timeZone !== source.character.timeZone
      )
        appointmentError("APPOINTMENT_CITY_UNCLEAR", "请确认旅伴所在城市与时区。", 422);
      const startsAt = resolveAppointmentTime(
          detected.localStartsAt,
          detected.timeZone,
        ),
        start = Date.parse(startsAt);
      if (
        !detected.title.trim() ||
        !detected.placeName.trim() ||
        detected.durationMinutes < 10 ||
        detected.durationMinutes > 480
      )
        appointmentError(
          "APPOINTMENT_UNCONFIRMED",
          "请先确认完整的主题、地点与时长。",
          422,
        );
      const evidence = prepared.context.messages.filter((m) =>
        detected.evidence.some((e) => e.messageId === m.id && e.version === m.version),
      );
      const evidenceHash = hash(appointmentMessageFacts(evidence));
      await this.database.sql.begin(async (sql) => {
        await this.lock(sql, userId, input.characterId);
        const current = await this.context.messages(
          sql,
          userId,
          input.characterId,
          input.conversationId,
        );
        if (
          evidence.some(
            (original) =>
              !current.some(
                (message) =>
                  message.id === original.id && message.version >= original.version,
              ),
          )
        )
          appointmentError(
            "APPOINTMENT_EVIDENCE_CHANGED",
            "消息版本已变化，请重新确认。",
          );
        if (hash(appointmentMessageFacts(current)) !== digest)
          appointmentError(
            "APPOINTMENT_EVIDENCE_CHANGED",
            "对话已有新消息，请重新检测约定。",
          );
        if (
          hash(
            appointmentMessageFacts(
              current.filter((m) =>
                detected.evidence.some((e) => e.messageId === m.id),
              ),
            ),
          ) !== evidenceHash
        )
          appointmentError("APPOINTMENT_EVIDENCE_CHANGED", "消息已更新，请重新确认。");
        const [previous] =
          await sql`select id from app.appointments where user_id=${userId} and character_id=${input.characterId} and evidence_hash=${evidenceHash}`;
        if (previous) return;
        if (detected.replacesAppointmentId) {
          const old = await this.saved(sql, userId, detected.replacesAppointmentId);
          if (
            old.snapshot.characterId !== input.characterId ||
            old.snapshot.status !== "confirmed"
          )
            appointmentError(
              "APPOINTMENT_RESCHEDULE_CONFLICT",
              "这次约定已开始或结束，不能改期。",
            );
          const previousEvidence = old.evidence as { id: string }[];
          if (evidence.some((m) => previousEvidence.some((p) => p.id === m.id)))
            appointmentError(
              "APPOINTMENT_UNCONFIRMED",
              "改期需要双方新的确认消息。",
              422,
            );
          const cancelled = {
            ...old.snapshot,
            status: "cancelled",
            revision: old.snapshot.revision + 1,
          };
          await sql`update app.appointments set snapshot=${json(cancelled)}::jsonb,updated_at=now() where id=${old.snapshot.id}`;
        }
        const appointment: Appointment = {
          id: randomUUID(),
          characterId: input.characterId,
          title: detected.title,
          cityId: detected.cityId,
          cityName: detected.cityName,
          timeZone: detected.timeZone,
          placeName: detected.placeName,
          startsAt,
          endsAt: new Date(start + detected.durationMinutes * 60_000).toISOString(),
          windowOpensAt: new Date(start - 30 * 60_000).toISOString(),
          windowClosesAt: new Date(start + 120 * 60_000).toISOString(),
          status: "confirmed",
          revision: 0,
        };
        await sql`insert into app.appointments(id,user_id,character_id,conversation_id,evidence_hash,evidence,snapshot) values(${appointment.id},${userId},${input.characterId},${input.conversationId},${evidenceHash},${json(evidence)}::jsonb,${json(appointment)}::jsonb)`;
      });
      await this.database
        .sql`update app.appointment_operations set status='completed',lease_until=null where user_id=${userId} and command_id=${operationId} and lease_token=${token}`;
      return await this.list(userId);
    } catch (error) {
      await this.database
        .sql`update app.appointment_operations set status='failed',lease_until=null where user_id=${userId} and command_id=${operationId} and lease_token=${token}`;
      throw error;
    }
  }
  async start(userId: string, id: string, input: AppointmentCommand) {
    return this.mutate(userId, id, input, "start");
  }
  async choose(userId: string, id: string, input: AppointmentChoice) {
    return this.mutate(userId, id, input, "choice");
  }
  async cancel(userId: string, id: string, input: AppointmentCommand) {
    return this.mutate(userId, id, input, "cancel");
  }
  private async mutate(
    userId: string,
    id: string,
    input: AppointmentChoice,
    kind: "start" | "choice" | "cancel",
  ): Promise<AppointmentDetail> {
    const requestHash = hash({ id, kind, input }),
      token = randomUUID();
    const prepared = await this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId, id);
      const row = await this.saved(sql, userId, id);
      const [previous] = await sql<
        Operation[]
      >`select * from app.appointment_operations where user_id=${userId} and command_id=${input.commandId} for update`;
      if (previous?.request_hash !== undefined && previous.request_hash !== requestHash)
        appointmentError(
          "APPOINTMENT_COMMAND_CONFLICT",
          "同一操作编号不能用于不同请求。",
        );
      if (previous?.status === "completed" && previous.response)
        return { response: previous.response };
      if (
        previous?.status === "running" &&
        previous.lease_until &&
        new Date(previous.lease_until).getTime() > this.now().getTime()
      )
        appointmentError(
          "APPOINTMENT_OPERATION_PENDING",
          "这次行动仍在生成，请稍后使用同一操作重试。",
        );
      if (row.snapshot.revision !== input.expectedRevision)
        appointmentError(
          "APPOINTMENT_VERSION_CONFLICT",
          "另一个设备已更新故事，请先刷新。",
        );
      if (kind === "cancel") {
        if (row.snapshot.status !== "confirmed")
          appointmentError("APPOINTMENT_CLOSED", "约定已结束。");
        row.snapshot = {
          ...row.snapshot,
          status: "cancelled",
          revision: row.snapshot.revision + 1,
        };
        await sql`update app.appointment_operations set status='failed',lease_token=null,lease_until=null where appointment_id=${id} and status='running'`;
        await this.save(sql, userId, row);
        const response = this.detailRow(row);
        await sql`insert into app.appointment_operations(user_id,command_id,appointment_id,kind,request_hash,status,response) values(${userId},${input.commandId},${id},${kind},${requestHash},'completed',${json(response)}::jsonb)`;
        return { response };
      }
      const [running] = await sql<
        { lease_until: Date }[]
      >`select lease_until from app.appointment_operations where appointment_id=${id} and status='running' and command_id<>${input.commandId}`;
      if (running && new Date(running.lease_until).getTime() > this.now().getTime())
        appointmentError("APPOINTMENT_OPERATION_PENDING", "另一项行动正在处理。");
      await sql`update app.appointment_operations set status='failed',lease_token=null,lease_until=null where appointment_id=${id} and status='running'`;
      if (kind === "start") {
        if (row.session) return { response: this.detailRow(row) };
        await this.context.verifyEvidence?.(
          sql,
          userId,
          row.conversation_id,
          row.evidence as AppointmentMessage[],
        );
        assertEntry(row.snapshot, await this.context.city(sql, userId), this.now());
      } else if (row.snapshot.status !== "in_progress" || !row.session)
        appointmentError("APPOINTMENT_NOT_STARTED", "请先进入约定。");
      const session = row.session ?? { id: randomUUID(), blocks: [], decisions: [] };
      let context: AppointmentGenerationContext = previous?.context ?? {
        userId,
        operationId: input.commandId,
        appointment: row.snapshot,
        character: await this.context.character(sql, userId, row.snapshot.characterId),
        session,
        action: kind === "choice" ? resolveAction(session, input) : null,
      };
      if (previous?.status === "failed" && previous.recoverable && !previous.draft) {
        const attempt = (context.recoveryAttempt ?? 0) + 1;
        context = {
          ...context,
          operationId: stableId(`recovery:${input.commandId}:${String(attempt)}`),
          recoveryAttempt: attempt,
          serviceFundedRetry: true,
        };
      }
      await sql`insert into app.appointment_operations(user_id,command_id,appointment_id,kind,request_hash,status,lease_token,lease_until,context)
   values(${userId},${input.commandId},${id},${kind},${requestHash},'running',${token},${new Date(this.now().getTime() + 15 * 60_000).toISOString()}::timestamptz,${json(context)}::jsonb)
   on conflict(user_id,command_id) do update set status='running',lease_token=excluded.lease_token,lease_until=excluded.lease_until,context=excluded.context,recoverable=false,updated_at=now()`;
      return { context, draft: previous?.draft };
    });
    if ("response" in prepared)
      return prepared.response.appointment.status === "completed"
        ? this.detail(userId, id)
        : prepared.response;
    try {
      const draft = prepared.draft ?? (await this.narrative.generate(prepared.context));
      // Save accepted AI output before final application: crash/retry never regenerates a different branch.
      await this.database
        .sql`update app.appointment_operations set draft=${json(draft)}::jsonb where user_id=${userId} and command_id=${input.commandId} and lease_token=${token} and status='running'`;
      const result = await this.database.sql.begin(async (sql) => {
        await this.lock(sql, userId, id);
        const row = await this.saved(sql, userId, id);
        const [operation] = await sql<
          Operation[]
        >`select * from app.appointment_operations where user_id=${userId} and command_id=${input.commandId} for update`;
        if (
          operation?.lease_token !== token ||
          operation.status !== "running" ||
          row.snapshot.revision !== input.expectedRevision
        )
          appointmentError(
            "APPOINTMENT_VERSION_CONFLICT",
            "故事已更新，此次生成未被接受。",
          );
        const session = structuredClone(prepared.context.session);
        const block = {
          ...draft.block,
          id: stableId(`block:${id}:${input.commandId}`),
          sequence: session.blocks.length,
        };
        if (prepared.context.action) {
          const previousBlock = session.blocks.at(-1);
          if (!previousBlock)
            appointmentError("APPOINTMENT_INVALID_SESSION", "故事缺少当前段落。", 500);
          session.decisions.push({
            id: input.commandId,
            blockId: previousBlock.id,
            input: prepared.context.action.input,
            custom: prepared.context.action.custom,
            outcome: draft.outcome,
            createdAt: this.now().toISOString(),
          });
        }
        session.blocks.push(block);
        row.session = session;
        row.snapshot = {
          ...row.snapshot,
          status: block.ending ? "completed" : "in_progress",
          revision: row.snapshot.revision + 1,
        };
        if (block.ending)
          row.summary = {
            title: row.snapshot.title,
            reflection: "正在根据已发生的经历整理总结。",
            affinity: { status: "pending", reason: "关系审阅与结算尚未完成。" },
            memories: [],
          };
        await this.save(sql, userId, row);
        const response = this.detailRow(row);
        await sql`update app.appointment_operations set status='completed',response=${json(response)}::jsonb,lease_until=null where user_id=${userId} and command_id=${input.commandId} and lease_token=${token}`;
        return response;
      });
      if (result.appointment.status === "completed") {
        await this.ensureReview(userId, id).catch(() => undefined);
        return await this.database.sql.begin(async (sql) =>
          this.projectDetail(
            sql,
            userId,
            this.detailRow(await this.saved(sql, userId, id)),
          ),
        );
      }
      return result;
    } catch (error) {
      const recoverable =
        error instanceof AppError &&
        (error.code.startsWith("AI_UPSTREAM_") ||
          [
            "AI_OUTPUT_LIMIT",
            "AI_EMPTY_RESPONSE",
            "OPERATION_IN_PROGRESS",
            "OPERATION_FINALIZED",
            "OPERATION_RESULT_EXPIRED",
          ].includes(error.code) ||
          (error.code.startsWith("APPOINTMENT_") && error.statusCode >= 500));
      await this.database
        .sql`update app.appointment_operations set status='failed',lease_until=null,recoverable=${recoverable} where user_id=${userId} and command_id=${input.commandId} and lease_token=${token} and status='running'`;
      throw error;
    }
  }
  private async save(sql: TransactionSql, userId: string, row: Row) {
    await sql`update app.appointments set snapshot=${json(row.snapshot)}::jsonb,session=${json(row.session)}::jsonb,summary=${json(row.summary)}::jsonb,updated_at=now() where id=${row.snapshot.id} and user_id=${userId}`;
  }
  private async ensureReview(userId: string, id: string) {
    const context = await this.database.sql.begin(async (sql) => {
      const row = await this.saved(sql, userId, id);
      if (row.snapshot.status !== "completed" || !row.session) return null;
      const [existing] =
        await sql`select 1 from app.appointment_settlements where appointment_id=${id}`;
      if (existing) return null;
      const [lease] = await sql<
        { review_operation_id: string | null; review_lease_until: string | null }[]
      >`select review_operation_id::text,review_lease_until::text from app.appointments where id=${id}`;
      if (
        lease?.review_lease_until &&
        Date.parse(lease.review_lease_until) > this.now().getTime()
      )
        return null;
      // Crash recovery reuses the same request; a completed rejected review gets a fresh attempt.
      const operationId = lease?.review_operation_id ?? randomUUID();
      await sql`update app.appointments set review_operation_id=${operationId},review_lease_until=${new Date(this.now().getTime() + 15 * 60_000).toISOString()}::timestamptz where id=${id}`;
      return {
        userId,
        operationId,
        appointment: row.snapshot,
        session: row.session,
        character: await this.context.character(sql, userId, row.snapshot.characterId),
        action: null,
      };
    });
    if (!context) return;
    try {
      const review = await this.narrative.review(context);
      const decisionIds = new Set(context.session.decisions.map((d) => d.id)),
        blockIds = new Set(context.session.blocks.map((b) => b.id));
      if (
        review.signals.some(
          (s) =>
            s.evidenceDecisionIds.length === 0 ||
            s.evidenceDecisionIds.some((id) => !decisionIds.has(id)),
        ) ||
        review.memories.some(
          (m) =>
            m.evidenceBlockIds.length === 0 ||
            m.evidenceBlockIds.some((id) => !blockIds.has(id)),
        )
      )
        appointmentError("APPOINTMENT_REVIEW_INVALID", "总结证据不完整。", 502);
      await this.database.sql.begin(async (sql) => {
        await this.lock(sql, userId, id);
        const row = await this.saved(sql, userId, id);
        const inserted =
          await sql`insert into app.appointment_settlements(appointment_id,user_id,review,evidence_hash) values(${id},${userId},${json(review)}::jsonb,${hash(context.session)}) on conflict do nothing returning appointment_id`;
        if (!inserted.length) return;
        const memories = review.memories.map((m, index) => ({
          id: stableId(`memory:${id}:${String(index)}`),
          content: m.content,
          status: "active",
        }));
        for (const memory of memories)
          await this.settlement.memory(
            sql,
            userId,
            row.snapshot.characterId,
            memory.id,
            memory.content,
            id,
            stableId(`memory-sync:${memory.id}`),
            json({
              appointmentId: id,
              sessionId: context.session.id,
              blockIds:
                review.memories[memories.indexOf(memory)]?.evidenceBlockIds ?? [],
              decisionIds: context.session.decisions.map((d) => d.id),
              startsAt: context.appointment.startsAt,
              timeZone: context.appointment.timeZone,
            }),
            new Intl.DateTimeFormat("sv-SE", {
              timeZone: context.appointment.timeZone,
              year: "numeric",
              month: "2-digit",
              day: "2-digit",
            }).format(new Date(context.appointment.startsAt)),
          );
        row.summary = {
          title: row.snapshot.title,
          reflection: review.reflection,
          affinity: { status: "pending", reason: "共同经历已审阅，等待关系引擎结算。" },
          memories,
        };
        await this.save(sql, userId, row);
      });
    } catch (error) {
      await this.database
        .sql`update app.appointments set review_operation_id=null,review_lease_until=null where id=${id} and user_id=${userId} and review_operation_id=${context.operationId}`;
      throw error;
    }
  }
  async settlementSeed(userId: string, id: string) {
    await this.ensureReview(userId, id);
    return this.database.sql.begin(async (sql) => {
      const row = await this.saved(sql, userId, id);
      const [ledger] = await sql<
        { review: AppointmentReview; status: string; created_at: Date }[]
      >`select review,status,created_at from app.appointment_settlements where appointment_id=${id}`;
      if (!ledger)
        appointmentError("APPOINTMENT_SETTLEMENT_PENDING", "经历审阅尚未完成。");
      const character = await this.settlement.character(
        sql,
        userId,
        row.snapshot.characterId,
      );
      if (character?.deletedAt !== null)
        appointmentError("APPOINTMENT_CHARACTER_NOT_FOUND", "角色已移除。", 404);
      return {
        eventId: id,
        settlementAt: new Date(ledger.created_at).toISOString(),
        characterVersion: character.version,
        relationship:
          (character.payload as { relationship?: Record<string, unknown> })
            .relationship ?? null,
        review: ledger.review,
        settled: ledger.status === "settled",
      };
    });
  }
  async settle(
    userId: string,
    id: string,
    input: {
      commandId: string;
      expectedCharacterVersion: number;
      relationship: Record<string, unknown>;
    },
  ) {
    return this.database.sql.begin(async (sql) => {
      await this.lock(sql, userId, id);
      const row = await this.saved(sql, userId, id);
      const [ledger] = await sql<
        { review: AppointmentReview; status: string }[]
      >`select review,status from app.appointment_settlements where appointment_id=${id} for update`;
      if (!ledger) appointmentError("APPOINTMENT_SETTLEMENT_PENDING", "经历尚未审阅。");
      if (ledger.status === "settled")
        return this.projectDetail(sql, userId, this.detailRow(row));
      const character = await this.settlement.character(
        sql,
        userId,
        row.snapshot.characterId,
      );
      if (character?.deletedAt !== null)
        appointmentError("APPOINTMENT_CHARACTER_NOT_FOUND", "角色已移除。", 404);
      if (character.version !== input.expectedCharacterVersion)
        appointmentError(
          "CONTENT_VERSION_CONFLICT",
          "角色关系已更新，请重新读取结算依据。",
        );
      const previous =
        (character.payload as { relationship?: Record<string, unknown> })
          .relationship ?? {};
      const snapshot = input.relationship;
      const after = Number(snapshot.affinity);
      const events = Array.isArray(snapshot.recentEvents)
        ? (snapshot.recentEvents as { id: string; source: string; delta: number }[])
        : [];
      const event = events.find(
        (e) => e.id.toLowerCase() === id.toLowerCase() && e.source === "appointment",
      );
      const priorIds = Array.isArray(previous.settledAppointmentIDs)
        ? (previous.settledAppointmentIDs as string[])
        : [];
      const ids = Array.isArray(snapshot.settledAppointmentIDs)
        ? (snapshot.settledAppointmentIDs as string[])
        : [];
      if (
        !Number.isFinite(after) ||
        after < 0 ||
        after > 150 ||
        !event ||
        !Number.isFinite(event.delta) ||
        after - event.delta < 0 ||
        after - event.delta > 150 ||
        after - event.delta > Number(previous.affinity ?? 10) + 0.000001 ||
        event.delta < -18 ||
        event.delta > 5 ||
        !ids.some((e) => e.toLowerCase() === id.toLowerCase()) ||
        priorIds.some((e) => !ids.some((i) => i.toLowerCase() === e.toLowerCase())) ||
        Number(snapshot.revision) !== Number(previous.revision ?? 0) + 1
      )
        appointmentError(
          "APPOINTMENT_SETTLEMENT_INVALID",
          "关系结果与本次经历不匹配。",
          422,
        );
      await this.settlement.relationship(
        sql,
        userId,
        row.snapshot.characterId,
        input.expectedCharacterVersion,
        snapshot,
        input.commandId,
      );
      const receipt = {
        before: after - event.delta,
        after,
        delta: event.delta,
        reason: ledger.review.reflection,
      };
      await sql`update app.appointment_settlements set status='settled',receipt=${json(receipt)}::jsonb,settled_at=now() where appointment_id=${id}`;
      if (!row.summary)
        appointmentError("APPOINTMENT_INVALID_SESSION", "总结缺失。", 500);
      row.summary = { ...row.summary, affinity: { status: "settled", ...receipt } };
      await this.save(sql, userId, row);
      return this.projectDetail(sql, userId, this.detailRow(row));
    });
  }
}
export function stableId(value: string) {
  const hex = createHash("sha256").update(value).digest("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}
