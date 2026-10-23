import { createHash } from "node:crypto";

/** Canonical serialisation shared by frozen content and presentation bindings. */
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
