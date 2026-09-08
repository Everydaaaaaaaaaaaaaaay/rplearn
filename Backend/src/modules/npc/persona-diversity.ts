import { createHash } from "node:crypto";
import type {
  NpcBackgroundMotif,
  NpcDiversityProfile,
  NpcDiversityReview,
  NpcInteractionStyle,
  NpcInterestDomain,
  NpcOccupationDomain,
  NpcSocialRole,
  NpcTrait,
  PublicNpcCard,
} from "./types.js";

export const occupationDomains = [
  "agriculture-nature",
  "arts-media",
  "business-finance",
  "education",
  "healthcare",
  "hospitality-food",
  "public-service",
  "retired",
  "science-technology",
  "service-retail",
  "skilled-trades",
  "sports-fitness",
  "student",
  "transport-logistics",
  "other",
] as const satisfies readonly NpcOccupationDomain[];

export const socialRoles = [
  "caregiver",
  "connector",
  "creator",
  "explorer",
  "helper",
  "learner",
  "mentor",
  "observer",
  "organizer",
  "performer",
  "problem-solver",
  "storyteller",
] as const satisfies readonly NpcSocialRole[];

export const interactionStyles = [
  "analytical",
  "animated",
  "blunt",
  "formal",
  "gentle",
  "humorous",
  "playful",
  "practical",
  "reflective",
  "reserved",
  "reassuring",
  "curious",
] as const satisfies readonly NpcInteractionStyle[];

export const interestDomains = [
  "arts",
  "books-learning",
  "community",
  "crafts-making",
  "food-drink",
  "games",
  "history-culture",
  "music",
  "nature",
  "photography-film",
  "sports",
  "technology",
  "travel",
  "wellness",
] as const satisfies readonly NpcInterestDomain[];

export const traits = [
  "adventurous",
  "ambitious",
  "calm",
  "candid",
  "careful",
  "curious",
  "disciplined",
  "empathetic",
  "independent",
  "optimistic",
  "pragmatic",
  "reserved",
  "sociable",
  "spontaneous",
  "witty",
] as const satisfies readonly NpcTrait[];

export const backgroundMotifs = [
  "belonging",
  "career-change",
  "exploration",
  "family-duty",
  "fresh-start",
  "mastery",
  "migration",
  "ordinary-life",
  "recovery",
  "rivalry",
  "self-discovery",
  "service",
  "tradition",
] as const satisfies readonly NpcBackgroundMotif[];

export type DiversityCandidate = Readonly<{
  card: PublicNpcCard;
  profile: NpcDiversityProfile;
}>;

export function canonicalizeDiversityProfile(
  profile: NpcDiversityProfile,
): NpcDiversityProfile {
  return {
    ...profile,
    interestDomains: [...new Set(profile.interestDomains)].sort(),
    traits: [...new Set(profile.traits)].sort(),
  };
}

const stopWords = new Set([
  "a",
  "an",
  "and",
  "are",
  "at",
  "for",
  "from",
  "has",
  "in",
  "is",
  "of",
  "the",
  "to",
  "with",
  "喜欢",
  "一个",
  "一些",
  "以及",
]);

