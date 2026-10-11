import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { loadCuratedCatalog } from "../../../src/modules/learning/catalog.js";
import {
  contentHash,
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";

import { uploadLearningAudio } from "../../../src/modules/learning/audio.js";
import { learningImageFixture } from "../../helpers/learning-images.js";

const catalogPath = fileURLToPath(
  new URL("../../../config/learning/", import.meta.url),
);
const directories: string[] = [];
async function copyCatalog() {
  const directory = await mkdtemp(join(tmpdir(), "lingotrip-catalog-"));
  directories.push(directory);
  await cp(catalogPath, directory, { recursive: true });
  return directory;
}
afterEach(async () => {
  await Promise.all(
    directories.splice(0).map((path) => rm(path, { recursive: true, force: true })),
  );
});

describe("原创课程发布门槛", () => {
  it("学校年级与三个成人档独立统计，逐题样例通过且结果可复现", async () => {
    const catalog = await loadCuratedCatalog(catalogPath);
    expect(catalog.units).toHaveLength(99);
    expect(catalog.summary).toEqual([
      ...["primary3", "primary4", "junior3", "senior2", "primary1"].flatMap((level) =>
        ["oliver", "ruby", "marcus"].map((roleKey) => ({
          roleKey,
          level,
          units: 3,
          questions: 18,
        })),
      ),
      ...[
        "primary5",
        "primary6",
        "junior1",
        "junior2",
        "senior1",
        "senior3",
        "primary2",
      ].flatMap((level) =>
        ["oliver", "ruby", "marcus"].map((roleKey) => ({
          roleKey,
          level,
          units: 2,
          questions: 12,
        })),
      ),
      { roleKey: "companion", level: "undergraduate", units: 2, questions: 36 },
      { roleKey: "companion", level: "postgraduate", units: 2, questions: 36 },
      { roleKey: "companion", level: "advanced", units: 2, questions: 36 },
      ...["senior1", "senior2", "senior3"].map((level) => ({
        roleKey: "companion",
        level,
        units: 2,
        questions: 36,
      })),
    ]);
    expect((await loadCuratedCatalog(catalogPath)).hash).toBe(catalog.hash);
  });

  it("逐个校验后不保留媒体字节，上传前发现文件替换即拒绝", async () => {
    const directory = await copyCatalog();
    const catalog = await loadCuratedCatalog(directory);
    expect(catalog.audioAssets.every((a) => !("bytes" in a))).toBe(true);
    expect(catalog.imageAssets.every((a) => !("bytes" in a))).toBe(true);
    const asset = catalog.audioAssets[0];
    if (!asset) throw new Error("缺少听力夹具。");
    const bytes = await asset.loadBytes();
    bytes[bytes.length - 1] = (bytes[bytes.length - 1] ?? 0) ^ 1;
    await writeFile(join(directory, "audio", `${asset.metadata.id}.wav`), bytes);
    const store = {
      headObject: vi.fn(),
      createUploadUrl: vi.fn(),
      createDownloadUrl: vi.fn(),
    };
    await expect(uploadLearningAudio([asset], store)).rejects.toThrow("不一致");
    expect(store.headObject).not.toHaveBeenCalled();
  });

  it("已审核内容被改写时拒绝，即使 JSON 仍然合法", async () => {
    const directory = await copyCatalog();
    const path = join(directory, "units", "oliver.primary3.reading-circle.json");
    const unit = unitSchema.parse(JSON.parse(await readFile(path, "utf8")));
    unit.title = "未经审核的新标题";
    await writeFile(path, JSON.stringify(unit));
    await expect(loadCuratedCatalog(directory)).rejects.toThrow("需要重新逐题审核");
  });

  it("同一听力操作语允许不同录音，重复原文仍拒绝", async () => {
    const directory = await copyCatalog();
    const id = "oliver.primary1.bookmark-colours";
    const unitPath = join(directory, "units", `${id}.json`);
    const reviewPath = join(directory, "reviews", `${id}.json`);
    const unit = unitSchema.parse(JSON.parse(await readFile(unitPath, "utf8")));
    const [first, second] = unit.questions.filter((q) => q.type === "listeningChoice");
    if (!first || !second || first.audio.text === second.audio.text)
      throw new Error("缺少两段不同听力夹具。");
    const review = JSON.parse(await readFile(reviewPath, "utf8")) as {
      contentHash: string;
    };
    async function save() {
      review.contentHash = contentHash(unit);
      await writeFile(unitPath, JSON.stringify(unit));
      await writeFile(reviewPath, JSON.stringify(review));
    }
    second.prompt = first.prompt;
    await save();
    await expect(loadCuratedCatalog(directory)).resolves.toBeDefined();
    second.audio = first.audio;
    await save();
    await expect(loadCuratedCatalog(directory)).rejects.toThrow("与题库中已有题干重复");
  });

  it("多空题相同操作语按正文与候选区分，改编号不绕过重复检查", async () => {
    const directory = await copyCatalog();
    const id = "oliver.primary3.reading-circle";
    const unitPath = join(directory, "units", `${id}.json`);
    const reviewPath = join(directory, "reviews", `${id}.json`);
    const unit = unitSchema.parse(JSON.parse(await readFile(unitPath, "utf8")));
    const review = JSON.parse(await readFile(reviewPath, "utf8")) as {
      contentHash: string;
      questions: { questionId: string; optionNotes: unknown; probes: unknown }[];
    };
    // 仅工程夹具，验证材料身份；不进入正式教学内容。
    function cloze(index: number, passage: string, renamed = false): LearningQuestion {
      const old = unit.questions[index];
      if (!old) throw new Error("缺少待转换的工程题目。");
      const first = renamed ? "x" : "one";
      const second = renamed ? "y" : "two";
      const a = renamed ? "new-a" : "a";
      const b = renamed ? "new-b" : "b";
      const c = renamed ? "new-c" : "c";
      const accepted = [
        { slotId: first, tokenId: a },
        { slotId: second, tokenId: b },
      ];
      const checked = review.questions.find((q) => q.questionId === old.id);
      if (!checked) throw new Error("缺少对应的工程审核记录。");
      checked.optionNotes = {};
      checked.probes = [
        { answer: { kind: "cloze", fills: accepted }, correct: true },
        {
          answer: {
            kind: "cloze",
            fills: [
              { slotId: first, tokenId: b },
              { slotId: second, tokenId: a },
            ],
          },
          correct: false,
        },
      ];
      return {
        id: old.id,
        goalId: old.goalId,
        type: "cloze",
        instruction: "填写两个工程插槽。",
        prompt: "每空选一个词块，余项不用。",
        explanation: "只用于检验目录重复材料拦截。",
        hint: "工程隔离测试材料。",
        difficultyReason: "不是可发布的教学题目。",
        passage,
        tokens: [
          { id: a, text: "first" },
          { id: b, text: "second" },
          { id: c, text: "other" },
        ],
        acceptedFills: [accepted],
      };
    }
    async function save() {
      review.contentHash = contentHash(unit);
      await writeFile(unitPath, JSON.stringify(unit));
      await writeFile(reviewPath, JSON.stringify(review));
    }
    unit.questions[0] = cloze(0, "The first record has {one} and {two}.");
    unit.questions[1] = cloze(1, "Another independent record uses {one} before {two}.");
    await save();
    await expect(loadCuratedCatalog(directory)).resolves.toBeDefined();
    unit.questions[1] = cloze(1, "The first record has {x} and {y}.", true);
    await save();
    await expect(loadCuratedCatalog(directory)).rejects.toThrow("与题库中已有题干重复");
  });

  it("不能只重新计算哈希掩盖错误的判题内容", async () => {
    const directory = await copyCatalog();
    const id = "oliver.primary3.reading-circle";
    const path = join(directory, "units", `${id}.json`);
    const reviewPath = join(directory, "reviews", `${id}.json`);
    const unit = unitSchema.parse(JSON.parse(await readFile(path, "utf8")));
    const question = unit.questions[0];
    if (question?.type !== "choice" && question?.type !== "listeningChoice")
      throw new Error("缺少预期选择题。");
    question.answer = "a";
    const review = JSON.parse(await readFile(reviewPath, "utf8")) as Record<
      string,
      unknown
    >;
    review.contentHash = contentHash(unit);
    await writeFile(path, JSON.stringify(unit));
    await writeFile(reviewPath, JSON.stringify(review));
    await expect(loadCuratedCatalog(directory)).rejects.toThrow(
      "判题结果不符合审核样例",
    );
  });

  it("图片题必须绑定已校验文件和逐题图片审核", async () => {
    const directory = await copyCatalog();
    const id = "oliver.primary3.reading-circle";
    const unitPath = join(directory, "units", `${id}.json`);
    const reviewPath = join(directory, "reviews", `${id}.json`);
    const registryPath = join(directory, "catalog.json");
    const unit = unitSchema.parse(JSON.parse(await readFile(unitPath, "utf8")));
    const question = unit.questions.find((q) => q.type === "choice");
    if (question?.type !== "choice" || !question.options[0])
      throw new Error("缺少测试题。");
    const asset = learningImageFixture();
    question.options[0].imageAssetId = asset.metadata.id;
    const review = JSON.parse(await readFile(reviewPath, "utf8")) as {
      contentHash: string;
      questions: { questionId: string; imageReview?: string }[];
    };
    review.contentHash = contentHash(unit);
    await writeFile(unitPath, JSON.stringify(unit));
    await writeFile(reviewPath, JSON.stringify(review));
    await expect(loadCuratedCatalog(directory)).rejects.toThrow("未审核的图片");
    const registry = JSON.parse(await readFile(registryPath, "utf8")) as Record<
      string,
      unknown
    >;
    const existingImages = registry.imageAssets as unknown[];
    registry.imageAssets = [...existingImages, asset.metadata];
    await writeFile(registryPath, JSON.stringify(registry));
    await mkdir(join(directory, "images"), { recursive: true });
    await writeFile(join(directory, "images", `${asset.metadata.id}.png`), asset.bytes);
    await expect(loadCuratedCatalog(directory)).rejects.toThrow("缺少图片语义");
    const checked = review.questions.find((q) => q.questionId === question.id);
    if (!checked) throw new Error("缺少审核记录。");
    checked.imageReview =
      "这是工程样本，仅验证文件与审核记录绑定，不是教学图片质量结论。";
    await writeFile(reviewPath, JSON.stringify(review));
    expect((await loadCuratedCatalog(directory)).imageAssets).toHaveLength(
      existingImages.length + 1,
    );
  });

  it("来源失联于登记表时不能发布", async () => {
    const directory = await copyCatalog();
    const path = join(directory, "catalog.json");
    const registry = JSON.parse(await readFile(path, "utf8")) as {
      sources: { id: string }[];
    };
    registry.sources = registry.sources.filter(
      (source) => source.id !== "jingtong.primary3.upper.2024",
    );
    await writeFile(path, JSON.stringify(registry));
    await expect(loadCuratedCatalog(directory)).rejects.toThrow("未登记的教材来源");
  });
});
