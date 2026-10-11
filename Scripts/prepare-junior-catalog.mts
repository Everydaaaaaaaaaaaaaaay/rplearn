import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cp, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { loadCuratedCatalog } from "../Backend/src/modules/learning/catalog.ts";
import { loadBankCatalog } from "../Backend/src/modules/learning/bank-catalog.ts";
import { bankIdentity } from "../Backend/src/modules/learning/bank-content.ts";
import {
  contentHash,
  publicUnit,
  questionSchema,
  unitSchema,
} from "../Backend/src/modules/learning/content.ts";

// 仅映射逐题亲写并复核的内容。输出隔离候选目录，绝不更新正式清单或连接数据库。
const root = resolve(new URL("..", import.meta.url).pathname);
const source = join(root, "Backend/config/learning");
const build = await realpath(join(root, "build"));
const parent = await realpath(
  resolve(process.argv[2] ?? join(build, "learning-junior-20261011")),
);
assert(
  parent === build || parent.startsWith(build + sep),
  "输出必须位于本仓库build目录。",
);
const output = join(parent, "candidate-catalog");
await mkdir(output); // 已存在即停止，避免覆盖任何旧证据。
const read = async (path: string) => JSON.parse(await readFile(path, "utf8"));
const write = async (path: string, value: unknown) =>
  writeFile(path, JSON.stringify(value, null, 2) + "\n");
