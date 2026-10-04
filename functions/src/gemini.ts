// Idea generation with Gemini (CLAUDE.md "Idea generation (Gemini)").
// Gemini decides WHAT KINDS of hangouts fit the group and writes the descriptions;
// real venues/photos always come from Google Places (places.ts).
//
// generateIdeas never throws: on any failure (no key, network, bad JSON, too few ideas)
// it tops up from a built-in list filtered by the group's preferences.
//
// Uses only globals (fetch, AbortController, setTimeout, process.env) accessed through
// globalThis, so it type-checks with or without @types/node.
import { LatLng } from "./logic/types";
import { GroupPreferences, toPromptText, ActivityTypeId, TYPE_IDS, PRICE_LEVEL } from "./logic/preferences";

export const GEMINI_MODEL = "gemini-2.5-flash";
const GEMINI_TIMEOUT_MS = 20_000;

export interface Idea {
  activity: string;
  description: string;
  category: string;
  searchQuery: string;
  tags: string[];
}

export interface GenerateIdeasInput {
  count: number;
  prefs: GroupPreferences;
  planDescription: string;
  start: Date;
  end: Date;
  center: LatLng | null;
  areaText: string;
  excludeActivities: string[];
  /** Optional IANA zone (owner's) so the prompt can state local time of day. */
  timeZone?: string;
}

// ---------------------------------------------------------------------------
// Minimal runtime helpers (shared with places.ts)
// ---------------------------------------------------------------------------

interface FetchResponseLike {
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
  text(): Promise<string>;
}
interface FetchInitLike {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  signal?: unknown;
}
type FetchLike = (url: string, init?: FetchInitLike) => Promise<FetchResponseLike>;
interface Runtime {
  fetch?: FetchLike;
  AbortController?: new () => { signal: unknown; abort(): void };
  setTimeout?: (fn: () => void, ms: number) => unknown;
  clearTimeout?: (h: unknown) => void;
  process?: { env: Record<string, string | undefined> };
  console?: { warn(...args: unknown[]): void };
}
const rt = globalThis as unknown as Runtime;

export function envVar(name: string): string | undefined {
  const v = rt.process?.env?.[name];
  return v && v.trim().length > 0 ? v.trim() : undefined;
}

export function logWarn(...args: unknown[]): void {
  rt.console?.warn(...args);
}

/**
 * fetch + JSON with a timeout. Returns null on any error or non-2xx status (never throws).
 * Error messages never include request headers, so API keys are not logged.
 */
