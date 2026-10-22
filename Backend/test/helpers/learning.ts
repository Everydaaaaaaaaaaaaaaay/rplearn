import type { LearningUnit } from "../../src/modules/learning/content.js";

/** 仅用于合同与事务测试，不能导入正式题库。 */
export function learningFixture(id = "test.unit-one"): LearningUnit {
  const common = {
    goalId: "test.greetings",
    instruction: "按题目要求作答。",
    prompt: "选择合适的表达。",
    explanation: "测试解析：检查目标表达。",
    hint: "注意题目中的关键词。",
    difficultyReason: "仅供程序测试。",
  };
  return {
    id,
    version: 1,
    schemaVersion: 1,
    scoringVersion: 1,
    roleKey: "oliver",
    roleVersion: 1,
    level: "primary3",
    title: "测试单元",
    summary: "仅供隔离测试。",
    scene: "测试场景",
    estimatedMinutes: 5,
    goalIds: ["test.greetings"],
    prerequisiteGoalIds: [],
    references: [
      {
        sourceId: "test.source",
        unit: "测试",
        pages: "无",
        alignment: "仅供程序测试。",
      },
    ],
    authorship: {
      kind: "authored",
      author: "程序测试",
      reviewedBy: "程序测试",
      reviewedAt: "2026-09-26",
      reviewNotes: "不是教学内容。",
    },
    beats: [
      {
        id: "intro",
        afterQuestion: 0,
        speaker: "Oliver",
        text: "Hello!",
        translation: "你好！",
      },
      {
        id: "outro",
        afterQuestion: 6,
        speaker: "Oliver",
        text: "See you!",
        translation: "再见！",
      },
    ],
    questions: [
      {
        ...common,
        id: "q.choice",
        type: "choice",
        options: [
          { id: "hello", text: "Hello!" },
          { id: "bye", text: "Goodbye!" },
        ],
        answer: "hello",
      },
      {
        ...common,
        id: "q.listen",
        type: "listeningChoice",
        options: [
          { id: "tea", text: "tea" },
          { id: "water", text: "water" },
        ],
        answer: "water",
        audio: { assetId: "test.water", text: "Water, please.", voice: "M5" },
      },
      {
        ...common,
        id: "q.arrange",
        type: "arrange",
        tokens: [
          { id: "i", text: "I" },
          { id: "am", text: "am" },
          { id: "name", text: "Oliver" },
        ],
        acceptedOrders: [["i", "am", "name"]],
      },
      {
        ...common,
        id: "q.complete",
        type: "completion",
        acceptedAnswers: ["I'm Oliver", "I am Oliver"],
        normalization: { ignoreCase: true, ignoreTerminalPunctuation: true },
      },
      {
        ...common,
        id: "q.dictate",
        type: "dictation",
        acceptedAnswers: ["Hello"],
        normalization: { ignoreCase: false, ignoreTerminalPunctuation: false },
        audio: { assetId: "test.hello", text: "Hello", voice: "M5" },
      },
      {
        ...common,
        id: "q.match",
        type: "matching",
        left: [
          { id: "hello", text: "Hello" },
          { id: "bye", text: "Goodbye" },
        ],
        right: [
          { id: "greeting", text: "问候" },
          { id: "farewell", text: "告别" },
        ],
        answerPairs: [
          { left: "hello", right: "greeting" },
          { left: "bye", right: "farewell" },
        ],
      },
    ],
  };
}

/** Fresh supply uses bounded word completion; legacy dictation fixtures remain above for history/grading tests. */
export function freshLearningFixture(id = "test.unit-one"): LearningUnit {
  const unit = learningFixture(id);
  unit.questions = unit.questions.map((q) =>
    q.type === "dictation" ? { ...q, type: "listeningCompletion", wordLimit: 1 } : q,
  );
  return unit;
}
