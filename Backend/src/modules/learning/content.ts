import { createHash } from "node:crypto";
import { z } from "zod";

export const levelKeys = [
  "kindergarten",
  "primary1",
  "primary2",
  "primary3",
  "primary4",
  "primary5",
  "primary6",
  "junior1",
  "junior2",
  "junior3",
  "senior1",
  "senior2",
  "senior3",
  "undergraduate",
  "postgraduate",
  "advanced",
] as const;
export const levelSchema = z.enum(levelKeys);
export type LearningLevel = z.infer<typeof levelSchema>;
const identifier = z.string().regex(/^[a-z][a-z0-9_.-]{0,119}$/);
const text = z.string().trim().min(1).max(1200);
const option = z.strictObject({
  id: identifier,
  text: text.max(240),
  imageAssetId: identifier.optional(),
});
const normalization = z.strictObject({
  ignoreCase: z.boolean(),
  ignoreTerminalPunctuation: z.boolean(),
});
export const clozeFillSchema = z.strictObject({
  slotId: identifier,
  tokenId: identifier,
});
/** 空位只能由显式标记声明，保持客户端呈现顺序与判题身份一致。 */
export function clozeSlotIds(passage: string): string[] {
  return [...passage.matchAll(/\{([a-z][a-z0-9_.-]{0,119})\}/gu)].map(
    (match) => match[1] ?? "",
  );
}
const baseQuestion = {
  id: identifier,
  goalId: identifier,
  instruction: text,
  prompt: text,
  explanation: text,
  hint: text,
  difficultyReason: text,
};
const audioReference = z.strictObject({
  assetId: identifier,
  text,
  voice: z.string().min(1).max(32),
});

export const questionSchema = z.discriminatedUnion("type", [
  z.strictObject({
    ...baseQuestion,
    type: z.literal("audioMatching"),
    audioOptions: z
      .array(z.strictObject({ id: identifier, audio: audioReference }))
      .min(2)
      .max(4),
    right: z
      .array(
        z.strictObject({
          ...option.shape,
          imageAssetId: identifier,
          caption: text.max(40).optional(),
        }),
      )
      .min(3)
      .max(5),
    answerPairs: z
      .array(z.strictObject({ left: identifier, right: identifier }))
      .min(2)
      .max(4),
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("audioChoice"),
    audioOptions: z
      .array(z.strictObject({ id: identifier, audio: audioReference }))
      .min(2)
      .max(5),
    answer: identifier,
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("cloze"),
    passage: text,
    tokens: z.array(option).min(2).max(12),
    acceptedFills: z.array(z.array(clozeFillSchema).min(2).max(6)).min(1).max(8),
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("choice"),
    options: z.array(option).min(2).max(5),
    answer: identifier,
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("listeningChoice"),
    options: z.array(option).min(2).max(5),
    answer: identifier,
    audio: z.strictObject({
      assetId: identifier,
      text,
      voice: z.string().min(1).max(32),
    }),
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("arrange"),
    tokens: z.array(option).min(2).max(18),
    acceptedOrders: z.array(z.array(identifier).min(2).max(18)).min(1).max(8),
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("audioArrange"),
    tokens: z.array(option).min(2).max(18),
    acceptedOrders: z.array(z.array(identifier).min(2).max(18)).min(1).max(8),
    audio: z.strictObject({
      assetId: identifier,
      text,
      voice: z.string().min(1).max(32),
    }),
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("completion"),
    acceptedAnswers: z.array(text.max(240)).min(1).max(12),
    normalization,
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("dictation"),
    audio: z.strictObject({
      assetId: identifier,
      text,
      voice: z.string().min(1).max(32),
    }),
    acceptedAnswers: z.array(text.max(240)).min(1).max(12),
    normalization,
  }),
  z.strictObject({
    ...baseQuestion,
    type: z.literal("matching"),
    left: z.array(option).min(2).max(5),
    right: z.array(option).min(2).max(5),
    answerPairs: z
      .array(z.strictObject({ left: identifier, right: identifier }))
      .min(2)
      .max(5),
  }),
]);
export type LearningQuestion = z.infer<typeof questionSchema>;

