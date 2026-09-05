import { randomInt } from "node:crypto";
import type { AvatarProfile, AvatarRequirements } from "./types.js";

export type AvatarCandidate = Readonly<{
  id: string;
  imageUrl: string;
  tags: readonly string[];
  profile: AvatarProfile | null;
}>;

export function avatarMatches(
  candidate: AvatarCandidate,
  request: AvatarRequirements,
): boolean {
  if (candidate.profile !== null) {
    if (
      request.age < candidate.profile.ageMin ||
      request.age > candidate.profile.ageMax
    )
      return false;
    if (candidate.profile.gender !== request.gender) return false;
  } else {
    // Compatibility for explicitly imported v1 assets; missing tags never mean a wildcard.
    const band = request.age < 25 ? "young" : request.age < 45 ? "adult" : "mature";
    if (
      !candidate.tags.includes(`gender:${request.gender}`) ||
      !candidate.tags.includes(`age:${band}`)
    )
      return false;
  }
  return request.requiredTags.every((tag) => candidate.tags.includes(tag));
}

export function chooseAvatar(
  candidates: readonly AvatarCandidate[],
  request: AvatarRequirements,
  seen: ReadonlySet<string>,
  draw: (maximum: number) => number = (maximum) => randomInt(maximum),
): Readonly<{
  avatar: AvatarCandidate | undefined;
  eligibleCount: number;
  unseenCount: number;
  reason: "matched" | "coverage_gap" | "user_pool_exhausted";
}> {
  const eligible = candidates.filter((candidate) => avatarMatches(candidate, request));
  const available = eligible.filter((candidate) => !seen.has(candidate.id));
  if (available.length === 0)
    return {
      avatar: undefined,
      eligibleCount: eligible.length,
      unseenCount: 0,
      reason: eligible.length === 0 ? "coverage_gap" : "user_pool_exhausted",
    };
  const index = draw(available.length);
  if (!Number.isInteger(index) || index < 0 || index >= available.length)
    throw new RangeError("Avatar random index is outside the candidate set");
  return {
    avatar: available[index],
    eligibleCount: eligible.length,
    unseenCount: available.length,
    reason: "matched",
  };
}
