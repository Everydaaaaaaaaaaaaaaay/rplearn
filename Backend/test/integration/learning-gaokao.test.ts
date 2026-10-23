import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  LearningEngineRepository,
  type LearningSession,
} from "../../src/modules/learning/engine-repository.js";
import { LearningBankSession } from "../../src/modules/learning/bank-repository.js";
import { gaokaoCatalog } from "../../src/modules/learning/gaokao-policy.js";
import { loadGaokaoCatalog } from "../../src/modules/learning/gaokao-catalog.js";
import {
  contentHash,
  type LearningLevel,
  type LearningUnit,
} from "../../src/modules/learning/content.js";
import { learningFixture } from "../helpers/learning.js";
import { integrationConfig } from "../helpers/integration.js";

function required<T>(v: T | null | undefined): T {
  if (v == null) throw new Error("Missing fixture");
  return v;
}
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "高中真题供给、退役与进度保留事务",
  () => {
    let db: DatabaseResource, engine: LearningEngineRepository;
    let original: LearningUnit;
    const users: string[] = [];
    const legacy = {
      ...learningFixture("test.gaokao-legacy"),
      level: "senior3" as const,
    };
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      engine = new LearningEngineRepository(db);
      const c = await loadGaokaoCatalog();
      await engine.publishBatch(
        c.units,
        [],
        c.imageAssets.map((a) => a.metadata),
      );
      const sourceId = required(
        gaokaoCatalog().practices.find(
          (p) =>
            p.kind === "authored" &&
            p.components.every((c) => c.family === "reading_choice"),
        ),
      ).components[0]?.sourceUnitId;
      const originals = JSON.parse(
        await readFile(
          new URL("../../config/learning/originals/catalog.json", import.meta.url),
          "utf8",
        ),
      ) as { units: { unit: LearningUnit }[] };
      original = required(originals.units.find((e) => e.unit.id === sourceId)).unit;
      await engine.publishBatch([legacy, original]);
    }, 30000);
    afterAll(async () => {
      for (const id of users) await db.sql`delete from app.users where id=${id}`;
      for (const id of [
        ...gaokaoCatalog().practices.map((p) => p.unit.id),
        legacy.id,
        original.id,
      ]) {
        await db.sql`delete from app.learning_unit_versions where unit_id=${id}`;
        await db.sql`delete from app.learning_units where id=${id}`;
      }
      await db.close();
    });
    async function account() {
      const user = randomUUID(),
        character = randomUUID();
      users.push(user);
      await db.sql`insert into app.users(id) values(${user})`;
      const command = <T>(f: (s: LearningSession) => Promise<T>) =>
        engine.command(user, randomUUID(), "test", {}, f);
      await command((s) => s.ensureCharacter(character, "oliver"));
      await db.sql`update app.learning_characters set characters=1000 where user_id=${user}`;
      return { user, character, command };
    }
    it("所有入口排除旧高中混合题；旧客户端不能绕过完整题组协议", async () => {
      const a = await account();
      for (const level of ["senior1", "senior2", "senior3"] as const) {
        expect(
          (await engine.read(a.user, (s) => s.originals(level))).units,
        ).toHaveLength(
          gaokaoCatalog().practices.filter((p) => p.unit.level === level).length,
        );
        expect(
          (
            await engine.read(a.user, (s) =>
              s.availability("oliver", level, a.character, true),
            )
          ).availableUnits,
        ).toBe(gaokaoCatalog().practices.filter((p) => p.unit.level === level).length);
        expect(
          (
            await engine.read(a.user, (s) =>
              s.availability("oliver", level, a.character),
            )
          ).availableUnits,
        ).toBe(0);
        expect(
          await db.sql.begin((sql) =>
            new LearningBankSession(sql, a.user).choices(level, "oliver"),
          ),
        ).toEqual([]);
      }
      await expect(
        a.command((s) => s.start(a.character, "senior3")),
      ).rejects.toMatchObject({ code: "LEARNING_CLIENT_UPDATE_REQUIRED" });
      expect(
        (
          await a.command((s) =>
            s.start(a.character, "senior3", {
              completeGroups: true,
              originalUnitId: legacy.id,
            }),
          )
        ).status,
      ).toBe("preparing");
      const content = await engine.read(a.user, (s) => s.publishedContent(true));
      expect(
        content.filter((r) => r.level.startsWith("senior")).map((r) => r.count),
      ).toEqual([16, 22, 22]);
    });
    it("旧18题练习退出活动入口，答案、冻结稿、完成时间及已得积分原样保留", async () => {
      const a = await account(),
        id = randomUUID(),
        round = randomUUID();
      const [state] = await db.sql<
        { cycle_id: string }[]
      >`select cycle_id from app.learning_characters where user_id=${a.user}`;
      const payload = {
        ...legacy,
        questions: Array.from({ length: 18 }, (_, i) => ({
          ...required(legacy.questions[0]),
          id: `legacy.q${String(i)}`,
        })),
      };
      await db.sql`insert into app.learning_attempts(id,user_id,character_id,cycle_id,level_key,snapshot) values(${id},${a.user},${a.character},${required(state).cycle_id},'senior3',${JSON.stringify(payload)}::jsonb)`;
      await db.sql`insert into app.learning_rounds(id,attempt_id,ordinal,question_ids) values(${round},${id},0,${payload.questions.map((q) => q.id)})`;
      await db.sql`insert into app.learning_answers(round_id,question_id,answer,result) values(${round},'legacy.q0','{"kind":"choice","optionId":"hello"}'::jsonb,'{"outcome":"correct"}'::jsonb)`;
      await db.sql`insert into app.learning_rewards(attempt_id,question_id,user_id,level_key,goal_id,points) values(${id},'legacy.q0',${a.user},'senior3','test.greetings',1)`;
      await db.sql`insert into app.learning_level_progress(user_id,level_key,points) values(${a.user},'senior3',1)`;
      expect(
        (await engine.read(a.user, (s) => s.character(a.character))).activeAttemptId,
      ).toBeNull();
      const next = await a.command((s) =>
        s.start(a.character, "senior3", {
          completeGroups: true,
          originalUnitId: "gaokao.senior3.2025-national1.cloze",
        }),
      );
      expect(required(next.attempt).unit.questions).toHaveLength(15);
      const [old] =
        await db.sql`select snapshot,first_completed_at,superseded_at from app.learning_attempts where id=${id}`;
      expect(contentHash(required(old).snapshot)).toBe(contentHash(payload));
      expect(required(old).first_completed_at).toBeNull();
      expect(required(old).superseded_at).not.toBeNull();
      expect(
        (await engine.read(a.user, (s) => s.attempt(id))).round.answers,
      ).toHaveLength(1);
      expect(
        (await engine.read(a.user, (s) => s.progress())).find(
          (p) => p.level === "senior3",
        )?.points,
      ).toBe(1);
      expect(
        (await engine.read(a.user, (s) => s.character(a.character))).characters,
      ).toBe(500);
      await expect(a.command((s) => s.finish(id, true))).rejects.toMatchObject({
        code: "LEARNING_PRACTICE_REPLACED",
      });
    });
    it("真题跨旅伴跨年级不重复，耗尽真题后仍仅供合格原创", async () => {
      const a = await account();
      for (const slug of ["reading-ab", "reading-cd", "cloze", "language"]) {
        await db.sql`update app.learning_characters set characters=1000 where user_id=${a.user}`;
        const response = await a.command((s) =>
          s.start(a.character, "senior1", {
            completeGroups: true,
            originalUnitId: `gaokao.senior1.2025-national1.${slug}`,
          }),
        );
        const attempt = required(response.attempt);
        expect(attempt.unit.questions.every((q) => Boolean(q.material))).toBe(true);
        await a.command((s) => s.finish(attempt.id, true));
      }
      const other = randomUUID();
      await a.command((s) => s.ensureCharacter(other, "oliver"));
      await db.sql`update app.learning_characters set characters=1000 where user_id=${a.user}`;
      for (const level of ["senior1", "senior2", "senior3"] as LearningLevel[]) {
        expect(
          (
            await engine.read(a.user, (s) =>
              s.availability("oliver", level, other, true),
            )
          ).availableUnits,
        ).toBe(
          gaokaoCatalog().practices.filter(
            (p) => p.kind === "authored" && p.unit.level === level,
          ).length,
        );
        expect(
          (
            await a.command((s) =>
              s.start(other, level, {
                completeGroups: true,
                originalUnitId: `gaokao.${level}.2025-national1.cloze`,
              }),
            )
          ).status,
        ).toBe("preparing");
      }
    });
    it("旧完整原创练习的曝光不会因重新分成两篇而重抽，未作答账号可正常作答获分", async () => {
      const pair = required(
        gaokaoCatalog().practices.find(
          (p) =>
            p.kind === "authored" &&
            p.components.some((c) => c.sourceUnitId === original.id),
        ),
      );
      const a = await account();
      const [state] = await db.sql<
        { cycle_id: string }[]
      >`select cycle_id from app.learning_characters where user_id=${a.user}`;
      await db.sql`insert into app.learning_attempts(id,user_id,character_id,cycle_id,unit_id,unit_version,level_key,first_completed_at) values(${randomUUID()},${a.user},${a.character},${required(state).cycle_id},${original.id},${original.version},${original.level},now())`;
      await db.sql`update app.learning_characters set cycle_id=${randomUUID()} where user_id=${a.user}`;
      expect(
        (
          await a.command((s) =>
            s.start(a.character, original.level, {
              completeGroups: true,
              originalUnitId: pair.unit.id,
            }),
          )
        ).status,
      ).toBe("preparing");
      const fresh = await account();
      const started = await fresh.command((s) =>
        s.start(fresh.character, pair.unit.level, {
          completeGroups: true,
          originalUnitId: pair.unit.id,
        }),
      );
      const attempt = required(started.attempt);
      const q = required(pair.unit.questions[0]);
      if (q.type !== "choice") throw new Error("Missing reading fixture");
      const receipt = await fresh.command((s) =>
        s.submit({
          attemptId: attempt.id,
          roundId: attempt.round.id,
          questionId: q.id,
          answer: { kind: "choice", optionId: q.answer },
        }),
      );
      expect(receipt.awardedPoints).toBe(1);
      expect(receipt.attempt.unit.title).toContain("高考题型原创");
      await fresh.command((s) => s.finish(attempt.id, true));
      await db.sql`update app.learning_characters set characters=1000 where user_id=${fresh.user}`;
      const otherHalf = required(
        gaokaoCatalog().practices.find(
          (p) =>
            p.kind === "authored" &&
            p.unit.id !== pair.unit.id &&
            p.components.some((c) => c.sourceUnitId === original.id),
        ),
      );
      const next = await fresh.command((s) =>
        s.start(fresh.character, otherHalf.unit.level, {
          completeGroups: true,
          originalUnitId: otherHalf.unit.id,
        }),
      );
      expect(next.status).toBe("started");
      expect(
        required(next.attempt).unit.questions.every(
          (q) => !pair.unit.questions.some((seen) => seen.id === q.id),
        ),
      ).toBe(true);
    });
  },
);