function normalized(value: string | null | undefined): string {
  return (value ?? "")
    .normalize("NFKC")
    .toLocaleLowerCase("en-US")
    .replaceAll(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replaceAll(/\s+/g, " ");
}

function normalizedList(values: readonly string[]): readonly string[] {
  return values.map(normalized).filter(Boolean).sort();
}

function narrativeValue(card: PublicNpcCard): string {
  return JSON.stringify({
    background: normalized(card.background),
    hobbies: normalizedList(card.hobbies),
    occupation: normalized(card.occupation),
    personality: normalized(card.personality),
    speechStyle: normalized(card.speechStyle),
    voice: {
      anchorLines: normalizedList(card.personaVoice.anchorLines),
      boundaries: normalizedList(card.personaVoice.boundaries),
      conversationalHabits: normalizedList(card.personaVoice.conversationalHabits),
      flaws: normalizedList(card.personaVoice.flaws),
      values: normalizedList(card.personaVoice.values),
    },
  });
}

export function personaSignature(card: PublicNpcCard): string {
  return createHash("sha256").update(narrativeValue(card)).digest("hex");
}

function tokens(card: PublicNpcCard): Set<string> {
  const source = [
    card.occupation,
    ...card.hobbies,
    card.personality,
    card.speechStyle ?? "",
    card.background ?? "",
    ...card.personaVoice.values,
    ...card.personaVoice.flaws,
    ...card.personaVoice.conversationalHabits,
  ]
    .map(normalized)
    .join(" ");
  const result = new Set(
    source.split(" ").filter((value) => value.length > 1 && !stopWords.has(value)),
  );
  for (const value of source.match(/[\p{Script=Han}]{3,}/gu) ?? []) {
    for (let index = 0; index < value.length - 1; index += 1)
      result.add(value.slice(index, index + 2));
  }
  return result;
}

function jaccard<T>(left: ReadonlySet<T>, right: ReadonlySet<T>): number {
  if (left.size === 0 && right.size === 0) return 0;
  let intersection = 0;
  for (const item of left) if (right.has(item)) intersection += 1;
  return intersection / (left.size + right.size - intersection);
}

function ageBand(age: number): string {
  if (age < 20) return "teen";
  if (age < 30) return "young-adult";
  if (age < 45) return "adult";
  if (age < 60) return "midlife";
  return "older-adult";
}

type Comparison = Readonly<{
  dimensions: readonly string[];
  lexicalSimilarity: number;
  score: number;
}>;

function compare(left: DiversityCandidate, right: DiversityCandidate): Comparison {
  const dimensions: string[] = [];
  let score = 0;
  const same = (condition: boolean, weight: number, dimension: string) => {
    if (!condition) return;
    score += weight;
    dimensions.push(dimension);
  };
  same(
    left.profile.occupationDomain === right.profile.occupationDomain,
    24,
    "occupation-domain",
  );
  same(left.profile.socialRole === right.profile.socialRole, 14, "social-role");
  same(
    left.profile.interactionStyle === right.profile.interactionStyle,
    12,
    "interaction-style",
  );
  same(
    left.profile.backgroundMotif === right.profile.backgroundMotif,
    10,
    "background-motif",
  );
  same(left.profile.energy === right.profile.energy, 5, "energy");
  same(left.profile.warmth === right.profile.warmth, 5, "warmth");
  same(left.profile.structure === right.profile.structure, 5, "structure");
  same(ageBand(left.card.age) === ageBand(right.card.age), 5, "life-stage");
  score +=
    12 *
    jaccard(
      new Set(left.profile.interestDomains),
      new Set(right.profile.interestDomains),
    );
  score += 8 * jaccard(new Set(left.profile.traits), new Set(right.profile.traits));
  const lexicalSimilarity = jaccard(tokens(left.card), tokens(right.card));
  return { dimensions, lexicalSimilarity, score };
}

function guidance(
  profile: NpcDiversityProfile,
  dimensions: readonly string[],
): string[] {
  const result: string[] = [];
  if (dimensions.includes("occupation-domain"))
    result.push(`Choose an occupation outside the ${profile.occupationDomain} domain.`);
  if (dimensions.includes("social-role"))
    result.push(`Give the person a social role other than ${profile.socialRole}.`);
  if (dimensions.includes("interaction-style"))
    result.push(
      `Use a clearly different interaction style from ${profile.interactionStyle}.`,
    );
  if (dimensions.includes("background-motif"))
    result.push(
      `Build the background around a motif other than ${profile.backgroundMotif}.`,
    );
  if (dimensions.includes("life-stage"))
    result.push(
      "Move the character to a meaningfully different life stage when plausible.",
    );
  if (result.length < 2)
    result.push(
      "Change at least three core dimensions, not merely the name or appearance.",
    );
  return result.slice(0, 4);
}

export function reviewPersonaDiversity(
  candidate: DiversityCandidate,
  existing: readonly DiversityCandidate[],
): NpcDiversityReview {
  let closest: Comparison | undefined;
  let rejected: Comparison | undefined;
  const signature = personaSignature(candidate.card);
  for (const item of existing) {
    const comparison = compare(candidate, item);
    if (closest === undefined || comparison.score > closest.score) closest = comparison;
    if (personaSignature(item.card) === signature) {
      rejected = { ...comparison, score: 100 };
      break;
    }
    const coreMatches = comparison.dimensions.filter((dimension) =>
      [
        "occupation-domain",
        "social-role",
        "interaction-style",
        "background-motif",
      ].includes(dimension),
    ).length;
    const tooSimilar =
      (comparison.score >= 82 && coreMatches >= 3) ||
      (comparison.score >= 72 &&
        comparison.lexicalSimilarity >= 0.62 &&
        coreMatches >= 2 &&
        comparison.dimensions.includes("occupation-domain"));
    if (tooSimilar && (rejected === undefined || comparison.score > rejected.score))
      rejected = comparison;
  }
  if (closest === undefined)
    return { decision: "accept", similarityScore: 0, dimensions: [], guidance: [] };
  const result = rejected ?? closest;
  return {
    decision: rejected ? "revise" : "accept",
    similarityScore: Math.round(result.score),
    dimensions: rejected ? result.dimensions : [],
    guidance: rejected ? guidance(candidate.profile, result.dimensions) : [],
  };
}

function containsAny(value: string, options: readonly string[]): boolean {
  return options.some((option) => value.includes(option));
}

/** Compatibility classification for identities created by older clients. */
export function deriveDiversityProfile(card: PublicNpcCard): NpcDiversityProfile {
  const occupation = normalized(card.occupation);
  const narrative = normalized(
    [
      card.occupation,
      card.personality,
      card.speechStyle,
      card.background,
      ...card.hobbies,
      ...card.personaVoice.values,
      ...card.personaVoice.conversationalHabits,
    ].join(" "),
  );
  const occupationDomain: NpcOccupationDomain = containsAny(occupation, [
    "student",
    "pupil",
    "研究生",
    "学生",
  ])
    ? "student"
    : containsAny(occupation, ["retired", "退休"])
      ? "retired"
      : containsAny(occupation, [
            "teacher",
            "professor",
            "tutor",
            "educat",
            "教师",
            "老师",
          ])
        ? "education"
        : containsAny(occupation, [
              "doctor",
              "nurse",
              "therap",
              "medical",
              "health",
              "医生",
              "护士",
            ])
          ? "healthcare"
          : containsAny(occupation, [
                "chef",
                "cook",
                "baker",
                "barista",
                "cafe",
                "restaurant",
                "厨",
                "咖啡",
              ])
            ? "hospitality-food"
            : containsAny(occupation, [
                  "engineer",
                  "developer",
                  "scientist",
                  "research",
                  "data",
                  "程序",
                  "工程",
                  "科研",
                ])
              ? "science-technology"
              : containsAny(occupation, [
                    "artist",
                    "design",
                    "writer",
                    "music",
                    "actor",
                    "producer",
                    "photograph",
                    "艺术",
                    "设计",
                    "作家",
                    "音乐",
                    "摄影",
                  ])
                ? "arts-media"
                : containsAny(occupation, [
                      "mechanic",
                      "carpenter",
                      "electric",
                      "repair",
                      "craft",
                      "维修",
                      "木工",
                    ])
                  ? "skilled-trades"
                  : containsAny(occupation, [
                        "shop",
                        "sales",
                        "retail",
                        "vendor",
                        "cashier",
                        "店员",
                        "摊主",
                        "销售",
                      ])
                    ? "service-retail"
                    : containsAny(occupation, [
                          "driver",
                          "pilot",
                          "courier",
                          "logistics",
                          "司机",
                          "快递",
                        ])
                      ? "transport-logistics"
                      : containsAny(occupation, [
                            "farmer",
                            "gardener",
                            "ranger",
                            "农",
                            "园丁",
                          ])
                        ? "agriculture-nature"
                        : containsAny(occupation, [
                              "police",
                              "firefighter",
                              "civil servant",
                              "social worker",
                              "警察",
                              "消防",
                              "公务员",
                            ])
                          ? "public-service"
                          : containsAny(occupation, [
                                "coach",
                                "athlete",
                                "trainer",
                                "运动员",
                                "教练",
                              ])
                            ? "sports-fitness"
                            : containsAny(occupation, [
                                  "manager",
                                  "account",
                                  "bank",
                                  "consult",
                                  "finance",
                                  "经理",
                                  "会计",
                                  "金融",
                                ])
                              ? "business-finance"
                              : "other";
  const socialRole: NpcSocialRole = containsAny(narrative, [
    "teach",
    "guide",
    "mentor",
    "教",
    "指导",
  ])
    ? "mentor"
    : containsAny(narrative, ["help", "care", "support", "照顾", "帮助"])
      ? "helper"
      : containsAny(narrative, ["organize", "host", "community", "组织", "社区"])
        ? "connector"
        : containsAny(narrative, [
              "create",
              "make",
              "design",
              "write",
              "制作",
              "创作",
              "设计",
            ])
          ? "creator"
          : containsAny(narrative, ["travel", "explore", "adventure", "旅行", "探索"])
            ? "explorer"
            : containsAny(narrative, ["story", "history", "collects", "故事", "历史"])
              ? "storyteller"
              : "observer";
  const interactionStyle: NpcInteractionStyle = containsAny(narrative, [
    "quiet",
    "reserved",
    "少言",
    "内向",
  ])
    ? "reserved"
    : containsAny(narrative, ["funny", "humor", "joke", "幽默", "玩笑"])
      ? "humorous"
      : containsAny(narrative, ["gentle", "soft", "温柔", "柔和"])
        ? "gentle"
        : containsAny(narrative, ["direct", "blunt", "candid", "直接", "坦率"])
          ? "blunt"
          : containsAny(narrative, ["practical", "concrete", "务实", "实际"])
            ? "practical"
            : containsAny(narrative, ["analytical", "precise", "分析", "严谨"])
              ? "analytical"
              : "curious";
  const interestMap: readonly [NpcInterestDomain, readonly string[]][] = [
    ["arts", ["art", "paint", "draw", "艺术", "绘画"]],
    ["books-learning", ["book", "read", "learn", "书", "阅读", "学习"]],
    ["community", ["community", "volunteer", "社区", "志愿"]],
    ["crafts-making", ["craft", "wood", "sew", "手工", "木工", "缝"]],
    ["food-drink", ["cook", "food", "coffee", "tea", "烹饪", "咖啡", "茶"]],
    ["games", ["game", "chess", "游戏", "棋"]],
    ["history-culture", ["history", "museum", "历史", "博物馆"]],
    ["music", ["music", "jazz", "vinyl", "音乐", "爵士", "黑胶"]],
    ["nature", ["garden", "hike", "bird", "自然", "园艺", "徒步"]],
    ["photography-film", ["photo", "film", "摄影", "电影"]],
    ["sports", ["sport", "run", "cycle", "运动", "跑步", "骑行"]],
    ["technology", ["tech", "code", "robot", "科技", "编程"]],
    ["travel", ["travel", "trip", "旅行"]],
    ["wellness", ["yoga", "meditat", "wellness", "瑜伽", "冥想"]],
  ];
  const foundInterests = interestMap
    .filter(([, keywords]) => containsAny(narrative, keywords))
    .map(([domain]) => domain)
    .slice(0, 4);
  const traitMap: readonly [NpcTrait, readonly string[]][] = [
    ["adventurous", ["adventurous", "冒险"]],
    ["ambitious", ["ambitious", "有抱负"]],
    ["calm", ["calm", "冷静"]],
    ["candid", ["candid", "direct", "坦率"]],
    ["careful", ["careful", "谨慎"]],
    ["curious", ["curious", "好奇"]],
    ["disciplined", ["disciplined", "自律"]],
    ["empathetic", ["empathetic", "kind", "体贴", "善良"]],
    ["independent", ["independent", "独立"]],
    ["optimistic", ["optimistic", "乐观"]],
    ["pragmatic", ["practical", "pragmatic", "务实"]],
    ["reserved", ["reserved", "quiet", "内向"]],
    ["sociable", ["social", "chatty", "外向", "健谈"]],
    ["spontaneous", ["spontaneous", "随性"]],
    ["witty", ["witty", "humor", "幽默"]],
  ];
  const foundTraits = traitMap
    .filter(([, keywords]) => containsAny(narrative, keywords))
    .map(([trait]) => trait)
    .slice(0, 4);
  const backgroundMotif: NpcBackgroundMotif = containsAny(narrative, [
    "move",
    "migrat",
    "移居",
    "搬到",
  ])
    ? "migration"
    : containsAny(narrative, ["career change", "new career", "转行"])
      ? "career-change"
      : containsAny(narrative, ["recover", "rebuild", "康复", "重建"])
        ? "recovery"
        : containsAny(narrative, ["family", "parent", "child", "家庭", "父母", "孩子"])
          ? "family-duty"
          : containsAny(narrative, ["tradition", "heritage", "传统", "传承"])
            ? "tradition"
            : containsAny(narrative, ["master", "practice", "craft", "钻研", "手艺"])
              ? "mastery"
              : "ordinary-life";
  return {
    version: 1,
    occupationDomain,
    socialRole,
    interactionStyle,
    interestDomains: foundInterests,
    traits: foundTraits,
    backgroundMotif,
    energy: containsAny(narrative, ["energetic", "animated", "活力", "热情"])
      ? "high"
      : containsAny(narrative, ["quiet", "calm", "安静", "冷静"])
        ? "low"
        : "medium",
    warmth: containsAny(narrative, ["warm", "kind", "gentle", "温暖", "善良", "温柔"])
      ? "warm"
      : containsAny(narrative, ["reserved", "distant", "疏离", "内向"])
        ? "reserved"
        : "balanced",
    structure: containsAny(narrative, [
      "organized",
      "precise",
      "disciplined",
      "有条理",
      "严谨",
      "自律",
    ])
      ? "structured"
      : containsAny(narrative, ["spontaneous", "impulsive", "随性", "冲动"])
        ? "spontaneous"
        : "balanced",
  };
}

/**
 * Keep model-provided nuance, but do not let an obviously contradictory label bypass
 * admission. Only confident compatibility classifications override submitted values.
 */
export function reconcileDiversityProfile(
  card: PublicNpcCard,
  submitted: NpcDiversityProfile,
): NpcDiversityProfile {
  const derived = deriveDiversityProfile(card);
  return canonicalizeDiversityProfile({
    ...submitted,
    occupationDomain:
      derived.occupationDomain === "other"
        ? submitted.occupationDomain
        : derived.occupationDomain,
    socialRole:
      derived.socialRole === "observer" ? submitted.socialRole : derived.socialRole,
    interactionStyle:
      derived.interactionStyle === "curious"
        ? submitted.interactionStyle
        : derived.interactionStyle,
    backgroundMotif:
      derived.backgroundMotif === "ordinary-life"
        ? submitted.backgroundMotif
        : derived.backgroundMotif,
    interestDomains: [
      ...new Set([...submitted.interestDomains, ...derived.interestDomains]),
    ]
      .sort()
      .slice(0, 4),
    traits: [...new Set([...submitted.traits, ...derived.traits])].sort().slice(0, 4),
    energy: derived.energy === "medium" ? submitted.energy : derived.energy,
    warmth: derived.warmth === "balanced" ? submitted.warmth : derived.warmth,
    structure:
      derived.structure === "balanced" ? submitted.structure : derived.structure,
  });
}
