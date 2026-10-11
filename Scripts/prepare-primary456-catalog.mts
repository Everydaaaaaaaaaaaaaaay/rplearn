import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  cp,
  lstat,
  mkdir,
  readFile,
  realpath,
  writeFile,
} from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { loadCuratedCatalog } from "../Backend/src/modules/learning/catalog.ts";
import { loadBankCatalog } from "../Backend/src/modules/learning/bank-catalog.ts";
import { bankIdentity } from "../Backend/src/modules/learning/bank-content.ts";
import {
  contentHash,
  publicUnit,
  questionSchema,
  unitSchema,
} from "../Backend/src/modules/learning/content.ts";
import {
  answerSchema,
  gradeAnswer,
} from "../Backend/src/modules/learning/grading.ts";

// 仅转换作者已亲写的字段、来源、审阅及作答样例；不生成教学文本或错误答案。
const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const source = join(root, "Backend/config/learning");
const build = await realpath(join(root, "build"));
const parent = await realpath(
  resolve(process.argv[2] ?? join(build, "learning-primary456-20261011")),
);
assert(
  parent === build || parent.startsWith(build + sep),
  "输出父目录必须实际位于本仓库build内。",
);
const levels = (process.argv[3] ?? "primary4,primary5,primary6").split(",");
assert(
  !process.argv[4] &&
    levels.length > 0 &&
    new Set(levels).size === levels.length &&
    levels.every((level) =>
      ["primary4", "primary5", "primary6"].includes(level),
    ),
  "年级参数必须为不重复的primary4、primary5、primary6逗号列表。",
);
const expectedQuestions = levels.length * 36;
const expectedUnits = levels.length * 2;
const expectedAudio = levels.reduce(
  (sum, level) => sum + (level === "primary4" ? 7 : 6),
  0,
);
const output = join(parent, "candidate-catalog");
try {
  await lstat(output);
  throw new Error("候选目录已存在，拒绝覆盖旧证据。");
} catch (error) {
  if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
}
const inputs: Record<string, string> = {};
const sha = (data: Buffer) => createHash("sha256").update(data).digest("hex");
const read = async (path: string) => JSON.parse(await readFile(path, "utf8"));
const write = async (path: string, value: unknown) =>
  writeFile(path, JSON.stringify(value, null, 2) + "\n");
const readInput = async (relative: string) => {
  let data: Buffer;
  try {
    data = await readFile(join(root, relative));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT")
      throw new Error(
        `缺少必需审阅输入：${relative}。未创建候选目录；不编造媒体或审阅。`,
      );
    throw error;
  }
  inputs[relative] = sha(data);
  return JSON.parse(data.toString());
};
// 先检查音频报告存在，缺失时不能留下半成品目录。
const audioReportPath =
  "Backend/config/learning/authoring/primary456-audio-review-2026-10-11.json";
const audioReview = await readInput(audioReportPath);
assert(Array.isArray(audioReview.clips), "音频报告缺少clips。");
assert(Array.isArray(audioReview.failures), "音频报告缺少完整失败记录。");
const selectedClips = audioReview.clips.filter((clip: any) =>
  levels.includes(clip.level),
);
assert(
  audioReview.failures.every(
    (failure: any) => !levels.includes(failure.level),
  ) && selectedClips.length === expectedAudio,
  "所选年级媒体尚未全部通过，拒绝创建候选目录。",
);
const clips = new Map(
  selectedClips.map((clip: any) => [clip.questionId, clip]),
);
assert.equal(clips.size, selectedClips.length, "音频报告题号重复。");
const baseline = await loadCuratedCatalog(source);
const baselineBank = await loadBankCatalog(source);
const registry = structuredClone(baseline.registry);
const manifest = await read(join(source, "bank.json"));
const date = "2026-10-11";
const reviewer = "Astra逐题作者自审；候选接入合同检查";
const plans: any[] = [];
const mappedIds = new Map<string, string>();
const audioFiles = new Map<string, Buffer>();
const seenClips = new Set<string>();

