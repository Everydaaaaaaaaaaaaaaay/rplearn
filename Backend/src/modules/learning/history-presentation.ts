import { readFileSync } from "node:fs";
import { z } from "zod";
import type { LearningUnit } from "./content.js";
import { contentHash } from "./content-hash.js";

type HistorySource = Pick<
  LearningUnit,
  "title" | "summary" | "scene" | "originalGroup" | "questions"
>;
const entrySchema = z.strictObject({
  sourceUnitId: z.string(),
  sourceHash: z.string().regex(/^[a-f0-9]{64}$/),
  kind: z.string().min(2).max(24),
  topic: z.string().min(2).max(70),
  reviewBasis: z.string().min(8),
});
let reviewed: Map<string, z.infer<typeof entrySchema>> | undefined;
function reviewedTitles() {
  if (!reviewed) {
    const file = z
      .strictObject({ version: z.literal(1), entries: z.array(entrySchema).max(2000) })
      .parse(
        JSON.parse(
          readFileSync(
            new URL("../../../config/learning/history-titles.json", import.meta.url),
            "utf8",
          ),
        ) as unknown,
      );
    reviewed = new Map(file.entries.map((entry) => [entry.sourceHash, entry]));
    if (reviewed.size !== file.entries.length)
      throw new Error("练习记录标题存在重复内容身份。");
  }
  return reviewed;
}

/** Bind copy to the complete question content, not a reusable unit ID or a learner. */
export function historyTitleSourceHash(unit: HistorySource) {
  return contentHash({
    title: unit.title,
    summary: unit.summary,
    scene: unit.scene,
    originalGroup: unit.originalGroup ?? null,
    questions: unit.questions,
  });
}

const kinds: Record<string, string> = {
  reading_choice: "阅读理解",
  reading_tf: "阅读判断",
  choice_cloze: "完形填空",
  shared_insertion: "七选五",
  passage_form: "语法填空",
  gaokao_mixed: "七选五＋语法填空",
  sentence_choice: "单项选择",
  sentence_form: "词形填空",
  dialogue_matching: "对话配对",
  word_picture_matching: "图词配对",
  cross_text_matching: "观点匹配",
};
const internalID =
  /\b(?:original|grade\d+|primary\d+|senior\d+|junior\d+|gaokao|expansion)[._-]|\b[a-z]+(?:-[a-z0-9]+){2,}\b/i;
const generic =
  /^(?:高考题型原创|高中客观专项|\d+[·/]\d+新题|独立练习|完整原创练习|两篇|[A-D]|\d+|阅读理解|完形填空|七选五|语法填空|单项选择|听音选图|图词配对|问答\/对话配对)(?:（.*）)?$/;

function topicWithoutScaffolding(title: string) {
  return title
    .replace(/\d+[·/]\d+新题\s*·?\s*/g, "")
    .replace(
      /^(?:小[一二三四五六]|初[一二三]|高[一二三]|小学[一二三四五六]年级|初中[一二三]年级|高中[一二三]年级)(?:完整[^：:]*|[^：:·]*题)?[：:]\s*/,
      "",
    )
    .split(/\s*·\s*/)
    .filter((part) => part && !generic.test(part))
    .join(" · ")
    .trim();
}

function topicFromContent(unit: HistorySource) {
  const paragraphs = [
    unit.originalGroup?.material ?? "",
    ...unit.questions.map((q) => q.material ?? ""),
  ]
    .flatMap((text) => text.split(/\n+/))
    .map((text) => text.trim());
  const heading = paragraphs.find(
    (text) =>
      text.length >= 4 &&
      text.length <= 90 &&
      !internalID.test(text) &&
      !/^(?:阅读|听|看|从每|用括号|根据|共用|共享|录音|第\d|[A-D]\d?\s*$)/.test(text),
  );
  if (heading) return heading;
  const prompts = unit.questions
    .map((q) => q.prompt.trim())
    .filter(
      (text) =>
        text.length > 0 &&
        text.length <= 32 &&
        !internalID.test(text) &&
        !/^(?:听|看|选择|第\d|Fill gap|Complete gap)/i.test(text),
    );
  if (prompts.length) return [...new Set(prompts)].slice(0, 3).join("、");
  // Narrative units have a meaningful authored scene even when a legacy label is an ID.
  return (
    unit.scene
      .split(/[。！？\n]/)
      .find((part) => part.trim().length > 0)
      ?.trim()
      .slice(0, 70) ?? "日常交流"
  );
}

/** Display only: never rewrite a frozen attempt, published unit, answer or reward. */
export function historyTitleForPresentation(unit: HistorySource) {
  const revision = reviewedTitles().get(historyTitleSourceHash(unit));
  if (revision) return `${revision.kind} · ${revision.topic}`;
  const group = unit.originalGroup;
  const kind = group
    ? (kinds[group.family] ?? group.label.replace(/（[^）]*）/g, ""))
    : "综合练习";
  const topic = topicWithoutScaffolding(unit.title);
  return `${/[\u4e00-\u9fff]/.test(kind) && !internalID.test(kind) ? kind : "综合练习"} · ${topic && !internalID.test(topic) ? topic : topicFromContent(unit)}`;
}
