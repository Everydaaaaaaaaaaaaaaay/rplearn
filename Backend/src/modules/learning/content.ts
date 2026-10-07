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
const baseQuestion = {
  id: identifier,
  goalId: identifier,
  instruction: text,
  prompt: text,
  explanation: text,
  hint: text,
  difficultyReason: text,
};

export const questionSchema = z.discriminatedUnion("type", [
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
      if (question.type === "choice" || question.type === "listeningChoice") {
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
          question.left.length !== question.right.length ||
          question.left.length !== question.answerPairs.length
        ) {
          fail("配对必须完整覆盖左右两侧。");
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
    case "completion":
      return common;
    case "dictation":
      return { ...common, audio: { assetId: question.audio.assetId } };
  }
}

export function questionImageIds(question: LearningQuestion): string[] {
  const options =
    question.type === "choice" || question.type === "listeningChoice"
      ? question.options
      : question.type === "matching"
        ? [...question.left, ...question.right]
        : [];
  return [
    ...new Set(
      options.flatMap((option) => (option.imageAssetId ? [option.imageAssetId] : [])),
    ),
  ];
}

export function publicUnit(unit: LearningUnit) {
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
    questions: unit.questions.map(publicQuestion),
  };
}
