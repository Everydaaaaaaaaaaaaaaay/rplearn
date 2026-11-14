import test from "node:test";
import assert from "node:assert/strict";
import { projectActivityStory } from "./activity-world-editorial.mjs";

const story = {
  background: "Generated biography",
  migrationExplanationZh: "Old draft notice",
  nodes: [
    { id: "start", beats: [{ english: "First encounter", chinese: "初遇" }] },
  ],
  causality: {
    presenceReason: "An independent errand",
    reunionCommonFacts: "Met at the new cafe",
  },
  reunion: {
    titleZh: "再遇",
    beats: [
      {
        speaker: "narrator",
        english: "On another visit to the same cafe, Alex looks up.",
        chinese: "另一次来到咖啡馆时，Alex抬起头。",
      },
      {
        speaker: "npc",
        english: "Hello again. The same tea, please.",
        chinese: "又见面了。请给我同样的茶。",
      },
    ],
  },
};
const originalCard = { name: "Alex", background: "Original biography" };
const binding = {
  preserveOriginalBackground: true,
  migrationExplanationZh: "明确的资料修订",
};

test("projects the canonical biography and notice without mutating the candidate", () => {
  const projected = projectActivityStory(story, {
    originalCard,
    binding,
    placeTitleZh: "咖啡馆",
  });
  assert.equal(projected.background, "Original biography");
  assert.equal(
    projected.migrationExplanationZh,
    binding.migrationExplanationZh,
  );
  assert.equal(story.background, "Generated biography");
  assert.deepEqual(projected.nodes, story.nodes);
  assert.equal(
    projected.causality.presenceReason,
    story.causality.presenceReason,
  );
});

test("reunion context works for contacts first met at a legacy place", () => {
  const projected = projectActivityStory(story, {
    originalCard,
    binding,
    placeTitleZh: "咖啡馆",
  });
  assert.equal(
    projected.reunion.beats[0].english,
    "At the cafe, Alex looks up.",
  );
  assert.equal(projected.reunion.beats[0].chinese, "在咖啡馆，Alex抬起头。");
  assert.match(projected.causality.reunionCommonFacts, /旧活动联系人/);
  assert.equal(
    projected.reunion.beats[1].english,
    story.reunion.beats[1].english,
  );
});

test("preserves an explicitly revised biography and non-temporal captions", () => {
  const current = structuredClone(story);
  current.reunion.beats[0].english = "At the market, Alex waits.";
  current.reunion.beats[0].chinese = "在市场，Alex等着。";
  const projected = projectActivityStory(current, {
    originalCard,
    binding: {},
    placeTitleZh: "市场",
  });
  assert.equal(projected.background, current.background);
  assert.equal(
    projected.migrationExplanationZh,
    current.migrationExplanationZh,
  );
  assert.deepEqual(projected.reunion, current.reunion);
});

test("normalizes authored causal prose while preserving original biography wording", () => {
  const current = structuredClone(story);
  current.causality.currentState = "平时健谈；今天疲倦";
  const original = { ...originalCard, background: "Original; biography" };
  const projected = projectActivityStory(current, {
    originalCard: original,
    binding,
    placeTitleZh: "咖啡馆",
  });
  assert.equal(projected.causality.currentState, "平时健谈。今天疲倦");
  assert.equal(projected.background, original.background);
  assert.equal(current.causality.currentState, "平时健谈；今天疲倦");
});
