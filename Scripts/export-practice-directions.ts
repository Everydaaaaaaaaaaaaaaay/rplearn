import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { unitSchema } from "../Backend/src/modules/learning/content.js";
import { loadExpansionCatalog } from "../Backend/src/modules/learning/expansion-catalog.js";
import { seniorPracticeCatalog } from "../Backend/src/modules/learning/senior-practice-catalog.js";
import { practiceDirectionSourceHash } from "../Backend/src/modules/learning/practice-directions.js";

const root = new URL("../", import.meta.url);
const originals = JSON.parse(
  readFileSync(
    new URL("Backend/config/learning/originals/catalog.json", root),
    "utf8",
  ),
) as { units: { unit: unknown }[] };
const catalog = seniorPracticeCatalog();
const units = [
  ...originals.units.map((e: { unit: unknown }) => unitSchema.parse(e.unit)),
  ...loadExpansionCatalog().units,
  ...catalog.practices.map((p) => p.unit),
  ...catalog.historicalPractices.map((p) => p.unit),
];
function familyFor(
  unit: (typeof units)[number],
  question: (typeof unit.questions)[number],
) {
  const family = unit.originalGroup?.family ?? "";
  if (
    ![
      "gaokao_language",
      "gaokao_mixed",
      "shared_insertion_passage_form",
    ].includes(family)
  )
    return family;
  return question.type === "completion"
    ? "passage_form"
    : question.goalId.includes("shared_insertion")
      ? "shared_insertion"
      : "reading_choice";
}
const sources = new Map<
  string,
  { family: string; instruction: string; prefix: string; sampleUnit: string }
>();
for (const unit of units)
  for (const q of unit.questions) {
    const material = q.material ?? unit.originalGroup?.material ?? "";
    const family = familyFor(unit, q);
    const prefix = material.split("\n\n", 1)[0] ?? "";
    const key = JSON.stringify([family, q.instruction, prefix]);
    if (!sources.has(key))
      sources.set(key, {
        family,
        instruction: q.instruction,
        prefix,
        sampleUnit: unit.id,
      });
  }
if (process.argv.includes("--audit")) {
  writeFileSync(
    new URL("build/practice-direction-sources.json", root),
    JSON.stringify([...sources.values()], null, 2) + "\n",
  );
} else {
  type Reviewed = {
    family: string;
    sourceInstruction: string;
    sourcePrefix: string;
    instruction: string;
    removePrefix: string;
  };
  const reviewed: Reviewed[] = JSON.parse(
    readFileSync(
      new URL("Scripts/data/practice-direction-copy.json", root),
      "utf8",
    ),
  );
  const grammarHeadings = new Set<string>(
    JSON.parse(
      readFileSync(
        new URL("Scripts/data/practice-grammar-headings.json", root),
        "utf8",
      ),
    ),
  );
  const lookup = new Map(
    reviewed.map((r) => [
      JSON.stringify([r.family, r.sourceInstruction, r.sourcePrefix]),
      r,
    ]),
  );
  const reviewedCopy = (
    family: string,
    instruction: string,
    material: string,
  ) =>
    lookup.get(
      JSON.stringify([family, instruction, material.split("\n\n", 1)[0] ?? ""]),
    ) ?? lookup.get(JSON.stringify([family, instruction, ""]));
  const originalById = new Map(
    originals.units.map((e) => {
      const unit = unitSchema.parse(e.unit);
      return [unit.id, unit] as const;
    }),
  );
  const componentDirections = new Map<
    string,
    { instruction: string; sourceDirections: string }
  >();
  for (const practice of [...catalog.practices, ...catalog.historicalPractices])
    for (const component of practice.components) {
      const source =
        component.sourceUnitId && originalById.get(component.sourceUnitId);
      for (const [index, id] of component.questionIds.entries()) {
        const number = component.sourceNumbers[index];
        const question =
          source && number !== undefined
            ? source.questions[number - 1]
            : undefined;
        const copy =
          question &&
          source &&
          reviewedCopy(
            component.family,
            question.instruction,
            question.material ?? source.originalGroup?.material ?? "",
          );
        if (copy)
          componentDirections.set(id, {
            instruction: copy.instruction,
            sourceDirections: copy.sourceInstruction + "\n" + copy.sourcePrefix,
          });
        // The retained national-I paper explicitly prints two unused options.
        if (
          practice.kind === "past-paper" &&
          component.family === "shared_insertion"
        )
          componentDirections.set(id, {
            instruction:
              "Choose the best option for each gap. There are two extra options.",
            sourceDirections:
              "阅读下面短文, 从短文后的选项中选出可以填入空白处的最佳选项。选项中有两项为多余选项。",
          });
      }
    }
  const bindings = new Set<string>();
  const rules = new Map<
    string,
    {
      instruction: string;
      sourceDirections: string;
      removePrefix: string;
      bindings: string[];
    }
  >();
  for (const unit of units)
    for (const q of unit.questions) {
      const material = q.material ?? unit.originalGroup?.material ?? "";
      const family = familyFor(unit, q);
      const copy = reviewedCopy(family, q.instruction, material);
      if (!copy)
        throw new Error(`Unreviewed practice directions: ${unit.id}/${q.id}`);
      const hash = practiceDirectionSourceHash(q, material);
      if (bindings.has(hash)) continue;
      bindings.add(hash);
      let removePrefix = copy.removePrefix;
      // These are reviewed standalone administrative notes, not question prose.
      if (removePrefix && family === "sentence_choice")
        for (const note of [
          "\n\n各题语境独立。同一选项中有分号时，依次回填该题两个空，但只作答一次。",
          "\n\n各题语境独立。",
        ])
          if (material.startsWith(removePrefix + note)) removePrefix += note;
      if (family === "passage_form") {
        const remainder = material.slice(removePrefix.length).trimStart();
        const heading = remainder.split("\n\n", 1)[0] ?? "";
        if (grammarHeadings.has(heading)) {
          // Exact reviewed author/section headings only; never infer from prose length.
          removePrefix = material.slice(
            0,
            material.length - remainder.length + heading.length,
          );
        }
      }
      const sourceCopy = componentDirections.get(q.id);
      const instruction = sourceCopy?.instruction ?? copy.instruction;
      const sourceDirections =
        sourceCopy?.sourceDirections ?? copy.sourceInstruction;
      const ruleKey = JSON.stringify([
        instruction,
        removePrefix,
        sourceDirections,
      ]);
      let rule = rules.get(ruleKey);
      if (!rule) {
        rule = {
          instruction,
          sourceDirections,
          removePrefix,
          bindings: [],
        };
        rules.set(ruleKey, rule);
      }
      rule.bindings.push(hash);
    }
  const result = {
    version: 1,
    reviewNotes:
      "Display-only English paper directions. Existing English paper wording is retained where applicable; Chinese source directions are translated with task constraints preserved. Exact frozen question plus effective-material bindings; only reviewed administrative opening blocks are removed. Original manuscripts, prose, options, scoring and history remain intact.",
    rules: [...rules.values()].map((r) => ({
      ...r,
      bindings: r.bindings.sort(),
    })),
  };
  writeFileSync(
    new URL("Backend/config/learning/practice-directions.json", root),
    JSON.stringify(result, null, 2) + "\n",
  );
  console.log(
    JSON.stringify({
      sourceGroups: units.length,
      reviewedVariants: reviewed.length,
      rules: rules.size,
      bindings: bindings.size,
      output: fileURLToPath(
        new URL("Backend/config/learning/practice-directions.json", root),
      ),
    }),
  );
}