function checkRecognition(recognition: any, label: string) {
  assert(
    recognition && typeof recognition === "object",
    `${label}缺少识别记录。`,
  );
  assert.deepEqual(
    Object.keys(recognition).sort(),
    ["base.en", "small.en"],
    `${label}需要双模型识别。`,
  );
  for (const result of Object.values(recognition) as any[]) {
    assert.equal(result.exact, true, `${label}识别未精确通过。`);
    assert.equal(typeof result.text, "string", `${label}缺少识别原文。`);
  }
}
function checkCandidates(clip: any) {
  // 母版可含多话轮；每段必须保留各自候选识别，不能只检查第一段。
  assert(
    Array.isArray(clip.candidateSegments) && clip.candidateSegments.length > 0,
    `${clip.questionId}缺少candidateSegments。`,
  );
  for (const [index, candidate] of clip.candidateSegments.entries()) {
    assert(typeof candidate.text === "string" && candidate.text.length > 0);
    assert(
      ["F3", "M3", "M5"].includes(candidate.voice),
      `${clip.questionId}候选声线未登记。`,
    );
    assert.match(candidate.sha256, /^[a-f0-9]{64}$/);
    checkRecognition(
      candidate.candidateRecognition,
      `${clip.questionId}候选话轮${index + 1}`,
    );
  }
  assert.equal(
    clip.spokenText,
    clip.candidateSegments.map((segment: any) => segment.text).join(" "),
    `${clip.questionId}实际朗读全文与话轮拼接不一致。`,
  );
  const voices = [
    ...new Set(clip.candidateSegments.map((segment: any) => segment.voice)),
  ].sort();
  assert.equal(
    clip.voice,
    voices.join("+"),
    `${clip.questionId}母版声线标识不一致。`,
  );
}

for (const level of levels) {
  const formal = await readInput(
    `Backend/config/learning/authoring/${level}-formal.astra.json`,
  );
  const draftPath = `Backend/config/learning/authoring/${level}.astra.json`;
  await readInput(draftPath);
  assert.equal(
    formal.inputHashes[`${level}.astra.json`],
    inputs[draftPath],
    `${level}原稿已变化。`,
  );
  const deliveryPath = `Backend/config/learning/authoring/${level}-delivery.astra.json`;
  const delivery = await readInput(deliveryPath);
  assert.equal(formal.level, level);
  assert.equal(delivery.level, level);
  assert.equal(formal.questions.length, 36);
  assert.equal(new Set(formal.questions.map((row: any) => row.id)).size, 36);
  assert.equal(
    formal.inputHashes[`${level}-delivery.astra.json`],
    inputs[deliveryPath],
    `${level}正式审阅所绑定delivery已变化。`,
  );
  assert.equal(delivery.stories.length, 2);
  assert.deepEqual(
    delivery.stories.map((story: any) => story.questionGroup).sort(),
    ["a", "b"],
  );
  const questions = [];
  for (const row of formal.questions) {
    assert.equal(row.id, row.question.id);
    assert.match(
      row.id,
      new RegExp(`^p${level.at(-1)}\\.astra\\.[ab](0[1-9]|1[0-8])$`),
    );
    const raw = structuredClone(row.question);
    assert(!raw.audio, `${row.id}应由真实媒体报告填入audio。`);
    const needsAudio = [
      "listeningChoice",
      "audioArrange",
      "dictation",
    ].includes(raw.type);
    const clip = clips.get(row.id) as any;
    assert.equal(Boolean(clip), needsAudio, `${row.id}音频登记与题型不一致。`);
    if (needsAudio) {
      assert.equal(clip.audioScript, row.audioScript, `${row.id}台词不一致。`);
      assert.equal(typeof row.audioScript, "string");
      assert(row.audioScript.length > 0);
      checkRecognition(clip.masterRecognition, `${row.id}母版`);
      checkCandidates(clip);
      assert.equal(clip.sampleRate, 24000);
      assert.equal(clip.channels, 1);
      assert.equal(clip.sampleWidth, 2);
      assert(Number.isFinite(clip.durationMs) && clip.durationMs > 0);
      assert(Number.isFinite(clip.wpm) && clip.wpm > 0);
      const path = await realpath(resolve(root, clip.file));
      assert(path.startsWith(build + sep), `${row.id}音频必须实际来自build。`);
      const bytes = await readFile(path);
      assert.equal(sha(bytes), clip.sha256, `${row.id}音频母版哈希不符。`);
      const id = "audio." + clip.sha256;
      assert(
        !registry.audioAssets?.some((asset) => asset.id === id),
        `${row.id}音频身份重复，需人工检查。`,
      );
      audioFiles.set(id, bytes);
      registry.audioAssets ??= [];
      registry.audioAssets.push({
        id,
        sha256: clip.sha256,
        byteSize: bytes.length,
        durationMs: clip.durationMs,
        contentType: "audio/wav",
        transcript: clip.audioScript,
        voice: clip.voice,
        reviewedAt: date,
        reviewNotes: `候选与母版双模型转写记录已校验，媒体哈希一致；实际${clip.wpm}词/分。证据见primary456-audio-review-2026-10-11.json。仅客观记录，未声称独立人耳与原生播放验收。`,
      });
      raw.audio = { assetId: id, text: clip.audioScript, voice: clip.voice };
      seenClips.add(row.id);
    } else assert(!row.audioScript, `${row.id}非音频题意外携带脚本。`);
    const question = questionSchema.parse(raw);
    assert(
      registry.goals.some(
        (goal) => goal.id === question.goalId && goal.level === level,
      ),
      `${row.id}目标${question.goalId}不在正式同级目录，禁止猜映射。`,
    );
    assert(Array.isArray(row.references) && row.references.length > 0);
    for (const reference of row.references)
      assert(
        registry.sources.some((entry) => entry.id === reference.sourceId),
        `${row.id}来源${reference.sourceId}未登记。`,
      );
    assert(
      row.optionNotes &&
        typeof row.optionNotes === "object" &&
        !Array.isArray(row.optionNotes),
      `${row.id}optionNotes必须作者逐项写成对象。`,
    );
    assert.deepEqual(
      Object.keys(row.optionNotes).sort(),
      "options" in question
        ? question.options.map((option) => option.id).sort()
        : [],
    );
    for (const note of Object.values(row.optionNotes))
      assert(typeof note === "string" && note.length >= 8);
    assert(
      row.probes.some((probe: any) => probe.correct) &&
        row.probes.some((probe: any) => !probe.correct),
    );
    for (const probe of row.probes) {
      const answer = answerSchema.parse(probe.answer);
      assert.equal(
        gradeAnswer(question, answer).outcome === "correct",
        probe.correct,
        `${row.id}作者样例判题不符。`,
      );
    }
    questions.push(question);
    assert(!mappedIds.has(row.id));
    mappedIds.set(row.id, bankIdentity(question));
  }
  plans.push({ level, formal, delivery, questions });
}
assert.equal(mappedIds.size, expectedQuestions);
assert.equal(
  seenClips.size,
  clips.size,
  "媒体报告有未使用题号，不能静默忽略。",
);

