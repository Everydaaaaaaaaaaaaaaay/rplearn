import type { ContentRecord } from "../content/types.js";

export type Attention = "focused" | "online" | "recentlyActive" | "offline";
export interface ReplyPlan {
  userMessageId: string;
  attention: Attention;
  noticedAt: number;
  generationStartsAt: number;
  typingStartsAt: number;
  firstBubbleAt: number;
  continuingConversation: boolean;
}
export interface ComposerLease {
  sequence: number;
  until: number;
}
export interface ReplySimulation {
  plan: ReplyPlan;
  quietUntil: number;
  preparationMilliseconds?: number;
  latestUserMessageId?: string;
  composers: Record<string, ComposerLease>;
  resumeTypingAt: number;
  preparedText?: string;
  fragments?: string[];
  deliveredCount?: number;
  nextDeliveryAt?: number;
}

// Mirrors NPCAttentionPolicy and RoleplayTurnTakingPolicy for the durable producer.
const zones: Record<string, string> = {
  london: "Europe/London",
  melbourne: "Australia/Melbourne",
  newyork: "America/New_York",
  capetown: "Africa/Johannesburg",
  singapore: "Asia/Singapore",
  dublin: "Europe/Dublin",
  edinburgh: "Europe/London",
  vancouver: "America/Vancouver",
  auckland: "Pacific/Auckland",
  nairobi: "Africa/Nairobi",
  toronto: "America/Toronto",
  sydney: "Australia/Sydney",
  neworleans: "America/Chicago",
  manchester: "Europe/London",
  kingston: "America/Jamaica",
};
type Rhythm = "earlyBird" | "daytime" | "nightOwl" | "irregular";
function stable(id: string, bucket: number, salt: string): number {
  let hash = 14695981039346656037n;
  for (const byte of new TextEncoder().encode(
    `${id.toLowerCase()}|${bucket.toString()}|${salt}`,
  )) {
    hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * 1099511628211n);
  }
  return Number(hash % 1000001n) / 1000000;
}
function sample(
  range: readonly [number, number],
  id: string,
  salt: string,
  early = false,
): number {
  const center = (stable(id, 0, `${salt}-a`) + stable(id, 0, `${salt}-b`)) / 2;
  return (range[0] + (range[1] - range[0]) * (early ? center ** 1.65 : center)) * 1000;
}
function activity(character: ContentRecord) {
  const payload = character.payload as Record<string, unknown>;
  const card = (payload.card ?? {}) as Record<string, unknown>;
  const explicit = card.activityProfile as
    | { timeZoneIdentifier?: string; rhythm?: Rhythm; focusDurationMinutes?: number }
    | undefined;
  let zone =
    explicit?.timeZoneIdentifier ??
    zones[typeof card.regionId === "string" ? card.regionId.toLowerCase() : ""] ??
    "Etc/UTC";
  try {
    new Intl.DateTimeFormat("en", { timeZone: zone }).format();
  } catch {
    zone = "Etc/UTC";
  }
  const identity = [card.occupation, card.personality, card.background]
    .join(" ")
    .toLowerCase();
  const words = new Set(identity.split(/[^\p{L}]+/u));
  const matches = (signals: string[]) =>
    signals.some((signal) =>
      Buffer.byteLength(signal, "utf8") === signal.length
        ? words.has(signal)
        : identity.includes(signal),
    );
  const rhythm =
    explicit?.rhythm ??
    (matches([
      "night",
      "late",
      "jazz",
      "club",
      "bartender",
      "pub",
      "夜",
      "酒吧",
      "夜班",
      "爵士",
    ])
      ? "nightOwl"
      : matches([
            "barista",
            "bakery",
            "teacher",
            "farmer",
            "surf",
            "咖啡师",
            "烘焙",
            "教师",
            "农",
            "冲浪",
          ])
        ? "earlyBird"
        : "daytime");
  return {
    zone,
    rhythm,
    focusMinutes: Math.min(12, Math.max(4, explicit?.focusDurationMinutes ?? 7)),
    metAt: Date.parse(String(payload.metAt)),
  };
}
function probability(rhythm: Rhythm, hour: number, weekend: boolean): number {
  const schedules: Record<Rhythm, readonly (readonly [number, number])[]> = {
    earlyBird: [
      [5, 0.02],
      [7, 0.18],
      [12, 0.68],
      [18, 0.58],
      [22, 0.32],
      [24, 0.07],
    ],
    daytime: [
      [6, 0.025],
      [9, 0.16],
      [12, 0.58],
      [14, 0.42],
      [19, 0.66],
      [23, 0.38],
      [24, 0.08],
    ],
    nightOwl: [
      [2, 0.42],
      [7, 0.045],
      [11, 0.1],
      [17, 0.4],
      [21, 0.58],
      [24, 0.72],
    ],
    irregular: [
      [1, 0.18],
      [6, 0.055],
      [10, 0.22],
      [18, 0.5],
      [24, 0.54],
    ],
  };
  const base = schedules[rhythm].find(([end]) => hour < end)?.[1] ?? 0.18;
  return Math.min(0.82, base + (weekend && hour >= 9 ? 0.06 : 0));
}
const clockFormatters = new Map<string, Intl.DateTimeFormat>();
function localClock(at: number, zone: string) {
  let formatter = clockFormatters.get(zone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: zone,
      year: "numeric",
      month: "numeric",
      day: "numeric",
      weekday: "short",
      hour: "numeric",
      minute: "numeric",
      hourCycle: "h23",
      timeZoneName: "longOffset",
    });
    clockFormatters.set(zone, formatter);
  }
  const parts = formatter.formatToParts(at);
  const value = (key: Intl.DateTimeFormatPartTypes) =>
    parts.find((p) => p.type === key)?.value ?? "0";
  const offsetMinutes = (parts: Intl.DateTimeFormatPart[]) => {
    const offset = /GMT([+-])(\d+):(\d+)/.exec(
      parts.find((p) => p.type === "timeZoneName")?.value ?? "GMT",
    );
    return offset
      ? (Number(offset[2]) * 60 + Number(offset[3])) * (offset[1] === "-" ? -1 : 1)
      : 0;
  };
  const localDay = Date.UTC(
    Number(value("year")),
    Number(value("month")) - 1,
    Number(value("day")),
  );
  let midnight = localDay - offsetMinutes(parts) * 60_000;
  // Re-evaluate the offset at midnight across daylight-saving transitions.
  midnight = localDay - offsetMinutes(formatter.formatToParts(midnight)) * 60_000;
  return {
    hour: Number(value("hour")) + Number(value("minute")) / 60,
    day: Math.trunc(midnight / 86_400_000),
    weekend: ["Sat", "Sun"].includes(value("weekday")),
  };
}
function scheduledAttention(
  id: string,
  at: number,
  profile: ReturnType<typeof activity>,
): Attention {
  const boundary = (bucket: number) =>
    bucket * 1_800_000 + (stable(id, bucket, "boundary") * 2 - 1) * 720_000;
  const online = (bucket: number) => {
    const date = boundary(bucket);
    const local = localClock(date, profile.zone);
    const hour = (local.hour + stable(id, local.day, "daily-rhythm") * 2 - 1 + 24) % 24;
    return (
      stable(id, Math.trunc(date / 1_800_000), "presence") <
      probability(profile.rhythm, hour, local.weekend)
    );
  };
  let bucket = Math.floor(at / 1_800_000);
  while (boundary(bucket) > at) bucket -= 1;
  while (boundary(bucket + 1) <= at) bucket += 1;
  if (online(bucket)) return "online";
  for (let offset = 1; offset <= 96; offset += 1) {
    if (online(bucket - offset))
      return at - boundary(bucket - offset + 1) < 1_800_000
        ? "recentlyActive"
        : "offline";
  }
  return "offline";
}
export function replyPlan(
  character: ContentRecord,
  latest: Pick<ContentRecord, "resourceId" | "payload">,
  history: Pick<ContentRecord, "resourceId" | "payload">[],
  now: number,
): ReplyPlan {
  const profile = activity(character);
  const payload = latest.payload as { createdAt: string; orderIndex: number };
  const sentAt = Math.min(now, Date.parse(payload.createdAt));
  const previous = history
    .filter((m) => {
      const p = m.payload as { role?: string; orderIndex?: number };
      return p.role === "assistant" && Number(p.orderIndex) < payload.orderIndex;
    })
    .at(-1);
  const elapsed = previous
    ? sentAt - Date.parse((previous.payload as { createdAt: string }).createdAt)
    : Infinity;
  const continuingConversation =
    elapsed >= 0 && elapsed <= profile.focusMinutes * 60_000;
  const welcome = sentAt - profile.metAt;
  const welcomeOnline =
    welcome >= 0 &&
    welcome <=
      1_200_000 +
        stable(character.resourceId, Math.trunc(profile.metAt / 1000), "welcome") *
          900_000;
  const attention =
    continuingConversation || welcomeOnline
      ? "focused"
      : scheduledAttention(character.resourceId, sentAt, profile);
  const ranges: Record<Attention, readonly [number, number]> = {
    focused: [3, 7],
    online: [8, 22],
    recentlyActive: [20, 45],
    offline: [60, 300],
  };
  const firstDelay = sample(
    ranges[attention],
    latest.resourceId,
    "first-bubble",
    attention === "offline",
  );
  const leadRange: readonly [number, number] =
    attention === "focused" ? [1.2, 2.8] : attention === "online" ? [2, 4.5] : [2.5, 6];
  const lead = Math.min(
    sample(leadRange, latest.resourceId, "typing-lead"),
    Math.max(800, firstDelay - 500),
  );
  const typingStartsAt = continuingConversation
    ? sentAt + sample([3, 4], latest.resourceId, "focused-typing-start")
    : sentAt + firstDelay - lead;
  const noticedAt =
    attention === "focused" || attention === "online"
      ? sentAt
      : Math.max(
          sentAt,
          typingStartsAt - sample([1.2, 4.5], latest.resourceId, "noticed"),
        );
  const generationCandidate =
    attention === "focused"
      ? sentAt + Math.min(1200, firstDelay * 0.3)
      : attention === "online"
        ? sentAt + Math.min(3200, firstDelay * 0.35)
        : noticedAt + 200;
  return {
    userMessageId: latest.resourceId,
    attention,
    noticedAt,
    generationStartsAt: Math.max(
      noticedAt,
      Math.min(generationCandidate, typingStartsAt - 200),
    ),
    typingStartsAt,
    firstBubbleAt: Math.max(sentAt + firstDelay, typingStartsAt + lead),
    continuingConversation,
  };
}
export function quietWindow(text: string, count: number, continuing: boolean): number {
  const trimmed = text.trim().replace(/["'”’\])}]+$/u, "");
  const lastWord =
    trimmed
      .toLowerCase()
      .split(/[^\p{L}]+/u)
      .at(-1) ?? "";
  const open =
    /[,;:—\-…]$/u.test(trimmed) ||
    (!/[.?!。？！]$/u.test(trimmed) &&
      (!lastWord ||
        [
          "and",
          "but",
          "because",
          "if",
          "or",
          "so",
          "then",
          "though",
          "when",
          "while",
        ].includes(lastWord)));
  const target =
    (continuing ? 3 : 8) +
    Math.min(text.trim().split(/\s+/).filter(Boolean).length * 0.045, 0.75) +
    Math.min(Math.max(0, count - 1) * 0.32, 0.96) +
    (open ? 0.7 : 0);
  return Math.min(continuing ? 4 : 9, Math.max(continuing ? 3 : 8, target)) * 1000;
}
export function handoffAt(simulation: ReplySimulation): number {
  return Math.max(
    simulation.quietUntil,
    ...Object.values(simulation.composers).map((lease) => lease.until),
  );
}
export function generationEligibleAt(simulation: ReplySimulation): number {
  return Math.max(
    simulation.plan.generationStartsAt,
    handoffAt(simulation) + (simulation.preparationMilliseconds ?? 0),
  );
}
export function typingDuration(
  text: string,
  index: number,
  generationId?: string,
): number {
  const words = text.trim().split(/\s+/).filter(Boolean).length;
  const characters = Array.from(text.replace(/\s/gu, "")).length;
  const punctuation = Array.from(text).filter((c) => ",;:?!…—".includes(c)).length;
  return (
    Math.min(
      24,
      Math.max(
        1.2,
        0.65 +
          (index > 0 ? 0.25 : 0) +
          Math.max(words * 0.58, characters * 0.11) +
          punctuation * 0.1 +
          (generationId ? (stable(generationId, index, "typing-pace") - 0.5) * 0.6 : 0),
      ),
    ) * 1000
  );
}
export function visiblePhase(
  simulation: ReplySimulation | undefined,
  status: string,
  now: number,
): "waiting" | "preparing" | "yielding" | "typing" {
  if (!simulation) return status === "dispatched" ? "typing" : "waiting";
  if (now < handoffAt(simulation)) return "yielding";
  if (status === "queued") return "waiting";
  return now < Math.max(simulation.plan.typingStartsAt, simulation.resumeTypingAt)
    ? "preparing"
    : "typing";
}