export const unitSchema = z
  .strictObject({
    id: identifier,
    version: z.number().int().min(1),
    schemaVersion: z.literal(1),
    scoringVersion: z.literal(1),
    roleKey: identifier,
    roleVersion: z.number().int().min(1),
    level: levelSchema,
    title: text.max(100),
    summary: text.max(300),
    scene: text.max(300),
    estimatedMinutes: z.number().int().min(2).max(20),
    goalIds: z.array(identifier).min(1).max(18),
    prerequisiteGoalIds: z.array(identifier).max(30),
    references: z
      .array(
        z.strictObject({
          sourceId: identifier,
          unit: text.max(200),
          pages: text.max(100),
          alignment: text.max(500),
        }),
      )
      .min(1)
      .max(48),
    authorship: z.strictObject({
      kind: z.enum(["authored", "generated"]),
      author: text.max(100),
      reviewedBy: text.max(100),
      reviewedAt: z.iso.date(),
      reviewNotes: text,
    }),
    beats: z
      .array(
        z.strictObject({
          id: identifier,
          afterQuestion: z.number().int().min(0).max(18),
          speaker: text.max(60),
          text: text.max(500),
          translation: text.max(500),
        }),
      )
      .min(2)
      .max(12),
    questions: z.array(questionSchema).min(4).max(18),
  })
  .superRefine((unit, context) => {
    const fail = (message: string) => context.addIssue({ code: "custom", message });
    const unique = (values: readonly string[], name: string) => {
      if (new Set(values).size !== values.length) fail(`${name}不能重复。`);
    };
    unique(
      unit.questions.map((q) => q.id),
      "题目标识",
    );
    unique(
      unit.beats.map((beat) => beat.id),
      "镜头标识",
    );
    unique(unit.goalIds, "学习目标");
    for (const goal of unit.goalIds) {
      if (!unit.questions.some((q) => q.goalId === goal))
        fail("每个学习目标必须有对应题目。");
    }
    for (const beat of unit.beats) {
      if (beat.afterQuestion > unit.questions.length) fail("镜头位置超过题目数量。");
    }
    if (!unit.beats.some((beat) => beat.afterQuestion === 0)) fail("单元必须有开场。");
    for (const question of unit.questions) {
      if (!unit.goalIds.includes(question.goalId)) fail("题目引用了未声明的学习目标。");
      if (question.type === "audioChoice" || question.type === "audioMatching") {
        unique(
          question.audioOptions.map((o) => o.id),
          "声音选项标识",
        );
        unique(
          question.audioOptions.map((o) => o.audio.assetId),
          "声音选项素材",
        );
        unique(
          question.audioOptions.map((o) => o.audio.text.trim().toLowerCase()),
          "声音选项原文",
        );
        if (
          question.type === "audioChoice" &&
          !question.audioOptions.some((o) => o.id === question.answer)
        )
          fail("正确答案必须是已有声音选项。");
        if (question.type === "audioMatching") {
          unique(
            question.right.map((o) => o.id),
            "图片选项标识",
          );
          unique(
            question.right.map((o) => [o.imageAssetId, o.caption ?? ""].join("/")),
            "图片选项内容",
          );
          unique(
            question.answerPairs.map((p) => p.left),
            "声音配对答案",
          );
          unique(
            question.answerPairs.map((p) => p.right),
            "图片配对答案",
          );
          if (
            question.right.length <= question.audioOptions.length ||
            question.answerPairs.length !== question.audioOptions.length
          )
            fail("声音配图必须覆盖全部声音，并保留至少一个干扰图片。");
          if (
            question.answerPairs.some(
              (p) =>
                !question.audioOptions.some((o) => o.id === p.left) ||
                !question.right.some((o) => o.id === p.right),
            )
          )
            fail("声音配图答案引用了不存在的选项。");
        }
      } else if (question.type === "choice" || question.type === "listeningChoice") {
        unique(
          question.options.map((o) => o.id),
          "选项标识",
        );
        unique(
          question.options.map((o) => o.text.trim().toLowerCase()),
          "选项文字",
        );
        if (!question.options.some((o) => o.id === question.answer))
          fail("正确答案必须是已有选项。");
      } else if (question.type === "arrange" || question.type === "audioArrange") {
        if (question.tokens.some((token) => token.imageAssetId))
          fail("词块组句只接收文字；图片请用于选择或配对。");
        unique(
          question.tokens.map((o) => o.id),
          "词块标识",
        );
        for (const order of question.acceptedOrders) {
          unique(order, "组句答案中的词块标识");
          if (order.some((id) => !question.tokens.some((token) => token.id === id))) {
            fail("组句答案包含不存在的词块。");
          }
        }
      } else if (question.type === "cloze") {
        const slots = clozeSlotIds(question.passage);
        if (slots.length < 2 || slots.length > 6)
          fail("多空填词必须包含二至六个空位。");
        if (/[{}]/u.test(question.passage.replace(/\{[a-z][a-z0-9_.-]{0,119}\}/gu, "")))
          fail("多空填词包含无效空位标记。");
        unique(slots, "空位标识");
        unique(
          question.tokens.map((token) => token.id),
          "词块标识",
        );
        unique(
          question.tokens.map((token) => token.text.trim().toLowerCase()),
          "词块文字",
        );
        if (question.tokens.some((token) => token.imageAssetId))
          fail("多空填词只接收文字词块。");
        for (const fills of question.acceptedFills) {
          unique(
            fills.map((fill) => fill.slotId),
            "答案空位",
          );
          unique(
            fills.map((fill) => fill.tokenId),
            "答案词块",
          );
          if (
            fills.length !== slots.length ||
            fills.some(
              (fill) =>
                !slots.includes(fill.slotId) ||
                !question.tokens.some((token) => token.id === fill.tokenId),
            )
          )
            fail("多空答案必须完整覆盖已有空位，且每个词块最多使用一次。");
        }
      } else if (question.type === "matching") {
        unique(
          question.left.map((o) => o.id),
          "左侧标识",
        );
        unique(
          question.right.map((o) => o.id),
          "右侧标识",
        );
        unique(
          question.answerPairs.map((p) => p.left),
          "左侧答案",
        );
        unique(
          question.answerPairs.map((p) => p.right),
          "右侧答案",
        );
        if (
          question.left.length > question.right.length ||
          question.left.length !== question.answerPairs.length
        ) {
          fail("配对必须覆盖全部左侧项目，右侧可保留干扰项。");
        }
        if (
          question.answerPairs.some(
            (p) =>
              !question.left.some((o) => o.id === p.left) ||
              !question.right.some((o) => o.id === p.right),
          )
        ) {
          fail("配对答案引用了不存在的项目。");
        }
      }
    }
  });