export async function fetchJson(url: string, init: FetchInitLike, timeoutMs: number, label: string): Promise<unknown | null> {
  const f = rt.fetch;
  if (!f) {
    logWarn(`[${label}] fetch unavailable`);
    return null;
  }
  const controller = rt.AbortController ? new rt.AbortController() : null;
  const timer = controller && rt.setTimeout ? rt.setTimeout(() => controller.abort(), timeoutMs) : null;
  try {
    const res = await f(url, { ...init, signal: controller ? controller.signal : undefined });
    if (!res.ok) {
      let body = "";
      try { body = (await res.text()).slice(0, 300); } catch { /* ignore */ }
      logWarn(`[${label}] HTTP ${res.status}: ${body}`);
      return null;
    }
    return await res.json();
  } catch (e) {
    logWarn(`[${label}] request failed: ${e instanceof Error ? e.message : String(e)}`);
    return null;
  } finally {
    if (timer !== null && rt.clearTimeout) rt.clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// Built-in fallback ideas
// ---------------------------------------------------------------------------

interface Seed {
  activity: string;
  description: string;
  category: ActivityTypeId;
  term: string;          // Places search term, e.g. "bowling alley"
  setting: "indoor" | "outdoor" | "either";
  price: number;         // Places-style level 1–4
  vibe: "chill" | "lively" | "either";
  minMinutes: number;
  tags: string[];
}

const SEEDS: Seed[] = [
  // food & drink
  { activity: "Tacos and aguas frescas", description: "A relaxed taqueria stop with plenty to share around the table.", category: "food", term: "taqueria", setting: "indoor", price: 1, vibe: "either", minMinutes: 45, tags: ["Food", "Casual"] },
  { activity: "Coffee and pastries", description: "Grab a table at a cozy cafe and catch up over good coffee.", category: "food", term: "cozy coffee shop", setting: "indoor", price: 1, vibe: "chill", minMinutes: 30, tags: ["Cafe", "Chill"] },
  { activity: "Bubble tea run", description: "Pick a flavor, find a seat and take it easy.", category: "food", term: "bubble tea", setting: "indoor", price: 1, vibe: "chill", minMinutes: 30, tags: ["Drinks", "Chill"] },
  { activity: "Food hall grazing", description: "Everyone picks their own stall, then regroup at one big table.", category: "food", term: "food hall", setting: "indoor", price: 2, vibe: "lively", minMinutes: 60, tags: ["Food", "Lively"] },
  { activity: "Brunch", description: "A slow brunch with something for every appetite.", category: "food", term: "brunch restaurant", setting: "indoor", price: 2, vibe: "chill", minMinutes: 60, tags: ["Food", "Brunch"] },
  { activity: "Pizza night out", description: "Split a few pies at a well-loved local pizzeria.", category: "food", term: "pizzeria", setting: "indoor", price: 2, vibe: "either", minMinutes: 60, tags: ["Food", "Group-friendly"] },
  { activity: "Ice cream", description: "A quick, sweet stop that works for any schedule.", category: "food", term: "ice cream shop", setting: "either", price: 1, vibe: "chill", minMinutes: 30, tags: ["Dessert"] },
  { activity: "Patio dinner", description: "Dinner outside on a patio while the evening winds down.", category: "food", term: "restaurant with outdoor patio", setting: "outdoor", price: 2, vibe: "either", minMinutes: 90, tags: ["Food", "Outdoors"] },
  { activity: "Ramen", description: "Steaming bowls of ramen at a cozy noodle bar.", category: "food", term: "ramen restaurant", setting: "indoor", price: 2, vibe: "chill", minMinutes: 60, tags: ["Food"] },
  { activity: "Korean BBQ", description: "Grill at the table together. Great for groups.", category: "food", term: "korean bbq", setting: "indoor", price: 3, vibe: "lively", minMinutes: 90, tags: ["Food", "Group-friendly"] },
  { activity: "Nice dinner out", description: "A sit-down dinner somewhere a little special.", category: "food", term: "highly rated restaurant", setting: "indoor", price: 3, vibe: "chill", minMinutes: 90, tags: ["Food", "Special"] },
  { activity: "Dessert cafe", description: "Cake, crepes or gelato at a sweet little spot.", category: "food", term: "dessert cafe", setting: "indoor", price: 1, vibe: "chill", minMinutes: 30, tags: ["Dessert", "Chill"] },
  // active
  { activity: "Bowling", description: "A few frames of bowling. No skill required, lots of laughs.", category: "active", term: "bowling alley", setting: "indoor", price: 2, vibe: "lively", minMinutes: 60, tags: ["Active", "Group-friendly"] },
  { activity: "Mini golf", description: "A friendly round of mini golf with plenty of trash talk.", category: "active", term: "mini golf", setting: "either", price: 2, vibe: "lively", minMinutes: 60, tags: ["Active", "Games"] },
  { activity: "Bouldering", description: "Try some beginner routes at a climbing gym; shoes are rentable.", category: "active", term: "climbing gym", setting: "indoor", price: 2, vibe: "either", minMinutes: 90, tags: ["Active"] },
  { activity: "Roller skating", description: "Lace up and do a few laps at the rink.", category: "active", term: "roller skating rink", setting: "indoor", price: 2, vibe: "lively", minMinutes: 90, tags: ["Active", "Lively"] },
  { activity: "Kayak rental", description: "Paddle around together on the water for an hour or two.", category: "active", term: "kayak rental", setting: "outdoor", price: 2, vibe: "chill", minMinutes: 90, tags: ["Active", "Outdoors"] },
  { activity: "Batting cages", description: "Take some swings at the batting cages.", category: "active", term: "batting cages", setting: "either", price: 2, vibe: "lively", minMinutes: 45, tags: ["Active"] },
  { activity: "Axe throwing", description: "Book a lane and try your aim at axe throwing.", category: "active", term: "axe throwing", setting: "indoor", price: 3, vibe: "lively", minMinutes: 60, tags: ["Active", "Special"] },
  // games
  { activity: "Board game cafe", description: "Pick from a huge shelf of games over snacks and drinks.", category: "games", term: "board game cafe", setting: "indoor", price: 1, vibe: "chill", minMinutes: 90, tags: ["Games", "Chill"] },
  { activity: "Arcade", description: "Classic and new arcade games, with tickets and prizes.", category: "games", term: "arcade", setting: "indoor", price: 2, vibe: "lively", minMinutes: 60, tags: ["Games", "Lively"] },
  { activity: "Trivia night", description: "Form a team and see what you all know at trivia.", category: "games", term: "bar trivia night", setting: "indoor", price: 2, vibe: "lively", minMinutes: 90, tags: ["Games", "Lively"] },
  { activity: "Escape room", description: "Work together to crack the puzzles before time runs out.", category: "games", term: "escape room", setting: "indoor", price: 3, vibe: "lively", minMinutes: 60, tags: ["Games", "Teamwork"] },
  { activity: "Pool and darts", description: "Shoot some pool and throw darts at a laid-back spot.", category: "games", term: "pool hall", setting: "indoor", price: 1, vibe: "either", minMinutes: 60, tags: ["Games"] },
  { activity: "Karaoke", description: "Grab a private room and take turns at the mic.", category: "games", term: "karaoke", setting: "indoor", price: 2, vibe: "lively", minMinutes: 90, tags: ["Games", "Lively"] },
  // arts & entertainment
  { activity: "Movie", description: "Catch whatever's playing at a nearby theater.", category: "arts", term: "movie theater", setting: "indoor", price: 2, vibe: "chill", minMinutes: 120, tags: ["Movies"] },
  { activity: "Museum visit", description: "Wander the galleries at your own pace.", category: "arts", term: "museum", setting: "indoor", price: 2, vibe: "chill", minMinutes: 90, tags: ["Arts", "Chill"] },
  { activity: "Live music", description: "See a local band at a music venue.", category: "arts", term: "live music venue", setting: "indoor", price: 3, vibe: "lively", minMinutes: 120, tags: ["Music", "Lively"] },
  { activity: "Comedy show", description: "Laugh through a stand-up set at a comedy club.", category: "arts", term: "comedy club", setting: "indoor", price: 3, vibe: "lively", minMinutes: 90, tags: ["Comedy"] },
  { activity: "Art gallery hop", description: "Pop into a gallery and see what's on.", category: "arts", term: "art gallery", setting: "indoor", price: 1, vibe: "chill", minMinutes: 60, tags: ["Arts", "Free-ish"] },
  { activity: "Pottery painting", description: "Paint your own mug or plate at a ceramics studio.", category: "arts", term: "paint your own pottery studio", setting: "indoor", price: 3, vibe: "chill", minMinutes: 90, tags: ["Arts", "Creative"] },
  // nature
  { activity: "Botanical garden", description: "Explore the gardens and greenhouses together.", category: "nature", term: "botanical garden", setting: "outdoor", price: 1, vibe: "chill", minMinutes: 60, tags: ["Nature", "Outdoors"] },
  { activity: "Picnic in the park", description: "Bring snacks and claim a sunny spot on the grass.", category: "nature", term: "park with picnic area", setting: "outdoor", price: 1, vibe: "chill", minMinutes: 60, tags: ["Nature", "Outdoors"] },
  { activity: "Beach afternoon", description: "Hang out by the water and soak up some sun.", category: "nature", term: "beach", setting: "outdoor", price: 1, vibe: "chill", minMinutes: 90, tags: ["Nature", "Outdoors"] },
  { activity: "Conservatory visit", description: "Warm, green and calm, whatever the weather outside.", category: "nature", term: "conservatory greenhouse", setting: "indoor", price: 1, vibe: "chill", minMinutes: 60, tags: ["Nature", "Indoors"] },
  { activity: "Zoo", description: "Visit the animals and grab a snack along the way.", category: "nature", term: "zoo", setting: "outdoor", price: 1, vibe: "either", minMinutes: 120, tags: ["Nature"] },
  // markets & shopping
  { activity: "Farmers market", description: "Browse the stalls and grab snacks from local vendors.", category: "markets", term: "farmers market", setting: "outdoor", price: 1, vibe: "lively", minMinutes: 60, tags: ["Market", "Outdoors"] },
  { activity: "Thrift store hunt", description: "Dig for the best find under ten dollars.", category: "markets", term: "thrift store", setting: "indoor", price: 1, vibe: "chill", minMinutes: 60, tags: ["Shopping"] },
  { activity: "Bookstore browse", description: "Wander the shelves at an independent bookstore.", category: "markets", term: "independent bookstore", setting: "indoor", price: 1, vibe: "chill", minMinutes: 45, tags: ["Shopping", "Chill"] },
  { activity: "Record store dig", description: "Flip through crates at a local record store.", category: "markets", term: "record store", setting: "indoor", price: 1, vibe: "chill", minMinutes: 45, tags: ["Music", "Shopping"] },
  // events
  { activity: "Night market", description: "Street food and stalls at a night market.", category: "events", term: "night market", setting: "outdoor", price: 2, vibe: "lively", minMinutes: 90, tags: ["Event", "Lively"] },
  { activity: "Local show", description: "See what's on tonight at a local theater.", category: "events", term: "theater", setting: "indoor", price: 3, vibe: "either", minMinutes: 120, tags: ["Event", "Arts"] },
  { activity: "Sports game", description: "Catch a local game and cheer together.", category: "events", term: "sports stadium", setting: "either", price: 3, vibe: "lively", minMinutes: 150, tags: ["Event", "Lively"] },
];

/** Hangouts are always out somewhere: no stay-in, at-home or walk ideas. */
const BANNED = /\b(stay[- ]?in|at home|home[- ]cooked|potluck|movie night in|netflix|walk|walking|stroll)\b/i;

function seedScore(s: Seed, prefs: GroupPreferences): number {
  let score = 0;
  const idx = prefs.likedTypes.indexOf(s.category);
  if (idx >= 0) score += 10 - Math.min(idx, 6);
  score += prefs.scores[s.category]?.score ?? 0;
  if (prefs.avoidTypes.includes(s.category)) score -= 20;
  if (prefs.setting !== "either" && s.setting !== "either" && s.setting !== prefs.setting) score -= 8;
  if (prefs.vibe !== "either" && s.vibe !== "either" && s.vibe !== prefs.vibe) score -= 3;
  // Soft interests signal: words from members' interests that appear in the seed.
  const blob = `${s.activity} ${s.term} ${s.tags.join(" ")}`.toLowerCase();
  for (const text of prefs.interests) {
    for (const w of text.toLowerCase().split(/[^a-z]+/)) {
      if (w.length >= 4 && blob.includes(w)) score += 2;
    }
  }
  return score;
}

function buildQuery(term: string, areaText: string): string {
  return areaText.trim() ? `${term} near ${areaText.trim()}` : term;
}

/** Fallback ideas filtered and ranked by the group's preferences, with category variety. */
export function fallbackIdeas(input: Pick<GenerateIdeasInput, "count" | "prefs" | "start" | "end" | "areaText" | "excludeActivities">): Idea[] {
  const { count, prefs } = input;
  const durationMin = Math.max(0, (input.end.getTime() - input.start.getTime()) / 60000);
  const excluded = new Set(input.excludeActivities.map((a) => a.trim().toLowerCase()));
  const ceiling = prefs.maxPriceLevel ?? PRICE_LEVEL.mid;

  const pick = (strict: boolean, allowRepeats = false): Seed[] => {
    const candidates = SEEDS.filter((s) => allowRepeats || !excluded.has(s.activity.toLowerCase()))
      .filter((s) => !strict || s.price <= ceiling)
      .filter((s) => !strict || durationMin === 0 || s.minMinutes <= durationMin + 15)
      .filter((s) => !strict || !prefs.avoidTypes.includes(s.category))
      .filter((s) => !strict || prefs.setting === "either" || s.setting === "either" || s.setting === prefs.setting)
      .map((s) => ({ s, score: seedScore(s, prefs) }))
      .sort((a, b) => b.score - a.score);
    // Round-robin across categories (best category first) for variety.
    const byCat = new Map<string, Seed[]>();
    for (const { s } of candidates) {
      const list = byCat.get(s.category) ?? [];
      list.push(s);
      byCat.set(s.category, list);
    }
    const out: Seed[] = [];
    const cats = [...byCat.keys()];
    let added = true;
    while (added) {
      added = false;
      for (const c of cats) {
        const next = byCat.get(c)!.shift();
        if (next) { out.push(next); added = true; }
      }
    }
    return out;
  };

  let chosen = pick(true);
  if (chosen.length < count) {
    const extra = pick(false).filter((s) => !chosen.includes(s));
    chosen = [...chosen, ...extra];
  }
  if (chosen.length < count) {
    // Many rounds in: repeat earlier kinds of ideas rather than return too few.
    const repeats = pick(false, true).filter((s) => !chosen.includes(s));
    chosen = [...chosen, ...repeats];
  }
  return chosen.slice(0, Math.max(0, count)).map((s) => ({
    activity: s.activity,
    description: s.description,
    category: s.category,
    searchQuery: buildQuery(s.term, input.areaText),
    tags: s.tags,
  }));
}

// ---------------------------------------------------------------------------
// Gemini
// ---------------------------------------------------------------------------

function describeTime(start: Date, end: Date, timeZone?: string): string {
  const minutes = Math.round((end.getTime() - start.getTime()) / 60000);
  let local = "";
  try {
    const fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: timeZone || "America/Chicago",
      weekday: "long", month: "long", day: "numeric", hour: "numeric", minute: "2-digit",
    });
    local = fmt.format(start);
  } catch {
    local = start.toISOString();
  }
  return `${local} (local time), for about ${minutes} minutes`;
}

