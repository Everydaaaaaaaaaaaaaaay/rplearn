import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cp, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { loadCuratedCatalog } from "../Backend/src/modules/learning/catalog.ts";
import { loadBankCatalog } from "../Backend/src/modules/learning/bank-catalog.ts";
import {
  assembleBankQuestions,
  bankQuestionSchema,
  type BankQuestion,
} from "../Backend/src/modules/learning/bank-content.ts";
import { contentHash } from "../Backend/src/modules/learning/content.ts";

// 只整理已审稿及显式线上快照，不生成题目，不连接服务器，不修改正式目录。
const root = resolve(new URL("..", import.meta.url).pathname);
const build = await realpath(join(root, "build"));
const [candidateArg, snapshotArg, parentArg, ...extra] = process.argv.slice(2);
assert(
  candidateArg && snapshotArg && parentArg && !extra.length,
  "用法：prepare-junior-publication 候选目录 线上初中题库快照 新的build子目录",
);
const withinBuild = async (path: string) => {
  const actual = await realpath(resolve(path));
  assert(actual.startsWith(build + sep), "输入输出必须位于本仓库build子目录。");
  return actual;
};
const candidate = await withinBuild(candidateArg);
const snapshotPath = await withinBuild(snapshotArg);
const parent = await withinBuild(parentArg);
const output = join(parent, "publication-catalog");
const read = async (path: string) => JSON.parse(await readFile(path, "utf8"));
const write = async (path: string, value: unknown) =>
  writeFile(path, JSON.stringify(value, null, 2) + "\n");
const fileHash = async (path: string) =>
  createHash("sha256")
    .update(await readFile(path))
    .digest("hex");
const accepted = await read(join(candidate, "acceptance.json"));
const original = await loadBankCatalog(candidate);
const curated = await loadCuratedCatalog(candidate);
assert.equal(original.hash, accepted.bankHash, "候选题库与验收摘要不一致。");
assert.equal(
  curated.hash,
  accepted.candidateHash,
  "候选课程与验收摘要不一致。",
);
assert.equal(
  (await loadCuratedCatalog(join(root, "Backend/config/learning"))).hash,
  accepted.baselineHash,
  "正式基线变化，须重新准备候选。",
);
for (const [path, hash] of Object.entries(accepted.inputs)) {
  const absolute = await realpath(join(root, path));
  assert(
    absolute.startsWith(join(root, "Backend/config/learning/authoring") + sep),
  );
  assert.equal(await fileHash(absolute), hash, `作者稿变化：${path}`);
}
const snapshot = await read(snapshotPath);
assert(Number.isFinite(Date.parse(snapshot.at)), "线上快照缺少有效时间。");
const levels = ["junior1", "junior2", "junior3"];
assert.deepEqual(Object.keys(snapshot.levels).sort(), levels);
const live = new Map<
  string,
  { question: BankQuestion; hash: string; published: boolean }
>();
for (const level of levels) {
  for (const row of snapshot.levels[level]) {
    const question = bankQuestionSchema.parse(row.payload);
    assert.equal(question.level, level);
    assert.equal(row.id, question.id);
    assert.equal(
      row.content_hash,
      contentHash(question),
      "线上快照载荷和摘要不符。",
    );
    assert.equal(row.current_version, question.version);
    assert.equal(typeof row.published, "boolean");
    assert(!live.has(question.id), "线上快照重复身份。");
    live.set(question.id, {
      question,
      hash: row.content_hash,
      published: row.published,
    });
  }
  // 不把截断的分页或只有待修订题目的快照当作完整组卷池。
  const baselineIDs = original.entries.filter(
    (e) =>
      e.question.level === level &&
      !accepted.units.some((u) => u.id === e.unitId),
  );
  for (const entry of baselineIDs)
    assert(live.has(entry.question.id), "线上快照缺少既有题。");
}
const unitIDs = new Set(accepted.units.map((u) => u.id));
const added = original.entries.filter((entry) => unitIDs.has(entry.unitId));
assert.equal(added.length, 108);
const newByID = new Map(added.map((entry) => [entry.question.id, entry]));
for (const entry of added)
  assert(!live.has(entry.question.id), "新题身份已上线，须人工核对发布状态。");
