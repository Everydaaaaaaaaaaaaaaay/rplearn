// 只读校验作者定稿，不生成教学文字，不写入正式目录，不伪造音频资产。
// 仓库根目录运行：Backend/node_modules/.bin/tsx Scripts/verify-primary456-formal.mts
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { resolve, basename } from "node:path";
import {
  questionSchema,
  clozeSlotIds,
  type LearningQuestion,
} from "../Backend/src/modules/learning/content.ts";
import {
  answerSchema,
  gradeAnswer,
} from "../Backend/src/modules/learning/grading.ts";

const root = fileURLToPath(new URL("../", import.meta.url));
const authoring = resolve(root, "Backend/config/learning/authoring");
const readJSON = async (path: string) =>
  JSON.parse(await readFile(path, "utf8"));
const catalog = await readJSON(
  resolve(root, "Backend/config/learning/catalog.json"),
);
const goals = new Map<string, { level: string; sourceIds: string[] }>(
  catalog.goals.map((g: any) => [g.id, g]),
);
const sources = new Set(catalog.sources.map((s: any) => s.id));
const requested = process.argv.slice(2);
const levels = requested.length
  ? requested
  : ["primary4", "primary5", "primary6"];
if (
  levels.some((level) => !["primary4", "primary5", "primary6"].includes(level))
)
  throw new Error("仅支持primary4、primary5、primary6。");
