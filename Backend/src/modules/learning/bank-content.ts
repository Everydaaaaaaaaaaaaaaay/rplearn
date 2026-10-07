import { z } from "zod";
import {
  contentHash,
  levelSchema,
  questionSchema,
  unitSchema,
  type LearningQuestion,
  type LearningUnit,
} from "./content.js";

const id = z.string().regex(/^[a-z][a-z0-9_.-]{0,119}$/);
export const bankTags = [
  "daily",
  "books",
  "community",
  "outdoors",
  "projects",
] as const;
export const bankQuestionSchema = z.strictObject({
  id,
  version: z.number().int().positive(),
  level: levelSchema,
  topic: z.enum(bankTags),
  roleKeys: z.array(id).max(100),
  // 由内容审核登记；共享任一组的题不能出现在同一挑战中。
  exclusionGroupIds: z
    .array(id)
    .max(30)
    .refine((groups) => new Set(groups).size === groups.length, "同卷互斥组不能重复。")
    .optional(),
  question: questionSchema,
  references: unitSchema.shape.references,
  reviewNotes: z.string().trim().min(30).max(2000),
});
export type BankQuestion = z.infer<typeof bankQuestionSchema>;
export const bankBlueprintSchema = z.strictObject({
  id,
  title: z.string().trim().min(1).max(100),
  level: levelSchema,
  topic: z.enum(bankTags),
  prerequisiteGoalIds: z.array(id).max(30),
  estimatedMinutes: unitSchema.shape.estimatedMinutes.optional(),
  openingStory: z
    .strictObject({
      title: z.string().trim().min(1).max(100),
      scene: unitSchema.shape.scene,
      beats: unitSchema.shape.beats.refine(
        (beats) => beats.every((beat) => beat.afterQuestion === 0),
        "完整开场故事必须在所有题目之前。",
      ),
    })
    .optional(),
  slots: z
    .array(
      z.strictObject({
        goalId: id,
        type: z.enum([
          "choice",
          "listeningChoice",
          "arrange",
          "audioArrange",
          "completion",
          "dictation",
          "matching",
        ]),
      }),
    )
    .min(6)
    .max(18)
    .refine(
      (slots) => slots.length === 6 || slots.length === 18,
      "组卷必须为六题或十八题。",
    ),
});
export type BankBlueprint = z.infer<typeof bankBlueprintSchema>;
export type BankCandidate = BankQuestion & {
  seen: boolean;
  mastered: boolean;
  reviewDue?: boolean;
};

/** 内容身份不含题内局部编号和教学说明；同一材料换角色、换编号不会变成一道新题。 */
export function bankIdentity(question: LearningQuestion): string {
  const clean = (value: string) => value.normalize("NFKC").trim().replace(/\s+/g, " ");
  const text = (
    items: { id: string; text: string; imageAssetId?: string | undefined }[],
    key: string,
  ) => {
    const item = items.find((o) => o.id === key);
    return item ? { text: clean(item.text), image: item.imageAssetId ?? null } : key;
  };
  const materials = (
    items: { id: string; text: string; imageAssetId?: string | undefined }[],
  ) =>
    items
      .map((o) => text(items, o.id))
      .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  let material: unknown;
  if (question.type === "choice" || question.type === "listeningChoice") {
    material = {
      options: materials(question.options),
      audio: "audio" in question ? clean(question.audio.text) : null,
    };
  } else if (question.type === "arrange" || question.type === "audioArrange") {
    material =
      question.type === "audioArrange"
        ? { tokens: materials(question.tokens), audio: clean(question.audio.text) }
        : materials(question.tokens);
  } else if (question.type === "matching") {
    material = { left: materials(question.left), right: materials(question.right) };
  } else {
    material = { audio: "audio" in question ? clean(question.audio.text) : null };
  }
  return `question.${contentHash({ type: question.type, prompt: clean(question.prompt), material })}`;
}

