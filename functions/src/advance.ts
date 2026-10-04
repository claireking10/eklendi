// The hangout state machine (docs/ARCHITECTURE.md "Hangout state machine").
// advanceHangout(id) is idempotent: every transition re-reads the hangout inside a
// transaction and only writes when the status it expects is still current, so any
// number of concurrent triggers can call it safely. Card generation (slow: Gemini +
// Places) is guarded by first flipping status to "generating" with a generationRound
// marker inside a transaction; only the caller that won the flip does the work.

import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import type { DocumentReference, DocumentData, Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { computeSlots, computeFallbackOffers, ComputedSlot, DEFAULT_TIME_ZONE } from "./logic/scheduling";
import { pickWinner, topOptions, VoteOption, VotesByMember } from "./logic/winner";
import {
  MemberAvailability, LatLng, SurveyAnswer, Interval,
  HORIZON_DAYS, MIN_GROUP, CARDS_PER_PERSON, DEFAULT_BUFFER_MINUTES,
} from "./logic/types";
import { buildGroupPreferences } from "./logic/preferences";
import { centroid, haversineMiles } from "./logic/geo";
import { generateIdeas, Idea } from "./gemini";
import { resolveVenue, Venue } from "./places";

type Data = DocumentData;

export interface MemberRow { uid: string; ref: DocumentReference; data: Data }

/** A generation that hasn't finished after this long is considered dead and may be retried. */
const GENERATION_STALE_MS = 4 * 60_000;
const MAX_STEPS = 8;

const NOT_ENOUGH_PEOPLE = "Not enough people left to plan this. Invite someone new or cancel the hangout.";

export function db() { return getFirestore(); }
export function hangoutRef(id: string): DocumentReference { return db().collection("hangouts").doc(id); }

// ───────────────────────── small helpers ─────────────────────────

export function toMs(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (v instanceof Timestamp) return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const anyV = v as { toMillis?: () => number; _seconds?: number; seconds?: number; _nanoseconds?: number; nanoseconds?: number };
  if (typeof anyV.toMillis === "function") return anyV.toMillis();
  if (typeof anyV._seconds === "number") return anyV._seconds * 1000 + Math.floor((anyV._nanoseconds ?? 0) / 1e6);
  if (typeof anyV.seconds === "number") return anyV.seconds * 1000 + Math.floor((anyV.nanoseconds ?? 0) / 1e6);
  if (typeof v === "string") {
    const t = Date.parse(v);
    return Number.isNaN(t) ? null : t;
  }
  return null;
}

export function ts(ms: number): Timestamp { return Timestamp.fromMillis(ms); }

export function inGroup(data: Data | undefined): boolean {
  return !!data && (data.state === "active" || data.state === "invited");
}

function locOf(v: unknown): (LatLng & { text: string }) | null {
  const o = v as { lat?: unknown; lng?: unknown; text?: unknown } | null | undefined;
  if (!o || typeof o.lat !== "number" || typeof o.lng !== "number") return null;
  if (!Number.isFinite(o.lat) || !Number.isFinite(o.lng)) return null;
  return { lat: o.lat, lng: o.lng, text: typeof o.text === "string" ? o.text : "" };
}

/** Uniform random index; uses Web Crypto (global in Node 20) when present. */
export function randomIndex(n: number): number {
  const c = (globalThis as unknown as { crypto?: { getRandomValues(a: Uint32Array): Uint32Array } }).crypto;
  if (c && typeof c.getRandomValues === "function") {
    const a = new Uint32Array(1);
    c.getRandomValues(a);
    return a[0] % n;
  }
  return Math.floor(Math.random() * n);
}

async function txMembers(tx: Transaction, ref: DocumentReference): Promise<MemberRow[]> {
  const snap = await tx.get(ref.collection("members"));
  return snap.docs.map((d) => ({ uid: d.id, ref: d.ref, data: d.data() }));
}

function toAvailability(m: MemberRow): MemberAvailability {
  const busyRaw: unknown[] = Array.isArray(m.data.busy) ? m.data.busy : [];
  const busy: Interval[] = [];
  for (const b of busyRaw) {
    const o = b as { start?: unknown; end?: unknown } | null;
    if (!o) continue;
    const s = toMs(o.start), e = toMs(o.end);
    if (s !== null && e !== null && e > s) busy.push({ start: s, end: e });
  }
  const buf = typeof m.data.bufferMinutes === "number" ? m.data.bufferMinutes : DEFAULT_BUFFER_MINUTES;
  return { uid: m.uid, name: typeof m.data.name === "string" ? m.data.name : "", busy, bufferMinutes: buf };
}

function ownerTimeZone(h: Data, group: MemberRow[]): string {
  const owner = group.find((m) => m.uid === h.ownerId);
  const tz = owner?.data.timeZone ?? group.find((m) => typeof m.data.timeZone === "string")?.data.timeZone;
  return typeof tz === "string" && tz.length > 0 ? tz : DEFAULT_TIME_ZONE;
}

function slotDoc(s: ComputedSlot, extra: Data = {}): Data {
  return {
    start: ts(s.start), end: ts(s.end), source: s.source, missingMemberIds: s.missingMemberIds,
    rank: s.rank, label: s.label, reason: s.reason, durationMinutes: s.durationMinutes, ...extra,
  };
}

function firstName(name: unknown): string {
  return typeof name === "string" && name.trim().length > 0 ? name.trim().split(/\s+/)[0] : "Someone";
}

// ───────────────────────── entry point ─────────────────────────

/** Runs state-machine steps until nothing changes. Safe to call from any trigger, any number of times. */
export async function advanceHangout(hangoutId: string): Promise<void> {
  for (let i = 0; i < MAX_STEPS; i++) {
    const progressed = await step(hangoutId);
    if (!progressed) return;
  }
  logger.warn(`advanceHangout(${hangoutId}): stopped after ${MAX_STEPS} steps`);
}

async function step(hangoutId: string): Promise<boolean> {
  const ref = hangoutRef(hangoutId);
  const snap = await ref.get();
  if (!snap.exists) return false;
  const h = snap.data() as Data;
  if (h.status === "cancelled") return false;

  if (await housekeeping(ref)) return true;

  const membersSnap = await ref.collection("members").get();
  const group: MemberRow[] = membersSnap.docs
    .map((d) => ({ uid: d.id, ref: d.ref, data: d.data() }))
    .filter((m) => inGroup(m.data));
  const status: string = h.status ?? "collectingAvailability";

  if (status !== "confirmed" && membersSnap.size > 0 && group.length < MIN_GROUP) {
    if (h.statusMessage !== NOT_ENOUGH_PEOPLE) {
      await ref.update({ statusMessage: NOT_ENOUGH_PEOPLE, updatedAt: FieldValue.serverTimestamp() });
    }
    return false;
  }
  if (h.statusMessage === NOT_ENOUGH_PEOPLE && group.length >= MIN_GROUP) {
    await ref.update({ statusMessage: "" });
  }

  switch (status) {
    case "collectingAvailability":
      if (!group.every((m) => m.data.availabilitySubmitted === true)) return false;
      return computeSlotsStep(ref);
    case "votingTimes":
      if (!group.every((m) => m.data.timesDone === true)) return false;
      return timeWinnerStep(ref);
    case "survey": {
      if (!group.every((m) => m.data.surveyDone === true)) return false;
      const round = await claimGeneration(ref, "survey");
      if (round === null) return false;
      await generateRound(hangoutId, round);
      return true;
    }
    case "generating": {
      const round = await claimGeneration(ref, "generating");
      if (round === null) return false;
      await generateRound(hangoutId, round);
      return true;
    }
    case "votingCards": {
      const round = typeof h.round === "number" ? h.round : 1;
      if (!group.every((m) => (typeof m.data.cardsDoneRound === "number" ? m.data.cardsDoneRound : 0) >= round)) return false;
      return cardWinnerStep(ref);
    }
    default:
      // noMutualTime, noAgreement, confirmed: wait for a user action (suggestTime, startNewRound, reopen).
      return false;
  }
}

// ───────────────────────── housekeeping: ownership + memberIds ─────────────────────────

/** Owner declined/was removed → random remaining member becomes owner. Drops departed uids from memberIds. */
async function housekeeping(ref: DocumentReference): Promise<boolean> {
  return db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    if (!hs.exists) return false;
    const h = hs.data() as Data;
    if (h.status === "cancelled") return false;
    const members = await txMembers(tx, ref);
    const group = members.filter((m) => inGroup(m.data));
    const updates: Data = {};

    const owner = members.find((m) => m.uid === h.ownerId);
    const ownerLeft = !!owner && (owner.data.state === "declined" || owner.data.state === "removed");
    if (ownerLeft && group.length > 0) {
      const active = group.filter((m) => m.data.state === "active");
      const pool = active.length > 0 ? active : group;
      const next = pool[randomIndex(pool.length)];
      updates.ownerId = next.uid;
      updates.statusMessage = `${firstName(owner?.data.name)} left, so ${firstName(next.data.name)} is the new owner.`;
      tx.update(next.ref, { role: "owner" });
      if (owner && owner.data.role === "owner") tx.update(owner.ref, { role: "member" });
    }

    const left = new Set(members.filter((m) => m.data.state === "declined" || m.data.state === "removed").map((m) => m.uid));
    const memberIds: string[] = Array.isArray(h.memberIds) ? h.memberIds : [];
    const kept = memberIds.filter((u) => !left.has(u));
    if (kept.length !== memberIds.length) updates.memberIds = kept;

    if (Object.keys(updates).length === 0) return false;
    updates.updatedAt = FieldValue.serverTimestamp();
    tx.update(ref, updates);
    return true;
  });
}

