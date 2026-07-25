import { describe, expect, it } from "vitest";
import { checkReadiness } from "../../src/app/readiness.js";

describe("checkReadiness", () => {
  it("reports checks without exposing dependency errors", async () => {
    const result = await checkReadiness(
      [
        {
          check: () => Promise.resolve(),
          name: "available",
        },
        {
          check: () => Promise.reject(new Error("secret connection details")),
          name: "unavailable",
        },
      ],
      100,
    );

    expect(result).toEqual([
      { name: "available", status: "available" },
      { name: "unavailable", status: "unavailable" },
    ]);
    expect(JSON.stringify(result)).not.toContain("secret connection details");
  });

  it("bounds slow checks", async () => {
    const startedAt = Date.now();
    const result = await checkReadiness(
      [
        {
          check: () => new Promise(() => undefined),
          name: "slow",
        },
      ],
      20,
    );

    expect(result).toEqual([{ name: "slow", status: "unavailable" }]);
    expect(Date.now() - startedAt).toBeLessThan(200);
  });
});