const sha = (data: Buffer) => createHash("sha256").update(data).digest("hex");
const baseline = await loadCuratedCatalog(source);
const registry = structuredClone(baseline.registry);
const manifest = await read(join(source, "bank.json"));
const inputs: Record<string, string> = {};
const readInput = async (relative: string) => {
  const data = await readFile(join(root, relative));
  inputs[relative] = sha(data);
  return JSON.parse(data.toString());
};
for (const directory of ["units", "reviews", "audio", "images"]) {
  // 复制而非链接：候选审阅不会修改既有已发布素材。
  await cp(join(source, directory), join(output, directory), {
    recursive: true,
  });
}
const audioReview = await readInput(
  "Backend/config/learning/authoring/junior-audio-review-2026-10-11.json",
);
const clips = new Map(audioReview.clips.map((clip) => [clip.questionId, clip]));
const reviewer = "Codex主代理逐题复核，Astra作者逐题自审";
const date = "2026-10-11";
const units = [];
const exclusionPairs = [];
for (const level of ["junior1", "junior2", "junior3"]) {
  const draft = await readInput(
    `Backend/config/learning/authoring/${level}.astra.json`,
  );
  const delivery = await readInput(
    `Backend/config/learning/authoring/${level}-delivery.astra.json`,
  );
  const review = await readInput(
    `Backend/config/learning/authoring/${level}-formal-review.astra.json`,
  );
  assert.equal(review.level, level);
  assert.equal(review.questions.length, 36);
  assert.equal(new Set(review.questions.map((q) => q.id)).size, 36);
  assert.deepEqual(
    review.questions.map((q) => q.id).sort(),
    draft.questions.map((q) => q.id).sort(),
  );
  const checks = new Map(review.questions.map((q) => [q.id, q]));
  const instructions = new Map(
    delivery.questions.map((q) => [q.id ?? q.questionId, q.instruction]),
  );
  const mapped = draft.questions.map((q) => {
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
                acceptedAnswers: [q.answer, ...(q.acceptedVariants ?? [])],
                normalization: {
                  ignoreCase: true,
                  ignoreTerminalPunctuation: true,
                },
              };
    const clip = clips.get(q.id);
    assert.equal(
      Boolean(clip),
      Boolean(q.audioScript),
      `${q.id} 音频登记不完整`,
    );
    if (clip) assert.equal(clip.audioScript, q.audioScript);
    return questionSchema.parse({
      id: q.id,
      goalId: q.goalId,
      type: q.type,
      instruction: instructions.get(q.id),
      prompt: q.prompt,
      hint: q.hint,
      explanation: q.explanation,
      difficultyReason: q.difficulty ?? q.review.difficulty,
      ...fields,
      ...(clip
        ? {
            audio: {
              assetId: "audio." + clip.sha256,
              text: clip.audioScript,
              voice: clip.voice,
            },
          }
        : {}),
    });
  });
  for (const q of mapped) {
    const clip = clips.get(q.id);
    if (!clip) continue;
    const path = await realpath(join(root, clip.file));
    assert(path.startsWith(build + sep), "音频必须来自本地已审定build记录。");
    const data = await readFile(path);
    assert.equal(sha(data), clip.sha256, `${q.id} 母版哈希变化`);
    assert.deepEqual(Object.keys(clip.masterRecognition).sort(), [
      "base.en",
      "small.en",
    ]);
    assert.deepEqual(Object.keys(clip.candidateRecognition).sort(), [
      "base.en",
      "small.en",
    ]);
    for (const result of [
      ...Object.values(clip.masterRecognition),
      ...Object.values(clip.candidateRecognition),
    ])
      assert.equal(result.exact, true);
    const id = "audio." + clip.sha256;
    assert(
      !registry.audioAssets?.some((a) => a.id === id),
      "新音频身份意外复用，需人工检查。",
    );
    registry.audioAssets ??= [];
    registry.audioAssets.push({
      id,
      sha256: clip.sha256,
      byteSize: data.length,
      durationMs: clip.durationMs,
      contentType: "audio/wav",
      transcript: clip.audioScript,
      voice: clip.voice,
      reviewedAt: date,
      reviewNotes: `完整台词采用Supertonic3离线合成；候选与母版均经base.en/small.en无提示转写核验，24kHz单声道PCM16，未切词拼接或后处理变速。实际${clip.wpm}词/分；完整证据见junior-audio-review-2026-10-11.json。尚未独立人耳听感审定，原生交互验收未完成。`,
    });
    await writeFile(join(output, "audio", id + ".wav"), data);
  }
  for (const story of delivery.stories) {
    const questions = mapped.filter((q) =>
      q.id.startsWith(`j${level.at(-1)}.astra.${story.questionGroup}`),
    );
    assert.equal(questions.length, 18);
    // 来源、页码、对齐说明逐题保留，不借用旧题参考资料。
    const references = questions.map((q) => {
      const original = draft.questions.find((row) => row.id === q.id);
      const checked = checks.get(q.id);
      const sourceId = original.sourceId ?? original.source.split(" ")[0];
      const pages =
        original.pages === undefined
          ? original.source.slice(sourceId.length).trim()
          : typeof original.pages === "string"
            ? original.pages
            : `印刷${original.pages.printed.join("、")}／PDF${original.pages.pdf.join("、")}`;
      return {
        sourceId,
        unit: q.id,
        pages,
        alignment: checked.sourceAlignment,
      };
    });
    const unit = unitSchema.parse({
      id: `companion.${level}.astra-${story.questionGroup}`,
      version: 1,
      schemaVersion: 1,
      scoringVersion: 1,
      roleKey: "companion",
      roleVersion: 1,
      level,
      title: story.title,
      summary: story.title,
      scene: story.beats[0].translation,
      estimatedMinutes: 14,
      goalIds: [...new Set(questions.map((q) => q.goalId))],
      prerequisiteGoalIds: [],
      references,
      authorship: {
        kind: "authored",
        author:
          typeof draft.author === "string" ? draft.author : draft.author.name,
        reviewedBy: reviewer,
        reviewedAt: date,
        reviewNotes:
          "从Astra逐题亲写及主代理复核的冻结稿机械映射；非程序组合出题。此目录仅供接入验收，尚未完成原生操作、互斥修订事务及线上挑战验证。",
      },
      beats: story.beats,
      questions,
    });
    const rows = questions.map((q) => {
      const checked = checks.get(q.id);
      const original = draft.questions.find((row) => row.id === q.id);
      const wrong = original.review.wrongExample;
      const probes =
        "options" in q
          ? q.options.map((o) => ({
              answer: { kind: "choice", optionId: o.id },
              correct: o.id === q.answer,
            }))
          : "acceptedAnswers" in q
            ? [
                ...q.acceptedAnswers.map((text) => ({
                  answer: { kind: "text", text },
                  correct: true,
                })),
                { answer: { kind: "text", text: wrong }, correct: false },
              ]
            : "acceptedOrders" in q
              ? [
                  ...q.acceptedOrders.map((tokenIds) => ({
                    answer: { kind: "arrange", tokenIds },
                    correct: true,
                  })),
                  {
                    answer: { kind: "arrange", tokenIds: wrong.split(",") },
                    correct: false,
                  },
                ]
              : [
                  {
                    answer: { kind: "matching", pairs: q.answerPairs },
                    correct: true,
                  },
                  {
                    answer: {
                      kind: "matching",
                      pairs: wrong.split(",").map((pair) => {
                        const [left, right] = pair.split("-");
                        return { left, right };
                      }),
                    },
                    correct: false,
                  },
                ];
      return {
        questionId: q.id,
        standaloneContext: checked.standaloneContext,
        ambiguityReview: checked.ambiguityReview,
        optionNotes: checked.optionNotes,
        probes,
      };
    });
    await write(join(output, "units", unit.id + ".json"), unit);
    await write(join(output, "reviews", unit.id + ".json"), {
      unitId: unit.id,
      contentHash: contentHash(unit),
      status: "approved",
      reviewKind: "author-self-review",
      reviewer,
      reviewedAt: date,
      roleFit: "无职业或姓名绑定的同行场景，完整故事前置且不承担题目作答条件。",
      levelFit:
        "逐题映射已核读教材目标、页码及边界；本组受控练习不代表整个年级课程覆盖。",
      limitations:
        "内容审阅通过不等于发布验收。双ASR及波形核验不等于人耳听感；原生交互与线上组卷待验，互斥题对须随入库一起生效。",
      questions: rows,
    });
    registry.unitIds.push(unit.id);
    manifest.units.push({ unitId: unit.id, topic: "daily", roleKeys: [] });
    await write(
      join(output, `${level}-${story.questionGroup}.public.json`),
      publicUnit(unit),
    );
    units.push({ id: unit.id, contentHash: contentHash(unit) });
  }
  const byID = new Map(mapped.map((q) => [q.id, bankIdentity(q)]));
  for (const pair of delivery.exclusions) {
    const newIDs = pair.candidateIds ?? [pair.candidateId];
    const oldIDs = pair.oldBankIds ?? [pair.oldBankId];
    const members = [
      ...newIDs.map((id) => {
        assert(byID.has(id));
        return byID.get(id);
      }),
      ...oldIDs,
    ];
    assert.equal(members.length, 2);
    assert.equal(new Set(members).size, 2);
    exclusionPairs.push({ id: pair.exclusionGroupId, members });
  }
}
await write(join(output, "catalog.json"), registry);
await write(join(output, "bank.json"), manifest);
const checked = await loadCuratedCatalog(output);
const bank = await loadBankCatalog(output);
assert.equal(checked.units.length, baseline.units.length + 6);
assert.equal(bank.entries.length, 846);
assert.equal(checked.audioAssets.length, 174);
assert.equal(exclusionPairs.length, 44);
const originalHashes = new Map(
  baseline.units.map((u) => [u.id, contentHash(u)]),
);
for (const unit of checked.units)
  if (originalHashes.has(unit.id))
    assert.equal(contentHash(unit), originalHashes.get(unit.id));
assert.equal(
  (await loadCuratedCatalog(source)).hash,
  baseline.hash,
  "正式目录发生变化。",
);
await write(join(output, "acceptance.json"), {
  status: "仅隔离候选，不可直接发布",
  pending: [
    "原生操作与播放验收",
    "合并线上现有修订与44对互斥，并通过事务发布",
    "线上真实挑战验收",
  ],
  baselineHash: baseline.hash,
  candidateHash: checked.hash,
  bankHash: bank.hash,
  inputs,
  units,
  exclusionPairs,
  questions: bank.entries.length,
  blueprints: bank.blueprints.length,
  audioAssets: checked.audioAssets.length,
});
console.log(
  JSON.stringify({
    output,
    newUnits: units.length,
    newQuestions: 108,
    newAudio: 34,
    exclusionPairs: exclusionPairs.length,
    status: "隔离目录合同验证通过，未发布",
  }),
);
