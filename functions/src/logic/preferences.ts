// Group preference model (CLAUDE.md "Group preference model" + "I don't care" handling).
// Pure: no imports outside src/logic.
//
// Scoring per survey question: yes = +2, maybe = +1, no = -2, dontCare = 0.
// "I don't care" is neutral: it never constrains the result and never counts as a No.
// If most of the group doesn't care about a dimension (type, setting, price, vibe),
// a sensible default is used for that dimension.
import { SurveyAnswer, SurveyQuestionId, SURVEY_QUESTION_IDS } from "./types";

export const TYPE_IDS = ["food", "active", "games", "arts", "nature", "markets", "events"] as const;
export type ActivityTypeId = typeof TYPE_IDS[number];

export const TYPE_LABELS: Record<ActivityTypeId, string> = {
  food: "food & drink (restaurants, cafes, dessert)",
  active: "something active (bowling, mini golf, climbing)",
  games: "games (board game cafe, arcade, trivia)",
  arts: "arts & entertainment (movies, live music, museums)",
  nature: "nature (parks, gardens, trails)",
  markets: "markets & shopping (farmers markets, thrift stores)",
  events: "events (festivals, shows, pop-ups)",
};

/** Sensible default activity types when the group doesn't care / likes nothing. */
export const DEFAULT_TYPES: ActivityTypeId[] = ["food", "games", "arts"];

export type Setting = "indoor" | "outdoor" | "either";
export type PriceTier = "low" | "mid" | "high";
export type Vibe = "chill" | "lively" | "either";
export type Dimension = "type" | "setting" | "price" | "vibe";

export interface QuestionScore {
  score: number;
  yes: number;
  maybe: number;
  no: number;
  dontCare: number;
}

export interface GroupPreferences {
  memberCount: number;
  scores: Record<SurveyQuestionId, QuestionScore>;
  /** Types the group leans toward, best first (never empty: defaults fill in). */
  likedTypes: ActivityTypeId[];
  /** Types most of the people who cared said no to. */
  avoidTypes: ActivityTypeId[];
  setting: Setting;
  /** Highest acceptable price tier per person: low = free/under $15, mid = $15–$30, high = over $30. */
  priceCeiling: PriceTier;
  /** Same ceiling as a Google Places price level (1–4). */
  maxPriceLevel: number;
  vibe: Vibe;
  /** Dimensions where most of the group didn't care, so a default was used. */
  defaultsApplied: Dimension[];
  /** Members' free-text interests. Soft signal only. */
  interests: string[];
}

const POINTS: Record<SurveyAnswer, number> = { yes: 2, maybe: 1, no: -2, dontCare: 0 };

const DIMENSIONS: Record<Dimension, readonly SurveyQuestionId[]> = {
  type: TYPE_IDS,
  setting: ["indoors", "outdoors"],
  price: ["priceLow", "priceMid", "priceHigh"],
  vibe: ["chill", "lively"],
};

export const PRICE_LEVEL: Record<PriceTier, number> = { low: 1, mid: 2, high: 4 };

function emptyScore(): QuestionScore {
  return { score: 0, yes: 0, maybe: 0, no: 0, dontCare: 0 };
}

function isAnswer(v: unknown): v is SurveyAnswer {
  return v === "yes" || v === "maybe" || v === "no" || v === "dontCare";
}

/**
 * Builds the shared model from every participating member's survey answers
 * (`answers[uid][questionId]`) and their free-text interests.
 * A missing answer is treated like "I don't care".
 */