const exclusionPairs = [];
const pairIds = new Set();
for (const plan of plans)
  for (const pair of plan.delivery.exclusionPairs) {
    assert(
      !pair.kind?.includes("original") && !pair.kind?.includes("resolved"),
      `${pair.exclusionGroupId}不是已确认有效互斥表。`,
    );
    assert(!pairIds.has(pair.exclusionGroupId), "互斥标识重复。");
    pairIds.add(pair.exclusionGroupId);
    const members = (pair.candidateIds ?? []).map((id: string) => {
      assert(mappedIds.has(id), `${id}候选身份不存在。`);
      return mappedIds.get(id);
    });
    for (const old of pair.oldQuestions ?? []) {
      assert.match(old.unitId, /^[a-z][a-z0-9_.-]{0,119}$/);
      const oldPath = await realpath(
        join(source, "units", old.unitId + ".json"),
      );
      assert(
        oldPath.startsWith((await realpath(join(source, "units"))) + sep),
        "旧单元路径越界。",
      );
      assert(
        baseline.registry.unitIds.includes(old.unitId),
        `${old.unitId}不是正式目录单元。`,
      );
      const oldUnit = unitSchema.parse(await read(oldPath));
      assert.equal(oldUnit.id, old.unitId);
      assert.equal(oldUnit.level, plan.level, "旧题年级不符。");
      const question = oldUnit.questions.find(
        (entry) => entry.id === old.localQuestionId,
      );
      assert(question, `${old.unitId}/${old.localQuestionId}不存在。`);
      members.push(bankIdentity(question));
    }
    assert.equal(members.length, 2, "互斥必须恰好两个成员。");
    assert.equal(new Set(members).size, 2, "互斥成员身份重复。");
    exclusionPairs.push({
      id: pair.exclusionGroupId,
      members,
      evidence: pair.evidence,
      reason: pair.reason,
    });
  }

// 所有必需输入先校验再创建目录；存在即拒绝，不覆盖原候选。
await mkdir(output);
assert((await realpath(output)).startsWith(build + sep));
for (const directory of ["units", "reviews", "audio", "images"])
  await cp(join(source, directory), join(output, directory), {
    recursive: true,
  });
for (const [id, bytes] of audioFiles)
  await writeFile(join(output, "audio", id + ".wav"), bytes);
