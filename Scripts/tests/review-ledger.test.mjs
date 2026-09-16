import test from "node:test";
import assert from "node:assert/strict";
import { replayReview } from "../../docs/learning-program/prototypes/review-ledger.mjs";
const event = (eventID, kind, extra = {}) => ({
  eventID,
  kind,
  itemID: "cosy",
  attemptID: "attempt-cosy",
  ...extra,
});
const reveal = event("show", "reveal");
const rate = event("rate", "rate", { rating: "forgot" });
const undo = event("undo", "undo", { targetEventID: "rate" });

test("retry is idempotent even when property order differs", () => {
  const result = replayReview([
    reveal,
    rate,
    { ...rate },
    {
      rating: "forgot",
      kind: "rate",
      itemID: "cosy",
      attemptID: "attempt-cosy",
      eventID: "rate",
    },
  ]);
  assert.equal(result.activeRatings.length, 1);
});
test("same event ID cannot change its meaning", () => {
  assert.throws(
    () => replayReview([reveal, rate, { ...rate, rating: "remembered" }]),
    /Conflicting/,
  );
});
test("undo preserves exposure and hint and correction is still one attempt", () => {
  const result = replayReview([
    event("hint", "hint"),
    reveal,
    rate,
    undo,
    event("correct", "rate", { rating: "remembered" }),
  ]);
  assert.equal(result.attempts.size, 1);
  assert.equal(result.attempts.get("attempt-cosy").answerExposed, true);
  assert.equal(result.activeRatings.length, 1);
  assert.deepEqual(result.activeRatings[0], {
    eventID: "correct",
    attemptID: "attempt-cosy",
    itemID: "cosy",
    rating: "remembered",
    hintUsed: true,
    corrected: true,
  });
});
test("repeated undo does not cancel the corrected rating", () => {
  const result = replayReview([
    reveal,
    rate,
    undo,
    event("correct", "rate", { rating: "fuzzy" }),
    event("undo-again", "undo", { targetEventID: "rate" }),
  ]);
  assert.equal(result.activeRatings[0].rating, "fuzzy");
});
test("invalid actions fail instead of silently changing counts", () => {
  assert.throws(() => replayReview([rate]), /Reveal/);
  assert.throws(
    () =>
      replayReview([
        reveal,
        rate,
        event("twice", "rate", { rating: "remembered" }),
      ]),
    /Undo/,
  );
  assert.throws(
    () =>
      replayReview([
        reveal,
        rate,
        event("wrong", "undo", { targetEventID: "missing" }),
      ]),
    /Invalid undo/,
  );
  assert.throws(
    () => replayReview([reveal, event("bad", "rate", { rating: "mastered" })]),
    /Invalid rating/,
  );
});
test("undo cannot affect a different attempt or swap its material", () => {
  assert.throws(
    () => replayReview([reveal, rate, { ...undo, attemptID: "other" }]),
    /Invalid undo/,
  );
  assert.throws(
    () => replayReview([reveal, { ...rate, itemID: "unwind" }]),
    /changed material/,
  );
});
test("ending without rating preserves exposure but adds no completed item", () => {
  const result = replayReview([reveal]);
  assert.equal(result.activeRatings.length, 0);
  assert.equal(result.attempts.get("attempt-cosy").answerExposed, true);
});
