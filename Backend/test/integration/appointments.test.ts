import { createLearningChatService } from "../../src/modules/learning/chat-service.js";
import { createContentReadService } from "../../src/modules/content/service.js";
import type { LearningContextReader } from "../../src/modules/learning/context.js";
import { chatBodyFingerprint } from "../../src/modules/learning/chat-contract.js";
import { AppError } from "../../src/shared/errors.js";
/* eslint-disable @typescript-eslint/require-await, @typescript-eslint/unbound-method -- injected asynchronous test doubles use no instance state. */
/* eslint-disable @typescript-eslint/no-non-null-assertion -- fixtures assert their required shape through business expectations. */
import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { integrationConfig } from "../helpers/integration.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAppointmentService } from "../../src/modules/appointments/service.js";
import { createAppointmentContentService } from "../../src/modules/content/service.js";
import type {
  AppointmentGenerationContext,
  Appointment,
  AppointmentNarrative,
  AppointmentMessage,
  DetectedAppointment,
} from "../../src/modules/appointments/contracts.js";
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "durable appointment transactions",
  () => {
    let runtime: RuntimeDependencies,
      service: ReturnType<typeof createAppointmentService>;
    const user = randomUUID(),
      other = randomUUID(),
      characterId = randomUUID(),
      conversationId = randomUUID();
    let clock = new Date("2026-11-01T12:00:00Z"),
      city = "london",
      generationCount = 0,
      ending = false;
    let messages: AppointmentMessage[] = [];
    let detection: DetectedAppointment | null = null;
    let gate: (() => Promise<void>) | null = null;
    const narrative: AppointmentNarrative = {
      detect: async () => detection,
      generate: async (context) => {
        generationCount++;
        if (gate) await gate();
        return {
          block: {
            id: randomUUID(),
            sequence: context.session.blocks.length,
            location: "Canal",
            beats: [
              {
                speaker: "character",
                english: "Let's walk along the canal.",
                chinese: "沿河走走吧。",
              },
            ],
            choices: ending ? [] : [{ id: "walk", english: "Walk", chinese: "散步" }],
            ending,
            ...(context.paragraphScenes ? { presentation: "paragraphs" as const } : {}),
          },
          outcome: "We walked along the canal.",
        };
      },
      review: async (context) => ({
        reflection: "A walk together.",
        signals: [],
        memories: [
          {
            content: "We walked along the canal.",
            evidenceBlockIds: context.session.blocks.map((b) => b.id),
          },
        ],
      }),
    };
    async function detectNew(zone = "Europe/London", localStartsAt = "2026-11-01T12:00:00") {
      messages = [
        {
          id: randomUUID(),
          version: 1,
          role: "user",
          userTimeZone: zone,
          content: "Meet at the canal today at noon?",
          createdAt: new Date(clock.getTime() + 1_000).toISOString(),
          serverCreatedAt: new Date(clock.getTime() - 2_000).toISOString(),
        },
        {
          id: randomUUID(),
          version: 1,
          role: "assistant",
          content: "Yes, noon at the canal.",
          createdAt: clock.toISOString(),
          serverCreatedAt: new Date(clock.getTime() - 1_000).toISOString(),
        },
      ];
      detection = {
        title: "Canal walk",
        cityId: "london",
        cityName: "London",
        timeZone: zone,
        placeName: "Canal",
        localStartsAt,
        timeReferenceMessageId: messages[0]!.id,
        durationMinutes: 60,
        evidence: messages.map((m) => ({ messageId: m.id, version: m.version })),
      };
      const result = await service.detect(user, { characterId, conversationId });
      return result.appointments[0]!;
    }
    const command = (a: Appointment) => ({
      commandId: randomUUID(),
      expectedRevision: a.revision,
    });
    beforeAll(async () => {
      runtime = createRuntimeDependencies(integrationConfig(process.env));
      await runMigrations(runtime.database);
      await runtime.start();
      for (const id of [user, other])
        await runtime.database.sql`insert into app.users(id) values(${id})`;
      await runtime.database
        .sql`insert into app.content_records(user_id,resource_type,resource_id,payload) values(${user},'character',${characterId},${JSON.stringify({ relationship: { affinity: 10, revision: 0 }, card: { name: "Oliver", regionId: "london" } })}::jsonb)`;
      service = createAppointmentService(
        runtime.database,
        {
          character: async () => ({
            id: characterId,
            name: "Oliver",
            cityId: "london",
            cityName: "London",
            timeZone: "Europe/London",
            persona: {},
          }),
          messages: async () => messages,
          city: async () => city,
        },
        narrative,
        createAppointmentContentService(runtime.database),
        () => clock,
      );
    });
    afterAll(async () => {
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition -- initialization can fail before assignment.
      if (runtime) {
        await runtime.database
          .sql`delete from app.users where id=any(${[user, other]}::uuid[])`;
        await runtime.close();
      }
    });
    it("deduplicates exact mutual evidence and enforces owner isolation", async () => {
      const a = await detectNew();
      expect(a.timelineEvents).toEqual([
        expect.objectContaining({
          kind: "confirmed",
          conversationId,
          messageId: messages[1]!.id,
          occurredAt: clock.toISOString(),
          title: a.title,
          placeName: a.placeName,
          startsAt: a.startsAt,
          timeZone: a.timeZone,
        }),
      ]);
      const replay = await service.detect(user, { characterId, conversationId });
      expect(replay.appointments).toEqual([a]);
      await expect(service.detail(other, a.id)).rejects.toMatchObject({
        code: "APPOINTMENT_NOT_FOUND",
      });
      expect((await service.list(other)).appointments).toHaveLength(0);
    });
    it("converts a Beijing agreement to an absolute entry window in London", async () => {
      const appointment = await detectNew("Asia/Shanghai", "2026-11-01T20:00:00");
      expect(appointment).toMatchObject({
        timeZone: "Europe/London",
        userTimeZone: "Asia/Shanghai",
        startsAt: "2026-11-01T12:00:00.000Z",
        windowOpensAt: "2026-11-01T11:30:00.000Z",
        windowClosesAt: "2026-11-01T14:00:00.000Z",
        timelineEvents: [{ userTimeZone: "Asia/Shanghai", startsAt: "2026-11-01T12:00:00.000Z" }],
      });
      expect((await service.start(user, appointment.id, command(appointment))).session?.blocks).toHaveLength(1);
    });
    it("rejects unilateral confirmation and nonexistent DST", async () => {
      await detectNew();
      messages = messages.map((m) => ({ ...m, id: randomUUID() }));
      detection!.evidence = messages
        .slice(0, 1)
        .map((m) => ({ messageId: m.id, version: 1 }));
      await expect(
        service.detect(user, { characterId, conversationId }),
      ).rejects.toMatchObject({ code: "APPOINTMENT_UNCONFIRMED" });
      messages = messages.map((m) => ({ ...m, id: randomUUID() }));
      detection!.evidence = messages.map((m) => ({ messageId: m.id, version: 1 }));
      detection!.timeReferenceMessageId = messages[0]!.id;
      detection!.localStartsAt = "2027-03-28T01:30:00";
      await expect(
        service.detect(user, { characterId, conversationId }),
      ).rejects.toMatchObject({ code: "APPOINTMENT_TIME_UNCLEAR" });
    });
    it("keeps the original plan until both parties confirm a reschedule", async () => {
      const original = await detectNew();
      messages = messages.map((m) => ({ ...m, id: randomUUID() }));
      detection!.replacesAppointmentId = original.id;
      detection!.localStartsAt = "2026-11-01T13:00:00";
      detection!.evidence = messages
        .slice(0, 1)
        .map((m) => ({ messageId: m.id, version: 1 }));
      await expect(
        service.detect(user, { characterId, conversationId }),
      ).rejects.toMatchObject({ code: "APPOINTMENT_UNCONFIRMED" });
      expect((await service.detail(user, original.id)).appointment.status).toBe(
        "confirmed",
      );
      expect(
        (await service.detail(user, original.id)).appointment.timelineEvents,
      ).toEqual(original.timelineEvents);
      messages = messages.map((m) => ({
        ...m,
        id: randomUUID(),
        content: m.role === "user" ? "Can we move it to 1pm?" : "Yes, 1pm works.",
      }));
      detection!.evidence = messages.map((m) => ({ messageId: m.id, version: 1 }));
      detection!.timeReferenceMessageId = messages[0]!.id;
      const changed = await service.detect(user, { characterId, conversationId });
      const replacement = changed.appointments[0]!;
      expect(replacement.startsAt).toBe("2026-11-01T13:00:00.000Z");
      expect(replacement.timelineEvents).toEqual([
        expect.objectContaining({
          kind: "rescheduled",
          messageId: messages[1]!.id,
          startsAt: replacement.startsAt,
          placeName: "Canal",
        }),
      ]);
      const superseded = (await service.detail(user, original.id)).appointment;
      expect(superseded.status).toBe("cancelled");
      expect(superseded.timelineEvents).toEqual(original.timelineEvents);
      expect(await service.detect(user, { characterId, conversationId })).toEqual(
        changed,
      );
    });
    it.each([
      ["relocated", "2026-11-01T12:00:00", "2026-11-01T12:00:00.000Z"],
      ["rescheduledAndRelocated", "2026-11-01T13:00:00", "2026-11-01T13:00:00.000Z"],
    ])(
      "records a mutually agreed replacement as %s",
      async (kind, localStartsAt, startsAt) => {
        const original = await detectNew();
        messages = messages.map((m) => ({
          ...m,
          id: randomUUID(),
          content: "The park instead.",
        }));
        detection!.replacesAppointmentId = original.id;
        detection!.title = "Park walk";
        detection!.placeName = "Park";
        detection!.localStartsAt = localStartsAt;
        detection!.evidence = messages.map((m) => ({ messageId: m.id, version: 1 }));
        detection!.timeReferenceMessageId = messages[0]!.id;
        const changed = await service.detect(user, { characterId, conversationId });
        expect(changed.appointments[0]!.timelineEvents).toEqual([
          expect.objectContaining({
            kind,
            conversationId,
            title: "Park walk",
            placeName: "Park",
            startsAt,
          }),
        ]);
        const superseded = (await service.detail(user, original.id)).appointment;
        expect(superseded.timelineEvents).toEqual(original.timelineEvents);
        expect(superseded.timelineEvents?.[0]?.placeName).toBe("Canal");
      },
    );
    it("freezes detector input and server clock for durable retries and prevents stale acceptance", async () => {
      await detectNew();
      messages = messages.map((m) => ({ ...m, id: randomUUID() }));
      const original = narrative.detect,
        requests: Parameters<AppointmentNarrative["detect"]>[0][] = [];
      narrative.detect = async (input) => {
        requests.push(input);
        if (requests.length === 1) throw new Error("detector interrupted");
        return null;
      };
      await expect(
        service.detect(user, { characterId, conversationId }),
      ).rejects.toThrow("detector interrupted");
      clock = new Date("2026-11-01T12:01:00Z");
      await service.detect(user, { characterId, conversationId });
      await service.detect(user, { characterId, conversationId });
      expect(requests).toHaveLength(2);
      expect({ ...requests[0], operationId: "stable" }).toEqual({
        ...requests[1],
        operationId: "stable",
      });
      clock = new Date("2026-11-01T12:00:00Z");
      messages = messages.map((m) => ({ ...m, id: randomUUID() }));
      detection!.evidence = messages.map((m) => ({ messageId: m.id, version: 1 }));
      detection!.timeReferenceMessageId = messages[0]!.id;
      let release!: () => void, entered!: () => void;
      const wait = new Promise<void>((r) => (release = r)),
        active = new Promise<void>((r) => (entered = r));
      narrative.detect = async (input) => {
        entered();
        await wait;
        return original(input);
      };
      const pending = service.detect(user, { characterId, conversationId });
      await active;
      messages = [
        ...messages,
        {
          id: randomUUID(),
          version: 1,
          role: "user",
          content: "Cancel that plan.",
          createdAt: clock.toISOString(),
        },
      ];
      release();
      await expect(pending).rejects.toMatchObject({
        code: "APPOINTMENT_EVIDENCE_CHANGED",
      });
      narrative.detect = original;
    });
    it("does not invalidate or duplicate confirmation when metadata revisions arrive during detection", async () => {
      await detectNew();
      messages = messages.map((m) => ({ ...m, id: randomUUID() }));
      detection!.timeReferenceMessageId = messages[0]!.id;
      detection!.evidence = messages.map((m) => ({
        messageId: m.id,
        version: m.version,
      }));
      const original = narrative.detect;
      let release!: () => void, entered!: () => void;
      let calls = 0;
      const wait = new Promise<void>((r) => (release = r)),
        active = new Promise<void>((r) => (entered = r));
      narrative.detect = async (input) => {
        calls++;
        entered();
        await wait;
        return original(input);
      };
      const pending = service.detect(user, { characterId, conversationId });
      await active;
      messages = messages.map((m) => ({ ...m, version: m.version + 1 }));
      release();
      const accepted = await pending,
        appointment = accepted.appointments[0]!;
      messages = messages.map((m) => ({ ...m, version: m.version + 1 }));
      const replay = await service.detect(user, { characterId, conversationId });
      expect(calls).toBe(1);
      expect(replay.appointments).toHaveLength(accepted.appointments.length);
      detection!.evidence = messages.map((message) => ({
        messageId: message.id,
        version: message.version,
      }));
      messages = [
        ...messages,
        {
          id: randomUUID(),
          version: 1,
          role: "user",
          content: "Thanks!",
          createdAt: clock.toISOString(),
        },
      ];
      const rediscovered = await service.detect(user, { characterId, conversationId });
      expect(calls).toBe(2);
      expect(rediscovered.appointments).toHaveLength(accepted.appointments.length);

      const [stored] = await runtime.database.sql<
        { evidence: AppointmentMessage[] }[]
      >`select evidence from app.appointments where id=${appointment.id}`;
      expect(stored!.evidence.every((message) => message.version === 1)).toBe(true);
      expect(
        (await service.start(user, appointment.id, command(appointment))).appointment
          .status,
      ).toBe("in_progress");
      narrative.detect = original;
    });
    it("binds completed assistant proof to the actual preceding server user turn and rejects cloned old acceptance", async () => {
      const originalUser = randomUUID(),
        reply = randomUUID(),
        newUser = randomUUID(),
        clone = randomUUID(),
        op = randomUUID(),
        cycle = randomUUID(),
        body = "Sure, noon at the canal.";
      const payload = (
        role: string,
        text: string,
        orderIndex: number,
        origin?: unknown,
      ) => ({
        role,
        text,
        kind: "text",
        isInterrupted: false,
        createdAt: "2099-01-01T00:00:00Z",
        orderIndex,
        learningOrigin: origin,
      });
      await runtime.database
        .sql`insert into app.content_records(user_id,resource_type,resource_id,parent_id,payload,created_at)
       values(${user},'message',${originalUser},${conversationId},${JSON.stringify(payload("user", "Original invitation", 999))}::jsonb,'2026-11-01T12:00:00Z'),
       (${user},'message',${reply},${conversationId},${JSON.stringify(payload("assistant", body, -999, { source: "assistant", cycleId: cycle, userMessageId: originalUser, operationId: op, fragmentIndex: 0, fragmentCount: 1 }))}::jsonb,'2026-11-01T12:00:01Z')`;
      await runtime.database
        .sql`insert into app.learning_chat_outbox(user_id,message_id,conversation_id,character_id,origin,body_fingerprint)
       values(${user},${originalUser},${conversationId},${characterId},${JSON.stringify({ source: "user", cycleId: cycle })}::jsonb,${chatBodyFingerprint("Original invitation")})`;
      await runtime.database
        .sql`insert into app.learning_chat_turns(user_id,user_message_id,conversation_id,character_id,cycle_id) values(${user},${originalUser},${conversationId},${characterId},${cycle})`;
      await runtime.database
        .sql`insert into app.learning_chat_operations(user_id,operation_id,user_message_id,request_fingerprint,body_fingerprint,completed_at) values(${user},${op},${originalUser},'server-receipt',${chatBodyFingerprint(body)},'2026-11-01T12:00:00.900Z')`;
      const reader = createAppointmentContentService(runtime.database),
        chat = createLearningChatService(
          runtime.database,
          {} as LearningContextReader,
          createContentReadService(runtime.database),
        );
      await runtime.database.sql.begin(async (sql) => {
        const original = await reader.message(sql, user, reply);
        expect(original).toBeDefined();
        expect(
          await chat.verifiedAppointmentMessages(
            sql,
            user,
            characterId,
            conversationId,
            [original!],
          ),
        ).toHaveLength(1);
      });
      await runtime.database
        .sql`insert into app.content_records(user_id,resource_type,resource_id,parent_id,payload,created_at)
       values(${user},'message',${newUser},${conversationId},${JSON.stringify(payload("user", "A different new proposal", -10000))}::jsonb,'2026-11-01T12:01:00Z'),
       (${user},'message',${clone},${conversationId},${JSON.stringify(payload("assistant", body, -20000, { source: "assistant", cycleId: cycle, userMessageId: originalUser, operationId: op, fragmentIndex: 0, fragmentCount: 1 }))}::jsonb,'2026-11-01T12:02:00Z')`;
      await runtime.database.sql.begin(async (sql) => {
        const copied = await reader.message(sql, user, clone);
        expect(
          await chat.verifiedAppointmentMessages(
            sql,
            user,
            characterId,
            conversationId,
            [copied!],
          ),
        ).toEqual([]);
        const original = await reader.message(sql, user, reply);
        expect(
          await chat.verifiedAppointmentMessages(
            sql,
            user,
            characterId,
            conversationId,
            [original!],
          ),
        ).toHaveLength(1);
      });
      await runtime.database
        .sql`update app.content_records set payload=jsonb_set(payload,'{text}','"Edited proposal"'),version=version+1 where user_id=${user} and resource_id=${originalUser}`;
      await runtime.database.sql.begin(async (sql) => {
        const original = await reader.message(sql, user, reply);
        expect(
          await chat.verifiedAppointmentMessages(
            sql,
            user,
            characterId,
            conversationId,
            [original!],
          ),
        ).toEqual([]);
      });
    });
    it("uses server clock and current app city for first entry", async () => {
      const a = await detectNew();
      city = "newyork";
      await expect(service.start(user, a.id, command(a))).rejects.toMatchObject({
        code: "APPOINTMENT_WRONG_CITY",
      });
      city = "london";
      clock = new Date("2026-11-01T11:29:00Z");
      await expect(service.start(user, a.id, command(a))).rejects.toMatchObject({
        code: "APPOINTMENT_OUTSIDE_WINDOW",
      });
      clock = new Date("2026-11-01T12:00:00Z");
    });
    it("commits immutable blocks and choices atomically and replays without generation", async () => {
      const a = await detectNew(),
        input = command(a),
        before = generationCount;
      const opened = await service.start(user, a.id, input, true);
      expect(opened.session?.blocks[0]?.presentation).toBe("paragraphs");
      expect(await service.start(user, a.id, input)).toEqual(opened);
      expect(generationCount).toBe(before + 1);
      const choose = {
        ...command(opened.appointment),
        input: "Change topic and walk quietly",
      };
      const next = await service.choose(user, a.id, choose);
      expect(next.session?.blocks[1]?.presentation).toBeUndefined();
      expect(next.session!.decisions[0]?.input).toBe(choose.input);
      expect(next.session!.blocks[0]).toEqual(opened.session!.blocks[0]);
      expect(await service.choose(user, a.id, choose, true)).toEqual(next);
      expect(opened.appointment.timelineEvents?.map(({ kind }) => kind)).toEqual([
        "confirmed",
        "started",
      ]);
      expect(next.appointment.timelineEvents).toEqual(
        opened.appointment.timelineEvents,
      );
      await expect(
        service.choose(user, a.id, { ...choose, input: "different" }),
      ).rejects.toMatchObject({ code: "APPOINTMENT_COMMAND_CONFLICT" });
    });
    it("resumes started stories after entry window", async () => {
      const a = await detectNew();
      const started = await service.start(user, a.id, command(a));
      clock = new Date("2026-11-04T12:00:00Z");
      expect(
        (
          await service.choose(user, a.id, {
            ...command(started.appointment),
            choiceId: "walk",
          })
        ).session!.blocks,
      ).toHaveLength(2);
      clock = new Date("2026-11-01T12:00:00Z");
    });
    it("serializes devices and cancellation fences late first entry", async () => {
      const a = await detectNew();
      let release!: () => void, entered!: () => void;
      const waiting = new Promise<void>((r) => (release = r)),
        active = new Promise<void>((r) => (entered = r));
      gate = () => {
        entered();
        return waiting;
      };
      const pending = service.start(user, a.id, command(a));
      await active;
      await expect(service.start(user, a.id, command(a))).rejects.toMatchObject({
        code: "APPOINTMENT_OPERATION_PENDING",
      });
      const cancel = command(a);
      const cancelled = await service.cancel(user, a.id, cancel);
      release();
      await expect(pending).rejects.toMatchObject({
        code: "APPOINTMENT_VERSION_CONFLICT",
      });
      gate = null;
      expect(cancelled.appointment.status).toBe("cancelled");
      expect(cancelled.appointment.timelineEvents?.map(({ kind }) => kind)).toEqual([
        "confirmed",
        "cancelled",
      ]);
      expect(await service.cancel(user, a.id, cancel)).toEqual(cancelled);
      const detail = await service.detail(user, a.id);
      expect(detail.session).toBeNull();
      expect(detail.appointment.timelineEvents).toEqual(
        cancelled.appointment.timelineEvents,
      );
      const next = await detectNew(),
        opened = await service.start(user, next.id, command(next));
      await expect(
        service.cancel(user, next.id, command(opened.appointment)),
      ).rejects.toMatchObject({ code: "APPOINTMENT_CLOSED" });
    });
    it("retries rejected reviews with a new durable attempt, and resumes crashed generations from the same context", async () => {
      const a = await detectNew();
      const input = command(a);
      const originalGenerate = narrative.generate;
      let fail = true;
      narrative.generate = async (context) => {
        if (fail) throw new Error("network interrupted");
        return originalGenerate(context);
      };
      await expect(service.start(user, a.id, input)).rejects.toThrow(
        "network interrupted",
      );
      await runtime.database
        .sql`update app.appointment_operations set status='running',lease_until=${new Date(clock.getTime() - 60_000).toISOString()} where user_id=${user} and command_id=${input.commandId}`;
      fail = false;
      const opened = await service.start(user, a.id, input);
      narrative.generate = originalGenerate;
      const originalReview = narrative.review,
        attempts: string[] = [];
      narrative.review = async (context) => {
        attempts.push(context.operationId);
        if (attempts.length === 1) throw new Error("malformed review");
        return originalReview(context);
      };
      ending = true;
      const finish = {
        ...command(opened.appointment),
        finish: true as const,
      };
      const complete = await service.choose(user, a.id, finish);
      ending = false;
      expect(complete.summary!.affinity.status).toBe("pending");
      const seed = await service.settlementSeed(user, a.id);
      expect(seed.settled).toBe(false);
      expect(attempts).toHaveLength(2);
      expect(attempts[0]).not.toBe(attempts[1]);
      expect(complete.appointment.timelineEvents?.map(({ kind }) => kind)).toEqual([
        "confirmed",
        "started",
        "completed",
      ]);
      expect(
        (await service.choose(user, a.id, finish)).appointment.timelineEvents,
      ).toEqual(complete.appointment.timelineEvents);
      narrative.review = originalReview;
    });
    it("projects one expiration at the entry deadline on repeated reads of a legacy snapshot", async () => {
      const a = await detectNew();
      await runtime.database
        .sql`update app.appointments set snapshot=snapshot-'timelineEvents' where id=${a.id}`;
      try {
        clock = new Date(a.windowClosesAt);
        const open = (await service.detail(user, a.id)).appointment;
        expect(open.status).toBe("confirmed");
        expect(open.timelineEvents).toBeUndefined();
        clock = new Date(clock.getTime() + 1_000);
        const expired = (await service.detail(user, a.id)).appointment;
        expect(expired.status).toBe("expired");
        expect(expired.timelineEvents).toEqual([
          expect.objectContaining({
            kind: "expired",
            conversationId,
            occurredAt: a.windowClosesAt,
            placeName: a.placeName,
            startsAt: a.startsAt,
          }),
        ]);
        expect(expired.timelineEvents?.[0]?.messageId).toBeUndefined();
        await expect(
          service.cancel(user, a.id, command(expired)),
        ).rejects.toMatchObject({
          code: "APPOINTMENT_CLOSED",
        });
        expect(
          (await service.list(user)).appointments.find(({ id }) => id === a.id),
        ).toEqual(expired);
      } finally {
        clock = new Date("2026-11-01T12:00:00Z");
      }
    });
    it("recovers a finalized upstream failure under a fresh service-funded ID without accepting a second branch", async () => {
      const a = await detectNew(),
        input = command(a),
        original = narrative.generate,
        attempts: AppointmentGenerationContext[] = [];
      narrative.generate = async (context) => {
        attempts.push(context);
        if (attempts.length === 1)
          throw new AppError({
            code: "AI_UPSTREAM_TIMEOUT",
            message: "interrupted",
            statusCode: 504,
          });
        return original(context);
      };
      await expect(service.start(user, a.id, input)).rejects.toMatchObject({
        code: "AI_UPSTREAM_TIMEOUT",
      });
      const result = await service.start(user, a.id, input);
      expect(result.session!.blocks).toHaveLength(1);
      expect(attempts[0]!.operationId).not.toBe(attempts[1]!.operationId);
      expect(attempts[1]!.serviceFundedRetry).toBe(true);
      expect(await service.start(user, a.id, input)).toEqual(result);
      expect(attempts).toHaveLength(2);
      narrative.generate = original;
    });
    it("settles once with CAS and preserves forgotten memories", async () => {
      const a = await detectNew(),
        opened = await service.start(user, a.id, command(a));
      ending = true;
      const completed = await service.choose(user, a.id, {
        ...command(opened.appointment),
        finish: true,
      });
      ending = false;
      expect(completed.summary?.affinity.status).toBe("pending");
      const seed = await service.settlementSeed(user, a.id);
      const relationship = {
        ...(seed.relationship ?? {}),
        affinity: 11,
        revision: 1,
        settledAppointmentIDs: [a.id],
        recentEvaluatedMessageIDs: [a.id],
        recentEvents: [
          {
            id: a.id,
            source: "appointment",
            delta: 1,
            reasonZh: "walk",
            createdAt: seed.settlementAt,
          },
        ],
      };
      await expect(
        service.settle(user, a.id, {
          commandId: randomUUID(),
          expectedCharacterVersion: seed.characterVersion + 1,
          relationship,
        }),
      ).rejects.toMatchObject({ code: "CONTENT_VERSION_CONFLICT" });
      const result = await service.settle(user, a.id, {
        commandId: randomUUID(),
        expectedCharacterVersion: seed.characterVersion,
        relationship,
      });
      expect(result.summary!.affinity).toMatchObject({
        status: "settled",
        before: 10,
        after: 11,
        delta: 1,
      });
      expect(
        (
          await service.settle(user, a.id, {
            commandId: randomUUID(),
            expectedCharacterVersion: seed.characterVersion,
            relationship,
          })
        ).summary,
      ).toEqual(result.summary);
      const memory = result.summary!.memories[0]!;
      const [originalRecord] = await runtime.database.sql<
        {
          payload: { content: string; importance: number; sourceUpToIndex: number };
          created_at: string;
        }[]
      >`select payload,created_at::text from app.content_records where user_id=${user} and resource_id=${memory.id}`;
      expect(originalRecord!.payload.importance).toBeGreaterThanOrEqual(1);
      expect(originalRecord!.payload.importance).toBeLessThanOrEqual(5);
      expect(originalRecord!.payload.sourceUpToIndex).toBeGreaterThanOrEqual(0);
      const originalSummary = result.summary;
      const generationBeforeManagement = generationCount;
      const prefix = "@lingotrip-memory-v2:";
      const metadata = JSON.parse(
        originalRecord!.payload.content.slice(prefix.length),
      ) as Record<string, unknown>;
      const edited = {
        ...metadata,
        text: "We chose a quiet riverside bench.",
        edited: true,
      };
      await runtime.database
        .sql`update app.content_records set payload=jsonb_set(payload,'{content}',${JSON.stringify(prefix + JSON.stringify(edited))}::jsonb),version=version+1 where user_id=${user} and resource_id=${memory.id}`;
      const editedDetail = await service.detail(user, a.id);
      expect(editedDetail.summary!.memories[0]).toEqual({
        id: memory.id,
        content: edited.text,
        status: "edited",
      });
      const forgotten = { ...edited, text: "", forgotten: true };
      await runtime.database
        .sql`update app.content_records set payload=jsonb_set(payload,'{content}',${JSON.stringify(prefix + JSON.stringify(forgotten))}::jsonb),version=version+1 where user_id=${user} and resource_id=${memory.id}`;
      const forgottenDetail = await service.detail(user, a.id);
      expect(forgottenDetail.summary!.memories[0]).toEqual({
        id: memory.id,
        content: "",
        status: "forgotten",
      });
      expect(forgottenDetail.appointment).toEqual(result.appointment);
      expect(forgottenDetail.session).toEqual(result.session);
      const [unchanged] = await runtime.database.sql<
        { summary: unknown; created_at: string }[]
      >`select a.summary,m.created_at::text from app.appointments a join app.content_records m on m.user_id=a.user_id and m.resource_id=${memory.id} and m.resource_type='memory' where a.id=${a.id}`;
      expect(unchanged!.summary).toEqual(originalSummary);
      expect(unchanged!.created_at).toBe(originalRecord!.created_at);
      expect(generationCount).toBe(generationBeforeManagement);
      await runtime.database
        .sql`update app.content_records set deleted_at=now() where user_id=${user} and resource_id=${memory.id}`;
      expect((await service.detail(user, a.id)).summary!.memories[0]).toEqual({
        id: memory.id,
        content: "",
        status: "deleted",
      });
      const [stored] = await runtime.database.sql<
        { deleted_at: Date }[]
      >`select deleted_at from app.content_records where user_id=${user} and resource_id=${memory.id}`;
      expect(stored!.deleted_at).not.toBeNull();
      expect((await service.settlementSeed(user, a.id)).settled).toBe(true);
    });
  },
);