function buildPrompt(input: GenerateIdeasInput): string {
  const lines = [
    "You plan casual hangouts for a group of friends. Suggest specific kinds of outings that suit the WHOLE group.",
    `Return exactly ${input.count} ideas as a JSON array. Each item: {"activity": short name (2-5 words), "description": one friendly sentence (max 20 words), "category": one of ${TYPE_IDS.join("|")}, "searchQuery": a Google Maps text search that finds a real place for it, like "bowling alley near Hyde Park, Chicago", "tags": 1-3 short tags}.`,
    "Rules:",
    "- Always out somewhere at a real venue type that Google Maps can find. No stay-in, at-home, walking or stroll ideas.",
    "- Do not name a specific business; describe the kind of place in searchQuery (the app finds the real venue).",
    "- Vary the ideas across the group's liked activity types; mostly match preferences but include a few different ones.",
    "- Respect the budget and the time of day (e.g. no brunch at night, nothing that closes before the start time).",
    `- When it starts: ${describeTime(input.start, input.end, input.timeZone)}.`,
    `- Area: ${input.areaText.trim() || "unknown"}${input.center ? ` (around ${input.center.lat.toFixed(3)}, ${input.center.lng.toFixed(3)})` : ""}. Put this area in every searchQuery.`,
  ];
  if (input.planDescription.trim()) lines.push(`- The group's own plan notes: "${input.planDescription.trim().slice(0, 300)}".`);
  if (input.excludeActivities.length > 0) {
    lines.push(`- Do NOT repeat these earlier ideas: ${input.excludeActivities.slice(0, 60).join(", ")}.`);
  }
  lines.push("", "Group preferences:", toPromptText(input.prefs));
  return lines.join("\n");
}

