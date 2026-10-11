import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
// 只验证人工稿组卷约束；不生成教学内容，不连接数据库。
const root = fileURLToPath(new URL("..", import.meta.url));
process.chdir(root);
import { loadBankCatalog } from "../Backend/src/modules/learning/bank-catalog.ts";
import { assembleBankQuestions } from "../Backend/src/modules/learning/bank-content.ts";
import { contentHash } from "../Backend/src/modules/learning/content.ts";
const directory = resolve(
  process.argv[2] ??
    "build/learning-strengthening-20261011/final/candidate-catalog",
);
assert(
  directory.startsWith(resolve("build") + sep),
  "仅验证build内隔离候选目录。",
);
const bank = await loadBankCatalog(directory);
const accepted = JSON.parse(
  readFileSync(directory + "/acceptance.json", "utf8"),
);
const saved = JSON.parse(
  readFileSync(
    "Backend/config/learning/bank-revisions/2026-10-11-cross-question.json",
    "utf8",
  ),
);
const pool = new Map(
  bank.entries.map((e) => [e.question.id, structuredClone(e.question)]),
);
for (const row of saved.updates) {
  assert.equal(contentHash(pool.get(row.question.id)), row.expectedHash);
  assert.equal(contentHash(row.question), row.contentHash);
  pool.set(row.question.id, row.question);
}
for (const pair of accepted.exclusionPairs)
  for (const id of pair.members) {
    const q = pool.get(id);
    assert(q);
    q.exclusionGroupIds = [
      ...new Set([...(q.exclusionGroupIds ?? []), pair.id]),
    ];
  }
let rolls = 0;
const levels = ["senior3", "undergraduate", "postgraduate"];
for (const b of bank.blueprints.filter((b) => levels.includes(b.level))) {
  for (const merged of [false, true])
    for (const history of ["fresh", "review", "mixed"])
      for (let seed = 1; seed <= 32; seed++) {
        let state = seed;
        const random = () =>
          (state = (Math.imul(state, 1664525) + 1013904223) >>> 0) / 4294967296;
        const fresh = [...pool.values()].map((q) => ({
          ...q,
          ...(merged ? { topic: "daily" as const } : {}),
          seen: false,
          mastered: false,
          reviewDue: false,
        }));
        // 混合历史须保留一个真实可解集合，不能假定原模板题在新增互斥后仍可同卷。
        const witness = assembleBankQuestions(
          merged ? { ...b, topic: "daily" } : b,
          fresh,
          "oliver",
          new Set(fresh.map((c) => c.question.goalId)),
          () => 0.5,
        );
        assert(witness, `${b.id} 缺少可解基线`);
        const own = new Set(witness.map((q) => q.id));
        const candidates = [...pool.values()].map((q) => {
          const seen =
            history === "review" ||
            (history === "mixed" && !own.has(q.id) && random() < 0.7);
          const mastered = seen && (history === "review" || random() < 0.5);
          return {
            ...q,
            ...(merged ? { topic: "daily" as const } : {}),
            seen,
            mastered,
            reviewDue: history === "review" || (mastered && random() < 0.5),
          };
        });
        const selected = assembleBankQuestions(
          merged ? { ...b, topic: "daily" } : b,
          candidates,
          "oliver",
          new Set(candidates.map((c) => c.question.goalId)),
          random,
        );
        assert(selected, `${b.id}/${history}/${seed} 缺题`);
        assert.equal(selected.length, b.slots.length);
        assert.equal(new Set(selected.map((q) => q.id)).size, selected.length);
        const groups = new Set();
        selected.forEach((q, i) => {
          assert.equal(q.question.goalId, b.slots[i].goalId);
          assert.equal(q.question.type, b.slots[i].type);
          for (const g of q.exclusionGroupIds ?? []) {
            assert(!groups.has(g), g);
            groups.add(g);
          }
        });
        rolls++;
      }
}
writeFileSync(
  "build/learning-strengthening-20261011/bank-verification.json",
  JSON.stringify(
    {
      rolls,
      blueprints: bank.blueprints.filter((b) => levels.includes(b.level))
        .length,
      exclusions: accepted.exclusionPairs.length,
      bankHash: bank.hash,
      scope:
        "混合历史保留一个有效可解样本，不保证任意历史均有足够未见题；仅本地正式基线、已存15项修订与本批候选的组卷验证；尚未读取本轮线上快照或准备事务发布载荷。",
    },
    null,
    2,
  ) + "\n",
);
console.log({ rolls });
