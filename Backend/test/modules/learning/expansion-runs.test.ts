import type * as NodeFs from "node:fs";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { contentHash } from "../../../src/modules/learning/content.js";
import {
  expansionGaokaoPractices,
  isExpansionUnit,
  loadExpansionCatalog,
  loadExpansionImages,
  loadExpansionAudio,
  verifyExpansionAudio,
} from "../../../src/modules/learning/expansion-catalog.js";
import type { LearningAudioAsset } from "../../../src/modules/learning/audio.js";
import type { LearningImageAsset } from "../../../src/modules/learning/images.js";
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
  function installRevision() {
    const entries = installBatch();
    const first = entries[0];
    if (!first) throw new Error("Missing previous unit");
    const original = JSON.parse(
      files.get(String(new URL("b000.json", base))) ?? "null",
    ) as Record<string, unknown>;
    const unit = {
      ...structuredClone(first.unit),
      version: 2,
      title: first.unit.title + "（审核修订）",
    };
    const revised = {
      ...first,
      unit,
      contentHash: contentHash(unit),
      revises: {
        version: 1,
        contentHash: first.contentHash,
        sourceSHA256: "a".repeat(64),
      },
    };
    const next = {
      ...original,
      batch: "b001",
      sourceSHA256: "c".repeat(64),
      entries: [revised],
    };
    files.set(
      String(new URL("index.json", base)),
      JSON.stringify({
        version: 1,
        run: "2026-10-28",
        batches: ["b000", "b001"],
        gaokaoBatches: [],
      }),
    );
    files.set(String(new URL("b001.json", base)), JSON.stringify(next));
    return { entries, original, revised, next };
  }
  it("selects the highest reviewed revision once while retaining untouched siblings and old batch hashes", () => {
    const { entries, original, revised } = installRevision();
    const catalog = loadExpansionCatalog(undefined, false, "2026-10-28");
    expect(catalog.entries).toHaveLength(entries.length);
    expect(catalog.units.find((u) => u.id === revised.unit.id)).toEqual(revised.unit);
    expect(catalog.entries.filter((e) => e.unit.id !== revised.unit.id)).toEqual(
      entries.filter((e) => e.unit.id !== revised.unit.id),
    );
    const old = loadExpansionCatalog("b000", false, "2026-10-28");
    expect(old.hash).toBe(contentHash([original]));
    expect(old.entries).toEqual(entries);
    expect(loadExpansionCatalog("b001", false, "2026-10-28").entries).toEqual([
      revised,
    ]);
  });
  it.each(["missing", "contentHash", "sourceSHA256", "version"])(
    "rejects a revision with an invalid %s binding",
    (field) => {
      const { revised, next } = installRevision();
      if (field === "missing") Reflect.deleteProperty(revised, "revises");
      else if (field === "version") revised.revises.version = 0;
      else revised.revises[field as "contentHash" | "sourceSHA256"] = "0".repeat(64);
      files.set(String(new URL("b001.json", base)), JSON.stringify(next));
      expect(() => loadExpansionCatalog(undefined, false, "2026-10-28")).toThrow();
    },
  );
  it("rejects repeated same-version identities even when their hashes agree", () => {
    const { revised, next } = installRevision();
    files.set(
      String(new URL("b002.json", base)),
      JSON.stringify({ ...next, batch: "b002", entries: [revised] }),
    );
    files.set(
      String(new URL("index.json", base)),
      JSON.stringify({
        version: 1,
        run: "2026-10-28",
        batches: ["b000", "b001", "b002"],
        gaokaoBatches: [],
      }),
    );
    expect(() => loadExpansionCatalog(undefined, false, "2026-10-28")).toThrow();
  });
  it("requires the frozen predecessor to remain indexed even for a selected correction batch", () => {
    installRevision();
    files.set(
      String(new URL("index.json", base)),
      JSON.stringify({
        version: 1,
        run: "2026-10-28",
        batches: ["b001"],
        gaokaoBatches: [],
      }),
    );
    expect(() => loadExpansionCatalog("b001", false, "2026-10-28")).toThrow(
      "previous unit/source",
    );
  });
  it("does not enable forward revisions in the frozen old run", () => {
    const old = loadExpansionCatalog("b000");
    const first = old.entries[0];
    if (!first) throw new Error("Missing old-run fixture");
    first.unit.version = 2;
    first.contentHash = contentHash(first.unit);
    const oldBase = new URL(
      "../../../config/learning/expansions/2026-10-24/",
      import.meta.url,
    );
    files.set(
      String(new URL("b000.json", oldBase)),
      JSON.stringify({ ...old.manifests[0], entries: old.entries }),
    );
    expect(() => loadExpansionCatalog("b000")).toThrow("identity/digest");
  });
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
  it("new-run listening requires explicit transcript/voice-bound audio metadata", async () => {
    const entries = installBatch();
    const first = entries[0],
      question = first?.unit.questions[0];
    if (!first || question?.type !== "choice") throw new Error("Missing fixture");
    const audio = (
      JSON.parse(
        readFileSync(
          new URL("../../../config/learning/originals/catalog.json", import.meta.url),
          "utf8",
        ),
      ) as { audioAssets: LearningAudioAsset[] }
    ).audioAssets[0];
    if (!audio) throw new Error("Missing owned audio fixture");
    first.unit.questions[0] = {
      ...question,
      type: "listeningChoice",
      audio: { assetId: audio.id, text: audio.transcript, voice: audio.voice },
    };
    first.contentHash = contentHash(first.unit);
    const manifest = {
      version: 1,
      run: "2026-10-28",
      batch: "b000",
      createdAt: "2026-10-28",
      entries,
      sourceSHA256: "a".repeat(64),
      reviewSHA256: "b".repeat(64),
      reviewKind: "author-self-review",
      reviewer: "same author",
    };
    files.set(String(new URL("b000.json", base)), JSON.stringify(manifest));
    expect(() => loadExpansionCatalog("b000", false, "2026-10-28")).toThrow("audio");
    files.set(
      String(new URL("b000.json", base)),
      JSON.stringify({ ...manifest, audioAssets: [audio] }),
    );
    expect(loadExpansionCatalog("b000", false, "2026-10-28").units).toHaveLength(
      entries.length,
    );
    await verifyExpansionAudio("b000", "2026-10-28");
    expect(await loadExpansionAudio("b000", "2026-10-28")).toHaveLength(0);
    files.set(
      String(new URL("b000.json", base)),
      JSON.stringify({
        ...manifest,
        audioAssets: [audio],
        newAudioAssetIds: [audio.id],
      }),
    );
    const selected = await loadExpansionAudio("b000", "2026-10-28");
    expect(selected.map((asset) => asset.metadata.id)).toEqual([audio.id]);
    files.set(
      String(new URL("b000.json", base)),
      JSON.stringify({
        ...manifest,
        audioAssets: [{ ...audio, transcript: "Different clip" }],
      }),
    );
    expect(() => loadExpansionCatalog("b000", false, "2026-10-28")).toThrow("audio");
  });
  it("new-run pictures need declared metadata and exact verified dimensions", async () => {
    const entries = installBatch(),
      first = entries[0],
      question = first?.unit.questions[0];
    if (!first || !question) throw new Error("Missing question fixture");
    const image = (
      JSON.parse(
        readFileSync(
          new URL("../../../config/learning/originals/catalog.json", import.meta.url),
          "utf8",
        ),
      ) as { imageAssets: LearningImageAsset[] }
    ).imageAssets[0];
    if (!image) throw new Error("Missing owned image fixture");
    question.materialImages = [
      { assetId: image.id, label: "Owned complete picture fixture" },
    ];
    first.contentHash = contentHash(first.unit);
    const manifest = {
      version: 1,
      run: "2026-10-28",
      batch: "b000",
      createdAt: "2026-10-28",
      entries,
      sourceSHA256: "a".repeat(64),
      reviewSHA256: "b".repeat(64),
      reviewKind: "author-self-review",
      reviewer: "same author",
    };
    files.set(String(new URL("b000.json", base)), JSON.stringify(manifest));
    expect(() => loadExpansionCatalog("b000", false, "2026-10-28")).toThrow("image");
    files.set(
      String(new URL("b000.json", base)),
      JSON.stringify({ ...manifest, imageAssets: [image] }),
    );
    expect(await loadExpansionImages("b000", "2026-10-28")).toHaveLength(1);
    files.set(
      String(new URL("b000.json", base)),
      JSON.stringify({
        ...manifest,
        imageAssets: [{ ...image, width: image.width + 1 }],
      }),
    );
    await expect(loadExpansionImages("b000", "2026-10-28")).rejects.toThrow();
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
    expect(invoke("validate", "b000", "--run", "2026-10-24").run).toBe("2026-10-24");
    expect(() => invoke("validate", "b999", "--run", "2026-10-28")).toThrow(
      "Unknown or duplicate expansion batch",
    );
    expect(() => invoke("withdraw", "all", "--run", "2026-10-29")).toThrow();
  });
});