const RESPONSE_SCHEMA = {
  type: "ARRAY",
  items: {
    type: "OBJECT",
    properties: {
      activity: { type: "STRING" },
      description: { type: "STRING" },
      category: { type: "STRING" },
      searchQuery: { type: "STRING" },
      tags: { type: "ARRAY", items: { type: "STRING" } },
    },
    required: ["activity", "description", "category", "searchQuery"],
  },
};

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Defensive parse of a Gemini generateContent response into ideas. Exported for tests. */
export function parseGeminiIdeas(data: unknown, areaText: string): Idea[] {
  const d = data as { candidates?: { content?: { parts?: { text?: unknown }[] } }[] } | null;
  const parts = d?.candidates?.[0]?.content?.parts ?? [];
  let text = parts.map((p) => (typeof p?.text === "string" ? p.text : "")).join("").trim();
  if (!text) return [];
  text = text.replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/, "").trim();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    const m = text.match(/\[[\s\S]*\]/);
    if (!m) return [];
    try { parsed = JSON.parse(m[0]); } catch { return []; }
  }
  const arr: unknown[] = Array.isArray(parsed)
    ? parsed
    : Array.isArray((parsed as { ideas?: unknown })?.ideas) ? (parsed as { ideas: unknown[] }).ideas : [];
  const out: Idea[] = [];
  for (const raw of arr) {
    const r = (raw ?? {}) as Record<string, unknown>;
    const activity = str(r.activity).slice(0, 60);
    if (!activity) continue;
    const catRaw = str(r.category).toLowerCase();
    const category = (TYPE_IDS as readonly string[]).includes(catRaw) ? catRaw : catRaw || "food";
    const searchQuery = str(r.searchQuery) || buildQuery(activity, areaText);
    const tags = Array.isArray(r.tags) ? r.tags.map(str).filter((t) => t.length > 0).slice(0, 3) : [];
    out.push({ activity, description: str(r.description).slice(0, 200), category, searchQuery, tags });
  }
  return out;
}

