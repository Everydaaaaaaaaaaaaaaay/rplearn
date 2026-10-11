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
  unitSchema,
} from "../Backend/src/modules/learning/content.ts";

// 只搬运逐题审定稿及真实媒体证据，不生成题文，不写正式目录或数据库。
const root = resolve(new URL("..", import.meta.url).pathname);
const source = join(root, "Backend/config/learning");
const authoring = join(source, "authoring");
const build = await realpath(join(root, "build"));
const parent = await realpath(
  resolve(process.argv[2] ?? join(build, "learning-strengthening-20261011")),
);
assert(!process.argv[3], "只接受一个候选输出父目录。");
assert(parent.startsWith(build + sep), "输出必须在本仓库build子目录。");
const output = join(parent, "candidate-catalog");
const read = async (path: string) => JSON.parse(await readFile(path, "utf8"));
const write = async (path: string, value: unknown) =>
  writeFile(path, JSON.stringify(value, null, 2) + "\n");
const sha = (data: Buffer) => createHash("sha256").update(data).digest("hex");
const inputs: Record<string, string> = {};
const input = async (name: string) => {
  const path = join(authoring, name);
  const data = await readFile(path);
  inputs[path.slice(root.length + 1)] = sha(data);
  return JSON.parse(data.toString());
};
// 生成器自身绑定制作证据；不能把先运行Python核验当成隐含前置条件。
const evidence = async (path: string) => {
  const data = await readFile(path);
  inputs[path.slice(root.length + 1)] = sha(data);
  return JSON.parse(data.toString());
};
const sameFile = async (path: string, folder: string) => {
  const actual = await realpath(path);
  assert.equal(
    resolve(actual, ".."),
    folder,
    "媒体必须位于对应等级的制作目录。",
  );
  return actual;
};
async function verifyClipEvidence(
  name: string,
  clip: any,
  planned: any,
  selected: any,
  proof: any,
) {
  const folder = await realpath(
    join(build, "learning-strengthening-20261011", name),
  );
  assert(planned && selected && proof, "缺少对应的实际制作记录。");
  assert.equal(clip.level, name);
  assert.equal(clip.scriptSha256, sha(Buffer.from(clip.transcript, "utf8")));
  assert.equal(planned.transcript, clip.transcript);
  assert.equal(selected.transcript, clip.transcript);
  assert.equal(proof.transcript, clip.transcript);
  assert.equal(selected.segment, planned.id);
  for (const key of ["minimumWpm", "maximumWpm", "targetWpm"])
    assert.equal(clip[key], planned[key], `审核语速字段与计划不一致：${key}`);
  assert(
    planned.minimumWpm > 0 &&
      planned.minimumWpm <= planned.targetWpm &&
      planned.targetWpm <= planned.maximumWpm,
  );
  const count = planned.segments.length;
  assert(count > 0);
  assert.equal(new Set(planned.segments.map((s: any) => s.id)).size, count);
  for (const rows of [clip.segments, selected.segments, proof.segments])
    assert.equal(rows.length, count, "审核、计划及实际选用话轮数量不一致。");
  const speakers = new Map<string, string>();
  let offset = 0;
  for (let index = 0; index < count; index++) {
    const review = clip.segments[index];
    const plan = planned.segments[index];
    const choice = selected.segments[index];
    const segment = proof.segments[index];
    for (const key of ["text", "speaker", "voice"]) {
      assert.equal(review[key], plan[key], `审核话轮与计划不一致：${key}`);
      assert.equal(
        review[key],
        choice[key],
        `审核话轮与选用记录不一致：${key}`,
      );
      assert.equal(review[key], segment[key], `审核话轮与清单不一致：${key}`);
    }
    assert.equal(choice.segment, plan.id);
    for (const key of ["take", "speed", "steps"]) {
      assert.equal(review[key], choice[key], `审核制作参数不一致：${key}`);
      assert.equal(review[key], segment[key], `清单制作参数不一致：${key}`);
    }
    assert(Math.abs(choice.speed - plan.rate) < 1e-6, "选用速率与计划不一致。");
    assert.equal(choice.expression, segment.expression);
    if (speakers.has(plan.speaker))
      assert.equal(speakers.get(plan.speaker), plan.voice);
    else speakers.set(plan.speaker, plan.voice);
    const pcmPath = await sameFile(segment.sourcePath, folder);
    assert.equal(pcmPath, await sameFile(join(folder, choice.pcmFile), folder));
    assert.equal(review.file, pcmPath.slice(root.length + 1));
    const pcm = await readFile(pcmPath);
    assert.equal(sha(pcm), review.sha256);
    assert.equal(review.sha256, segment.sha256);
    assert.equal(review.sha256, choice.sha256);
    assert.equal(pcm.length, choice.byteSize);
    const renderedPath = await sameFile(join(folder, choice.file), folder);
    assert.equal(sha(await readFile(renderedPath)), choice.sourceSha256);
    const rendering = await evidence(renderedPath.replace(/\.wav$/, ".json"));
    for (const key of [
      "segment",
      "text",
      "speaker",
      "voice",
      "take",
      "speed",
      "steps",
      "expression",
      "file",
    ])
      assert.equal(
        choice[key],
        rendering[key],
        `选用记录与原始渲染记录不一致：${key}`,
      );
    assert.equal(review.startSample, offset);
    assert.equal(review.startSample, segment.startSample);
    assert.equal(review.endSampleExclusive, segment.endSampleExclusive);
    assert.equal(
      review.endSampleExclusive - offset,
      Math.round(choice.durationSeconds * 24000),
    );
    offset = review.endSampleExclusive;
    assert.deepEqual(review.recognition, choice.recognition);
    assert.deepEqual(review.recognition, segment.candidateRecognition);
    if (index < count - 1) {
      assert.deepEqual(proof.gaps[index], {
        startSample: offset,
        endSampleExclusive: offset + 7200,
      });
      offset += 7200;
    }
  }
  assert.equal(proof.gaps.length, count - 1);
  assert.equal(proof.insertedGapSamples, count > 1 ? 7200 : 0);
  assert.equal(proof.sampleRate, 24000);
  assert.equal(selected.interSegmentSilenceMs, count > 1 ? 300 : 0);
  assert.deepEqual(
    selected.speakers,
    [...speakers].map(([id, voice]) => ({ id, voice })),
  );
  assert.equal(new Set(speakers.values()).size, speakers.size);
  assert.equal(clip.voice, [...speakers.values()].join("+"));
  assert.equal(clip.voice, selected.voice);
  const masterPath = await sameFile(selected.masterPath, folder);
  assert.equal(masterPath, await sameFile(proof.masterPath, folder));
  assert.equal(
    masterPath,
    await sameFile(join(folder, selected.masterFile), folder),
  );
  assert.equal(selected.masterFile, planned.id + ".wav");
  assert.equal(clip.file, masterPath.slice(root.length + 1));
  assert.equal(clip.sha256, selected.masterStats.sha256);
  assert.equal(clip.sha256, proof.masterSha256);
  assert.equal(clip.durationMs, Math.round(offset / 24));
  assert.equal(selected.gain, proof.gain);
  const spoken = planned.segments.map((s: any) => s.text).join(" ");
  assert.equal(selected.text, spoken);
  const wpm = (spoken.split(/\s+/).length / (offset / 24000)) * 60;
  assert(Math.abs(wpm - selected.wpm) < 1e-9);
  assert.equal(clip.wpm, Math.round(wpm * 100) / 100);
  assert.deepEqual(clip.masterRecognition, selected.masterRecognition);
}
const baseline = await loadCuratedCatalog(source);
const registry = structuredClone(baseline.registry);
const manifest = await read(join(source, "bank.json"));
const media = await input("strengthening-audio-review-2026-10-11.json");
const exclusions = await input("strengthening-exclusions-2026-10-11.json");
assert.equal(media.clips.length, 11);
assert.equal(new Set(media.clips.map((c) => c.questionId)).size, 11);
const mediaByID = new Map(media.clips.map((c) => [c.questionId, c]));
const reviewer = "Codex主代理逐题复核，Astra分级作者逐题自审";
const date = "2026-10-11";
const units = [];
const addedQuestions = new Map<string, string>();
await mkdir(output); // 不覆盖既有候选和验收证据。
for (const directory of ["units", "reviews", "audio", "images"])
  await cp(join(source, directory), join(output, directory), {
    recursive: true,
  });
