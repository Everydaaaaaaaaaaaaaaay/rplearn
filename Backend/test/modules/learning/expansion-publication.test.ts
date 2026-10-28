import { describe, expect, it, vi } from "vitest";
import { loadExpansionCatalog } from "../../../src/modules/learning/expansion-catalog.js";
import { contentHash } from "../../../src/modules/learning/content.js";
import { expansionPublication } from "../../../src/modules/learning/expansion-publication.js";
import { seniorPracticeCatalog } from "../../../src/modules/learning/senior-practice-catalog.js";
import * as seniorCatalog from "../../../src/modules/learning/senior-practice-catalog.js";
import { expansionCatalogOrigin } from "../../../src/modules/learning/expansion-origin.js";

describe("selected expansion publication includes admitted senior children", () => {
  it("derives the same selected payloads without loading the historical senior catalog", () => {
    const catalog = loadExpansionCatalog("b039", false, "2026-10-28");
    const expected = expansionPublication(catalog.units);
    const fullCatalog = vi
      .spyOn(seniorCatalog, "seniorPracticeCatalog")
      .mockImplementation(() => {
        throw new Error("Selected publication must not load the full senior catalog");
      });
    try {
      expect(expansionPublication(catalog.units, catalog.entries)).toEqual(expected);
      expect(fullCatalog).not.toHaveBeenCalled();
    } finally {
      fullCatalog.mockRestore();
    }
  });

  it("keeps the full component admission checks for scoped publication", () => {
    const catalog = loadExpansionCatalog("b039", false, "2026-10-28");
    const reviewed = structuredClone(catalog.entries);
    const parent = reviewed.find((e) => e.unit.level === "senior1");
    expect(parent?.components?.length).toBe(2);
    const component = parent?.components?.[0];
    const repeated = component?.questionIds[1];
    if (!component || !repeated) throw new Error("Missing senior fixture component");
    component.questionIds[0] = repeated;
    expect(() => expansionPublication(catalog.units, reviewed)).toThrow();
  });

  it("rejects reviewed payload drift even when the supplied digest was not updated", () => {
    const catalog = loadExpansionCatalog("b039", false, "2026-10-28");
    const reviewed = structuredClone(catalog.entries);
    const parent = reviewed.find((e) => e.unit.level === "senior1");
    if (!parent) throw new Error("Missing senior fixture parent");
    parent.unit.summary += " altered";
    expect(() => expansionPublication(catalog.units, reviewed)).toThrow();
  });

  it("rejects a hash-consistent parent that violates the senior workload boundary", () => {
    const catalog = loadExpansionCatalog("b039", false, "2026-10-28");
    const reviewed = structuredClone(catalog.entries);
    const parent = reviewed.find((e) => e.unit.level === "senior1");
    if (!parent) throw new Error("Missing senior fixture parent");
    parent.unit.estimatedMinutes = 1;
    parent.contentHash = contentHash(parent.unit);
    expect(() =>
      expansionPublication(
        reviewed.map((e) => e.unit),
        reviewed,
      ),
    ).toThrow();
  });

  it("registers six complete independent children of only the three selected new composite parents", () => {
    const catalog = loadExpansionCatalog("b039", false, "2026-10-28");
    const before = contentHash(catalog.units);
    const selected = expansionPublication(catalog.units);
    expect(selected.units).toHaveLength(14);
    expect(selected.admitted).toHaveLength(11);
    const children = selected.units.filter((u) =>
      u.id.startsWith("gaokao.independent."),
    );
    expect(children).toHaveLength(6);
    for (const child of children) {
      const parent = catalog.units.find((u) => u.id === expansionCatalogOrigin(child));
      expect(parent).toBeDefined();
      expect(Object.keys(child.originalGroup ?? {}).sort()).toEqual(
        Object.keys(parent?.originalGroup ?? {}).sort(),
      );
      expect([5, 10]).toContain(child.questions.length);
      expect(child.questions).toEqual(
        parent?.questions.filter((q) => child.questions.some((c) => c.id === q.id)),
      );
      expect(child.originalGroup?.sourceGroupIds).not.toContain(parent?.id);
      expect(selected.admitted.some((u) => u.id === child.id)).toBe(true);
      expect(selected.admitted.some((u) => u.id === parent?.id)).toBe(false);
    }
    expect(contentHash(catalog.units)).toBe(before);
  });

  it("does not expand a primary batch or attach new provenance to old independent units", () => {
    const catalog = loadExpansionCatalog("b001", false, "2026-10-28");
    const selected = expansionPublication(catalog.units);
    expect(selected.units).toEqual(catalog.units);
    expect(selected.admitted).toEqual(catalog.units);
    const old = seniorPracticeCatalog().practices.filter(
      (p) =>
        p.unit.id.startsWith("gaokao.independent.") &&
        p.unit.originalGroup?.sourceNotice.includes("2026-10-24"),
    );
    expect(old.length).toBeGreaterThan(0);
    expect(old.every((p) => expansionCatalogOrigin(p.unit) === undefined)).toBe(true);
    expect(
      old.find((p) => p.unit.id === "gaokao.independent.senior1.23a822c9f8ead1814def")
        ?.contentHash,
    ).toBe("e62b2717ffea5b3e12c7b17d0f3aeec510aa2bfefba4ad1fdcfdcca23962f0eb");
  });
});
