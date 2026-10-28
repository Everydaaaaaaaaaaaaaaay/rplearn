import type { LearningUnit } from "./content.js";

// Existing provenance text remains readable by rollback releases. Exposure keys stay independent.
export const expansionCatalogOriginMarker = "\nExpansion catalog unit: ";

export function expansionCatalogOrigin(unit: Pick<LearningUnit, "originalGroup">) {
  const notice = unit.originalGroup?.sourceNotice ?? "";
  const position = notice.lastIndexOf(expansionCatalogOriginMarker);
  if (position < 0) return undefined;
  const id = notice.slice(position + expansionCatalogOriginMarker.length);
  return /^expansion\.202610(?:24|28)\.[a-z0-9_.-]+$/.test(id) && id.length <= 120
    ? id
    : undefined;
}
