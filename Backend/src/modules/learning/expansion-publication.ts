import type { LearningUnit } from "./content.js";
import {
  independentSeniorPractices,
  seniorPracticeCatalog,
} from "./senior-practice-catalog.js";
import { expansionCatalogOrigin } from "./expansion-origin.js";
import { contentHash } from "./content.js";
import type { loadExpansionCatalog } from "./expansion-catalog.js";
import { validateGaokaoPractices } from "./gaokao-policy.js";

type ReviewedEntry = ReturnType<typeof loadExpansionCatalog>["entries"][number];

/** Publish only children of selected new parents; never republish the whole senior catalog. */
export function expansionPublication(
  source: readonly LearningUnit[],
  reviewed?: readonly ReviewedEntry[],
) {
  if (!source.some((u) => /^senior[123]$/.test(u.level)))
    return { units: [...source], admitted: [...source] };
  const ids = new Set(source.map((u) => u.id));
  const parents = source.filter((u) => /^senior[123]$/.test(u.level));
  const supplied = reviewed?.filter((e) => parents.some((u) => u.id === e.unit.id));
  if (
    supplied &&
    (supplied.length !== parents.length ||
      parents.some(
        (u) =>
          !supplied.some(
            (e) =>
              e.unit.id === u.id &&
              e.contentHash === contentHash(u) &&
              e.components?.length,
          ),
      ))
  ) {
    throw new Error(
      "Selected senior publication requires matching reviewed parents/components",
    );
  }
  const selectedParents = supplied?.map((e) => ({
    kind: "authored" as const,
    unit: e.unit,
    contentHash: e.contentHash,
    components: e.components ?? [],
  }));
  if (selectedParents) validateGaokaoPractices(selectedParents);
  const admitted = selectedParents
    ? independentSeniorPractices(selectedParents)
    : seniorPracticeCatalog().practices;
  const practices = admitted
    .filter((p) => ids.has(p.unit.id) || ids.has(expansionCatalogOrigin(p.unit) ?? ""))
    .map((p) => p.unit);
  const derived = practices.filter((u) => !ids.has(u.id));
  return {
    units: [...source, ...derived],
    admitted: [...source.filter((u) => !/^senior[123]$/.test(u.level)), ...practices],
  };
}