const groups = new Map<string, string[]>();
const pairs: { id: string; members: string[] }[] = accepted.exclusionPairs;
assert.equal(pairs.length, 44);
assert.equal(new Set(pairs.map((p) => p.id)).size, pairs.length);
for (const pair of pairs) {
  assert.equal(pair.members.length, 2);
  assert.equal(new Set(pair.members).size, 2);
  assert(
    pair.members.some((id) => newByID.has(id)),
    "本批互斥应至少包含一道新题。",
  );
  const members = pair.members.map((id) => {
    const entry = newByID.get(id);
    const old = live.get(id);
    assert(entry || old, `互斥题不存在：${id}`);
    if (old) assert(old.published, "待修订旧题已下架，不能随目录自动恢复。");
    groups.set(id, [...(groups.get(id) ?? []), pair.id]);
    return entry?.question ?? old!.question;
  });
  assert.equal(members[0]?.level, members[1]?.level, "互斥题对跨年级。");
}
const manifest = await read(join(candidate, "bank.json"));
assert(!manifest.revisions?.length, "候选已携带修订，不能重复合并。");
for (const rule of manifest.units) {
  if (!unitIDs.has(rule.unitId)) continue;
  assert(!rule.questionExclusions, "新题已有互斥元数据，需人工复核。");
  rule.questionExclusions = Object.fromEntries(
    added
      .filter((e) => e.unitId === rule.unitId && groups.has(e.question.id))
      .map((e) => [e.localQuestionId, groups.get(e.question.id)]),
  );
}
manifest.revisions = [...groups]
  .filter(([id]) => live.has(id))
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([id, additions]) => {
    const old = live.get(id)!;
    const question = bankQuestionSchema.parse({
      ...old.question,
      version: old.question.version + 1,
      exclusionGroupIds: [
        ...new Set([...(old.question.exclusionGroupIds ?? []), ...additions]),
      ],
      reviewNotes:
        old.question.reviewNotes +
        "\n2026-10-11初中接入：依据逐题复核的具体题对补充同卷互斥，保留线上现有题文、答案、解析、来源与媒体。",
    });
    assert.deepEqual(question.question, old.question.question);
    assert.deepEqual(question.references, old.question.references);
    return { expectedHash: old.hash, question };
  });
await mkdir(output);
for (const directory of ["units", "reviews", "audio", "images"])
  await cp(join(candidate, directory), join(output, directory), {
    recursive: true,
  });
await cp(join(candidate, "catalog.json"), join(output, "catalog.json"));
await write(join(output, "bank.json"), manifest);
const ready = await loadBankCatalog(output);
assert.equal(ready.catalogHash, original.catalogHash);
const effective = new Map(
  [...live].filter(([, r]) => r.published).map(([id, r]) => [id, r.question]),
);
for (const entry of ready.entries.filter((e) => unitIDs.has(e.unitId)))
  effective.set(entry.question.id, entry.question);
for (const revision of ready.revisions)
  effective.set(revision.question.id, revision.question);
for (const pair of pairs) {
  for (const id of pair.members)
    assert(effective.get(id)?.exclusionGroupIds?.includes(pair.id));
  const registered = [...effective.values()]
    .filter((q) => q.exclusionGroupIds?.includes(pair.id))
    .map((q) => q.id)
    .sort();
  assert.deepEqual(
    registered,
    [...pair.members].sort(),
    "新互斥组不可意外扩散到其他题。",
  );
}
let rolls = 0;
for (const blueprint of ready.blueprints.filter((b) =>
  levels.includes(b.level),
)) {
  const own = new Set(
    ready.entries
      .filter((e) => `bank.${e.unitId}` === blueprint.id)
      .map((e) => e.question.id),
  );
  assert.equal(own.size, blueprint.slots.length);
  const covered = new Set(
    [...effective.values()].map((q) => q.question.goalId),
  );
  for (const mergedTopics of [false, true])
    for (const history of ["fresh", "review", "mixed"])
      for (let seed = 1; seed <= 64; seed++) {
        let state = seed;
        const random = () =>
          (state = (Math.imul(state, 1664525) + 1013904223) >>> 0) / 4294967296;
        const pool = [...effective.values()].map((q) => {
          const seen =
            history === "review" ||
            (history === "mixed" && !own.has(q.id) && random() < 0.7);
          const mastered = seen && (history === "review" || random() < 0.5);
          return {
            ...q,
            ...(mergedTopics ? { topic: "daily" as const } : {}),
            seen,
            mastered,
            reviewDue: history === "review" || (mastered && random() < 0.5),
          };
        });
        const selected = assembleBankQuestions(
          mergedTopics ? { ...blueprint, topic: "daily" } : blueprint,
          pool,
          "oliver",
          covered,
          random,
        );
        assert(
          selected,
          `${blueprint.id} seed=${seed} history=${history} 无法组卷`,
        );
        assert.equal(selected.length, blueprint.slots.length);
        assert.equal(new Set(selected.map((q) => q.id)).size, selected.length);
        selected.forEach((q, index) => {
          assert.equal(q.question.type, blueprint.slots[index]?.type);
          assert.equal(q.question.goalId, blueprint.slots[index]?.goalId);
        });
        for (const pair of pairs)
          assert(
            !pair.members.every((id) => selected.some((q) => q.id === id)),
            `互斥失效：${pair.id}`,
          );
        rolls++;
      }
}
await write(join(output, "publication-review.json"), {
  status: "事务包已离线核验，原生交互与线上验收仍待完成，不可据此自动发布",
  snapshotAt: snapshot.at,
  snapshotSha256: await fileHash(snapshotPath),
  candidateHash: accepted.candidateHash,
  hash: ready.hash,
  revisions: ready.revisions.map((r) => ({
    id: r.question.id,
    version: r.question.version,
    expectedHash: r.expectedHash,
    contentHash: contentHash(r.question),
  })),
  newUnits: [...unitIDs],
  newQuestions: added.length,
  exclusionPairs: pairs,
  rolls,
  historyScope:
    "全新、全到期复习、保留本蓝图原有完整题组未见而其余随机已见/掌握/到期；不覆盖任意耗尽状态，不证明未登记语义冲突不存在。",
});
console.log(
  JSON.stringify({
    output,
    newQuestions: added.length,
    revisions: ready.revisions.length,
    exclusionPairs: pairs.length,
    rolls,
    hash: ready.hash,
    published: false,
  }),
);
