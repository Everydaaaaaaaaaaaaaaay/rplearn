import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { loadCuratedCatalog } from "../../../src/modules/learning/catalog.js";
import { contentHash, unitSchema } from "../../../src/modules/learning/content.js";

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
  it("三、四年级各包含三个角色各三个不同单元，全部逐题样例通过且结果可复现", async () => {
    const catalog = await loadCuratedCatalog(catalogPath);
    expect(catalog.units).toHaveLength(18);
    expect(catalog.summary).toEqual(
      ["primary3", "primary4"].flatMap((level) =>
        ["oliver", "ruby", "marcus"].map((roleKey) => ({
          roleKey,
          level,
          units: 3,
          questions: 18,
        })),
      ),
    );
    expect((await loadCuratedCatalog(catalogPath)).hash).toBe(catalog.hash);
  });

  it("已审核内容被改写时拒绝，即使 JSON 仍然合法", async () => {
    const directory = await copyCatalog();
    const path = join(directory, "units", "oliver.primary3.reading-circle.json");
    const unit = unitSchema.parse(JSON.parse(await readFile(path, "utf8")));
    unit.title = "未经审核的新标题";
    await writeFile(path, JSON.stringify(unit));
    await expect(loadCuratedCatalog(directory)).rejects.toThrow("需要重新逐题审核");
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
