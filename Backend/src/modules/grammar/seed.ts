import { readFile } from "node:fs/promises";
import type { GrammarConcept } from "./types.js";

export async function loadGrammarSeed(): Promise<GrammarConcept[]> {
  const file = JSON.parse(
    await readFile(
      new URL("../../../config/grammar/seed.json", import.meta.url),
      "utf8",
    ),
  ) as {
    points: (Omit<GrammarConcept, "explanationZh" | "patterns"> & {
      explanation_zh: string;
      patterns: {
        steps: string[];
        maximum_gaps: number[];
        highlighted_steps?: number[];
      }[];
    })[];
  };
  return file.points.map(({ explanation_zh, patterns, ...p }) => ({
    ...p,
    explanationZh: explanation_zh,
    patterns: patterns.map(({ maximum_gaps, highlighted_steps, ...pattern }) => ({
      ...pattern,
      maximumGaps: maximum_gaps,
      ...(highlighted_steps === undefined
        ? {}
        : { highlightedSteps: highlighted_steps }),
    })),
  }));
}
