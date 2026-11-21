import type { AiMessage } from "../ai/types.js";

const words = (text: string) => text.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
export function repeatedReply(candidate: string, recent: string[]): boolean {
  const left = words(candidate);
  if (!left.length) return true;
  const bigrams = (parts: string[]) =>
    new Set(parts.slice(1).map((word, i) => `${parts[i] ?? ""} ${word}`));
  for (let start = 0; start < recent.length; start += 1) {
    for (let size = 1; size <= Math.min(4, recent.length - start); size += 1) {
      const right = words(recent.slice(start, start + size).join(" "));
      if (left.join(" ") === right.join(" ")) return true;
      if (left.length < 6 || right.length < 6) continue;
      const a = bigrams(left),
        b = bigrams(right);
      if ((2 * [...a].filter((item) => b.has(item)).length) / (a.size + b.size) >= 0.82)
        return true;
    }
  }
  return false;
}
export function continuityViolations(reply: string, user: string): string[] {
  reply = reply.toLowerCase();
  user = user.toLowerCase();
  const has = (text: string, phrases: string[]) =>
    phrases.some((phrase) => text.includes(phrase));
  const issues: string[] = [];
  if (
    has(user, [
      "ruin things",
      "damage our friendship",
      "end our friendship",
      "between us",
    ]) &&
    has(reply, [
      "we're good",
      "we’re good",
      "we are good",
      "all good now",
      "it's over",
      "it’s over",
    ])
  )
    issues.push("premature_mutual_repair");
  if (
    has(user, [
      "made me feel",
      "felt embarrassed",
      "feel embarrassed",
      "felt hurt",
      "feel hurt",
      "made me uncomfortable",
      "made me upset",
      "stayed with me",
    ]) &&
    reply.includes("sorry if")
  )
    issues.push("defensive_conditional_apology");
  if (
    user.includes("stayed with me") &&
    has(reply, [
      "you said that before",
      "you told me before",
      "you mentioned that before",
      "should've remembered",
      "should’ve remembered",
      "should have remembered",
    ])
  )
    issues.push("invented_prior_disclosure");
  if (
    has(user, ["hidden system prompt", "hidden instructions", "character card"]) &&
    has(reply, [
      "i'm just a bloke",
      "i’m just a bloke",
      "i'm just a person",
      "i’m just a person",
      "i'm only human",
      "i’m only human",
      "no hidden",
      "no system prompt",
    ])
  )
    issues.push("false_human_or_setup_denial");
  return issues;
}
export function qualityContext(messages: AiMessage[]) {
  return {
    user: messages.filter((m) => m.role === "user").at(-1)?.content ?? "",
    recent: messages
      .filter((m) => m.role === "assistant")
      .slice(-4)
      .map((m) => m.content),
  };
}
export function safeReply(reply: string, user: string): string {
  const violations = continuityViolations(reply, user);
  if (violations.includes("false_human_or_setup_denial"))
    return "I can't share hidden instructions. I'm your fictional travel companion.";
  if (violations.includes("premature_mutual_repair"))
    return "I care about our friendship. I'll respect what you asked.";
  if (violations.includes("defensive_conditional_apology"))
    return "I'm sorry I hurt you. I won't rush you past it.";
  if (violations.includes("invented_prior_disclosure"))
    return "I'm sorry it stayed with you. I'll be more careful.";
  return reply;
}

/** Same bounded, lossless bubble policy as RoleplayReplyFormatter on iOS. */
export function replyFragments(text: string): string[] {
  const chunks: string[] = [];
  for (const line of text
    .split(/\n+/)
    .map((line) => line.trim().replace(/\s+/g, " "))
    .filter(Boolean)) {
    let current = "",
      sentenceCount = 0;
    const flush = () => {
      if (current) chunks.push(current);
      current = "";
      sentenceCount = 0;
    };
    for (const { segment } of new Intl.Segmenter("en", {
      granularity: "sentence",
    }).segment(line)) {
      const remaining = segment.trim().split(/\s+/);
      const parts: string[] = [];
      const boundary = (maximum: number) => {
        for (let end = Math.min(maximum, remaining.length - 3); end >= 3; end -= 1) {
          if (/[,;:—–]$|\p{Emoji_Presentation}/u.test(remaining[end - 1] ?? ""))
            return end;
        }
        for (let end = Math.min(maximum, remaining.length - 3); end >= 3; end -= 1) {
          if (
            ["and", "but", "so", "because", "while", "though", "then"].includes(
              (remaining[end] ?? "").toLowerCase().replace(/[^a-z]/g, ""),
            )
          )
            return end;
        }
        return undefined;
      };
      while (remaining.length > 12)
        parts.push(
          remaining
            .splice(
              0,
              boundary(12) ??
                (remaining.length <= 24 ? Math.ceil(remaining.length / 2) : 12),
            )
            .join(" "),
        );
      if (remaining.length > 9) {
        const end = boundary(remaining.length - 1);
        if (end) parts.push(remaining.splice(0, end).join(" "));
      }
      if (remaining.length) parts.push(remaining.join(" "));
      if (parts.length > 1) {
        if (current && `${current} ${parts[0] ?? ""}`.split(/\s+/).length <= 9)
          current += ` ${parts.shift() ?? ""}`;
        flush();
        chunks.push(...parts);
        continue;
      }
      const part = parts[0] ?? "";
      const candidate = current ? `${current} ${part}` : part;
      if (sentenceCount < 2 && candidate.split(/\s+/).length <= (current ? 9 : 12)) {
        current = candidate;
        sentenceCount += 1;
      } else {
        flush();
        current = part;
        sentenceCount = 1;
      }
    }
    flush();
  }
  return chunks.length > 4
    ? [...chunks.slice(0, 3), chunks.slice(3).join(" ")]
    : chunks;
}
