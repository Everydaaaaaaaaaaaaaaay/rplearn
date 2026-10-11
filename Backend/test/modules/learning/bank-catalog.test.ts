import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { loadBankCatalog } from "../../../src/modules/learning/bank-catalog.js";
import { contentHash } from "../../../src/modules/learning/content.js";
import { learningFixture } from "../../helpers/learning.js";

vi.mock("../../../src/modules/learning/catalog.js", () => ({
  loadCuratedCatalog: vi.fn(() =>
    Promise.resolve({
      units: [learningFixture()],
      hash: "隔离课程摘要",
    }),
  ),
}));
function required<T>(value: T | undefined): T {
  if (value === undefined) throw new Error("测试夹具缺少必要内容。");
  return value;
}
const directories: string[] = [];
afterEach(async () => {
  await Promise.all(
    directories
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true })),
  );
});
async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "bank-manifest-"));
  directories.push(directory);
  const manifest = {
    version: 1,
    reviewNotes: "仅检查已审目录的工程映射，不用于教学出题，不能发布这些隔离测试夹具。",
    units: [{ unitId: learningFixture().id, topic: "daily", roleKeys: [] as string[] }],
  };
  const save = (value: unknown) =>
    writeFile(join(directory, "bank.json"), JSON.stringify(value));
  await save(manifest);
  return { directory, manifest, save };
}
describe("目录互斥元数据与事务修订", () => {
  it("旧目录哈希保持不变，新题互斥直接进入首版且不改题面", async () => {
    const { directory, manifest, save } = await fixture();
    const original = await loadBankCatalog(directory);
    expect(original.hash).toBe(
      contentHash({ entries: original.entries, blueprints: original.blueprints }),
    );
    const rule = required(manifest.units[0]);
    await save({
      ...manifest,
      units: [{ ...rule, questionExclusions: { "q.choice": ["test.answer-pair"] } }],
    });
    const next = await loadBankCatalog(directory);
    expect(next.entries[0]?.question.exclusionGroupIds).toEqual(["test.answer-pair"]);
    expect(next.entries[0]?.question.question).toEqual(
      original.entries[0]?.question.question,
    );
    expect(next.entries[1]).toEqual(original.entries[1]);
    expect(next.hash).not.toBe(original.hash);
  });
  it("修订预期哈希和完整内容均进入发布摘要，重复修订身份拒绝", async () => {
    const { directory, manifest, save } = await fixture();
    const original = await loadBankCatalog(directory);
    const revision = {
      expectedHash: "a".repeat(64),
      question: {
        ...required(original.entries[0]).question,
        version: 2,
        exclusionGroupIds: ["test.answer-pair"],
      },
    };
    await save({ ...manifest, revisions: [revision] });
    const next = await loadBankCatalog(directory);
    expect(next.revisions).toEqual([revision]);
    expect(next.entries).toEqual(original.entries);
    expect(next.hash).not.toBe(original.hash);
    await save({
      ...manifest,
      revisions: [{ ...revision, expectedHash: "b".repeat(64) }],
    });
    expect((await loadBankCatalog(directory)).hash).not.toBe(next.hash);
    await save({ ...manifest, revisions: [revision, revision] });
    await expect(loadBankCatalog(directory)).rejects.toThrow("重复修订身份");
  });
  it("拼错题号或重复互斥组不得悄悄忽略", async () => {
    const { directory, manifest, save } = await fixture();
    await save({
      ...manifest,
      units: [
        {
          ...manifest.units[0],
          questionExclusions: { "q.missing": ["test.answer-pair"] },
        },
      ],
    });
    await expect(loadBankCatalog(directory)).rejects.toThrow("不存在的题目");
    await save({
      ...manifest,
      units: [
        {
          ...manifest.units[0],
          questionExclusions: { "q.choice": ["test.answer-pair", "test.answer-pair"] },
        },
      ],
    });
    await expect(loadBankCatalog(directory)).rejects.toThrow("互斥组不能重复");
  });
});