for (const name of ["cet4", "cet6", "senior3"]) {
  const draft = await input(`${name}-strengthening-20261011.canonical.json`);
  const review = await input(
    `${name}-strengthening-formal-review-20261011.json`,
  );
  const goals = await input(`${name}-strengthening-goals-20261011.json`);
  const production = join(build, "learning-strengthening-20261011", name);
  const plan = await evidence(join(production, "production-plan.json"));
  assert.equal(
    plan.authoringSha256,
    inputs[
      `Backend/config/learning/authoring/${name}-strengthening-20261011.canonical.json`
    ],
  );
  const selection = await evidence(join(production, "selection.json"));
  const proofs = await evidence(join(production, "manifest.json"));
  const expectedAudio = draft.questions
    .filter((q: any) => q.audio)
    .map((q: any) => q.id)
    .sort();
  for (const rows of [plan.clips, selection, proofs])
    assert.deepEqual(
      rows.map((row: any) => row.questionId).sort(),
      expectedAudio,
      "制作记录必须完整且不重复。",
    );
  assert.equal(draft.questions.length, 18);
  assert.equal(review.unitId, draft.id);
  assert.equal(
    review.contentHash,
    contentHash(draft),
    "逐题审阅绑定的原稿已变化。",
  );
  assert.deepEqual(
    review.questions.map((q) => q.questionId).sort(),
    draft.questions.map((q) => q.id).sort(),
  );
  for (const goal of goals) {
    assert.equal(goal.level, draft.level);
    assert(
      !registry.goals.some((g) => g.id === goal.id),
      "新目标与正式目标重复，须人工合并。",
    );
    registry.goals.push(goal);
  }
  const unit = structuredClone(draft);
  for (const q of unit.questions) {
    const clip = mediaByID.get(q.id) as any;
    assert.equal(Boolean(clip), Boolean(q.audio), `${q.id} 媒体登记不完整`);
    if (clip) {
      await verifyClipEvidence(
        name,
        clip,
        plan.clips.find((row: any) => row.questionId === q.id),
        selection.find((row: any) => row.questionId === q.id),
        proofs.find((row: any) => row.questionId === q.id),
      );
      assert.equal(clip.transcript, q.audio.text);
      assert.equal(
        clip.segments.map((s) => s.text).join(" "),
        clip.transcript.replace(
          /(?:^| )([AB]): /g,
          (label, _speaker, offset) => (offset === 0 ? "" : " "),
        ),
        "完整话轮与原脚本不一致。",
      );
      const path = await realpath(join(root, clip.file));
      assert(
        path.startsWith(build + sep),
        "媒体必须来自本仓库build内的审定母版。",
      );
      const bytes = await readFile(path);
      assert.equal(sha(bytes), clip.sha256, `${q.id} 母版字节已变化`);
      assert.equal(bytes.length, clip.byteSize);
      assert(clip.segments.length > 0);
      for (const recognition of [
        clip.masterRecognition,
        ...clip.segments.map((s) => s.recognition),
      ]) {
        assert.deepEqual(Object.keys(recognition).sort(), [
          "base.en",
          "small.en",
        ]);
        for (const check of Object.values(recognition) as any[])
          assert.equal(check.exact, true);
      }
      assert(clip.wpm >= clip.minimumWpm && clip.wpm <= clip.maximumWpm);
      const id = "audio." + clip.sha256;
      const speakers = [
        ...new Map(
          clip.segments.map((s) => [
            s.speaker,
            { id: s.speaker, voice: s.voice },
          ]),
        ).values(),
      ] as { id: string; voice: string }[];
      const voice = speakers[0]!.voice;
      assert(!registry.audioAssets?.some((a) => a.id === id));
      registry.audioAssets ??= [];
      registry.audioAssets.push({
        id,
        sha256: clip.sha256,
        byteSize: bytes.length,
        durationMs: clip.durationMs,
        contentType: "audio/wav",
        transcript: clip.transcript,
        voice,
        ...(speakers.length > 1 ? { speakers } : {}),
        reviewedAt: date,
        reviewNotes: `Supertonic3离线合成完整台词；候选和母版均经base.en/small.en无提示转写核对。24kHz单声道PCM16，无削波，实际${clip.wpm}词/分；仅整话轮拼接、增益和重采样。完整证据见strengthening-audio-review-2026-10-11.json；不冒称独立人耳或教学效度验收。`,
      });
      await writeFile(join(output, "audio", id + ".wav"), bytes);
      q.audio = { assetId: id, text: clip.transcript, voice };
    }
    addedQuestions.set(q.id, bankIdentity(q));
  }
  unit.authorship.reviewedBy = reviewer;
  unit.authorship.reviewedAt = date;
  unit.authorship.reviewNotes =
    "Astra逐题亲写及主代理复核，题前完整故事与每题独立材料保留；本次仅补充真实音频及精确目标登记。受控练习不等同自由产出或整卷测评；独立人耳、原生连续作答及线上发布验收尚待完成。";
  const validated = unitSchema.parse(unit);
  await write(join(output, "units", unit.id + ".json"), validated);
  await write(join(output, "reviews", unit.id + ".json"), {
    unitId: unit.id,
    contentHash: contentHash(validated),
    status: "approved",
    reviewKind: "author-self-review",
    reviewer,
    reviewedAt: date,
    roleFit: "无同行角色职业或姓名绑定；完整开场先于问答，题目不依赖故事记忆。",
    levelFit:
      "依据已核读的本级资料与逐题难度边界审核；长材料、受控巩固与听记支架不冒充完整课程或整卷能力测量。",
    limitations:
      "纸面内容、客观媒体与判题样例审核不等于独立教师、听感及学习者效度验证；混卷互斥需与真实线上版本一起发布。",
    questions: review.questions,
  });
  registry.unitIds.push(unit.id);
  manifest.units.push({ unitId: unit.id, topic: "daily", roleKeys: [] });
  await write(
    join(output, name + ".public.json"),
    publicUnit(validated, "strengthening-preview"),
  );
  units.push({ id: unit.id, contentHash: contentHash(validated) });
}
// 旧目标的历史题数不充当永久上限；能力边界不扩展到新模态。
const listeningGoal = registry.goals.find(
  (g) => g.id === "senior3.listen-discourse-position",
);
assert(listeningGoal);
listeningGoal.boundaries =
  "校园及日常活动语境；短发言或对话自带全部信息，至少两个选项需依据录音才能区分。不考未明示的讽刺、重音含义或成人专业知识；不等同完整高中听力覆盖。旧单元五道及强化单元三道听选是已提供的教学切片，不是目标的永久题数上限。";
