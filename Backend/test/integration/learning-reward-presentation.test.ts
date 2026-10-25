import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { learningFixture } from "../helpers/learning.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("本轮实际积分展示", () => {
  let db: DatabaseResource;
  let repository: LearningEngineRepository;
  const user = randomUUID(),
    character = randomUUID(),
    attempt = randomUUID();
  const unit = learningFixture(`test.reward-display-${randomUUID()}`);
  beforeAll(async () => {
    db = createDatabase(integrationConfig());
    await runMigrations(db);
    repository = new LearningEngineRepository(db);
    await repository.publish(unit);
    await db.sql`insert into app.users(id) values(${user})`;
    const state = await repository.command(user, randomUUID(), "test", {}, (s) =>
      s.ensureCharacter(character, "oliver"),
    );
    await db.sql`insert into app.learning_attempts(id,user_id,character_id,cycle_id,unit_id,unit_version,level_key)
      values(${attempt},${user},${character},${state.cycleId},${unit.id},1,'primary3')`;
  });
  afterAll(async () => {
    await db.sql`delete from app.users where id=${user}`;
    await db.sql`delete from app.learning_unit_versions where unit_id=${unit.id}`;
    await db.sql`delete from app.learning_units where id=${unit.id}`;
    await db.close();
  });
  it("答对不等于获分；补答只显示当前轮积分，重新读取不丢失", async () => {
    const first = randomUUID();
    await db.sql`insert into app.learning_rounds(id,attempt_id,ordinal,question_ids,completed_at)
      values(${first},${attempt},0,${["q.choice", "q.listen", "q.arrange"]},now())`;
    for (const [id, correct, points] of [
      ["q.choice", true, 1],
      ["q.listen", true, 0],
      ["q.arrange", false, 0],
    ] as const) {
      await db.sql`insert into app.learning_answers(round_id,question_id,answer,result)
        values(${first},${id},'{"kind":"skip"}',${JSON.stringify({ outcome: correct ? "correct" : "incorrect", explanation: "Test", solution: { kind: "text", text: "Test" } })}::jsonb)`;
      if (correct)
        await db.sql`insert into app.learning_rewards(attempt_id,question_id,user_id,level_key,goal_id,points)
        values(${attempt},${id},${user},'primary3','test.greetings',${points})`;
    }
    const snapshot = await repository.read(user, (s) => s.attempt(attempt));
    expect(snapshot.round.answers.map((a) => a.awardedPoints)).toEqual([1, 0, 0]);
    const retry = randomUUID();
    await db.sql`insert into app.learning_rounds(id,attempt_id,ordinal,question_ids,completed_at)
      values(${retry},${attempt},1,${["q.arrange"]},now())`;
    await db.sql`insert into app.learning_answers(round_id,question_id,answer,result)
      values(${retry},'q.arrange','{"kind":"skip"}','{"outcome":"correct","explanation":"Test","solution":{"kind":"text","text":"Test"}}')`;
    await db.sql`insert into app.learning_rewards(attempt_id,question_id,user_id,level_key,goal_id,points)
      values(${attempt},'q.arrange',${user},'primary3','test.greetings',1)`;
    for (let i = 0; i < 2; i++) {
      const fresh = await repository.read(user, (s) => s.attempt(attempt));
      expect(fresh.round.answers.map((a) => a.awardedPoints)).toEqual([1]);
      expect(fresh.correctQuestionIds).toHaveLength(3);
    }
  });
});
