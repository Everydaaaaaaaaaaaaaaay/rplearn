import { createHash } from "node:crypto";
import type { GrammarConcept, GrammarProposal } from "./types.js";

export const hash = (value: unknown) =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex");
export function patternIdentity(point: Pick<GrammarConcept, "patterns">): string {
  return hash(
    point.patterns
      .map((p) => ({
        steps: p.steps.map((s) => s.split("|").sort().join("|")),
        maximumGaps: p.maximumGaps,
      }))
      .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))),
  );
}
export const conceptId = (identity: string) => `shared-${hash(identity).slice(0, 32)}`;
export function equivalentPattern(
  proposal: GrammarProposal,
  points: readonly GrammarConcept[],
): string | undefined {
  return points.find((p) => patternIdentity(p) === patternIdentity(proposal))?.id;
}

/** Generated examples must demonstrate the detector and must not reuse a private sentence. */
export function proposalIsSafe(proposal: GrammarProposal, sentence: string): boolean {
  const normalized = (s: string) =>
    s
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  const common = new Set([
    "This",
    "That",
    "These",
    "Those",
    "The",
    "She",
    "They",
    "His",
    "Her",
    "Our",
    "Their",
    "You",
    "Your",
    "Have",
    "Has",
    "Had",
    "Would",
    "Could",
    "Should",
    "Will",
    "Can",
    "May",
    "When",
    "What",
    "Where",
    "Why",
    "How",
    "Please",
    "Let",
  ]);
  const names = (sentence.match(/\b[A-Z][a-z]{2,}\b/g) ?? []).filter(
    (word) => !common.has(word),
  );
  const generic = JSON.stringify(proposal).toLowerCase();
  return (
    !names.some((name) => new RegExp(`\\b${name.toLowerCase()}\\b`).test(generic)) &&
    proposal.examples.every(
      (e) =>
        normalized(e.en) !== normalized(sentence) &&
        !/[\w.+-]+@[\w.-]+\.[a-z]{2,}|https?:\/\/|\b\d{4,}\b/i.test(e.en + e.zh),
    ) &&
    proposal.patterns.every((p) =>
      proposal.examples.some((e) => patternMatches(p, e.en)),
    )
  );
}
export function patternMatches(
  pattern: GrammarConcept["patterns"][number],
  sentence: string,
): boolean {
  const words = sentence.toLowerCase().match(/[a-z]+(?:'[a-z]+)?/g) ?? [];
  const accepts = (step: string, word: string) =>
    step === "<word>" ||
    (step === "<gerund>"
      ? word.endsWith("ing")
      : step === "<past-participle>"
        ? /(?:ed|en)$/.test(word) ||
          [
            "been",
            "gone",
            "done",
            "seen",
            "made",
            "had",
            "read",
            "said",
            "found",
            "left",
            "bought",
            "brought",
            "taken",
            "written",
            "spoken",
            "known",
            "given",
            "eaten",
            "got",
            "met",
            "put",
            "cut",
            "set",
            "felt",
            "told",
            "thought",
            "heard",
          ].includes(word)
        : step === "<comparative>"
          ? word.endsWith("er") || ["more", "less", "better", "worse"].includes(word)
          : step.split("|").includes(word));
  const visit = (step: number, position: number): boolean => {
    if (step === pattern.steps.length) return true;
    const start = position + 1;
    const end =
      step === 0
        ? words.length - 1
        : Math.min(words.length - 1, start + (pattern.maximumGaps[step - 1] ?? 0));
    for (let i = start; i <= end; i++) {
      const token = words[i],
        expected = pattern.steps[step];
      if (
        token !== undefined &&
        expected !== undefined &&
        accepts(expected, token) &&
        visit(step + 1, i)
      )
        return true;
    }
    return false;
  };
  return visit(0, -1);
}