const exclusionPairs = exclusions.pairs.map((pair) => {
  assert.equal(pair.members.length, 2);
  return {
    id: pair.id,
    members: pair.members.map((member) => {
      if (member.newQuestionId) {
        assert(addedQuestions.has(member.newQuestionId));
        return addedQuestions.get(member.newQuestionId);
      }
      const old = baseline.units.find((u) => u.id === member.unitId);
      assert(old && old.version === member.unitVersion);
      const q = old.questions.find((q) => q.id === member.questionId);
      assert(q);
      const id = bankIdentity(q);
      assert.equal(id, member.bankId);
      return id;
    }),
  };
});
await write(join(output, "catalog.json"), registry);
await write(join(output, "bank.json"), manifest);
const catalog = await loadCuratedCatalog(output);
const bank = await loadBankCatalog(output);
assert.equal(catalog.units.length, baseline.units.length + 3);
assert.equal(catalog.audioAssets.length, baseline.audioAssets.length + 11);
for (const old of baseline.units)
  assert.equal(
    contentHash(catalog.units.find((u) => u.id === old.id)!),
    contentHash(old),
  );
assert.equal((await loadCuratedCatalog(source)).hash, baseline.hash);
await write(join(output, "acceptance.json"), {
  status: "隔离候选，未发布",
  baselineHash: baseline.hash,
  candidateHash: catalog.hash,
  bankHash: bank.hash,
  inputs,
  units,
  exclusionPairs,
  pending: [
    "真实线上修订合并及互斥原子发布",
    "原生连续作答与播放验收",
    "独立人耳听感审核",
  ],
  questions: bank.entries.length,
  blueprints: bank.blueprints.length,
  audioAssets: catalog.audioAssets.length,
});
console.log(
  JSON.stringify({
    output,
    newQuestions: 54,
    newUnits: 3,
    newAudio: 11,
    exclusions: exclusionPairs.length,
  }),
);
