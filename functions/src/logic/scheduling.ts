// Mutual free windows, buffers, sensible hours, slot ranking, horizon extension and the
// "all but one" fallback. Pure: epoch milliseconds in, epoch milliseconds out.
// See CLAUDE.md "Calendars and scheduling", "Time horizon", "No mutual availability"
// and docs/ARCHITECTURE.md (slots).

import {
  Interval, MemberAvailability, MAX_SLOTS, HORIZON_DAYS, EXTENDED_HORIZON_DAYS, DEFAULT_BUFFER_MINUTES,
} from "./types";

export const MINUTE_MS = 60_000;
export const HOUR_MS = 60 * MINUTE_MS;
export const DAY_MS = 24 * HOUR_MS;
export const DEFAULT_TIME_ZONE = "America/Chicago";
/** Sensible hours: start no earlier than 9:00, end no later than 23:00 (owner's time zone). */
export const DAY_START_HOUR = 9;
export const DAY_END_HOUR = 23;
/** Never start within 1 hour of now. */
export const MIN_LEAD_MINUTES = 60;
/** Durations used when the owner picked "I don't care how long". */
export const DEFAULT_ANY_DURATIONS = [60, 120];
const SLOT_STEP_MS = 30 * MINUTE_MS;

export type SlotSource = "computed" | "fallback";

export interface ComputedSlot {
  start: number;
  end: number;
  durationMinutes: number;
  /** 1-based rank (1 = best). */
  rank: number;
  label: string;
  reason: string;
  /** Non-empty only for "all but one" fallback slots. */
  missingMemberIds: string[];
  source: SlotSource;
}

export interface ComputeSlotsInput {
  members: MemberAvailability[];
  durationsMinutes: number[];
  durationAny: boolean;
  nowMs: number;
  ownerTimeZone?: string | null;
  /** Starting horizon, default 14. Extended to 30 when nothing fits. */
  horizonDays?: number;
  maxSlots?: number;
}

export interface ComputeSlotsResult {
  slots: ComputedSlot[];
  horizonDays: number;
  /** true when the slots are "all but one" fallback slots. */
  fallback: boolean;
}

// ───────────────────────── time zone helpers (Intl only) ─────────────────────────

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatter(tz: string): Intl.DateTimeFormat {
  let f = formatterCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz, hourCycle: "h23",
      year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
    });
    formatterCache.set(tz, f);
  }
  return f;
}

/** Returns a valid IANA zone (falls back to America/Chicago). */
export function resolveTimeZone(tz?: string | null): string {
  if (!tz) return DEFAULT_TIME_ZONE;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return DEFAULT_TIME_ZONE;
  }
}

export interface LocalParts {
  year: number; month: number; day: number; hour: number; minute: number; second: number;
  /** 0 = Sunday … 6 = Saturday */
  weekday: number;
}

export function localParts(ms: number, tz: string): LocalParts {
  const parts = formatter(tz).formatToParts(new Date(ms));
  const get = (type: string): number => {
    const p = parts.find((x) => x.type === type);
    return p ? parseInt(p.value, 10) : 0;
  };
  const year = get("year"), month = get("month"), day = get("day");
  let hour = get("hour");
  if (hour === 24) hour = 0;
  const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return { year, month, day, hour, minute: get("minute"), second: get("second"), weekday };
}

/** Offset of `tz` from UTC at instant `ms`, in ms (Chicago in summer → -5h). */
export function tzOffsetMs(ms: number, tz: string): number {
  const p = localParts(ms, tz);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  const floored = Math.floor(ms / 1000) * 1000;
  return asUtc - floored;
}

/** Wall-clock time in `tz` → epoch ms. month is 1-based; day may overflow (normalized). */
export function localToUtc(year: number, month: number, day: number, hour: number, minute: number, tz: string): number {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  let t = guess - tzOffsetMs(guess, tz);
  const off2 = tzOffsetMs(t, tz);
  if (guess - off2 !== t) t = guess - off2;
  return t;
}

