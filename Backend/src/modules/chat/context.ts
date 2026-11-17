import { z } from "zod";
import type { ContentRecord } from "../content/types.js";

export function historyWindow(tier: unknown, voice: boolean): number {
  const count = tier === "pro" ? 40 : tier === "plus" ? 24 : 12;
  return voice ? Math.min(12, count) : count;
}
const memoryPrefix = "@lingotrip-memory-v2:";
const factSchema = z.object({
  key: z.string(),
  text: z.string(),
  archived: z.boolean().optional(),
  forgotten: z.boolean().optional(),
  edited: z.boolean().optional(),
  status: z.string().optional(),
  eventDate: z.string().optional(),
  observedAt: z.string().optional(),
});
interface Note {
  id: string;
  date: string;
  text: string;
  tier: string;
  importance: number;
  source?: string;
  fact?: z.infer<typeof factSchema>;
}
export function memoryNotes(memories: ContentRecord[]) {
  const notes: Note[] = [];
  for (const memory of memories) {
    const payload = memory.payload as {
      content?: string;
      createdAt?: string;
      tier?: string;
      importance?: number;
      source?: string;
    };
    if (!payload.content || memory.deletedAt) continue;
    let fact: z.infer<typeof factSchema> | undefined;
    if (payload.content.startsWith(memoryPrefix)) {
      try {
        fact = factSchema.parse(JSON.parse(payload.content.slice(memoryPrefix.length)));
      } catch {
        continue;
      }
    }
    notes.push({
      id: memory.resourceId,
      date: fact?.observedAt ?? payload.createdAt ?? memory.createdAt,
      text: fact?.text ?? payload.content,
      tier: payload.tier ?? "long",
      importance: payload.importance ?? 1,
      ...(payload.source ? { source: payload.source } : {}),
      ...(fact ? { fact } : {}),
    });
  }
  const cutoff = notes
    .filter((n) => n.fact?.forgotten === true || n.fact?.edited === true)
    .map((n) => n.date)
    .sort()
    .at(-1);
  return {
    cutoff,
    notes: notes.filter(
      (n) =>
        !n.fact?.forgotten &&
        !/\b(today|tomorrow|tonight|yesterday|last night|this morning|this afternoon|this evening|this weekend|next week|next month|last week|last month|currently|in a few days|in a couple of days)\b/i.test(
          n.text,
        ) &&
        (!cutoff || n.date > cutoff || (n.fact && !n.fact.key.startsWith("legacy."))),
    ),
  };
}
const stopWords = new Set(
  "a an the i me my you your we our is are was were be been have has had it that this do did does of in on at to for and or but about remember told said what which please".split(
    " ",
  ),
);
function terms(text: string): Set<string> {
  const words =
    text
      .normalize("NFKC")
      .toLowerCase()
      .match(/[\p{L}\p{N}]+/gu) ?? [];
  return new Set(
    words
      .filter((w) => !stopWords.has(w))
      .map((word) => word.replace(/(ing|ed|es|s)$/u, "")),
  );
}
export function recalledMemories(
  notes: Note[],
  query: string,
  preferredIds: string[] = [],
) {
  const queryTerms = terms(query);
  const preferred = new Set(preferredIds);
  const newest = new Map<string, Note>();
  for (const note of notes.toSorted((a, b) => a.date.localeCompare(b.date)))
    newest.set(note.text.trim().toLowerCase(), note);
  const ranked = Array.from(newest.values())
    .map((note) => {
      const overlap = Array.from(terms(note.text)).filter((term) =>
        queryTerms.has(term),
      ).length;
      return { note, overlap, preferred: preferred.has(note.id) };
    })
    .filter(
      ({ note, overlap, preferred }) =>
        !note.fact?.archived || overlap > 0 || preferred,
    )
    .sort((a, b) => {
      const relevance =
        Number(b.preferred) - Number(a.preferred) || b.overlap - a.overlap;
      if (relevance) return relevance;
      const anchors = Number(b.note.importance >= 4) - Number(a.note.importance >= 4);
      return (
        anchors ||
        (a.note.importance >= 4 ? b.note.importance - a.note.importance : 0) ||
        b.note.date.localeCompare(a.note.date)
      );
    });
  let used = 0;
  const selected: { date: string; fact: unknown; scope?: string }[] = [];
  for (const long of [true, false]) {
    let count = 0,
      groupUsed = 0;
    const budget = long ? Math.floor(520 / 3) : 520 - used;
    for (const { note } of ranked.filter(
      ({ note }) => (note.tier === "long") === long,
    )) {
      if (count >= (long ? 8 : 12)) break;
      const cost =
        Math.ceil(
          Array.from(note.text).reduce(
            (sum, ch) => sum + (ch.charCodeAt(0) > 127 ? 0.5 : 0.25),
            0,
          ),
        ) + 20;
      if (groupUsed + cost > budget) continue;
      groupUsed += cost;
      used += cost;
      count += 1;
      selected.push({
        date: note.date,
        fact: note.fact ?? note.text,
        ...(note.source === "appointment"
          ? {
              scope:
                "Shared in-app appointment experience. No inference about real-world identity or permanent preferences.",
            }
          : {}),
      });
    }
  }
  selected.sort((a, b) => a.date.localeCompare(b.date));
  return selected;
}
const experiences: Record<
  string,
  { name: string; city: string; paths: Record<string, string> }