/** 所有插槽都满足才交卷；不靠降级、重复题或少题凑齐。 */
export function assembleBankQuestions(
  blueprint: BankBlueprint,
  candidates: readonly BankCandidate[],
  roleKey: string,
  coveredGoals: ReadonlySet<string>,
  random: () => number = Math.random,
): BankQuestion[] | null {
  if (blueprint.prerequisiteGoalIds.some((goal) => !coveredGoals.has(goal)))
    return null;
  const pool = candidates.filter(
    (q) =>
      q.level === blueprint.level &&
      q.topic === blueprint.topic &&
      ((!q.seen && !q.mastered) || (q.mastered && q.reviewDue === true)) &&
      (q.roleKeys.length === 0 || q.roleKeys.includes(roleKey)),
  );
  const choices = blueprint.slots.map((slot) => {
    const matches = pool.filter(
      (q) => q.question.goalId === slot.goalId && q.question.type === slot.type,
    );
    // 保留新题优先；每个插槽只随机一次，回溯时不反复重抽同一候选。
    const fresh = matches.filter((q) => !q.mastered);
    const review = matches.filter((q) => q.mastered);
    const rotate = (items: BankCandidate[]) => {
      if (!items.length) return items;
      const start = Math.min(
        items.length - 1,
        Math.max(0, Math.floor(random() * items.length)),
      );
      return [...items.slice(start), ...items.slice(0, start)];
    };
    return [...rotate(fresh), ...rotate(review)];
  });
  if (choices.some((items) => items.length === 0)) return null;
  const used = new Set<string>();
  const selected: BankQuestion[] = [];
  // 互斥约束可能让前面的随机选择堵住后续插槽；有限回溯寻找完整合法试卷。
  let remainingVisits = 10_000;
  const fill = (slot: number): boolean => {
    if (slot === choices.length) return true;
    for (const candidate of choices[slot] ?? []) {
      if (--remainingVisits < 0) return false;
      if (used.has(candidate.id)) continue;
      if (
        selected.some((previous) =>
          candidate.exclusionGroupIds?.some((group) =>
            previous.exclusionGroupIds?.includes(group),
          ),
        )
      )
        continue;
      used.add(candidate.id);
      selected.push(candidate);
      if (fill(slot + 1)) return true;
      selected.pop();
      used.delete(candidate.id);
      if (remainingVisits < 0) return false;
    }
    return false;
  };
  return fill(0) ? selected : null;
}

const scenes = {
  daily: [
    "桌边的小计划",
    "桌上摊着几张便笺，你们开始整理今天的小安排。",
    "最后一张便笺收进了口袋，你们准备出发。",
  ],
  books: [
    "书页间的停留",
    "你们在阅读角坐下，翻开一本夹着便笺的小册子。",
    "小册子合上，书签留在了今天翻到的那一页。",
  ],
  community: [
    "街角的消息",
    "你们在社区留言板前停下，几张新卡片吸引了注意。",
    "街角渐渐热闹起来，你们把看过的卡片放回原处。",
  ],
  outdoors: [
    "出发前的片刻",
    "你们在窗边整理外出要用的小卡片，门外传来脚步声。",
    "卡片整理好了，你们带上随身的小包走向门口。",
  ],
  projects: [
    "工作台的一页",
    "你们在工作台前摊开资料，留出一块地方放新的便笺。",
    "资料放回文件夹，桌面上只留下一张下次见面的便笺。",
  ],
} as const;

