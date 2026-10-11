import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { loadBankCatalog } from "../Backend/src/modules/learning/bank-catalog.ts";
import {
  assembleBankQuestions,
  bankBlueprintSchema,
  bankIdentity,
  bankQuestionSchema,
} from "../Backend/src/modules/learning/bank-content.ts";
import {
  questionSchema,
  unitSchema,
} from "../Backend/src/modules/learning/content.ts";
import { learningFixture } from "../Backend/test/helpers/learning.ts";

// 只在内存核验人工交付稿。测试音频引用和临时分类不可导入正式目录。
const directory = new URL("../Backend/config/learning/", import.meta.url);
const catalog = await loadBankCatalog(directory.pathname);
const reports = [];
for (const level of ["junior1", "junior2", "junior3"]) {
  const read = async (suffix: string) =>
    JSON.parse(
      await readFile(
        new URL(`authoring/${level}${suffix}.astra.json`, directory),
        "utf8",
      ),
    );
  const draft = await read("");
  const delivery = await read("-delivery");
  const instructions = new Map(
    delivery.questions.map((q) => [q.id ?? q.questionId, q.instruction]),
  );
  assert.equal(instructions.size, 36);
  assert.deepEqual(
    [...instructions.keys()].sort(),
    draft.questions.map((q) => q.id).sort(),
  );
  const original = catalog.entries.filter(
    (entry) => entry.question.level === level,
  );
  const entries = original.map((entry) => structuredClone(entry.question));
  const newEntries = draft.questions.map((q) => {
    const fields =
      q.type === "choice" || q.type === "listeningChoice"
        ? { options: q.options, answer: q.answer }
        : q.type === "arrange" || q.type === "audioArrange"
          ? { tokens: q.tokens, acceptedOrders: q.acceptedOrders }
          : q.type === "matching"
            ? {
                left: q.left,
                right: q.right,
                answerPairs: q.answerPairs.map(([left, right]) => ({
                  left,
                  right,
                })),
              }
            : {
                acceptedAnswers: [q.answer, ...q.acceptedVariants],
                normalization: {
                  ignoreCase: true,
                  ignoreTerminalPunctuation: true,
                },
              };
    const question = questionSchema.parse({
      id: q.id,
      goalId: q.goalId,
      type: q.type,
      prompt: q.prompt,
      instruction: instructions.get(q.id),
      hint: q.hint,
      explanation: q.explanation,
      difficultyReason: q.difficulty ?? q.review.difficulty,
      ...fields,
      ...(q.audioScript
        ? {
            audio: {
              assetId: "test.pending-audio",
              text: q.audioScript,
              voice: "test",
            },
          }
        : {}),
    });
    return bankQuestionSchema.parse({
      id: bankIdentity(question),
      version: 1,
      level,
      topic: "daily",
      roleKeys: [],
      question,
      // 此处只验证抽题合同；正式引用必须另按逐题来源映射。
      references: original[0].question.references,
      reviewNotes:
        "仅供离线组卷的内存夹具；没有完成媒体、真实引用映射、原生体验或发布验收，不可导入。",
    });
  });
  const local = new Map(newEntries.map((entry) => [entry.question.id, entry]));
  entries.push(...newEntries);
  assert.equal(
    new Set(entries.map((entry) => entry.id)).size,
    entries.length,
    `${level} 身份重复`,
  );
  const byId = new Map(entries.map((entry) => [entry.id, entry]));
  const exclusions = delivery.exclusions.map((row) => ({
    ...row,
    candidates: row.candidateIds ?? [row.candidateId],
    previous: row.oldBankIds ?? [row.oldBankId],
    oldQuestions:
      row.oldQuestions ??
      (row.oldBankId
        ? [{ unitId: row.oldUnitId, localQuestionId: row.oldQuestionId }]
        : []),
  }));
  assert.equal(
    new Set(exclusions.map((row) => row.exclusionGroupId)).size,
    exclusions.length,
  );
  const pairs: string[][] = [];
  for (const row of exclusions) {
    assert.equal(
      row.candidates.length + row.previous.length,
      2,
      "互斥必须是具体题对",
    );
    assert.equal(row.previous.length, row.oldQuestions.length);
    for (let i = 0; i < row.previous.length; i++) {
      const ref = row.oldQuestions[i];
      const old = original.find(
        (entry) =>
          entry.unitId === ref.unitId &&
          entry.localQuestionId === ref.localQuestionId,
      );
      assert(old, `旧题引用不存在：${JSON.stringify(ref)}`);
      assert.equal(old.question.id, row.previous[i], "旧题身份与人工记录不符");
    }
    const members = [
      ...row.candidates.map((id) => {
        const entry = local.get(id);
        assert(entry, `候选题不存在：${id}`);
        return entry;
      }),
      ...row.previous.map((id) => {
        const entry = byId.get(id);
        assert(entry, `旧库题不存在：${id}`);
        return entry;
      }),
    ];
    assert.equal(new Set(members.map((entry) => entry.id)).size, 2);
    pairs.push(members.map((entry) => entry.id));
    for (const entry of members) {
      entry.exclusionGroupIds = [
        ...(entry.exclusionGroupIds ?? []),
        row.exclusionGroupId,
      ];
      bankQuestionSchema.parse(entry);
    }
  }
  const assertRoll = (roll: typeof entries | null, expected: number) => {
    assert(roll, `${level} 无法完成${expected}题组卷`);
    assert.equal(roll.length, expected);
    const ids = new Set(roll.map((entry) => entry.id));
    assert.equal(ids.size, expected);
    for (const pair of pairs)
      assert(!pair.every((id) => ids.has(id)), `互斥失效：${pair}`);
  };
  const newBlueprints = delivery.stories.map((story) => {
    assert.equal(story.skippable, true);
    assert.equal(story.beats.length, 3);
    assert.deepEqual(
      story.beats.map((beat) => beat.id),
      ["opening.1", "opening.2", "opening.3"],
    );
    assert(story.beats.every((beat) => beat.afterQuestion === 0));
    const group = newEntries.filter((entry) =>
      entry.question.id.startsWith(
        `j${level.at(-1)}.astra.${story.questionGroup}`,
      ),
    );
    assertRoll(group, 18);
    const fixture = unitSchema.parse({
      ...learningFixture(),
      level,
      title: story.title,
      summary: story.title,
      scene: story.beats[0].translation,
      beats: story.beats,
      questions: group.map((entry) => entry.question),
      goalIds: [...new Set(group.map((entry) => entry.question.goalId))],
    });
    return bankBlueprintSchema.parse({
      id: `test.${level}.${story.questionGroup}`,
      title: story.title,
      level,
      topic: "daily",
      prerequisiteGoalIds: [],
      openingStory: {
        title: story.title,
        scene: fixture.scene,
        beats: fixture.beats,
      },
      slots: fixture.questions.map((q) => ({ goalId: q.goalId, type: q.type })),
    });
  });
  assert.equal(newBlueprints.length, 2);
  const blueprints = [
    ...catalog.blueprints.filter((b) => b.level === level),
    ...newBlueprints,
  ];
  const covered = new Set(entries.map((entry) => entry.question.goalId));
  let rolls = 0;
  for (const mergedTopics of [false, true]) {
    // 合并分类是额外压力测试，使所有已审题对有机会相遇，不改变正式分类。
    for (const due of [false, true]) {
      const pool = entries.map((entry) => ({
        ...entry,
        ...(mergedTopics ? { topic: "daily" as const } : {}),
        seen: due,
        mastered: due,
        reviewDue: due,
      }));
      for (const blueprint of blueprints)
        for (let seed = 1; seed <= 64; seed++) {
          let state = seed;
          const random = () =>
            (state = (Math.imul(state, 1664525) + 1013904223) >>> 0) /
            4294967296;
          const roll = assembleBankQuestions(
            mergedTopics ? { ...blueprint, topic: "daily" } : blueprint,
            pool,
            "test.companion",
            covered,
            random,
          );
          assert(
            roll,
            `${level} ${blueprint.id} seed=${seed} 合并分类=${mergedTopics} 到期复习=${due} 组卷失败`,
          );
          assertRoll(roll, blueprint.slots.length);
          rolls++;
        }
    }
  }
  reports.push({
    level,
    instructions: instructions.size,
    stories: newBlueprints.length,
    exclusionPairs: pairs.length,
    rolls,
  });
}
console.log(
  JSON.stringify({
    reports,
    scope:
      "人工稿离线接入核验；不写目录或数据库，不证明未登记的语义冲突不存在、媒体或原生端验收通过。",
  }),
);
