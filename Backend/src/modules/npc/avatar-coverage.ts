import type { AvatarManifest } from "./avatar-catalog.js";
import { avatarPreference, chooseAvatar, rankAvatars } from "./avatar-matching.js";
import { cultureMap } from "./culture-map.js";
import type { PublicNpcCard } from "./types.js";

export type CoveragePersona = Pick<PublicNpcCard, "hobbies" | "personality"> & {
  id: string;
};
export function auditAvatarCoverage(
  manifest: AvatarManifest,
  personas: readonly CoveragePersona[],
) {
  const candidates = manifest.avatars.filter(
    (asset) => asset.enabled && !asset.reserved,
  );
  const used = new Set<string>();
  const results = personas.map((persona) => {
    const preference = avatarPreference(persona);
    const all = rankAvatars(candidates, preference);
    const available = candidates.filter((avatar) => !used.has(avatar.familyId));
    const selected = chooseAvatar(available, preference, `coverage:${persona.id}`);
    if (selected) used.add(selected.avatar.familyId);
    return {
      id: persona.id,
      preference,
      candidateFamilies: new Set(all.map((match) => match.avatar.familyId)).size,
      selectedAvatarId: selected?.avatar.id ?? null,
      aestheticOnly: selected?.matchedInterests.length === 0,
      shortage:
        all.length === 0 ? "no-match" : selected === undefined ? "depleted" : null,
    };
  });
  const cultures = cultureMap.map(([id, domain]) => {
    const matches = candidates.filter((avatar) =>
      avatar.metadata.cultures.includes(id),
    );
    return {
      id,
      domain,
      families: new Set(matches.map((avatar) => avatar.familyId)).size,
      expressions: [
        ...new Set(matches.flatMap((avatar) => avatar.metadata.expressions)),
      ].sort(),
    };
  });
  const facets = (field: "regions" | "eras" | "aesthetics") => {
    const values = new Map<string, Set<string>>();
    for (const avatar of candidates) {
      for (const value of avatar.metadata[field]) {
        const families = values.get(value) ?? new Set<string>();
        families.add(avatar.familyId);
        values.set(value, families);
      }
    }
    return [...values]
      .map(([value, families]) => ({ value, families: families.size }))
      .sort((a, b) => a.value.localeCompare(b.value));
  };
  return {
    version: 1,
    regions: facets("regions"),
    eras: facets("eras"),
    aesthetics: facets("aesthetics"),
    supplied: manifest.avatars.length,
    eligible: candidates.length,
    families: new Set(candidates.map((asset) => asset.familyId)).size,
    cultures,
    replenishment: cultures.filter(
      (culture) => culture.families < 3 || culture.expressions.length < 2,
    ),
    personas: results,
    unmatched: results.filter((result) => result.shortage === "no-match").length,
    depleted: results.filter((result) => result.shortage === "depleted").length,
    aestheticOnly: results.filter((result) => result.aestheticOnly).length,
    // Never interpret the seed vocabulary's coverage as coverage of all human culture.
    unrecognizedInterests: [
      ...new Set(
        results
          .filter((result) => result.preference.interests.length === 0)
          .map((result) => result.preference.interestText),
      ),
    ],
  };
}