> = {
  departures_mainline_melbourne_v2: {
    name: "Ruby Walker",
    city: "melbourne",
    paths: {
      RB11: "The friend stayed twenty minutes and heard your application opening about bottle caps on the beach. You were still writing when they left. Submission and admission are unknown. No next walk was booked.",
      RB12: "The friend stayed twenty minutes doing their own thing while you wrote, and left on time. Your application remained unfinished. No next walk was booked.",
      RB21: "The friend left to keep their afternoon. In that story you agreed to meet at the café at four the following afternoon. The walk has not happened in the record. That story-relative date is not today's date.",
      RB22: "The friend left with their coffee. You agreed not to pick another date yet. They did not hear the bottle-cap opening. No new appointment exists.",
    },
  },
  departures_city_newyork_v2: {
    name: "Marcus Rivera",
    city: "newyork",
    paths: {
      ML11: "You were late. The friend ate first. You arrived at one twenty and walked with them to the corner until one thirty, joking about a song. You did not eat lunch together or book another lunch.",
      ML12: "You were late. The friend ate first. You arrived at one twenty and sat briefly, joking about a cold chip. No next lunch was booked. Full forgiveness is unknown.",
      ML21: "You missed lunch together. With permission you checked your days off and offered Tuesday or Thursday at noon. The friend had not chosen either. These are story-world suggestions, not current confirmed dates.",
      ML22: "You missed lunch together. The friend asked to leave planning with them until they want to arrange something. You accepted. Wait for them to reopen planning before offering dates or pressing for a meeting.",
    },
  },
};
export function storyExperiences(
  character: Record<string, unknown>,
  stories: ContentRecord[],
  cutoff?: string,
) {
  if (character.isMainCharacter !== true) return [];
  const card = character.card as { name?: string; regionId?: string } | undefined;
  return stories.flatMap((story) => {
    const edition = experiences[story.resourceId];
    const payload = story.payload as {
      completedAt?: string;
      flags?: Record<string, boolean>;
    };
    if (
      !edition ||
      edition.name !== card?.name ||
      edition.city !== card.regionId ||
      !payload.completedAt ||
      (cutoff && payload.completedAt <= cutoff)
    )
      return [];
    const paths = Object.keys(edition.paths).filter(
      (key) => payload.flags?.[`experience.${key}`],
    );
    return paths.length === 1
      ? [{ completedAt: payload.completedAt, fact: edition.paths[paths[0] ?? ""] }]
      : [];
  });
}
export function learnerGuidance(level: unknown): string {
  switch (level) {
    case "kindergarten":
      return "Use one line of at most 6 very common words. Accept single-word replies. Ask a concrete yes/no or either/or question only when a decision needs one.";
    case "primary1":
    case "primary2":
    case "primary3":
      return "Use 1–2 lines, at most 8 common words each and 16 total. One idea, simple present tense. Accept fragments and one-word answers. Demonstrate only when asked.";
    case "primary4":
    case "primary5":
    case "primary6":
      return "Use 1–3 lines, at most 10 words each and 20 total. Common vocabulary and simple past/future. Avoid uncommon idioms. At most one focused question.";
    case "junior1":
    case "junior2":
    case "junior3":
      return "Use 1–3 lines, at most 12 words each and 24 total. Familiar everyday vocabulary, simple joined clauses and common phrasal verbs. At most one focused question.";
    case "senior1":
    case "senior2":
    case "senior3":
      return "Use 1–3 lines, at most 12 words each and 26 total. Ordinary spoken vocabulary and natural clauses. Develop one idea; occasional idioms only when the topic needs them.";
    case "undergraduate":
      return "Use 1–3 lines, at most 12 words each and 26 total. Common spoken English with nuance and humour when relevant. Leave room for the friend.";
    default:
      return "Use 1–3 lines, at most 12 words each and 28 total. Natural everyday spoken English with nuance. Advanced comprehension never requires rare, literary or academic vocabulary.";
  }
}
export function privateContinuity(persona: Record<string, unknown>, now: Date) {
  const relationship = {
    schemaVersion: 2,
    affinity: 10,
    bondFloor: 5,
    familiarity: 0.08,
    trust: 0.12,
    rapport: 0.1,
    care: 0.1,
    respect: 0.5,
    unresolvedStrain: 0,
    ...((persona.relationship ?? {}) as Record<string, unknown>),
  } as Record<string, unknown>;
  const growth = (persona.growth ?? {}) as {
    isPaused?: boolean;
    arcs?: Record<string, unknown>[];
  };
  const clamp = (value: number, low: number, high: number) =>
    Math.min(high, Math.max(low, value));
  const affinity = Number(relationship.affinity ?? 0),
    familiarity = clamp(Number(relationship.familiarity ?? 0), 0, 1);
  const anchor =
    relationship.lastSubstantiveInteractionAt ??
    (Number(relationship.schemaVersion ?? 1) < 2
      ? relationship.lastInteractionAt
      : undefined);
  const days =
    typeof anchor === "string"
      ? Math.max(0, (now.getTime() - Date.parse(anchor)) / 86400000)
      : 0;
  const cadence =
    Number(relationship.substantiveIntervalSampleCount ?? 0) >= 2
      ? clamp(Number(relationship.typicalContactIntervalDays ?? 0), 1, 45)
      : 0;
  const grace = 4 + 14 * familiarity + 0.75 * cadence;
  const floor = clamp(Math.min(Number(relationship.bondFloor ?? 0), affinity), 0, 120);
  const halfLife =
    24 + 150 * (floor / 120) ** 0.85 + 50 * familiarity + Math.min(45, 1.5 * cadence);
  const projected = clamp(
    days > grace
      ? floor + Math.max(affinity - floor, 0) * 0.5 ** ((days - grace) / halfLife)
      : affinity,
    0,
    150,
  );
  return {
    relationship: {
      ...Object.fromEntries(
        [
          "affinity",
          "familiarity",
          "trust",
          "rapport",
          "care",
          "respect",
          "unresolvedStrain",
          "lastInteractionAt",
          "lastSubstantiveInteractionAt",
        ].map((key) => [key, relationship[key]]),
      ),
      affinity: Math.round(projected),
    },
    growth: {
      isPaused: growth.isPaused,
      arcs: (growth.arcs ?? [])
        .filter((arc) => Number(arc.progress) > 0)
        .toSorted((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)))
        .slice(0, 4)
        .map((arc) => ({
          trait: arc.trait,
          direction: arc.direction,
          stage: arc.stage,
        })),
    },
    rules:
      "Let familiarity, trust, rapport, care, respect and unresolved strain gradually affect warmth, openness and boundaries. Keep all scores and private assessments private. English mistakes never reduce the relationship. Absence does not justify guilt or exclusivity. Growth is gradual and preserves core identity. Paused growth retains prior change without absorbing new evidence. Considering means contemplating without established change, experimenting means cautious attempts with setbacks, integrating means growing consistency with old habits under stress, established means a learned tendency with recognizable personality. Evidence is required for offline successes or shared events. Mention growth only when relevant.",
  };
}