export type LearningUnit = z.infer<typeof unitSchema>;

/** 保持字段顺序无关，发布与幂等检查共用规范序列化。 */
export function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJSON(record[key])}`)
      .join(",")}}`;
  }
  const result: unknown = JSON.stringify(value);
  if (typeof result !== "string") throw new Error("学习合同不能包含不可序列化的字段。");
  return result;
}

export function contentHash(value: unknown): string {
  return createHash("sha256").update(canonicalJSON(value)).digest("hex");
}

/** 只投影白名单字段，防止新增私有答案字段时意外被传给客户端。 */
export function publicQuestion(question: LearningQuestion) {
  const common = {
    id: question.id,
    type: question.type,
    goalId: question.goalId,
    instruction: question.instruction,
    prompt: question.prompt,
    hint: question.hint,
  };
  switch (question.type) {
    case "audioMatching":
      return {
        ...common,
        audioOptions: question.audioOptions.map((o) => ({
          id: o.id,
          audio: { assetId: o.audio.assetId },
        })),
        right: question.right,
      };
    case "audioChoice":
      return {
        ...common,
        audioOptions: question.audioOptions.map((o) => ({
          id: o.id,
          audio: { assetId: o.audio.assetId },
        })),
      };
    case "choice":
      return { ...common, options: question.options };
    case "listeningChoice":
      return {
        ...common,
        options: question.options,
        audio: { assetId: question.audio.assetId },
      };
    case "arrange":
      return { ...common, tokens: question.tokens };
    case "audioArrange":
      return {
        ...common,
        tokens: question.tokens,
        audio: { assetId: question.audio.assetId },
      };
    case "matching":
      return { ...common, left: question.left, right: question.right };
    case "cloze":
      return { ...common, passage: question.passage, tokens: question.tokens };
    case "completion":
      return common;
    case "dictation":
      return { ...common, audio: { assetId: question.audio.assetId } };
  }
}

/** 包含独立声音选项；资源授权、发布和后台检查共用同一媒体集合。 */
export function questionAudios(question: LearningQuestion) {
  return question.type === "audioChoice" || question.type === "audioMatching"
    ? question.audioOptions.map((o) => o.audio)
    : "audio" in question
      ? [question.audio]
      : [];
}

export function questionImageIds(question: LearningQuestion): string[] {
  const options =
    question.type === "choice" || question.type === "listeningChoice"
      ? question.options
      : question.type === "audioMatching"
        ? question.right
        : question.type === "matching"
          ? [...question.left, ...question.right]
          : [];
  return [
    ...new Set(
      options.flatMap((option) => (option.imageAssetId ? [option.imageAssetId] : [])),
    ),
  ];
}

export function publicUnit(unit: LearningUnit, attemptId?: string) {
  return {
    id: unit.id,
    version: unit.version,
    schemaVersion: unit.schemaVersion,
    roleKey: unit.roleKey,
    level: unit.level,
    title: unit.title,
    summary: unit.summary,
    scene: unit.scene,
    estimatedMinutes: unit.estimatedMinutes,
    goalIds: unit.goalIds,
    beats: unit.beats,
    questions: unit.questions.map((question) => {
      const projected = publicQuestion(question);
      if (attemptId && "audioOptions" in projected) {
        // 挑战身份决定稳定的显示顺序；补答和重进不换编号，答案仍以选项身份判定。
        projected.audioOptions.sort((a, b) =>
          contentHash([attemptId, question.id, a.id]).localeCompare(
            contentHash([attemptId, question.id, b.id]),
          ),
        );
      }
      if (
        attemptId &&
        (question.type === "audioMatching" || question.type === "matching") &&
        "right" in projected
      ) {
        // 文字配对同样按题独立排列，避免连续题复用答案位置；保持左侧材料阅读顺序。
        const side = question.type === "audioMatching" ? "image" : "matching-right";
        projected.right = [...projected.right].sort((a, b) =>
          contentHash([attemptId, question.id, side, a.id]).localeCompare(
            contentHash([attemptId, question.id, side, b.id]),
          ),
        );
      }
      return projected;
    }),
  };
}