const sceneLines = {
  daily: [
    ["Look! Some cards.", "看，有几张卡片。"],
    ["There are some cards on the table.", "桌上放着几张卡片。"],
    [
      "A few notes lie on the table, ready for the day's plans.",
      "几张便笺摊在桌上，等着安排今天的事情。",
    ],
  ],
  books: [
    ["Look! A book.", "看，一本书。"],
    ["You sit down with a little book.", "你们拿着一本小册子坐下。"],
    [
      "You find a quiet corner and open a booklet with handwritten notes.",
      "你们找到一个安静的角落，翻开夹着手写便笺的小册子。",
    ],
  ],
  community: [
    ["Look! New cards.", "看，新卡片。"],
    ["There are new cards on the board.", "留言板上有几张新卡片。"],
    [
      "You stop by a community noticeboard, where a few new cards catch your eye.",
      "你们在社区留言板前停下，几张新卡片吸引了注意。",
    ],
  ],
  outdoors: [
    ["Look! A bag.", "看，一个包。"],
    ["The bag is by the door. The cards are ready.", "包放在门边，卡片也准备好了。"],
    [
      "By the window, you sort through a few cards before heading out.",
      "出发前，你们在窗边整理几张卡片。",
    ],
  ],
  projects: [
    ["Look! Some pictures.", "看，几张图片。"],
    ["There are some pictures on the desk.", "桌上放着几张图片。"],
    [
      "You spread the papers across the worktable, leaving room for a fresh note.",
      "你们把资料摊在工作台上，留出地方放新的便笺。",
    ],
  ],
} as const;

/** 角色只担任同行者；题内具名人物与录音是材料中的第三人，不冒充当前角色。 */
export function bankUnit(
  blueprint: BankBlueprint,
  questions: readonly BankQuestion[],
  identity: string,
  roleKey: string,
  name: string,
): LearningUnit {
  const scene = scenes[blueprint.topic];
  const simple =
    blueprint.level.startsWith("primary") || blueprint.level === "kindergarten";
  const tier = ["kindergarten", "primary1", "primary2"].includes(blueprint.level)
    ? 0
    : simple
      ? 1
      : 2;
  const opening = sceneLines[blueprint.topic][tier];
  const ending =
    tier === 0
      ? ["Time to go!", "该出发了！"]
      : tier === 1
        ? ["The cards are in the bag. Let's go!", "卡片放进包里了，我们走吧！"]
        : [
            "You put the last card away and leave a note for next time.",
            "你们收起最后一张卡片，为下次见面留下一张便笺。",
          ];
  const references = [
    ...new Map(
      questions.flatMap((q) => q.references).map((r) => [contentHash(r), r]),
    ).values(),
  ];
  return unitSchema.parse({
    id: identity,
    version: 1,
    schemaVersion: 1,
    scoringVersion: 1,
    roleKey,
    roleVersion: 1,
    level: blueprint.level,
    title: blueprint.title,
    summary: blueprint.openingStory?.title ?? scene[0],
    scene: blueprint.openingStory?.scene ?? scene[1],
    estimatedMinutes: blueprint.estimatedMinutes ?? (questions.length > 6 ? 12 : 6),
    goalIds: [...new Set(questions.map((q) => q.question.goalId))],
    prerequisiteGoalIds: blueprint.prerequisiteGoalIds,
    references,
    authorship: {
      kind: "authored",
      author: "公共题库",
      reviewedBy: "已审核题目与开场情景",
      reviewedAt: "2026-10-07",
      reviewNotes:
        "题目来自已审核版本，剧情仅提供共同场景；本次组卷固定题目版本、顺序与首次得分身份。",
    },
    beats: blueprint.openingStory?.beats ?? [
      {
        id: "opening",
        afterQuestion: 0,
        speaker: "旁白",
        text: opening[0],
        translation: opening[1],
      },
      {
        id: "pause",
        afterQuestion: 3,
        speaker: name.slice(0, 60) || "同行者",
        text:
          tier === 0
            ? "Look!"
            : simple
              ? "Let's look at the next card."
              : "There is another card underneath. Let's take a look.",
        translation: tier === 0 ? "看这里！" : "下面还有一张卡片，我们看看。",
      },
      {
        id: "ending",
        afterQuestion: 6,
        speaker: "旁白",
        text: ending[0],
        translation: ending[1],
      },
    ],
    questions: questions.map((q) => ({ ...q.question, id: q.id })),
  });
}
