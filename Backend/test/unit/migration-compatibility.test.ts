import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { assertCompatibleMigrationInventory } from "../../src/db/migration-compatibility.js";

const previous = { hash: "previous", created_at: "1791244800000" };
const addition = {
  hash: "34e472719cee3febb55ff7b3e8bac92c0cecf48d7b62649c9628761dc0b1032e",
  created_at: "1791676800000",
};
describe("明确登记的兼容迁移", () => {
  it("共享语法库新增表和独立任务可保留数据回退，内容变动则拒绝", () => {
    const hash = createHash("sha256")
      .update(
        readFileSync(
          new URL("../../migrations/0044_shared_grammar.sql", import.meta.url),
        ),
      )
      .digest("hex");
    const row = { hash, created_at: "1793404800000" };
    expect(() => assertCompatibleMigrationInventory(1, [previous, row])).not.toThrow();
    expect(() =>
      assertCompatibleMigrationInventory(1, [previous, { ...row, hash: "changed" }]),
    ).toThrow();
  });
  it("现有迁移完整时通过，缺少迁移则拒绝", () => {
    expect(() => assertCompatibleMigrationInventory(1, [previous])).not.toThrow();
    expect(() => assertCompatibleMigrationInventory(2, [previous])).toThrow();
  });
  it("旧程序只接受已核对内容与时间的独立新增表", () => {
    expect(() =>
      assertCompatibleMigrationInventory(1, [addition, previous]),
    ).not.toThrow();
    expect(() =>
      assertCompatibleMigrationInventory(1, [
        previous,
        { ...addition, hash: "changed" },
      ]),
    ).toThrow();
    expect(() =>
      assertCompatibleMigrationInventory(1, [
        previous,
        { ...addition, created_at: "1791676800001" },
      ]),
    ).toThrow();
  });
  it("回退版本接受已核对的练习退役迁移，摘要变动则拒绝", () => {
    const supersession = {
      hash: "abe601bf211103949624799adf146eb5df39f80479760c8956b86ef2c4ee8657",
      created_at: "1792713600000",
    };
    expect(() =>
      assertCompatibleMigrationInventory(2, [previous, addition, supersession]),
    ).not.toThrow();
    expect(() =>
      assertCompatibleMigrationInventory(2, [
        previous,
        addition,
        { ...supersession, hash: "unknown" },
      ]),
    ).toThrow();
  });
  it("多选学习目标迁移仅接受已核对的摘要并支持回退", () => {
    const hash = "c67cd02ad3db4eb5d84e21176a2c3066daf080bf00e122db2af346c30fd26743";
    const goals = { hash, created_at: "1793318400000" };
    expect(() =>
      assertCompatibleMigrationInventory(1, [previous, goals]),
    ).not.toThrow();
    expect(() =>
      assertCompatibleMigrationInventory(1, [previous, { ...goals, hash: "changed" }]),
    ).toThrow();
  });
  it("未知额外迁移或重复迁移不能因总数更多而通过", () => {
    expect(() =>
      assertCompatibleMigrationInventory(1, [
        previous,
        addition,
        { hash: "unknown", created_at: "1791676800002" },
      ]),
    ).toThrow();
    expect(() =>
      assertCompatibleMigrationInventory(1, [previous, addition, addition]),
    ).toThrow();
  });
});
