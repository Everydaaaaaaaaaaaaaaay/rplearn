import type * as NodeFs from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { contentHash } from "../../../src/modules/learning/content.js";
import {
  expansionGaokaoPractices,
  isExpansionUnit,
  loadExpansionCatalog,
} from "../../../src/modules/learning/expansion-catalog.js";
const files = vi.hoisted(() => new Map<string, string>());
vi.mock("node:fs", async (original) => {
  const actual = await original<typeof NodeFs>();
  return {
    ...actual,
    readFileSync: (
      path: Parameters<typeof NodeFs.readFileSync>[0],
      options: Parameters<typeof NodeFs.readFileSync>[1],
    ) => {
      const value = files.get(String(path));
      return value ?? actual.readFileSync(path, options);
    },
  };
});
afterEach(() => files.clear());
const base = new URL(
  "../../../config/learning/expansions/2026-10-28/",
  import.meta.url,
);
function installBatch(run = "2026-10-28", wrongNamespace = false) {
  const old = loadExpansionCatalog("b000");
  const entries = old.entries.map((e) => {
    const unit = structuredClone(e.unit);
    unit.id = unit.id.replace("20261024", wrongNamespace ? "20261024" : "20261028");
    if (unit.originalGroup)
      unit.originalGroup.sourceNotice =
        "2026-10-28 author self-review; not independent teacher review";
    return { ...e, unit, contentHash: contentHash(unit) };
  });
  files.set(
    String(new URL("index.json", base)),
    JSON.stringify({ version: 1, run, batches: ["b000"], gaokaoBatches: [] }),
  );
  files.set(
    String(new URL("b000.json", base)),
    JSON.stringify({
      version: 1,
      run,
      batch: "b000",
      createdAt: "2026-10-28",
      entries,
      sourceSHA256: "a".repeat(64),
      reviewSHA256: "b".repeat(64),
      reviewKind: "author-self-review",
      reviewer: "same author",
    }),
  );
  return entries;
}
describe("explicit expansion runs", () => {
  it("preserves the old default and admits a reviewed new-run namespace", () => {
    const old = loadExpansionCatalog("b000");
    const entries = installBatch();
    expect(loadExpansionCatalog("b000").hash).toBe(old.hash);
    expect(loadExpansionCatalog("b000", false, "2026-10-28").entries).toEqual(entries);
    const first = entries[0];
    if (!first) throw new Error("Missing fixture");
    expect(isExpansionUnit(first.unit)).toBe(true);
    expect(
      expansionGaokaoPractices().every((p) => p.unit.level.startsWith("senior")),
    ).toBe(true);
  });
  it("rejects unsupported runs, wrong manifest run and mixed namespaces", () => {
    expect(() => loadExpansionCatalog(undefined, false, "2026-10-29")).toThrow();
    installBatch("2026-10-24");
    expect(() => loadExpansionCatalog("b000", false, "2026-10-28")).toThrow();
    installBatch("2026-10-28", true);
    expect(() => loadExpansionCatalog("b000", false, "2026-10-28")).toThrow("identity");
  });
  it("CLI keeps legacy arguments and accepts only an explicit allowlisted run", () => {
    const cli = fileURLToPath(
      new URL("../../../src/cli/learning-expansion.ts", import.meta.url),
    );
    const invoke = (...args: string[]) =>
      JSON.parse(
        execFileSync(process.execPath, ["--import", "tsx", cli, ...args], {
          encoding: "utf8",
          env: { ...process.env, NODE_ENV: "test" },
        }),
      ) as { hash: string; run: string };
    expect(invoke("validate", "b000").hash).toBe(loadExpansionCatalog("b000").hash);
    expect(invoke("validate", "all", "--run", "2026-10-28").run).toBe("2026-10-28");
    expect(() => invoke("withdraw", "all", "--run", "2026-10-29")).toThrow();
  });
});
