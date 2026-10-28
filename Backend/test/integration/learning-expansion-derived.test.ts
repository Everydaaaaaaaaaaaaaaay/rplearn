import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { LearningExpansionRepository } from "../../src/modules/learning/expansion-repository.js";
import { expansionPublication } from "../../src/modules/learning/expansion-publication.js";
import { loadExpansionCatalog } from "../../src/modules/learning/expansion-catalog.js";
import { contentHash, type LearningUnit } from "../../src/modules/learning/content.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { expansionCatalogOriginMarker } from "../../src/modules/learning/expansion-origin.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "新扩充高中子练习定向发布和撤回",
  () => {
    const catalog = loadExpansionCatalog("b039", false, "2026-10-28");
    const publication = expansionPublication(catalog.units);
    const users: string[] = [],
      extraUnits: string[] = [];
    let db: DatabaseResource,
      engine: LearningEngineRepository,
      expansion: LearningExpansionRepository;
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      engine = new LearningEngineRepository(db);
      expansion = new LearningExpansionRepository(db);
    });
    afterAll(async () => {
      for (const id of users) await db.sql`delete from app.users where id=${id}`;
      for (const id of [...publication.units.map((u) => u.id), ...extraUnits]) {
        await db.sql`delete from app.learning_unit_versions where unit_id=${id}`;
        await db.sql`delete from app.learning_units where id=${id}`;
      }
      await db.close();
    });

    it("实际注册可抽取子题、保留兄弟题供给，按批次及全轮撤回且不碰旧轮次或积分", async () => {
      const result = await expansion.publish(catalog.hash, "b039", [], "2026-10-28");
      expect(result.admittedPractices).toBe(11);
      const rows = await db.sql<
        { id: string; published: boolean }[]
      >`select id,published from app.learning_units where id=any(${publication.units.map((u) => u.id)})`;
      expect(rows).toHaveLength(14);
      expect(rows.every((r) => r.published)).toBe(true);
      const children = publication.admitted.filter((u) => u.level === "senior1");
      expect(children).toHaveLength(2);
      const first = children.find(
        (u) => u.originalGroup?.family === "shared_insertion",
      );
      const sibling = children.find((u) => u.originalGroup?.family === "passage_form");
      const originalGroup = first?.originalGroup;
      if (!first || !sibling || !originalGroup)
        throw new Error("Missing complete new senior children");
      const copy = (id: string, origin: string): LearningUnit => ({
        ...first,
        id,
        originalGroup: {
          ...originalGroup,
          id,
          sourceNotice:
            (originalGroup.sourceNotice.split(expansionCatalogOriginMarker)[0] ?? "") +
            expansionCatalogOriginMarker +
            origin,
        },
      });
      const future = copy(
        "gaokao.independent.senior1.future-run28-fixture",
        "expansion.20261028.future-parent-fixture",
      );
      const protectedOld = copy(
        "gaokao.independent.senior1.protected-old-fixture",
        "expansion.20261024.protected-parent-fixture",
      );
      extraUnits.push(future.id, protectedOld.id);
      await engine.publishBatch([future, protectedOld]);
      const user = randomUUID(),
        character = randomUUID();
      users.push(user);
      await db.sql`insert into app.users(id) values(${user})`;
      const command = (action: Parameters<LearningEngineRepository["command"]>[4]) =>
        engine.command(user, randomUUID(), "test-derived", {}, action);
      await command((s) => s.ensureCharacter(character, "companion"));
      const start = async (id: string) => {
        await command(async (s) =>
          s.debugFill(character, (await s.character(character)).cycleId),
        );
        const value = await engine.command(
          user,
          randomUUID(),
          "start-derived",
          { id },
          (s) =>
            s.start(character, "senior1", { completeGroups: true, originalUnitId: id }),
        );
        if (!value.attempt)
          throw new Error("Published independent practice was not actually available");
        return value.attempt;
      };
      const a = await start(first.id);
      const question = first.questions[0];
      if (!question) throw new Error("Missing question");
      const input = {
        attemptId: a.id,
        roundId: a.round.id,
        questionId: question.id,
        answer: gradeAnswer(question, { kind: "skip" }).solution,
      };
      const answer = await engine.command(
        user,
        randomUUID(),
        "answer-derived",
        input,
        (s) => s.submit(input),
      );
      expect(answer.awardedPoints).toBe(1);
      await command((s) => s.finish(a.id, true));
      const b = await start(sibling.id);
      expect(b.unit.id).toBe(sibling.id);
      const before = contentHash(
        await db.sql`select question_id,answer,result from app.learning_answers where round_id=${a.round.id} order by question_id`,
      );
      const withdrawn = await expansion.withdraw("b039", "2026-10-28");
      expect(withdrawn.withdrawnUnits).toBe(14);
      expect(withdrawn.retiredAttempts).toBe(2);
      expect(
        (await engine.read(user, (s) => s.character(character))).activeAttemptId,
      ).toBeNull();
      expect(
        (await engine.read(user, (s) => s.progress())).find(
          (p) => p.level === "senior1",
        )?.points,
      ).toBe(1);
      expect(
        contentHash(
          await db.sql`select question_id,answer,result from app.learning_answers where round_id=${a.round.id} order by question_id`,
        ),
      ).toBe(before);
      const full = await expansion.withdraw(undefined, "2026-10-28");
      expect(full.withdrawnUnits).toBe(1); // Unknown future child is found by persisted origin, without a local batch file.
      const [old] = await db.sql<
        { published: boolean }[]
      >`select published from app.learning_units where id=${protectedOld.id}`;
      expect(old?.published).toBe(true);
      expect((await expansion.withdraw(undefined, "2026-10-28")).withdrawnUnits).toBe(
        0,
      );
    });
  },
);
