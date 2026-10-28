import type { LearningUnit } from "./content.js";
import { seniorPracticeCatalog } from "./senior-practice-catalog.js";
import { expansionCatalogOrigin } from "./expansion-origin.js";

/** Publish only children of selected new parents; never republish the whole senior catalog. */
export function expansionPublication(source: readonly LearningUnit[]) {
  if (!source.some((u) => /^senior[123]$/.test(u.level)))
    return { units: [...source], admitted: [...source] };
  const ids = new Set(source.map((u) => u.id));
  const practices = seniorPracticeCatalog()
    .practices.filter(
      (p) => ids.has(p.unit.id) || ids.has(expansionCatalogOrigin(p.unit) ?? ""),
    )
    .map((p) => p.unit);
  const derived = practices.filter((u) => !ids.has(u.id));
  return {
    units: [...source, ...derived],
    admitted: [...source.filter((u) => !/^senior[123]$/.test(u.level)), ...practices],
  };
}
