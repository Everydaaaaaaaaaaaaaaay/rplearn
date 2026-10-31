import { AppError } from "../../shared/errors.js";
import type { OutingOperation, OutingSnapshot } from "./outing-types.js";

export function outingConflict(message: string, details?: unknown): never {
  throw new AppError({ code: "OUTING_CONFLICT", message, statusCode: 409, details });
}

export function outingBeats(snapshot: OutingSnapshot) {
  return snapshot.mode === "reunion"
    ? (snapshot.story?.reunion.beats ?? [])
    : (snapshot.story?.nodes.find((node) => node.id === snapshot.nodeId)?.beats ?? []);
}

export function advanceOuting(
  snapshot: OutingSnapshot,
  operation: OutingOperation,
): OutingSnapshot {
  if (operation.expectedRevision !== snapshot.revision)
    outingConflict("这次外出已有更新，请恢复最新进度。", {
      revision: snapshot.revision,
    });
  if (snapshot.status === "completed" || snapshot.status === "abandoned")
    outingConflict("这次外出已经结束，可在足迹中回看。", { status: snapshot.status });
  const next = structuredClone(snapshot);
  if (operation.type === "abandon") next.status = "abandoned";
  else if (operation.type === "presented") {
    if (snapshot.status !== "reserved") outingConflict("开场已确认，无需重复结算。");
    if (
      snapshot.mode !== "solitude" &&
      snapshot.beatIndex !== outingBeats(snapshot).length - 1
    )
      outingConflict("请先读完开场，再继续这次相遇。");
    next.status = "opening_presented";
  } else if (operation.type === "read") {
    const beats = outingBeats(snapshot);
    if (
      snapshot.mode === "solitude" ||
      operation.beatIndex < 0 ||
      operation.beatIndex < snapshot.beatIndex ||
      operation.beatIndex > snapshot.beatIndex + 1 ||
      operation.beatIndex >= beats.length
    )
      outingConflict("阅读位置与已保存进度不一致。");
    next.beatIndex = operation.beatIndex;
  } else if (operation.type === "choice") {
    if (snapshot.status === "reserved" || snapshot.mode !== "first_meeting")
      outingConflict("当前没有可以提交的故事选择。");
    const node = snapshot.story?.nodes.find((item) => item.id === snapshot.nodeId);
    if (!node || snapshot.beatIndex !== node.beats.length - 1)
      outingConflict("请先读完当前段落。");
    const index = node.choices.findIndex(
      (_, offset) => `${node.id}:${String(offset)}` === operation.choiceId,
    );
    const choice = node.choices[index];
    if (!choice) outingConflict("这个选项不属于当前段落。");
    next.nodeId = choice.next;
    next.beatIndex = -1;
    next.choices.push(operation.choiceId);
    next.status = "in_progress";
  } else {
    const node = snapshot.story?.nodes.find((item) => item.id === snapshot.nodeId);
    if (
      snapshot.status === "reserved" ||
      (snapshot.mode !== "solitude" &&
        snapshot.beatIndex !== outingBeats(snapshot).length - 1) ||
      (snapshot.mode === "first_meeting" &&
        (node?.choices.length !== 0 || snapshot.choices.length !== 2))
    )
      outingConflict("这次外出尚未到达结尾。");
    next.status = "completed";
  }
  next.revision += 1;
  return next;
}

/** Probabilities never change city/place eligibility. Rolls are supplied once per reservation. */
export function chooseOutingCandidate<T extends { known: boolean; weight: number }>(
  candidates: readonly T[],
  quietStreak: number,
  familiarStreak: number,
  encounterRoll: number,
  discoveryRoll: number,
  candidateRoll: number,
): T | null {
  if (!candidates.length || (quietStreak < 2 && encounterRoll >= 0.85)) return null;
  const unseen = candidates.filter((person) => !person.known);
  const known = candidates.filter((person) => person.known);
  const pool =
    unseen.length && (familiarStreak >= 2 || !known.length || discoveryRoll < 0.75)
      ? unseen
      : known.length
        ? known
        : unseen;
  const weights = pool.map((person) =>
    person.known ? Math.max(0.02, person.weight) : 1,
  );
  const sum = weights.reduce((total, value) => total + value, 0);
  let remainder = Math.min(1 - Number.EPSILON, Math.max(0, candidateRoll)) * sum;
  for (const [index, person] of pool.entries()) {
    remainder -= weights[index] ?? 0;
    if (remainder < 0) return person;
  }
  return pool.at(-1) ?? null;
}
