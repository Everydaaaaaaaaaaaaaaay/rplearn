import { readFileSync } from "node:fs";
import { z } from "zod";
import { contentHash, unitSchema, type LearningUnit } from "./content.js";
import { gaokaoCatalog } from "./gaokao-policy.js";
import { expansionCatalogOriginMarker } from "./expansion-origin.js";

type Practice = ReturnType<typeof gaokaoCatalog>["practices"][number];
let cached: { practices: Practice[]; historicalPractices: Practice[] } | undefined;

/** Independent practices reuse complete reviewed components and stable answer identities. */
export function seniorPracticeCatalog() {
  if (cached) return cached;
  const historicalPractices = gaokaoCatalog().practices;
  const practices: Practice[] = [];
  const seen = new Set<string>();
  for (const p of historicalPractices) {
    if (
      p.components.length === 1 ||
      p.components.every((c) => c.family === "reading_choice")
    ) {
      practices.push(p);
      continue;
    }
    for (const component of p.components) {
      const key = contentHash([p.unit.level, component.id]).slice(0, 20);
      const id = `gaokao.independent.${p.unit.level}.${key}`;
      if (seen.has(id)) continue;
      seen.add(id);
      const questions = component.questionIds.map((qid) => {
        const q = p.unit.questions.find((q) => q.id === qid);
        if (!q) throw new Error("独立练习缺少完整回应。");
        return q;
      });
      const label =
        component.family === "shared_insertion"
          ? "七选五"
          : component.family === "passage_form"
            ? "语法填空"
            : "阅读理解";
      if (
        (component.family === "shared_insertion" && questions.length !== 5) ||
        (component.family === "passage_form" && questions.length !== 10) ||
        !p.unit.originalGroup ||
        !questions[0]?.material
      )
        throw new Error("独立练习结构不完整。");
      const unit = unitSchema.parse({
        ...p.unit,
        id,
        title: `${p.kind === "past-paper" ? "高考真题" : "高考题型原创"} · ${label} · 独立练习`,
        summary: `${label}完整专项，共${String(questions.length)}题。`,
        estimatedMinutes: component.family === "shared_insertion" ? 8 : 10,
        questions,
        goalIds: [...new Set(questions.map((q) => q.goalId))],
        prerequisiteGoalIds: [],
        originalGroup: {
          ...p.unit.originalGroup,
          id,
          family: component.family,
          label,
          material: questions[0].material,
          sourceGroupIds: [component.id],
          candidateSHA256: contentHash([p.contentHash, component.id]),
          authorCheckSHA256: contentHash(questions),
          sourceNotice:
            p.unit.originalGroup.sourceNotice +
            " 本次独立呈现完整子题组；原题号、答案身份和历史作答保留。" +
            (p.unit.id.startsWith("expansion.20261028.")
              ? expansionCatalogOriginMarker + p.unit.id
              : ""),
        },
      });
      practices.push({
        kind: p.kind,
        unit,
        contentHash: contentHash(unit),
        components: [component],
      });
    }
  }
  const singles = z
    .object({
      version: z.literal(1),
      entries: z
        .array(
          z.object({
            unit: unitSchema,
            contentHash: z.string(),
            sourceUnitId: z.string(),
            sourceContentHash: z.string(),
          }),
        )
        .length(9),
    })
    .parse(
      JSON.parse(
        readFileSync(
          new URL(
            "../../../config/learning/gaokao/single-choice.json",
            import.meta.url,
          ),
          "utf8",
        ),
      ) as unknown,
    );
  for (const e of singles.entries) {
    if (
      contentHash(e.unit) !== e.contentHash ||
      e.unit.originalGroup?.family !== "sentence_choice" ||
      !/^senior[123]$/.test(e.unit.level) ||
      ![15, 20].includes(e.unit.questions.length) ||
      e.unit.questions.some((q) => q.type !== "choice" || q.options.length !== 4)
    )
      throw new Error("高中单项选择审核绑定不符。");
    practices.push({
      kind: "authored",
      unit: e.unit,
      contentHash: e.contentHash,
      components: [
        {
          id: e.sourceUnitId + "#whole",
          family: "sentence_choice",
          questionIds: e.unit.questions.map((q) => q.id),
          sourceNumbers: e.unit.questions.map((_, i) => i + 1),
          sourceUnitId: e.sourceUnitId,
          sourceContentHash: e.sourceContentHash,
        },
      ],
    });
  }
  cached = { practices, historicalPractices };
  return cached;
}
export const seniorPracticeIds = () =>
  seniorPracticeCatalog().practices.map((p) => p.unit.id);
export const seniorHistoryIds = () => [
  ...new Set(
    [
      ...seniorPracticeCatalog().practices,
      ...seniorPracticeCatalog().historicalPractices,
    ].map((p) => p.unit.id),
  ),
];
export const seniorPracticeHashes = () =>
  [
    ...seniorPracticeCatalog().practices,
    ...seniorPracticeCatalog().historicalPractices,
  ].map((p) => p.contentHash);
export function isAdmittedSeniorUnit(unit: LearningUnit) {
  return [
    ...seniorPracticeCatalog().practices,
    ...seniorPracticeCatalog().historicalPractices,
  ].some((p) => p.unit.id === unit.id && p.contentHash === contentHash(unit));
}
export function selectSeniorCandidate<T extends { payload: LearningUnit }>(
  candidates: readonly T[],
  previousId?: string,
  random = Math.random,
): T | undefined {
  const groups = new Map<string, T[]>();
  for (const c of candidates) {
    const family = c.payload.originalGroup?.family;
    if (!family) continue;
    const group = groups.get(family) ?? [];
    group.push(c);
    groups.set(family, group);
  }
  const previous = [
    ...seniorPracticeCatalog().practices,
    ...seniorPracticeCatalog().historicalPractices,
  ].find((p) => p.unit.id === previousId)?.unit.originalGroup?.family;
  const families = [...groups.keys()].filter(
    (f) => groups.size === 1 || f !== previous,
  );
  const family = families[Math.floor(random() * families.length)];
  const group = family ? groups.get(family) : undefined;
  return group?.[Math.floor(random() * group.length)];
}