const units = [];
for (const plan of plans)
  for (const story of plan.delivery.stories) {
    assert.equal(story.skippable, true);
    assert.equal(story.beats.length, 3);
    const questions = plan.questions.filter((question: any) =>
      question.id.startsWith(
        `p${plan.level.at(-1)}.astra.${story.questionGroup}`,
      ),
    );
    assert.equal(questions.length, 18);
    const rows = questions.map((question: any) =>
      plan.formal.questions.find((row: any) => row.id === question.id),
    );
    const unit = unitSchema.parse({
      id: `companion.${plan.level}.astra-${story.questionGroup}`,
      version: 1,
      schemaVersion: 1,
      scoringVersion: 1,
      roleKey: "companion",
      roleVersion: 1,
      level: plan.level,
      title: story.title,
      summary: story.title,
      scene: story.beats[0].translation,
      estimatedMinutes: 14,
      goalIds: [...new Set(questions.map((question: any) => question.goalId))],
      prerequisiteGoalIds: [],
      references: rows.flatMap((row: any) =>
        row.references.map((reference: any) => ({
          ...reference,
          unit: reference.unit ?? row.id,
        })),
      ),
      authorship: {
        kind: "authored",
        author: "Astra",
        reviewedBy: reviewer,
        reviewedAt: date,
        reviewNotes:
          "逐题作者稿机械映射，未程序造题；仅隔离候选，媒体听感、原生交互与发布验收仍需单独完成。",
      },
      beats: story.beats.map((beat: any, index: number) => {
        assert.equal(beat.afterQuestion, 0, "故事必须全部前置。");
        return { ...beat, id: `${story.id}.beat${index + 1}` };
      }),
      questions,
    });
    assert(!registry.unitIds.includes(unit.id), "候选单元身份已存在。");
    await write(join(output, "units", unit.id + ".json"), unit);
    await write(join(output, "reviews", unit.id + ".json"), {
      unitId: unit.id,
      contentHash: contentHash(unit),
      status: "approved",
      reviewKind: "author-self-review",
      reviewer,
      reviewedAt: date,
      roleFit: "普通同行者故事全部前置可跳过，题目上下文不依赖故事。",
      levelFit:
        "逐题采用formal记录的真实来源、页码及目标对齐，不代表全年课程覆盖。",
      limitations:
        "仅作者自审的隔离候选合同；媒体客观记录不替代人耳或原生播放，互斥需随正式修订生效。",
      questions: rows.map((row: any) => ({
        questionId: row.id,
        standaloneContext: row.standaloneContext,
        ambiguityReview: row.ambiguityReview,
        optionNotes: row.optionNotes,
        probes: row.probes,
      })),
    });
    registry.unitIds.push(unit.id);
    manifest.units.push({ unitId: unit.id, topic: "daily", roleKeys: [] });
    await write(
      join(output, `${plan.level}-${story.questionGroup}.public.json`),
      publicUnit(unit),
    );
    units.push({ id: unit.id, contentHash: contentHash(unit) });
  }
await write(join(output, "catalog.json"), registry);
await write(join(output, "bank.json"), manifest);
const checked = await loadCuratedCatalog(output);
const bank = await loadBankCatalog(output);
assert.equal(checked.units.length, baseline.units.length + expectedUnits);
assert.equal(
  bank.entries.length,
  baselineBank.entries.length + expectedQuestions,
);
assert.equal(
  checked.audioAssets.length,
  baseline.audioAssets.length + audioFiles.size,
);
for (const old of baseline.units)
  assert.equal(
    contentHash(checked.units.find((unit) => unit.id === old.id)!),
    contentHash(old),
  );
assert.equal(
  (await loadCuratedCatalog(source)).hash,
  baseline.hash,
  "正式目录已变化，请重新审阅输入快照。",
);
await write(join(output, "acceptance.json"), {
  status: "仅隔离候选，不可直接发布",
  levels,
  baselineHash: baseline.hash,
  candidateHash: checked.hash,
  bankHash: bank.hash,
  inputs,
  units,
  exclusionPairs,
  newQuestions: expectedQuestions,
  newAudio: audioFiles.size,
  pending: [
    "独立媒体听感与原生播放",
    "将有效互斥与正式版本修订一起写入",
    "线上完整组卷及挑战验收",
  ],
});
console.log(
  JSON.stringify({
    output,
    newUnits: units.length,
    newQuestions: expectedQuestions,
    newAudio: audioFiles.size,
    exclusionPairs: exclusionPairs.length,
    status: "隔离候选合同通过，未发布",
  }),
);
