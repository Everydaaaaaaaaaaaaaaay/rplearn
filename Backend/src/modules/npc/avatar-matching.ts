import { createHash } from "node:crypto";
import type { AvatarMetadata } from "./avatar-catalog.js";
import { cultureMap, expressionVocabulary } from "./culture-map.js";
import type { PublicNpcCard } from "./types.js";

export type AvatarCandidate = Readonly<{
  id: string;
  familyId: string;
  metadata: AvatarMetadata;
}>;
export type AvatarPreference = Readonly<{
  interests: readonly string[];
  expressions: readonly string[];
  interestText: string;
}>;

function normalize(value: string): string {
  return value.normalize("NFKC").toLowerCase().replace(/[-_]/gu, " ");
}
export function mentions(text: string, term: string): boolean {
  const normalizedTerm = normalize(term);
  const normalizedText = normalize(text);
  if (/[^\p{Script=Latin}\p{N}\s]/u.test(normalizedTerm)) {
    return normalizedText.includes(normalizedTerm);
  }
  const escaped = normalizedTerm.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
  return new RegExp(`(?<![\\p{L}\\p{N}])${escaped}(?![\\p{L}\\p{N}])`, "u").test(
    normalizedText,
  );
}

export function avatarPreference(
  card: Pick<PublicNpcCard, "hobbies" | "personality">,
): AvatarPreference {
  // Demographics, birthplace and appearance do not imply cultural taste.
  const interestText = card.hobbies.join("\n");
  return {
    interestText,
    interests: cultureMap
      .filter(([id, , ...aliases]) =>
        [id, ...aliases].some((term) => mentions(interestText, term)),
      )
      .map(([id]) => id),
    expressions: expressionVocabulary
      .filter((terms) =>
        terms.some((term) => mentions(`${interestText}\n${card.personality}`, term)),
      )
      .map(([id]) => id),
  };
}

export function rankAvatars(
  candidates: readonly AvatarCandidate[],
  preference: AvatarPreference,
) {
  const counts = new Map<string, number>();
  for (const avatar of candidates) {
    for (const culture of new Set(avatar.metadata.cultures)) {
      counts.set(culture, (counts.get(culture) ?? 0) + 1);
    }
  }
  return candidates
    .map((avatar) => {
      const labels = [...avatar.metadata.cultures, ...avatar.metadata.subjects];
      const interests = new Set(
        preference.interests.filter((id) =>
          labels.some((label) => {
            const entry = cultureMap.find(([cultureId]) => cultureId === id);
            return (
              normalize(label) === normalize(id) ||
              entry?.slice(2).some((alias) => normalize(alias) === normalize(label))
            );
          }),
        ),
      );
      // Open vocabulary supports emerging interests without changing the seed map.
      for (const label of labels) {
        if (mentions(preference.interestText, label)) {
          const canonical = cultureMap.find(([id, , ...aliases]) =>
            [id, ...aliases].some((alias) => normalize(alias) === normalize(label)),
          );
          interests.add(canonical?.[0] ?? normalize(label));
        }
      }
      const expressions = preference.expressions.filter((expression) =>
        [...avatar.metadata.aesthetics, ...avatar.metadata.expressions].some(
          (label) => {
            const vocabulary = expressionVocabulary.find(([id]) => id === expression);
            return vocabulary?.some((alias) => normalize(label) === normalize(alias));
          },
        ),
      );
      // Small penalty only: reserve scarce cross-cultural assets when simpler matches suffice.
      const scarcity = avatar.metadata.cultures.reduce(
        (sum, culture) =>
          sum + (interests.has(culture) ? 0 : 1 / (counts.get(culture) ?? 1)),
        0,
      );
      return {
        avatar,
        matchedInterests: [...interests],
        matchedExpressions: expressions,
        score:
          Math.min(interests.size, 3) * 10 +
          Math.min(expressions.length, 2) * 2 -
          Math.min(scarcity, 1),
      };
    })
    .filter(
      (result) =>
        result.matchedInterests.length > 0 ||
        (result.avatar.metadata.interestIndependent &&
          result.matchedExpressions.length > 0),
    )
    .sort((a, b) => b.score - a.score || a.avatar.id.localeCompare(b.avatar.id));
}

export function chooseAvatar(
  candidates: readonly AvatarCandidate[],
  preference: AvatarPreference,
  seed: string,
) {
  const ranked = rankAvatars(candidates, preference);
  const best = ranked[0];
  if (!best) return undefined;
  const shortlist = ranked.filter((entry) => entry.score >= best.score - 2);
  // Stable random order per user/NPC, independent of import order and safe across retries.
  return shortlist
    .map((entry) => ({
      entry,
      order: createHash("sha256").update(`${seed}:${entry.avatar.id}`).digest("hex"),
    }))
    .sort((a, b) => a.order.localeCompare(b.order))[0]?.entry;
}