/** Round up to the next :00 or :30 in local time. */
export function ceilToHalfHour(ms: number, tz: string): number {
  const off = tzOffsetMs(ms, tz);
  const local = ms + off;
  const rounded = Math.ceil(local / SLOT_STEP_MS) * SLOT_STEP_MS;
  return rounded - off;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function formatTime(ms: number, tz: string): string {
  const p = localParts(ms, tz);
  const h12 = p.hour % 12 === 0 ? 12 : p.hour % 12;
  const mm = p.minute < 10 ? `0${p.minute}` : `${p.minute}`;
  return `${h12}:${mm} ${p.hour < 12 ? "AM" : "PM"}`;
}

export function formatDay(ms: number, tz: string): string {
  const p = localParts(ms, tz);
  return `${WEEKDAYS[p.weekday]}, ${MONTHS[p.month - 1]} ${p.day}`;
}

// ───────────────────────── intervals ─────────────────────────

export function normalizeDurations(durationsMinutes: number[], durationAny: boolean): number[] {
  const valid = (durationsMinutes ?? [])
    .filter((d) => typeof d === "number" && Number.isFinite(d) && d >= 15 && d <= 12 * 60)
    .map((d) => Math.round(d));
  const unique = Array.from(new Set(valid)).sort((a, b) => a - b);
  if (durationAny || unique.length === 0) return DEFAULT_ANY_DURATIONS.slice();
  return unique;
}

function bufferOf(m: MemberAvailability): number {
  const b = m.bufferMinutes;
  return typeof b === "number" && Number.isFinite(b) && b >= 0 ? b : DEFAULT_BUFFER_MINUTES;
}

/** Union of every member's busy blocks, each widened by that member's buffer on both sides. */
export function mergedBusy(members: MemberAvailability[]): Interval[] {
  const all: Interval[] = [];
  for (const m of members) {
    const buf = bufferOf(m) * MINUTE_MS;
    for (const b of m.busy ?? []) {
      if (!b || !Number.isFinite(b.start) || !Number.isFinite(b.end) || b.end <= b.start) continue;
      all.push({ start: b.start - buf, end: b.end + buf });
    }
  }
  all.sort((a, b) => a.start - b.start);
  const out: Interval[] = [];
  for (const iv of all) {
    const last = out[out.length - 1];
    if (last && iv.start <= last.end) last.end = Math.max(last.end, iv.end);
    else out.push({ start: iv.start, end: iv.end });
  }
  return out;
}

/** window minus busy (busy must be merged + sorted). */
export function subtractBusy(window: Interval, busy: Interval[]): Interval[] {
  const out: Interval[] = [];
  let cursor = window.start;
  for (const b of busy) {
    if (b.end <= cursor) continue;
    if (b.start >= window.end) break;
    if (b.start > cursor) out.push({ start: cursor, end: Math.min(b.start, window.end) });
    cursor = Math.max(cursor, b.end);
    if (cursor >= window.end) break;
  }
  if (cursor < window.end) out.push({ start: cursor, end: window.end });
  return out;
}

interface DayWindow { window: Interval; dayIndex: number; dayKey: string; weekday: number }

function dayWindows(nowMs: number, tz: string, horizonDays: number): DayWindow[] {
  const earliest = ceilToHalfHour(nowMs + MIN_LEAD_MINUTES * MINUTE_MS, tz);
  const horizonEnd = nowMs + horizonDays * DAY_MS;
  const today = localParts(nowMs, tz);
  const out: DayWindow[] = [];
  for (let i = 0; i <= horizonDays + 1; i++) {
    const d = new Date(Date.UTC(today.year, today.month - 1, today.day + i));
    const y = d.getUTCFullYear(), m = d.getUTCMonth() + 1, day = d.getUTCDate();
    const dayStart = localToUtc(y, m, day, DAY_START_HOUR, 0, tz);
    const dayEnd = localToUtc(y, m, day, DAY_END_HOUR, 0, tz);
    const start = Math.max(dayStart, earliest);
    const end = Math.min(dayEnd, horizonEnd);
    if (end <= start) continue;
    out.push({ window: { start, end }, dayIndex: i, dayKey: `${y}-${m}-${day}`, weekday: d.getUTCDay() });
  }
  return out;
}

/** Mutual free windows (sensible hours, buffers applied, ≥1h from now) within the horizon. */
export function freeWindows(members: MemberAvailability[], nowMs: number, ownerTimeZone: string | null | undefined, horizonDays: number): Interval[] {
  const tz = resolveTimeZone(ownerTimeZone);
  const busy = mergedBusy(members);
  const out: Interval[] = [];
  for (const dw of dayWindows(nowMs, tz, horizonDays)) out.push(...subtractBusy(dw.window, busy));
  return out;
}

// ───────────────────────── candidates & ranking ─────────────────────────

interface Candidate {
  start: number;
  end: number;
  duration: number;
  score: number;
  dayKey: string;
  dayIndex: number;
  weekend: boolean;
  evening: boolean;
  window: Interval;
  missingMemberIds: string[];
}

function timeOfDayScore(hour: number, weekday: number): number {
  const weekend = weekday === 0 || weekday === 6;
  if (weekend) {
    if (hour >= 11 && hour <= 19.5) return 10;
    if (hour >= 9 && hour < 11) return 6;
    return 7;
  }
  if (hour >= 17 && hour <= 19.5) return weekday === 5 ? 11 : 10;
  if (hour > 19.5 && hour <= 21) return 7;
  if (hour >= 12 && hour <= 13) return 4;
  if (hour > 21) return 3;
  return 1; // weekday working hours
}

function candidatesFor(
  members: MemberAvailability[], nowMs: number, tz: string, horizonDays: number, durations: number[], missing: string[],
): Candidate[] {
  const busy = mergedBusy(members);
  const out: Candidate[] = [];
  for (const dw of dayWindows(nowMs, tz, horizonDays)) {
    const weekend = dw.weekday === 0 || dw.weekday === 6;
    for (const free of subtractBusy(dw.window, busy)) {
      for (const dur of durations) {
        const durMs = dur * MINUTE_MS;
        for (let s = ceilToHalfHour(free.start, tz); s + durMs <= free.end; s += SLOT_STEP_MS) {
          const p = localParts(s, tz);
          const hour = p.hour + p.minute / 60;
          const roomyHours = Math.min(3, (free.end - free.start - durMs) / HOUR_MS);
          const score =
            timeOfDayScore(hour, dw.weekday)
            - 0.6 * dw.dayIndex
            + 0.5 * roomyHours
            + 0.3 * Math.min(3, dur / 60);
          out.push({
            start: s, end: s + durMs, duration: dur, score, dayKey: dw.dayKey, dayIndex: dw.dayIndex,
            weekend, evening: !weekend && hour >= 17, window: free, missingMemberIds: missing,
          });
        }
      }
    }
  }
  return out;
}

function overlaps(a: Candidate, b: Candidate, gapMs: number): boolean {
  return a.start < b.end + gapMs && b.start < a.end + gapMs;
}

function byScore(a: Candidate, b: Candidate): number {
  return b.score - a.score || a.start - b.start || a.duration - b.duration;
}

function selectSpread(cands: Candidate[], max: number, durations: number[]): Candidate[] {
  const sorted = cands.slice().sort(byScore);
  const chosen: Candidate[] = [];
  const usedDays = new Set<string>();
  const conflicts = (c: Candidate): boolean => chosen.some((x) => x.dayKey === c.dayKey && overlaps(x, c, HOUR_MS));

  // Pass 1: best slot per day (spreads across days).
  for (const c of sorted) {
    if (chosen.length >= max) break;
    if (usedDays.has(c.dayKey)) continue;
    chosen.push(c);
    usedDays.add(c.dayKey);
  }
  // Pass 2: a second, non-overlapping slot on a day if there's room left.
  for (const c of sorted) {
    if (chosen.length >= max) break;
    if (chosen.includes(c) || conflicts(c)) continue;
    if (chosen.filter((x) => x.dayKey === c.dayKey).length >= 2) continue;
    chosen.push(c);
  }

  // Mix: make sure weekend / weeknight / every selected duration show up when possible.
  const protectedSet = new Set<Candidate>();
  if (chosen.length > 0) protectedSet.add(chosen[0]);
  const ensure = (pred: (c: Candidate) => boolean): void => {
    const existing = chosen.find(pred);
    if (existing) { protectedSet.add(existing); return; }
    const pick = sorted.find((c) => pred(c) && !chosen.includes(c) && !conflicts(c));
    if (!pick) return;
    if (chosen.length < max) {
      chosen.push(pick);
    } else {
      let victimIdx = -1;
      for (let i = chosen.length - 1; i >= 0; i--) {
        if (!protectedSet.has(chosen[i])) { victimIdx = i; break; }
      }
      if (victimIdx < 0) return;
      chosen.splice(victimIdx, 1, pick);
    }
    protectedSet.add(pick);
  };
  ensure((c) => c.weekend);
  ensure((c) => c.evening);
  if (durations.length > 1) for (const d of durations) ensure((c) => c.duration === d);

  return chosen.sort(byScore);
}

function describe(
  c: Candidate, members: MemberAvailability[], tz: string, index: number, earliestStart: number, nameOf: (uid: string) => string,
): { label: string; reason: string } {
  if (c.missingMemberIds.length > 0) {
    const who = c.missingMemberIds.map(nameOf).join(" and ");
    return { label: "All but one", reason: `Everyone but ${who} is free` };
  }
  const p = localParts(c.start, tz);
  let label: string;
  if (index === 0) label = "Best match";
  else if (c.start === earliestStart) label = "Soonest";
  else if (c.weekend) label = "Weekend";
  else if (p.hour >= 17) label = "Weeknight";
  else label = "Daytime";

  // Reason: the busy block that this slot starts right after (buffer applied).
  let best: { member: MemberAvailability; gapMin: number } | null = null;
  for (const m of members) {
    const buf = bufferOf(m);
    for (const b of m.busy ?? []) {
      const gapMin = (c.start - b.end) / MINUTE_MS;
      if (gapMin >= buf && gapMin <= buf + 30 && (!best || gapMin < best.gapMin)) best = { member: m, gapMin };
    }
  }
  if (best) {
    const name = best.member.name ? `${best.member.name}'s` : "someone's";
    return { label, reason: `Starts ${Math.round(best.gapMin)} min after ${name} event ends` };
  }
  const dayStart = localToUtc(p.year, p.month, p.day, DAY_START_HOUR, 0, tz);
  const dayEnd = localToUtc(p.year, p.month, p.day, DAY_END_HOUR, 0, tz);
  if (c.window.start <= dayStart && c.window.end >= dayEnd) {
    return { label, reason: c.evening ? "Everyone's free all evening" : "Everyone's free all day" };
  }
  if (c.window.end >= dayEnd) {
    return { label, reason: `Everyone's free from ${formatTime(c.window.start, tz)} on` };
  }
  return { label, reason: `Everyone's free ${formatTime(c.window.start, tz)} – ${formatTime(c.window.end, tz)}` };
}

function finalize(
  chosen: Candidate[], members: MemberAvailability[], tz: string, source: SlotSource,
): ComputedSlot[] {
  const names = new Map<string, string>(members.map((m) => [m.uid, m.name || "someone"]));
  const nameOf = (uid: string): string => names.get(uid) ?? "someone";
  const earliestStart = chosen.reduce((min, c) => Math.min(min, c.start), Number.POSITIVE_INFINITY);
  return chosen.map((c, i) => {
    const relevant = c.missingMemberIds.length > 0 ? members.filter((m) => !c.missingMemberIds.includes(m.uid)) : members;
    const { label, reason } = describe(c, relevant, tz, i, earliestStart, nameOf);
    return {
      start: c.start, end: c.end, durationMinutes: c.duration, rank: i + 1, label, reason,
      missingMemberIds: c.missingMemberIds.slice(), source,
    };
  });
}

export interface SlotFilter {
  /** Only slots starting at or after this instant. */
  notBefore?: number;
  /** Skip slots overlapping any of these (e.g. times already offered). */
  exclude?: Interval[];
}

function passes(c: Candidate, f: SlotFilter): boolean {
  if (f.notBefore !== undefined && c.start < f.notBefore) return false;
  if (f.exclude && f.exclude.some((e) => c.start < e.end && e.start < c.end)) return false;
  return true;
}

/** Ranked, spread-out full-group slots in a given horizon (no extension, no fallback). */
export function findSlots(input: ComputeSlotsInput & { horizonDays: number } & SlotFilter): ComputedSlot[] {
  const tz = resolveTimeZone(input.ownerTimeZone);
  const durations = normalizeDurations(input.durationsMinutes, input.durationAny);
  const max = input.maxSlots ?? MAX_SLOTS;
  if (input.members.length === 0) return [];
  const cands = candidatesFor(input.members, input.nowMs, tz, input.horizonDays, durations, [])
    .filter((c) => passes(c, input));
  return finalize(selectSpread(cands, max, durations), input.members, tz, "computed");
}

/** "All but one" slots: windows where every member except one is free (groups of 3+ only). */
export function findAllButOneSlots(input: ComputeSlotsInput & { horizonDays: number } & SlotFilter): ComputedSlot[] {
  const tz = resolveTimeZone(input.ownerTimeZone);
  const durations = normalizeDurations(input.durationsMinutes, input.durationAny);
  const max = input.maxSlots ?? MAX_SLOTS;
  if (input.members.length < 3) return [];
  const all: Candidate[] = [];
  for (const missing of input.members) {
    const others = input.members.filter((m) => m.uid !== missing.uid);
    all.push(...candidatesFor(others, input.nowMs, tz, input.horizonDays, durations, [missing.uid]).filter((c) => passes(c, input)));
  }
  return finalize(selectSpread(all, max, durations), input.members, tz, "fallback");
}

/**
 * Main entry: 14-day horizon → extend to 30 → "all but one" fallback → nothing.
 */
export function computeSlots(input: ComputeSlotsInput): ComputeSlotsResult {
  const first = input.horizonDays && input.horizonDays > 0 ? input.horizonDays : HORIZON_DAYS;
  const horizons = first < EXTENDED_HORIZON_DAYS ? [first, EXTENDED_HORIZON_DAYS] : [first];
  for (const h of horizons) {
    const slots = findSlots({ ...input, horizonDays: h });
    if (slots.length > 0) return { slots, horizonDays: h, fallback: false };
  }
  for (const h of horizons) {
    const slots = findAllButOneSlots({ ...input, horizonDays: h });
    if (slots.length > 0) return { slots, horizonDays: h, fallback: true };
  }
  return { slots: [], horizonDays: horizons[horizons.length - 1], fallback: false };
}

/**
 * Alternatives for the "No mutual time" screen (08b) after a time vote found no winner:
 * full-group slots later in the month (after the first 2 weeks when possible) plus
 * "all but one" slots in the next 2 weeks, never overlapping a time already offered.
 */
export function computeFallbackOffers(
  input: ComputeSlotsInput & { exclude?: Interval[] },
): ComputedSlot[] {
  const exclude = input.exclude ?? [];
  const base = { ...input, exclude, maxSlots: 4 };
  let later = findSlots({ ...base, horizonDays: EXTENDED_HORIZON_DAYS, notBefore: input.nowMs + HORIZON_DAYS * DAY_MS });
  if (later.length === 0) later = findSlots({ ...base, horizonDays: EXTENDED_HORIZON_DAYS });
  const abo = findAllButOneSlots({ ...base, horizonDays: HORIZON_DAYS });
  const out = [...later.map((s) => ({ ...s, source: "fallback" as SlotSource, label: "Later this month" })), ...abo];
  return out.map((s, i) => ({ ...s, rank: i + 1 }));
}
