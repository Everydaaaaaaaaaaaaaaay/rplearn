import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { loadBankCatalog } from "../Backend/src/modules/learning/bank-catalog.ts";
import {
  assembleBankQuestions,
  bankIdentity,
  bankQuestionSchema,
  bankUnit,
} from "../Backend/src/modules/learning/bank-content.ts";
import {
  contentHash,
  unitSchema,
} from "../Backend/src/modules/learning/content.ts";

// 只核验人工审定的修订清单，不生成题目、不连接或写入数据库。
const root = new URL("../", import.meta.url);
const catalog = await loadBankCatalog(
  new URL("Backend/config/learning/", root).pathname,
);
const plan = JSON.parse(
  await readFile(
    new URL(
      "Backend/config/learning/bank-revisions/2026-10-11-cross-question.json",
      root,
    ),
    "utf8",
  ),
);
const live = process.argv[2]
  ? JSON.parse(await readFile(process.argv[2], "utf8"))
  : undefined;
const entries = live
  ? live.items
      .filter((row) => row.published)
      .map((row) => bankQuestionSchema.parse(row.payload))
  : catalog.entries.map((entry) => entry.question);
const blueprints = live
  ? live.coverage.blueprints.map((row) => row.payload)
  : catalog.blueprints;
const original = new Map(entries.map((q) => [q.id, q]));
const ids = new Set<string>();
for (const update of plan.updates) {
  const q = bankQuestionSchema.parse(update.question);
  const old = original.get(q.id);
  assert(old, `缺少原题：${q.id}`);
  assert(!ids.has(q.id), `重复修订：${q.id}`);
  ids.add(q.id);
  assert.equal(contentHash(old), update.expectedHash, `原题已变化：${q.id}`);
  assert.equal(contentHash(q), update.contentHash, `修订哈希不一致：${q.id}`);
  assert.equal(q.version, old.version + 1);
  assert.equal(q.level, old.level);
  assert.equal(q.question.goalId, old.question.goalId);
  assert.equal(q.question.type, old.question.type);
  assert.equal(contentHash(q.references), contentHash(old.references));
  const media = (value) => ({
    audio: value.question.audio ?? null,
    images: JSON.stringify(value.question).match(/image\.[a-f0-9]{64}/g) ?? [],
  });
  assert.equal(
    contentHash(media(q)),
    contentHash(media(old)),
    "本轮不可更换媒体",
  );
}

let rolls = 0;
// 验证逐条发布的每个中间状态，避免后面的互斥先上线导致暂时无法组卷。
for (let prefix = 0; prefix <= plan.updates.length; prefix++) {
  const current = new Map(original);
  for (const update of plan.updates.slice(0, prefix))
    current.set(update.question.id, update.question);
  const materialIds = [...current.values()].map((q) =>
    bankIdentity(q.question),
  );
  assert.equal(
    new Set(materialIds).size,
    materialIds.length,
    "修订产生了重复题",
  );
  for (const reviewDue of [false, true]) {
    const pool = [...current.values()].map((q) => ({
      ...q,
      seen: reviewDue,
      mastered: reviewDue,
      reviewDue,
    }));
    for (const blueprint of blueprints) {
      for (let seed = 1; seed <= 20; seed++) {
        let state = seed;
        const random = () =>
          (state = (state * 1664525 + 1013904223) >>> 0) / 2 ** 32;
        const selected = assembleBankQuestions(
          blueprint,
          seed % 2 ? pool : [...pool].reverse(),
          "oliver",
          new Set(),
          random,
        );
        assert(
          selected,
          `发布第 ${prefix} 步无法组卷：${blueprint.id}，种子 ${seed}，复习 ${reviewDue}`,
        );
        assert.equal(selected.length, blueprint.slots.length);
        unitSchema.parse(
          bankUnit(blueprint, selected, "review.check", "oliver", "同伴"),
        );
        const groups = selected.flatMap((q) => q.exclusionGroupIds ?? []);
        assert.equal(new Set(groups).size, groups.length, "互斥题出现在同卷");
        rolls++;
      }
    }
  }
}
console.log(
  JSON.stringify({
    updates: ids.size,
    blueprints: blueprints.length,
    prefixes: plan.updates.length + 1,
    rolls,
    source: live ? "线上只读快照" : "正式目录",
    scope: "验证全新题池与全部到期复习题池，不代表任意部分学习历史或教学效果",
  }),
);