export async function generateIdeas(input: GenerateIdeasInput): Promise<Idea[]> {
  const count = Math.max(0, Math.floor(input.count));
  if (count === 0) return [];
  const excluded = new Set(input.excludeActivities.map((a) => a.trim().toLowerCase()));
  let ideas: Idea[] = [];

  const key = envVar("GEMINI_API_KEY");
  if (key) {
    const body = {
      contents: [{ role: "user", parts: [{ text: buildPrompt({ ...input, count }) }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
        temperature: 0.9,
      },
    };
    const data = await fetchJson(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
      { method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": key }, body: JSON.stringify(body) },
      GEMINI_TIMEOUT_MS,
      "gemini",
    );
    if (data) ideas = parseGeminiIdeas(data, input.areaText);
  } else {
    logWarn("[gemini] GEMINI_API_KEY not set; using built-in ideas");
  }

  // Filter: no banned ideas, no repeats of earlier rounds, no duplicates.
  const seen = new Set<string>();
  ideas = ideas.filter((i) => {
    const k = i.activity.toLowerCase();
    if (BANNED.test(`${i.activity} ${i.searchQuery}`) || excluded.has(k) || seen.has(k)) return false;
    seen.add(k);
    return true;
  });

  if (ideas.length < count) {
    const topUp = fallbackIdeas({
      ...input,
      count: count + ideas.length,
      excludeActivities: [...input.excludeActivities, ...ideas.map((i) => i.activity)],
    }).filter((i) => !seen.has(i.activity.toLowerCase()));
    ideas = [...ideas, ...topUp];
  }
  return ideas.slice(0, count);
}