const results: object[] = [];
let totalErrors = 0;
for (const level of levels) {
  const errors: string[] = [];
  const check = (ok: unknown, message: string) => {
    if (!ok) errors.push(message);
  };
  const counts: Record<string, number> = {};
  let questionCount = 0,
    probeCount = 0,
    correctProbes = 0,
    incorrectProbes = 0;
  let gradedProbes = 0,
    fullSchemaPassed = 0,
    pendingAudioValidated = 0;
  try {
    const document = await readJSON(
      resolve(authoring, `${level}-formal.astra.json`),
    );
    check(document.level === level, "年级标识与文件不一致。");
    check(
      document.inputHashes &&
        typeof document.inputHashes === "object" &&
        !Array.isArray(document.inputHashes),
      "inputHashes必须为对象。",
    );
    const expectedInputs = [
      `${level}.astra.json`,
      `${level}-delivery.astra.json`,
    ];
    check(
      Object.keys(document.inputHashes ?? {})
        .sort()
        .join("|") === expectedInputs.sort().join("|"),
      "inputHashes必须且仅包含原稿和delivery。",
    );
    for (const [name, expectedHash] of Object.entries(
      document.inputHashes ?? {},
    )) {
      check(
        basename(name) === name && expectedInputs.includes(name),
        `不允许的哈希输入路径：${name}`,
      );
      if (basename(name) !== name || !expectedInputs.includes(name)) continue;
      const actual = createHash("sha256")
        .update(await readFile(resolve(authoring, name)))
        .digest("hex");
      check(actual === expectedHash, `输入已漂移：${name}`);
    }
    check(
      Array.isArray(document.questions) && document.questions.length === 36,
      "必须包含36道题。",
    );
    const ids = new Set<string>();
    for (const row of document.questions ?? []) {
      const q = row.question;
      const id = row.id ?? q?.id ?? "未知题";
      questionCount++;
      try {
        check(q && row.id === q.id, `${id}：行ID与题目ID不一致。`);
        check(!ids.has(id), `${id}：重复ID。`);
        ids.add(id);
        counts[q.type] = (counts[q.type] ?? 0) + 1;
        const goal = goals.get(q.goalId);
        check(
          goal?.level === level,
          `${id}：目标未登记或年级不符：${q.goalId}`,
        );
        check(
          Array.isArray(row.references) && row.references.length > 0,
          `${id}：缺少来源。`,
        );
        for (const ref of row.references ?? []) {
          check(
            sources.has(ref.sourceId),
            `${id}：未知sourceId：${ref.sourceId}`,
          );
          check(
            typeof ref.pages === "string" &&
              ref.pages.trim().length > 0 &&
              ref.pages.length <= 100,
            `${id}：来源页码不合法。`,
          );
          check(
            typeof ref.alignment === "string" &&
              ref.alignment.trim().length > 0 &&
              ref.alignment.length <= 500,
            `${id}：缺少明确来源对齐。`,
          );
        }
        if (goal)
          check(
            goal.sourceIds.some((s) =>
              row.references?.some((r: any) => r.sourceId === s),
            ),
            `${id}：目标缺少对应来源。`,
          );
        for (const secondary of row.secondaryGoalIds ?? []) {
          const entry = goals.get(secondary);
          check(
            entry?.level === level,
            `${id}：次目标未登记或年级不符：${secondary}`,
          );
          if (entry)
            check(
              entry.sourceIds.some((s) =>
                row.references?.some((r: any) => r.sourceId === s),
              ),
              `${id}：次目标缺少来源。`,
            );
        }
        for (const field of ["standaloneContext", "ambiguityReview"]) {
          const note = row[field];
          check(
            typeof note === "string" &&
              note.trim().length >= 8 &&
              note.trim().length <= 2000,
            `${id}：${field}不符合catalog审阅文字长度。`,
          );
        }
        const notes = row.optionNotes;
        const notesObject =
          notes && typeof notes === "object" && !Array.isArray(notes);
        check(notesObject, `${id}：optionNotes必须为对象。`);
        if (notesObject) {
          for (const [key, value] of Object.entries(notes)) {
            check(
              /^[a-z][a-z0-9_.-]{0,119}$/.test(key),
              `${id}：非法审核选项ID：${key}`,
            );
            check(
              typeof value === "string" &&
                value.trim().length >= 8 &&
                value.trim().length <= 2000,
              `${id}：选项${key}说明须为8至2000字符。`,
            );
          }
          // 严格复现catalog.ts：非选择题必须为空对象，不能容忍词块审核塞在这里。
          if (q.type === "choice" || q.type === "listeningChoice") {
            check(
              Object.keys(notes).length === q.options.length &&
                q.options.every((o: any) => Object.hasOwn(notes, o.id)),
              `${id}：必须且仅审阅所有选择项。`,
            );
          } else
            check(
              Object.keys(notes).length === 0,
              `${id}：非选择题包含不适用的选项审核。`,
            );
        }
        const pendingAudio = [
          "listeningChoice",
          "audioArrange",
          "dictation",
        ].includes(q.type);
        if (pendingAudio) {
          check(
            !Object.hasOwn(q, "audio"),
            `${id}：当前定稿不得填写占位或假audio。`,
          );
          check(
            typeof row.audioScript === "string" &&
              row.audioScript.trim().length > 0,
            `${id}：缺少独立audioScript。`,
          );
          const branch = questionSchema.options.find(
            (schema) => schema.shape.type.value === q.type,
          );
          if (!branch || !("audio" in branch.shape))
            throw new Error(`${id}：无法定位真实听力schema。`);
          // 只删除尚待真实资产填入的字段，其余校验仍来自原严格schema。
          const withoutAudio = (branch as any).omit({ audio: true });
          withoutAudio.parse(q);
          const complete = questionSchema.safeParse(q);
          check(!complete.success, `${id}：无audio时完整schema必须拒绝。`);
          if (!complete.success)
            check(
              complete.error.issues.every((issue) => issue.path[0] === "audio"),
              `${id}：完整schema存在audio以外错误。`,
            );
          pendingAudioValidated++;
        } else {
          questionSchema.parse(q);
          fullSchemaPassed++;
        }
        if (q.type === "cloze") {
          const slots = clozeSlotIds(q.passage);
          check(
            slots.length >= 2 &&
              slots.length <= 6 &&
              new Set(slots).size === slots.length,
            `${id}：空位数量或身份不合法。`,
          );
          for (const fills of q.acceptedFills) {
            check(
              fills.length === slots.length &&
                new Set(fills.map((f: any) => f.slotId)).size ===
                  slots.length &&
                new Set(fills.map((f: any) => f.tokenId)).size ===
                  fills.length &&
                fills.every(
                  (f: any) =>
                    slots.includes(f.slotId) &&
                    q.tokens.some((t: any) => t.id === f.tokenId),
                ),
              `${id}：合法答案必须完整覆盖空位且词块不重复。`,
            );
          }
        }
        check(
          Array.isArray(row.probes) && row.probes.length >= 2,
          `${id}：至少需要两条样例。`,
        );
        check(
          row.probes?.some((p: any) => p.correct === true) &&
            row.probes?.some((p: any) => p.correct === false),
          `${id}：必须有正确和错误反例。`,
        );
        for (const probe of row.probes ?? []) {
          probeCount++;
          try {
            check(
              typeof probe.correct === "boolean",
              `${id}：correct必须为布尔值。`,
            );
            const answer = answerSchema.parse(probe.answer);
            check(answer.kind !== "skip", `${id}：skip不能充当错误反例。`);
            if (answer.kind === "arrange")
              check(
                answer.tokenIds.length === q.tokens.length,
                `${id}：排序样例必须完整使用词块。`,
              );
            if (answer.kind === "matching")
              check(
                answer.pairs.length === q.answerPairs.length,
                `${id}：配对样例必须完整配对。`,
              );
            if (answer.kind === "cloze")
              check(
                answer.fills.length === clozeSlotIds(q.passage).length,
                `${id}：多空样例必须完整填满。`,
              );
            const result = gradeAnswer(q as LearningQuestion, answer);
            check(
              result.outcome === (probe.correct ? "correct" : "incorrect"),
              `${id}：真实判题结果不符预期。`,
            );
            gradedProbes++;
            if (probe.correct) correctProbes++;
            else incorrectProbes++;
          } catch (error) {
            errors.push(`${id}：样例失败：${String(error)}`);
          }
        }
      } catch (error) {
        errors.push(`${id}：校验失败：${String(error)}`);
      }
    }
  } catch (error) {
    errors.push(`${level}：读取或结构失败：${String(error)}`);
  }
  totalErrors += errors.length;
  results.push({
    level,
    questionCount,
    types: counts,
    probeCount,
    gradedProbes,
    correctProbes,
    incorrectProbes,
    fullSchemaPassed,
    pendingAudioValidated,
    errors,
  });
}
console.log(JSON.stringify({ passed: totalErrors === 0, results }, null, 2));
if (totalErrors) process.exitCode = 1;
