import { describe, expect, it } from "vitest";
import { assertCompatibleMigrationInventory } from "../../src/db/migration-compatibility.js";

const previous = { hash: "previous", created_at: "1791244800000" };
const addition = {
  hash: "34e472719cee3febb55ff7b3e8bac92c0cecf48d7b62649c9628761dc0b1032e",
  created_at: "1791676800000",
};
describe("明确登记的兼容迁移", () => {
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
