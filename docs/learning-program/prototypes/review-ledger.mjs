// Executable single-session design prototype, not the production sync protocol.
export function replayReview(events) {
  const seen = new Map();
  const attempts = new Map();
  const ratings = new Map();
  const undone = new Set();
  for (const event of events) {
    const {
      eventID,
      attemptID,
      itemID,
      kind,
      rating = null,
      targetEventID = null,
    } = event;
    if (
      ![eventID, attemptID, itemID].every(
        (id) => typeof id === "string" && id.length,
      )
    ) {
      throw new Error("Missing event identity");
    }
    if (!["hint", "reveal", "rate", "undo"].includes(kind))
      throw new Error("Unknown event");
    // Fixed field order makes property order irrelevant to idempotent replay.
    const signature = JSON.stringify([
      attemptID,
      itemID,
      kind,
      rating,
      targetEventID,
    ]);
    if (seen.has(eventID)) {
      if (seen.get(eventID) !== signature)
        throw new Error("Conflicting event ID");
      continue;
    }
    seen.set(eventID, signature);
    let attempt = attempts.get(attemptID);
    if (!attempt) {
      attempt = {
        attemptID,
        itemID,
        hintUsed: false,
        answerExposed: false,
        corrected: false,
        activeRating: null,
      };
      attempts.set(attemptID, attempt);
    }
    if (attempt.itemID !== itemID) throw new Error("Attempt changed material");
    if (kind === "hint") attempt.hintUsed = true;
    if (kind === "reveal") attempt.answerExposed = true;
    if (kind === "rate") {
      if (!["forgot", "fuzzy", "remembered"].includes(rating))
        throw new Error("Invalid rating");
      if (!attempt.answerExposed) throw new Error("Reveal before self-rating");
      if (attempt.activeRating)
        throw new Error("Undo before correcting rating");
      const record = {
        eventID,
        attemptID,
        itemID,
        rating,
        hintUsed: attempt.hintUsed,
        corrected: attempt.corrected,
      };
      ratings.set(eventID, record);
      attempt.activeRating = record;
    }
    if (kind === "undo") {
      const target = ratings.get(targetEventID);
      if (!target || target.attemptID !== attemptID)
        throw new Error("Invalid undo target");
      // Repeated undo is harmless, including after a corrected rating exists.
      if (undone.has(targetEventID)) continue;
      undone.add(targetEventID);
      if (attempt.activeRating?.eventID === targetEventID)
        attempt.activeRating = null;
      attempt.corrected = true;
    }
  }
  return {
    attempts,
    activeRatings: [...ratings.values()].filter((r) => !undone.has(r.eventID)),
  };
}