export function buildGroupPreferences(
  answers: Record<string, Record<string, SurveyAnswer>>,
  interests: string[],
): GroupPreferences {
  const members = Object.keys(answers);
  const memberCount = members.length;

  const scores = {} as Record<SurveyQuestionId, QuestionScore>;
  for (const q of SURVEY_QUESTION_IDS) scores[q] = emptyScore();
  for (const uid of members) {
    const a = answers[uid] ?? {};
    for (const q of SURVEY_QUESTION_IDS) {
      const raw = a[q];
      const ans: SurveyAnswer = isAnswer(raw) ? raw : "dontCare";
      const s = scores[q];
      s.score += POINTS[ans];
      s[ans] += 1;
    }
  }

  // "Most of the group doesn't care" about a dimension: more than half of that
  // dimension's answers are dontCare (or nobody answered at all).
  const mostlyDontCare = (dim: Dimension): boolean => {
    const qs = DIMENSIONS[dim];
    let dc = 0;
    for (const q of qs) dc += scores[q].dontCare;
    const total = qs.length * memberCount;
    return total === 0 || dc * 2 > total;
  };

  const defaultsApplied: Dimension[] = [];

  // --- Activity types ---
  const avoidTypes = TYPE_IDS.filter((t) => {
    const s = scores[t];
    const cared = s.yes + s.maybe + s.no;
    return cared > 0 && s.no * 2 > cared && s.score < 0;
  });
  let likedTypes: ActivityTypeId[] = TYPE_IDS.filter((t) => scores[t].score > 0 && !avoidTypes.includes(t))
    .slice()
    .sort((a, b) => scores[b].score - scores[a].score || scores[b].yes - scores[a].yes);
  if (mostlyDontCare("type") || likedTypes.length === 0) {
    defaultsApplied.push("type");
    const extra = DEFAULT_TYPES.filter((t) => !likedTypes.includes(t) && !avoidTypes.includes(t));
    likedTypes = [...likedTypes, ...extra];
    if (likedTypes.length === 0) {
      // Everything avoided: fall back to the least-disliked types so there is always something.
      likedTypes = TYPE_IDS.slice().sort((a, b) => scores[b].score - scores[a].score).slice(0, 3);
    }
  }

  // --- Setting ---
  let setting: Setting = "either";
  if (mostlyDontCare("setting")) {
    defaultsApplied.push("setting");
  } else {
    const si = scores.indoors.score;
    const so = scores.outdoors.score;
    if (so < 0 && si >= so) setting = "indoor";
    else if (si < 0 && so > si) setting = "outdoor";
  }

  // --- Price: highest tier nobody said "no" to (a budget limit is respected even for one person). ---
  let priceCeiling: PriceTier = "mid";
  if (mostlyDontCare("price")) {
    defaultsApplied.push("price");
    if (scores.priceMid.no > 0) priceCeiling = "low";
  } else {
    const tiers: [PriceTier, SurveyQuestionId][] = [["high", "priceHigh"], ["mid", "priceMid"], ["low", "priceLow"]];
    const ok = tiers.find(([, q]) => scores[q].no === 0);
    if (ok) {
      priceCeiling = ok[0];
    } else {
      // Every tier has a "no": take the cheapest tier with the best net score, else low.
      const best = tiers.slice().reverse().sort((a, b) => scores[b[1]].score - scores[a[1]].score)[0];
      priceCeiling = scores[best[1]].score > 0 ? best[0] : "low";
    }
  }

  // --- Vibe ---
  let vibe: Vibe = "either";
  if (mostlyDontCare("vibe")) {
    defaultsApplied.push("vibe");
  } else {
    const sc = scores.chill.score;
    const sl = scores.lively.score;
    if (sl < 0 && sc >= sl) vibe = "chill";
    else if (sc < 0 && sl > sc) vibe = "lively";
    else if (sc - sl >= 3) vibe = "chill";
    else if (sl - sc >= 3) vibe = "lively";
  }

  const cleanInterests = interests.map((s) => (s ?? "").trim()).filter((s) => s.length > 0);

  return {
    memberCount,
    scores,
    likedTypes,
    avoidTypes,
    setting,
    priceCeiling,
    maxPriceLevel: PRICE_LEVEL[priceCeiling],
    vibe,
    defaultsApplied,
    interests: cleanInterests,
  };
}

const PRICE_TEXT: Record<PriceTier, string> = {
  low: "free or under $15 per person",
  mid: "up to about $30 per person",
  high: "any price (over $30 per person is fine)",
};

/** Human-readable summary for the Gemini prompt. */
export function toPromptText(prefs: GroupPreferences): string {
  const lines: string[] = [];
  lines.push(`Group size: ${prefs.memberCount} people.`);
  lines.push(`Activity types the group leans toward (best first): ${prefs.likedTypes.map((t) => TYPE_LABELS[t]).join("; ")}.`);
  if (prefs.avoidTypes.length > 0) {
    lines.push(`Avoid: ${prefs.avoidTypes.map((t) => TYPE_LABELS[t]).join("; ")}.`);
  }
  lines.push(
    prefs.setting === "either"
      ? "Setting: indoors or outdoors are both fine."
      : `Setting: ${prefs.setting === "indoor" ? "indoors" : "outdoors"} preferred.`,
  );
  lines.push(`Budget: ${PRICE_TEXT[prefs.priceCeiling]}.`);
  lines.push(
    prefs.vibe === "either"
      ? "Vibe: chill or lively both fine."
      : `Vibe: ${prefs.vibe === "chill" ? "chill and low-key, easy to talk" : "lively and busy, energy is fine"}.`,
  );
  if (prefs.defaultsApplied.length > 0) {
    lines.push(`Most of the group didn't care about: ${prefs.defaultsApplied.join(", ")} (sensible defaults used).`);
  }
  if (prefs.interests.length > 0) {
    lines.push(
      "Members' own words about hangouts they like (a soft hint only; still include good ideas that don't match): " +
        prefs.interests.map((s) => `"${s.replace(/\s+/g, " ").slice(0, 300)}"`).join(" | "),
    );
  }
  return lines.join("\n");
}
