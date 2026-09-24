import { randomUUID } from "node:crypto";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { integrationConfig } from "../helpers/integration.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createUnitLearningService, type UnitLearningService } from "../../src/modules/learning/unit-service.js";
import { authoredUnitSeeds, type UnitTemplate } from "../../src/modules/learning/unit-seeds.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("unit learning persistence", () => {
  let db: DatabaseResource, service: UnitLearningService;
  const user = randomUUID(), other = randomUUID(), progressing = randomUUID();
  const oliver = "8b3a2b24-8a4e-5a73-a2c4-0f5e8f05e001";
  const ruby = "8b3a2b24-8a4e-5a73-a2c4-0f5e8f05e002";
  beforeAll(async () => {
    db = createDatabase(integrationConfig());
    await runMigrations(db);
    await db.sql`insert into app.users(id) values (${user}), (${other}), (${progressing})`;
    await db.sql`insert into app.user_profiles(user_id,difficulty)
      values (${user},'primary1'), (${other},'primary1'), (${progressing},'primary1')`;
    service = createUnitLearningService(db);
  });
  afterAll(async () => {
    await db.sql`delete from app.users where id in (${user},${other},${progressing})`;
    await db.close();
  });
  it("deduplicates chat, isolates characters, awards each question once and keeps missed answers", async () => {
    const id = randomUUID();
    const input = { characterId: oliver, roleKey: "oliver", messageId: id, role: "user" as const, characterCount: 1000 };
    expect((await service.recordMessage(user, input)).ready).toBe(true);
    expect((await service.recordMessage(user, input)).chatCharacters).toBe(1000);
    expect((await service.read(user, ruby, "ruby")).progress.chatCharacters).toBe(0);
    expect((await service.read(other, oliver, "oliver")).progress.chatCharacters).toBe(0);
    const started = await service.start(user, oliver, "oliver");
    const attempt = started.active;
    expect(attempt).not.toBeNull();
    if (!attempt) throw Error("Missing attempt");
    const [stored] = await db.sql<{ payload: UnitTemplate }[]>`select payload
      from app.unit_learning_templates where id=${attempt.template.id}`;
    const seed = stored?.payload;
    if (!seed) throw Error("Missing unit template");
    const wrong = seed.questions[0]?.options.find(option => option !== seed.questions[0]?.answer);
    if (!wrong) throw Error("Missing distractor");
    expect((await service.answer(user, attempt.id, "q1", wrong)).awarded).toBe(false);
    await expect(service.answer(user, attempt.id, "q1", seed.questions[0]?.answer ?? "")).rejects.toMatchObject({ code: "UNIT_RETRY_AFTER_COMPLETION" });
    for (const question of seed.questions.slice(1))
      expect((await service.answer(user, attempt.id, question.id, question.answer)).awarded).toBe(true);
    const after = await service.read(user, oliver, "oliver");
    expect(after.progress.chatCharacters).toBe(0);
    expect(after.progress.gradeCorrect).toBe(2);
    expect(after.history).toHaveLength(1);
    expect((await service.answer(user, attempt.id, "q1", seed.questions[0]?.answer ?? "")).awarded).toBe(true);
    expect((await service.answer(user, attempt.id, "q1", seed.questions[0]?.answer ?? "")).awarded).toBe(false);
    expect((await service.read(user, oliver, "oliver")).progress.gradeCorrect).toBe(3);
    await service.recordMessage(user, { ...input, messageId: randomUUID() });
    const next = await service.start(user, oliver, "oliver");
    expect(next.active?.template.id).not.toBe(attempt.template.id);
  });
  it("does not share a private character's generated unit across accounts", async () => {
    const privateCharacter = randomUUID();
    const templateSource = authoredUnitSeeds[0];
    if (!templateSource) throw Error("Missing template fixture");
    const privateService = createUnitLearningService(db, (key, grade, characterId, owner) => Promise.resolve({
      template: { ...templateSource, id: `unit-private-${characterId}-${randomUUID()}`, roleKey: key, grade },
      scopeUserId: owner,
    }));
    for (const account of [user, other]) {
      await privateService.recordMessage(account, {
        characterId: privateCharacter, roleKey: "other", messageId: randomUUID(),
        role: "user", characterCount: 1000,
      });
    }
    const first = await privateService.start(user, privateCharacter, "other");
    const second = await privateService.start(other, privateCharacter, "other");
    expect(first.active?.template.id).not.toBe(second.active?.template.id);
  });
  it("lights one star after ten correct answers and advances a grade after ninety", async () => {
    const templateSource = authoredUnitSeeds[0];
    if (!templateSource) throw Error("Missing template fixture");
    const gradeService = createUnitLearningService(db, (key, grade) => Promise.resolve({
      template: { ...templateSource, id: `unit-progression-${randomUUID()}`, roleKey: key, grade },
      scopeUserId: null,
    }));
    for (let index = 0; index < 30; index += 1) {
      await gradeService.recordMessage(progressing, {
        characterId: oliver, roleKey: "oliver", messageId: randomUUID(),
        role: "user", characterCount: 1000,
      });
      const started = await gradeService.start(progressing, oliver, "oliver");
      if (!started.active) throw Error("Missing attempt");
      const seed = authoredUnitSeeds.find(unit => unit.id === started.active?.template.id) ?? templateSource;
      for (const question of seed.questions)
        await gradeService.answer(progressing, started.active.id, question.id, question.answer);
      if (index === 3) {
        const state = await gradeService.read(progressing, oliver, "oliver");
        expect(state.progress.stars).toBe(1);
        expect(state.progress.gradeCorrect).toBe(12);
      }
    }
    const state = await gradeService.read(progressing, oliver, "oliver");
    expect(state.progress.grade).toBe(2);
    expect(state.progress.gradeCorrect).toBe(0);
    expect(state.progress.stars).toBe(0);
    expect(state.progress.completedLevels).toBe(1);
    const [profile] = await db.sql<{ difficulty: string }[]>`select difficulty::text as difficulty
      from app.user_profiles where user_id=${progressing}`;
    expect(profile?.difficulty).toBe("primary2");
    const moved = await gradeService.changeGrade(progressing, oliver, "oliver", 6);
    expect(moved.progress.grade).toBe(6);
    expect(moved.progress.gradeCorrect).toBe(0);
    expect(moved.progress.completedLevels).toBe(1);
    expect(moved.history).toHaveLength(30);
    const [updatedProfile] = await db.sql<{ difficulty: string }[]>`select difficulty::text as difficulty
      from app.user_profiles where user_id=${progressing}`;
    expect(updatedProfile?.difficulty).toBe("primary6");
    await db.sql`update app.user_profiles set difficulty='junior1' where user_id=${progressing}`;
    const reconciled = await gradeService.read(progressing, oliver, "oliver");
    expect(reconciled.progress.grade).toBe(7);
    expect(reconciled.progress.gradeCorrect).toBe(0);
  });
});
