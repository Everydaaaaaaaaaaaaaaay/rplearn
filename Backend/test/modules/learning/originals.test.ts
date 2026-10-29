import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadOriginalCatalog } from "../../../src/modules/learning/original-catalog.js";
import { contentHash } from "../../../src/modules/learning/content.js";
import { describe, it, expect } from "vitest";
import { unitSchema, publicUnit } from "../../../src/modules/learning/content.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import { learningFixture } from "../../helpers/learning.js";

function required<T>(value: T | undefined): T {
  if (value === undefined) throw new Error("Missing test input");
  return value;
}
function original() {
  const fixture = learningFixture("original.test-group");
  const base = {
    goalId: "test.greetings",
    instruction: "填写各空。",
    prompt: "第一个空",
    explanation: "测试解析",
    hint: "查看全文",
    difficultyReason: "仅测试",
  };
  return unitSchema.parse({
    ...fixture,
    roleKey: "companion",
    beats: [],
    originalGroup: {
      id: "test-group",
      family: "passage_form",
      label: "语篇填空",
      candidateSHA256: "a".repeat(64),
      authorCheckSHA256: "b".repeat(64),
      sourceGroupIds: ["test.form"],
      sourceNotice: "测试形式，不是公开题库。",
      material: "Complete passage with all ten gaps and a final sentence.",
    },
    questions: Array.from({ length: 10 }, (_, i) => ({
      ...base,
      id: `q${String(i)}`,
      type: "completion",
      acceptedAnswers: ["learned", "learnt"],
      normalization: { ignoreCase: true, ignoreTerminalPunctuation: false },
      marking: {
        protocol: "english_phrase_v1",
        rejectedAnswers: ["learn"],
        maxWords: 1,
        unlisted: "review",
      },
    })),
  });
}

describe("完整原创题组发布与判分合同", () => {
  it("保留十个回应和全文，同时不下发作者答案、脚本或审核资料", () => {
    const unit = original();
    const result = publicUnit(unit);
    expect(result.questions).toHaveLength(10);
    expect(
      result.questions.every((q) => q.material === unit.originalGroup?.material),
    ).toBe(true);
    expect(result.beats).toEqual([]);
    expect(JSON.stringify(result)).not.toContain("acceptedAnswers");
    expect(JSON.stringify(result)).not.toContain("candidateSHA256");
    expect(JSON.stringify(result)).not.toContain("rejectedAnswers");
  });
  it("合法英美变体同等接受；其他作答按参考答案判错并返回解析", () => {
    const q = required(original().questions[0]);
    for (const text of ["learned", " LEARNT "])
      expect(gradeAnswer(q, { kind: "text", text }).outcome).toBe("correct");
    expect(gradeAnswer(q, { kind: "text", text: "learn" }).outcome).toBe("incorrect");
    expect(gradeAnswer(q, { kind: "text", text: "learning" }).outcome).toBe(
      "incorrect",
    );
    expect(gradeAnswer(q, { kind: "text", text: "have learned" }).outcome).toBe(
      "incorrect",
    );
  });
  it("非原创单元仍需要开场；完整题组不得夹带虚构剧情", () => {
    const unit = original();
    expect(unitSchema.safeParse({ ...unit, originalGroup: undefined }).success).toBe(
      false,
    );
    expect(
      unitSchema.safeParse({ ...unit, beats: learningFixture().beats }).success,
    ).toBe(false);
  });
  it("只重算单元哈希不能掩盖学生材料或作者答案被改写", async () => {
    const folder = await mkdtemp(join(tmpdir(), "original-binding-"));
    try {
      await mkdir(join(folder, "originals"));
      const unit = original();
      const student = {
        material: required(unit.originalGroup).material,
        questions: unit.questions.map((q) => ({
          id: q.id,
          type: q.type,
          prompt: q.prompt,
          instruction: q.instruction,
          options: null,
          audio: null,
          images: [],
        })),
      };
      const entry = {
        unit,
        contentHash: contentHash(unit),
        authoredPayloadSHA256: "c".repeat(64),
        studentInputHash: contentHash(student),
        probes: unit.questions.flatMap((q) => [
          {
            questionId: q.id,
            answer: { kind: "text", text: "learned" },
            outcome: "correct",
          },
          {
            questionId: q.id,
            answer: { kind: "text", text: "learn" },
            outcome: "incorrect",
          },
        ]),
      };
      const manifest = {
        version: 1,
        researchPlanSHA256: "a".repeat(64),
        scopeSHA256: "b".repeat(64),
        reviewBoundary:
          "frozen author checks; independent teacher and student validation not claimed",
        units: [entry],
        audioAssets: [],
        imageAssets: [],
        batches: [{ id: "b000", unitIds: [unit.id] }],
      };
      const path = join(folder, "originals/catalog.json");
      await writeFile(path, JSON.stringify(manifest));
      expect((await loadOriginalCatalog(folder)).units).toHaveLength(1);
      required(unit.originalGroup).material = "Changed passage";
      entry.contentHash = contentHash(unit);
      await writeFile(path, JSON.stringify(manifest));
      await expect(loadOriginalCatalog(folder)).rejects.toThrow(
        "完整学生输入与冻结审核不符",
      );
    } finally {
      await rm(folder, { recursive: true, force: true });
    }
  });
});