// ───────────────────────── collectingAvailability → votingTimes | noMutualTime ─────────────────────────

async function computeSlotsStep(ref: DocumentReference): Promise<boolean> {
  return db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    const h = hs.data() as Data | undefined;
    if (!h || h.status !== "collectingAvailability") return false;
    const group = (await txMembers(tx, ref)).filter((m) => inGroup(m.data));
    if (group.length < MIN_GROUP || !group.every((m) => m.data.availabilitySubmitted === true)) return false;
    const slotsSnap = await tx.get(ref.collection("slots"));

    const result = computeSlots({
      members: group.map(toAvailability),
      durationsMinutes: Array.isArray(h.durationsMinutes) ? h.durationsMinutes : [],
      durationAny: h.durationAny === true,
      nowMs: Date.now(),
      ownerTimeZone: ownerTimeZone(h, group),
      horizonDays: HORIZON_DAYS,
    });

    let keptSuggested = 0;
    for (const d of slotsSnap.docs) {
      if (d.data().source === "suggested") keptSuggested++;
      else tx.delete(d.ref);
    }
    for (const s of result.slots) tx.set(ref.collection("slots").doc(), slotDoc(s));

    const any = result.slots.length + keptSuggested > 0;
    let msg = "";
    if (!any) msg = "No time works for everyone in the next month.";
    else if (result.fallback) msg = "No time works for everyone, so here are times when all but one of you are free.";
    else if (result.horizonDays > HORIZON_DAYS) msg = "Nothing worked in the next 2 weeks, so we looked out a full month.";

    tx.update(ref, {
      status: any ? "votingTimes" : "noMutualTime",
      horizonDays: result.horizonDays,
      statusMessage: msg,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

// ───────────────────────── votingTimes → confirmed | survey | noMutualTime ─────────────────────────

async function timeWinnerStep(ref: DocumentReference): Promise<boolean> {
  return db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    const h = hs.data() as Data | undefined;
    if (!h || h.status !== "votingTimes") return false;
    const group = (await txMembers(tx, ref)).filter((m) => inGroup(m.data));
    if (group.length < MIN_GROUP || !group.every((m) => m.data.timesDone === true)) return false;
    const slotsSnap = await tx.get(ref.collection("slots"));
    const votesSnap = await tx.get(ref.collection("timeVotes"));

    const votable = slotsSnap.docs.filter((d) => d.data().offerOnly !== true);
    const options: VoteOption[] = [];
    for (const d of votable) {
      const s = toMs(d.data().start);
      if (s === null) continue;
      const missing = d.data().missingMemberIds;
      options.push({ id: d.id, start: s, excludedVoters: Array.isArray(missing) ? missing : [] });
    }
    const votes: VotesByMember = {};
    for (const d of votesSnap.docs) votes[d.id] = (d.data().votes ?? {}) as Record<string, string>;
    const groupIds = group.map((m) => m.uid);
    const winner = pickWinner(options, groupIds, votes);

    if (winner) {
      const sd = votable.find((d) => d.id === winner.id)!.data();
      const startMs = toMs(sd.start)!, endMs = toMs(sd.end)!;
      const winningSlot = { id: winner.id, start: ts(startMs), end: ts(endMs) };
      if (h.mode === "timeOnly") {
        const activity = typeof h.planDescription === "string" && h.planDescription.trim() ? h.planDescription.trim() : "Hangout";
        tx.update(ref, {
          winningSlot,
          status: "confirmed",
          title: activity,
          confirmed: { start: ts(startMs), end: ts(endMs), activity, venueName: "", address: "", cardId: null },
          statusMessage: "",
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(ref, { winningSlot, status: "survey", statusMessage: "", updatedAt: FieldValue.serverTimestamp() });
      }
      return true;
    }

    // No winner → offer alternatives (08b): later this month (everyone) + all-but-one.
    for (const d of slotsSnap.docs) if (d.data().offerOnly === true) tx.delete(d.ref);
    const exclude: Interval[] = [];
    for (const d of votable) {
      const s = toMs(d.data().start), e = toMs(d.data().end);
      if (s !== null && e !== null) exclude.push({ start: s, end: e });
    }
    const offers = computeFallbackOffers({
      members: group.map(toAvailability),
      durationsMinutes: Array.isArray(h.durationsMinutes) ? h.durationsMinutes : [],
      durationAny: h.durationAny === true,
      nowMs: Date.now(),
      ownerTimeZone: ownerTimeZone(h, group),
      exclude,
    });
    for (const s of offers) tx.set(ref.collection("slots").doc(), slotDoc(s, { source: "fallback", offerOnly: true }));
    tx.update(ref, {
      status: "noMutualTime",
      statusMessage: "No time got a yes or maybe from everyone.",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

// ───────────────────────── survey / generating → votingCards ─────────────────────────

/**
 * Flips status to "generating" (from `from`) and stamps generationRound/generationStartedAt.
 * Returns the round to generate, or null if someone else already claimed it.
 */
async function claimGeneration(ref: DocumentReference, from: "survey" | "generating"): Promise<number | null> {
  return db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    const h = hs.data() as Data | undefined;
    if (!h || h.status !== from) return null;
    const round = typeof h.round === "number" ? h.round : 1;
    if (from === "survey") {
      const group = (await txMembers(tx, ref)).filter((m) => inGroup(m.data));
      if (group.length < MIN_GROUP || !group.every((m) => m.data.surveyDone === true)) return null;
    } else {
      const started = toMs(h.generationStartedAt);
      const fresh = h.generationRound === round && started !== null && Date.now() - started < GENERATION_STALE_MS;
      if (fresh) return null; // someone is generating right now
    }
    tx.update(ref, {
      status: "generating",
      generationRound: round,
      generationStartedAt: FieldValue.serverTimestamp(),
      statusMessage: "Finding ideas for your group…",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return round;
  });
}

interface CardData {
  round: number; activity: string; description: string; category: string; venueName: string; address: string;
  lat: number; lng: number; distanceMiles: number | null; priceLevel: number | null; photoUrl: string | null;
  placeId: string; start: Timestamp; end: Timestamp; tags: string[];
}

/**
 * Generates round `round` (3 × group size cards at the winning time) and moves to votingCards.
 * Caller must have claimed the generation (status = generating, generationRound = round).
 */
export async function generateRound(hangoutId: string, round: number): Promise<void> {
  const ref = hangoutRef(hangoutId);
  try {
    const hs = await ref.get();
    const h = hs.data() as Data | undefined;
    if (!h || h.status !== "generating" || (h.round ?? 1) !== round) return;

    const group: MemberRow[] = (await ref.collection("members").get()).docs
      .map((d) => ({ uid: d.id, ref: d.ref, data: d.data() }))
      .filter((m) => inGroup(m.data));
    const startMs = toMs(h.winningSlot?.start);
    const endMs = toMs(h.winningSlot?.end);
    if (startMs === null || endMs === null || group.length === 0) {
      await finishGeneration(ref, round, [], "We lost track of the winning time. Ask the owner to reopen the hangout.");
      return;
    }

    // Survey answers + interests → group preference model.
    const uids = group.map((m) => m.uid);
    const answerSnaps = await db().getAll(...uids.map((u) => ref.collection("surveyAnswers").doc(u)));
    const answers: Record<string, Record<string, SurveyAnswer>> = {};
    for (const s of answerSnaps) answers[s.id] = ((s.exists ? s.data()?.answers : null) ?? {}) as Record<string, SurveyAnswer>;
    const userSnaps = await db().getAll(...uids.map((u) => db().collection("users").doc(u)));
    const users = new Map<string, Data>();
    for (const s of userSnaps) if (s.exists) users.set(s.id, s.data() as Data);
    const interests = uids
      .map((u) => users.get(u)?.interests)
      .filter((t): t is string => typeof t === "string" && t.trim().length > 0);
    const prefs = buildGroupPreferences(answers, interests);

    // Locality: centroid of where members travel from (fallback: approximate home).
    const locs = group.map((m) => locOf(m.data.startLocation) ?? locOf(users.get(m.uid)?.homeLocation));
    const center = centroid(locs.filter((l): l is LatLng & { text: string } => l !== null).map((l) => ({ lat: l.lat, lng: l.lng })));
    const ownerIdx = group.findIndex((m) => m.uid === h.ownerId);
    const areaText = (ownerIdx >= 0 ? locs[ownerIdx]?.text : "") || locs.find((l) => l && l.text)?.text || "";

    // Don't repeat earlier rounds.
    const prevCards = await ref.collection("cards").get();
    const usedActivities = new Set<string>();
    const usedPlaces = new Set<string>();
    for (const d of prevCards.docs) {
      const c = d.data();
      if (c.round === round) continue;
      if (typeof c.activity === "string") usedActivities.add(c.activity);
      if (typeof c.placeId === "string" && c.placeId) usedPlaces.add(c.placeId);
    }

    const count = CARDS_PER_PERSON * group.length;
    const cards: CardData[] = [];
    for (let attempt = 0; attempt < 2 && cards.length < count; attempt++) {
      const need = count - cards.length;
      const ideas: Idea[] = await generateIdeas({
        count: need,
        prefs,
        planDescription: typeof h.planDescription === "string" ? h.planDescription : "",
        start: new Date(startMs),
        end: new Date(endMs),
        center,
        areaText,
        excludeActivities: Array.from(usedActivities),
        timeZone: ownerTimeZone(h, group),
      });
      const venues: (Venue | null)[] = await Promise.all(ideas.map((idea) => resolveVenue(idea, center)));
      ideas.forEach((idea, i) => {
        usedActivities.add(idea.activity);
        const v = venues[i];
        if (!v || !v.placeId || usedPlaces.has(v.placeId) || cards.length >= count) return;
        usedPlaces.add(v.placeId);
        cards.push({
          round,
          activity: idea.activity,
          description: idea.description,
          category: idea.category ?? "",
          venueName: v.venueName,
          address: v.address,
          lat: v.lat,
          lng: v.lng,
          distanceMiles: center ? Math.round(haversineMiles(center, { lat: v.lat, lng: v.lng }) * 10) / 10 : null,
          priceLevel: v.priceLevel,
          photoUrl: v.photoUrl,
          placeId: v.placeId,
          start: ts(startMs),
          end: ts(endMs),
          tags: Array.isArray(idea.tags) ? idea.tags : [],
        });
      });
    }
    await finishGeneration(ref, round, cards,
      cards.length === 0 ? "We couldn't find real places nearby for this round. Try new ideas." : "");
  } catch (e) {
    logger.error(`generateRound(${hangoutId}, ${round}) failed`, e);
    try {
      await finishGeneration(ref, round, [], "Something went wrong finding ideas. Try new ideas.");
    } catch (e2) {
      logger.error("finishGeneration after failure also failed", e2);
    }
  }
}

async function finishGeneration(ref: DocumentReference, round: number, cards: CardData[], message: string): Promise<void> {
  await db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    const h = hs.data() as Data | undefined;
    if (!h || h.status !== "generating" || (h.round ?? 1) !== round || h.generationRound !== round) return;
    const stale = await tx.get(ref.collection("cards").where("round", "==", round));
    for (const d of stale.docs) tx.delete(d.ref);
    for (const c of cards) tx.set(ref.collection("cards").doc(), c);
    tx.update(ref, {
      status: cards.length > 0 ? "votingCards" : "noAgreement",
      statusMessage: message,
      topCardIds: [],
      generationStartedAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

// ───────────────────────── votingCards → confirmed | noAgreement ─────────────────────────

async function cardWinnerStep(ref: DocumentReference): Promise<boolean> {
  return db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    const h = hs.data() as Data | undefined;
    if (!h || h.status !== "votingCards") return false;
    const round = typeof h.round === "number" ? h.round : 1;
    const group = (await txMembers(tx, ref)).filter((m) => inGroup(m.data));
    const doneRound = (m: MemberRow): number => (typeof m.data.cardsDoneRound === "number" ? m.data.cardsDoneRound : 0);
    if (group.length < MIN_GROUP || !group.every((m) => doneRound(m) >= round)) return false;
    const cardsSnap = await tx.get(ref.collection("cards").where("round", "==", round));
    const voteSnaps = await Promise.all(group.map((m) => tx.get(ref.collection("cardVotes").doc(`${m.uid}_${round}`))));

    const cards = cardsSnap.docs.slice().sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    const options: VoteOption[] = cards.map((d) => ({ id: d.id, start: toMs(d.data().start) ?? 0 }));
    const votes: VotesByMember = {};
    group.forEach((m, i) => {
      const s = voteSnaps[i];
      votes[m.uid] = (s.exists ? (s.data()?.votes ?? {}) : {}) as Record<string, string>;
    });
    const ids = group.map((m) => m.uid);
    const winner = pickWinner(options, ids, votes);

    if (winner) {
      const c = cards.find((d) => d.id === winner.id)!.data();
      tx.update(ref, {
        status: "confirmed",
        title: c.activity ?? "Hangout",
        confirmed: {
          start: c.start, end: c.end, activity: c.activity ?? "Hangout",
          venueName: c.venueName ?? "", address: c.address ?? "", cardId: winner.id,
        },
        topCardIds: [],
        statusMessage: "",
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      const top = topOptions(options, ids, votes, 3);
      tx.update(ref, {
        status: "noAgreement",
        topCardIds: top.map((t) => t.id),
        statusMessage: "Not everyone agrees yet.",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    return true;
  });
}

// ───────────────────────── reopen (owner) ─────────────────────────

/**
 * Called from onHangoutWrite when status moves back to collectingAvailability from a later
 * state (owner reopened a confirmed hangout, or the group restarts planning).
 * Starts a fresh round: bumps round (unless the client already did), resets every member's
 * progress (availability, times, survey), and clears slots, time votes and survey answers.
 */
export async function resetForReopen(hangoutId: string, beforeRound: number): Promise<void> {
  const ref = hangoutRef(hangoutId);
  await db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    const h = hs.data() as Data | undefined;
    if (!h || h.status !== "collectingAvailability") return;
    const current = typeof h.round === "number" ? h.round : 1;
    if (h.reopenResetRound === current && current > beforeRound) return; // already reset
    const newRound = current > beforeRound ? current : beforeRound + 1;

    const members = await txMembers(tx, ref);
    const slots = await tx.get(ref.collection("slots"));
    const timeVotes = await tx.get(ref.collection("timeVotes"));
    const survey = await tx.get(ref.collection("surveyAnswers"));

    for (const d of slots.docs) tx.delete(d.ref);
    for (const d of timeVotes.docs) tx.delete(d.ref);
    for (const d of survey.docs) tx.delete(d.ref);
    for (const m of members) {
      if (!inGroup(m.data)) continue;
      tx.update(m.ref, { availabilitySubmitted: false, timesDone: false, surveyDone: false, notGoing: false, busy: [] });
    }
    tx.update(ref, {
      round: newRound,
      reopenResetRound: newRound,
      horizonDays: HORIZON_DAYS,
      title: "",
      winningSlot: FieldValue.delete(),
      confirmed: FieldValue.delete(),
      topCardIds: [],
      generationRound: FieldValue.delete(),
      generationStartedAt: FieldValue.delete(),
      statusMessage: "Back to planning. Everyone picks a time and takes the survey again.",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

const LATER_STATES = new Set(["votingTimes", "noMutualTime", "survey", "generating", "votingCards", "noAgreement", "confirmed"]);

/** onHangoutWrite handler body. Only acts on status/round changes, so our own writes don't loop. */
export async function onHangoutChanged(hangoutId: string, before: Data | undefined, after: Data | undefined): Promise<void> {
  if (!after) return;
  const statusChanged = !before || before.status !== after.status;
  const roundChanged = !before || before.round !== after.round;
  if (!statusChanged && !roundChanged) return;
  if (before && LATER_STATES.has(before.status) && after.status === "collectingAvailability") {
    await resetForReopen(hangoutId, typeof before.round === "number" ? before.round : 1);
  }
  await advanceHangout(hangoutId);
}
