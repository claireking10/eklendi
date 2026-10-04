// Callable implementations (wrapped by onCall in index.ts).
import { FieldValue } from "firebase-admin/firestore";
import type { DocumentData } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { db, hangoutRef, inGroup, toMs, ts, generateRound, advanceHangout } from "./advance";
import { geocode } from "./places";

type Data = DocumentData;

const MAX_DURATION_MS = 12 * 60 * 60_000;

function requireString(v: unknown, field: string): string {
  if (typeof v !== "string" || v.trim().length === 0) throw new HttpsError("invalid-argument", `${field} is required`);
  return v.trim();
}

function requireMs(v: unknown, field: string): number {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  if (!Number.isFinite(n)) throw new HttpsError("invalid-argument", `${field} must be epoch milliseconds`);
  return Math.round(n);
}

/**
 * suggestTime {hangoutId, start, end} (epoch ms). Adds a "suggested" slot (or promotes a matching
 * "No mutual time" offer), records the suggester's yes, makes everyone who already finished swipe
 * again, and puts the hangout back in votingTimes.
 */
export async function suggestTimeImpl(uid: string | undefined, data: unknown): Promise<{ slotId: string }> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first");
  const d = (data ?? {}) as Record<string, unknown>;
  const hangoutId = requireString(d.hangoutId, "hangoutId");
  const start = requireMs(d.start, "start");
  const end = requireMs(d.end, "end");
  if (end <= start) throw new HttpsError("invalid-argument", "end must be after start");
  if (end - start > MAX_DURATION_MS) throw new HttpsError("invalid-argument", "A hangout can be at most 12 hours");
  if (start < Date.now() - 5 * 60_000) throw new HttpsError("invalid-argument", "That time has already passed");

  const ref = hangoutRef(hangoutId);
  const slotId = await db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    if (!hs.exists) throw new HttpsError("not-found", "Hangout not found");
    const h = hs.data() as Data;
    if (h.status !== "votingTimes" && h.status !== "noMutualTime") {
      throw new HttpsError("failed-precondition", "Times can only be suggested while the group is picking a time");
    }
    const membersSnap = await tx.get(ref.collection("members"));
    const me = membersSnap.docs.find((m) => m.id === uid);
    if (!me || !inGroup(me.data())) throw new HttpsError("permission-denied", "You're not in this hangout");
    const myName = typeof me.data().name === "string" && me.data().name ? String(me.data().name).split(" ")[0] : "Someone";
    const slotsSnap = await tx.get(ref.collection("slots"));

    const same = (s: Data): boolean => toMs(s.start) === start && toMs(s.end) === end;
    const existing = slotsSnap.docs.find((s) => s.data().offerOnly !== true && same(s.data()));
    const offer = slotsSnap.docs.find((s) => s.data().offerOnly === true && same(s.data()));
    let id: string;
    if (existing) {
      id = existing.id;
    } else if (offer) {
      id = offer.id;
      tx.update(offer.ref, {
        source: "suggested", suggestedBy: uid, offerOnly: FieldValue.delete(),
        label: "Suggested", reason: `Suggested by ${myName}`, rank: 100,
      });
    } else {
      const newRef = ref.collection("slots").doc();
      id = newRef.id;
      tx.set(newRef, {
        start: ts(start), end: ts(end), source: "suggested", suggestedBy: uid, missingMemberIds: [],
        rank: 100, label: "Suggested", reason: `Suggested by ${myName}`, durationMinutes: Math.round((end - start) / 60_000),
      });
    }
    // Leaving "No mutual time": the remaining offers that nobody picked go away.
    if (h.status === "noMutualTime") {
      for (const s of slotsSnap.docs) if (s.data().offerOnly === true && s.id !== id) tx.delete(s.ref);
    }
    // Everyone else who already finished swipes the new card.
    for (const m of membersSnap.docs) {
      if (m.id !== uid && inGroup(m.data()) && m.data().timesDone === true) tx.update(m.ref, { timesDone: false });
    }
    // The suggester obviously wants it.
    tx.set(ref.collection("timeVotes").doc(uid), { votes: { [id]: "yes" } }, { merge: true });
    tx.update(ref, {
      status: "votingTimes",
      statusMessage: `${myName} suggested a new time.`,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return id;
  });
  await advanceHangout(hangoutId);
  return { slotId };
}

/** startNewRound {hangoutId}: from noAgreement → round + 1, generate new cards. */
export async function startNewRoundImpl(uid: string | undefined, data: unknown): Promise<{ round: number }> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first");
  const d = (data ?? {}) as Record<string, unknown>;
  const hangoutId = requireString(d.hangoutId, "hangoutId");
  const ref = hangoutRef(hangoutId);

  const claimed = await db().runTransaction(async (tx) => {
    const hs = await tx.get(ref);
    if (!hs.exists) throw new HttpsError("not-found", "Hangout not found");
    const h = hs.data() as Data;
    const me = await tx.get(ref.collection("members").doc(uid));
    if (!me.exists || !inGroup(me.data())) throw new HttpsError("permission-denied", "You're not in this hangout");
    const round = typeof h.round === "number" ? h.round : 1;
    if (h.status === "generating" || h.status === "votingCards") return { round, generate: false }; // someone already did
    if (h.status !== "noAgreement") throw new HttpsError("failed-precondition", "A new round can only start after a round with no agreement");
    const next = round + 1;
    tx.update(ref, {
      round: next,
      status: "generating",
      generationRound: next,
      generationStartedAt: FieldValue.serverTimestamp(),
      topCardIds: [],
      statusMessage: "Finding new ideas…",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { round: next, generate: true };
  });
  if (claimed.generate) {
    await generateRound(hangoutId, claimed.round);
    await advanceHangout(hangoutId);
  }
  return { round: claimed.round };
}

/** geocodeLocation {text} → {text, lat, lng}. */
export async function geocodeLocationImpl(uid: string | undefined, data: unknown): Promise<{ text: string; lat: number; lng: number }> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first");
  const d = (data ?? {}) as Record<string, unknown>;
  const text = requireString(d.text, "text");
  if (text.length > 200) throw new HttpsError("invalid-argument", "That location is too long");
  if (/^\s*\d{5}(-\d{4})?\s*$/.test(text)) {
    throw new HttpsError("invalid-argument", "A zip code alone isn't precise enough. Add a street, neighborhood or city.");
  }
  const result = await geocode(text);
  if (!result) throw new HttpsError("not-found", "Couldn't find that place. Try a street, neighborhood or city.");
  return result;
}
