import { describe, expect, it, vi } from "vitest";
import {
  assertAllowedModelsAvailable,
  assertRuntimeDatabaseAuthority,
  ProductionReadinessError,
  runProductionReadinessChecks,
  type RuntimeDatabaseAuthority,
} from "../../src/modules/operations/production-readiness.js";

const leastPrivilegeAuthority: RuntimeDatabaseAuthority = {
  canCreateDatabase: false,
  canCreateSchema: false,
  canUseAppSchema: true,
  hasTableDml: true,
  roleBypassesRls: false,
  roleCanCreateDatabase: false,
  roleCanCreateRole: false,
  roleCanLogin: true,
  roleCanReplicate: false,
  roleIsSuperuser: false,
  tableCount: 30,
};

describe("production readiness", () => {
  it("returns a deterministic, detail-free report while running every check", async () => {
    const secondCheck = vi.fn(() =>
      Promise.reject(new Error("postgres://secret@database.internal/app")),
    );

    const report = await runProductionReadinessChecks(
      [
        {
          check: () => Promise.resolve(),
          failureCode: "FIRST_FAILED",
          name: "first",
        },
        {
          check: secondCheck,
          failureCode: "SECOND_FAILED",
          name: "second",
        },
      ],
      100,
      () => new Date("2026-07-26T00:00:00.000Z"),
    );

    expect(report).toMatchObject({
      checkedAt: "2026-07-26T00:00:00.000Z",
      checks: [
        { name: "first", status: "passed" },
        { code: "SECOND_FAILED", name: "second", status: "failed" },
      ],
      passed: false,
    });
    expect(JSON.stringify(report)).not.toContain("database.internal");
    expect(secondCheck).toHaveBeenCalledOnce();
  });

  it("uses a stable timeout code", async () => {
    const report = await runProductionReadinessChecks(
      [
        {
          check: () => new Promise(() => undefined),
          failureCode: "DEPENDENCY_FAILED",
          name: "dependency",
        },
      ],
      5,
    );

    expect(report.checks).toMatchObject([
      { code: "CHECK_TIMEOUT", name: "dependency", status: "failed" },
    ]);
  });

  it("accepts a least-privilege runtime database role", () => {
    expect(() => assertRuntimeDatabaseAuthority(leastPrivilegeAuthority)).not.toThrow();
  });

  it.each([
    "roleIsSuperuser",
    "roleCanCreateDatabase",
    "roleCanCreateRole",
    "roleCanReplicate",
    "roleBypassesRls",
    "canCreateDatabase",
    "canCreateSchema",
  ] as const)("rejects elevated database authority: %s", (field) => {
    expect(() =>
      assertRuntimeDatabaseAuthority({
        ...leastPrivilegeAuthority,
        [field]: true,
      }),
    ).toThrow(expect.objectContaining({ code: "DATABASE_ROLE_OVER_PRIVILEGED" }));
  });

  it("rejects missing runtime data privileges", () => {
    expect(() =>
      assertRuntimeDatabaseAuthority({
        ...leastPrivilegeAuthority,
        hasTableDml: false,
      }),
    ).toThrow(expect.objectContaining({ code: "DATABASE_ROLE_UNDER_PRIVILEGED" }));
  });

  it("requires every allowlisted AI model to exist upstream", () => {
    expect(() =>
      assertAllowedModelsAvailable(
        ["deepseek-v4-flash", "deepseek-v4-pro"],
        ["deepseek-v4-flash"],
      ),
    ).toThrow(new ProductionReadinessError("AI_MODEL_UNAVAILABLE"));
  });
});
