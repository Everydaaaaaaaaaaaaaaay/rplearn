import { readFile } from "node:fs/promises";
import { beforeAll, describe, expect, it } from "vitest";
import type { LearningUnit } from "../../../src/modules/learning/content.js";
import { contentHash } from "../../../src/modules/learning/content-hash.js";
import {
  historyTitleForPresentation,
  historyTitleSourceHash,
} from "../../../src/modules/learning/history-presentation.js";
import { learningFixture } from "../../helpers/learning.js";

let originals: LearningUnit[];
beforeAll(async () => {
  const data = JSON.parse(
    await readFile(
      new URL("../../../config/learning/originals/catalog.json", import.meta.url),
      "utf8",
    ),
  ) as { units: { unit: LearningUnit }[] };
  originals = data.units.map((entry) => entry.unit);
});
function original(id: string) {
  const unit = originals.find((u) => u.id === id);
  if (!unit) throw new Error(`Missing unit ${id}`);
  return unit;
}

describe("Readable history titles", () => {
  it("uses concrete reviewed topics for the reported titles without altering snapshots", () => {
    for (const [id, expected] of [
      [
        "original.grade8-learner-tools-profile-matching",
        "阅读配对 · 为学习者选择英语学习工具",
      ],
      [
        "original.grade10-rehearsal-notes-reading",
        "阅读理解 · 用录像定位与改进戏剧排练笔记",
      ],
      [
        "original.primary1-sentences10-pictures-b",
        "听音选图 · 机器人问候、绘画与蓝气球",
      ],
      ["original.grade12-grammar-station-clock", "语法填空 · 志愿者修复旧车站时钟"],
    ] as const) {
      const unit = original(id);
      const before = contentHash(unit);
      expect(historyTitleForPresentation(unit)).toBe(expected);
      expect(contentHash(unit)).toBe(before);
    }
  });
  it("does not apply an old topic to changed content reusing the same unit ID", () => {
    const unit = original("original.grade8-learner-tools-profile-matching");
    const changed = { ...unit, title: "初二：船模实验与记录" };
    expect(historyTitleSourceHash(changed)).not.toBe(historyTitleSourceHash(unit));
    expect(historyTitleForPresentation(changed)).toBe("阅读理解 · 船模实验与记录");
  });
  it("removes level, engineering and quantity prefixes from unreviewed titles", () => {
    const unit = original("original.grade12-reading15-credit-dunes");
    const changed = { ...unit, title: "高三完整阅读四篇十五题：学分条件与沙地保护" };
    expect(historyTitleForPresentation(changed)).toBe("阅读理解 · 学分条件与沙地保护");
  });
  it("removes release-date scaffolding before formatting a new title", () => {
    const unit = original("original.grade8-learner-tools-profile-matching");
    expect(
      historyTitleForPresentation({
        ...unit,
        title: "高考题型原创 · 10·24新题 · A garden survey",
      }),
    ).toBe("阅读理解 · A garden survey");
  });
  it("uses the passage subject when a legacy title consists of a technical ID", () => {
    const unit = original("original.grade8-learner-tools-profile-matching");
    const changed = { ...unit, title: "阅读理解 · grade8-tools-reading-v2" };
    const title = historyTitleForPresentation(changed);
    expect(title).toContain("Four imaginary tools for English learners");
    expect(title).not.toContain("grade8");
  });
  it("also formats narrative practice without an originalGroup", () => {
    const unit = { ...learningFixture("test.history-title"), title: "为朋友购买围巾" };
    expect(historyTitleForPresentation(unit)).toBe("综合练习 · 为朋友购买围巾");
  });
});
