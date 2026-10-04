import { test } from "node:test";
import assert from "node:assert/strict";
import {
  computeSlots, findSlots, freeWindows, localParts, localToUtc, tzOffsetMs, ceilToHalfHour,
  normalizeDurations, mergedBusy, computeFallbackOffers, resolveTimeZone,
} from "../lib-logic/scheduling.js";

const TZ = "America/Chicago";
const MIN = 60_000;
const HOUR = 60 * MIN;
// Monday Oct 5 2026, 8:00 AM CDT (UTC-5)
const NOW = Date.UTC(2026, 9, 5, 13, 0);
const ct = (day, h, m = 0) => localToUtc(2026, 10, day, h, m, TZ); // Oct <day>, local time

const member = (uid, busy = [], bufferMinutes = 15, name = uid) => ({ uid, name, busy, bufferMinutes });

// Busy every day of the horizon except the given free window [fromH, toH) local, for days in `freeDays`.
function busyExcept(days, freeDays, fromH, toH, fromM = 0) {
  const busy = [];
  for (let d = 5; d < 5 + days; d++) {
    if (freeDays.includes(d)) {
      busy.push({ start: ct(d, 0), end: ct(d, fromH, fromM) });
      busy.push({ start: ct(d, toH), end: ct(d, 23, 59) });
    } else {
      busy.push({ start: ct(d, 0), end: ct(d, 23, 59) });
    }
  }
  return busy;
}

test("time zone helpers: Chicago offset and local conversion", () => {
  assert.equal(tzOffsetMs(NOW, TZ), -5 * HOUR);
  assert.equal(tzOffsetMs(Date.UTC(2026, 0, 15, 12), TZ), -6 * HOUR);
  assert.equal(ct(5, 8), NOW);
  const p = localParts(NOW, TZ);
  assert.deepEqual([p.year, p.month, p.day, p.hour, p.minute, p.weekday], [2026, 10, 5, 8, 0, 1]);
  assert.equal(ceilToHalfHour(ct(5, 15, 1), TZ), ct(5, 15, 30));
  assert.equal(ceilToHalfHour(ct(5, 15, 30), TZ), ct(5, 15, 30));
  assert.equal(resolveTimeZone("Not/AZone"), TZ);
  assert.equal(resolveTimeZone(undefined), TZ);
});

test("durations: multi-select kept, any → defaults", () => {
  assert.deepEqual(normalizeDurations([120, 60, 60], false), [60, 120]);
  assert.deepEqual(normalizeDurations([], false), [60, 120]);
  assert.deepEqual(normalizeDurations([30], true), [60, 120]);
  assert.deepEqual(normalizeDurations([240], false), [240]);
});

test("buffers widen busy blocks per member", () => {
  const merged = mergedBusy([
    member("a", [{ start: ct(5, 12), end: ct(5, 15) }], 15),
    member("b", [{ start: ct(5, 16), end: ct(5, 17) }], 30),
  ]);
  assert.deepEqual(merged, [
    { start: ct(5, 11, 45), end: ct(5, 15, 15) },
    { start: ct(5, 15, 30), end: ct(5, 17, 30) },
  ]);
});

test("class ends 3:00 → earliest start 3:15 (buffer), slot is a specific time", () => {
  // Only free window: Oct 5 from 3:00 PM (class ends) to 11 PM. Everything else busy.
  const busy = busyExcept(14, [5], 15, 23);
  const res = computeSlots({ members: [member("matt", busy, 15, "Matt"), member("zach")], durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ });
  assert.equal(res.horizonDays, 14);
  assert.equal(res.fallback, false);
  assert.ok(res.slots.length >= 1);
  const windows = freeWindows([member("matt", busy, 15)], NOW, TZ, 14);
  assert.equal(windows[0].start, ct(5, 15, 15));
  for (const s of res.slots) {
    assert.ok(s.start >= ct(5, 15, 30), "starts on the half hour after the buffer");
    assert.equal(s.end - s.start, 60 * MIN);
    assert.equal(new Date(s.start).getUTCMinutes() % 30, 0);
  }
  // With a buffer of 0, 3:00 is allowed.
  const noBuf = freeWindows([member("matt", busy, 0)], NOW, TZ, 14);
  assert.equal(noBuf[0].start, ct(5, 15));
});

test("starts 15 min after an event when the buffer lines up with :15 → rounds to :30, reason names the member", () => {
  // Busy until 5:15, buffer 15 → free from 5:30.
  const busy = busyExcept(14, [6], 17, 23, 15);
  const res = computeSlots({ members: [member("m", busy, 15, "Matt"), member("z")], durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ });
  const first = res.slots.find((s) => s.start === ct(6, 17, 30));
  assert.ok(first, "a slot starts at 5:30 PM");
  assert.match(first.reason, /Matt's event ends/);
});

test("free window must fit the duration including buffers", () => {
  // Free 6:00–7:00 PM only; with 15 min buffers the usable window is 6:15–6:45 → no 60-min slot.
  const busy = busyExcept(30, [6], 18, 19);
  const res = findSlots({ members: [member("a", busy, 15)], durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ, horizonDays: 14 });
  assert.equal(res.length, 0);
  const res30 = findSlots({ members: [member("a", busy, 0)], durationsMinutes: [30], durationAny: false, nowMs: NOW, ownerTimeZone: TZ, horizonDays: 14 });
  assert.ok(res30.length >= 1);
});

test("sensible hours: 9:00–23:00 in the owner's time zone, :00/:30 starts, ≥1h from now", () => {
  const res = computeSlots({ members: [member("a"), member("b")], durationsMinutes: [30, 60, 120, 180], durationAny: false, nowMs: NOW, ownerTimeZone: TZ });
  assert.equal(res.slots.length, 8);
  for (const s of res.slots) {
    const p = localParts(s.start, TZ);
    const e = localParts(s.end, TZ);
    assert.ok(p.hour >= 9, `start ${p.hour}`);
    assert.ok(e.hour < 23 || (e.hour === 23 && e.minute === 0), `end ${e.hour}:${e.minute}`);
    assert.ok(e.day === p.day);
    assert.ok(p.minute === 0 || p.minute === 30);
    assert.ok(s.start >= NOW + HOUR);
  }
  // Same calendars with an owner in Tokyo → slots in Tokyo daytime.
  const tokyo = computeSlots({ members: [member("a"), member("b")], durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: "Asia/Tokyo" });
  for (const s of tokyo.slots) {
    const p = localParts(s.start, "Asia/Tokyo");
    assert.ok(p.hour >= 9 && p.hour <= 22);
  }
});

test("never within one hour of now", () => {
  const now = ct(5, 16, 40);
  const res = findSlots({ members: [member("a")], durationsMinutes: [60], durationAny: false, nowMs: now, ownerTimeZone: TZ, horizonDays: 1 });
  assert.ok(res.length > 0);
  for (const s of res) assert.ok(s.start >= ct(5, 18), "earliest is 6:00 PM (5:40 + 1h → 6:00)");
});

test("at most 8 slots, spread across days, ranked with labels and reasons", () => {
  const res = computeSlots({ members: [member("a"), member("b"), member("c")], durationsMinutes: [60, 120], durationAny: false, nowMs: NOW, ownerTimeZone: TZ });
  assert.equal(res.slots.length, 8);
  const days = new Set(res.slots.map((s) => localParts(s.start, TZ).day));
  assert.ok(days.size >= 6, `spread across days, got ${days.size}`);
  assert.deepEqual(res.slots.map((s) => s.rank), [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.equal(res.slots[0].label, "Best match");
  assert.ok(res.slots.some((s) => s.label === "Weekend"));
  assert.ok(res.slots.some((s) => [0, 6].includes(localParts(s.start, TZ).weekday)), "includes a weekend slot");
  assert.ok(res.slots.some((s) => ![0, 6].includes(localParts(s.start, TZ).weekday) && localParts(s.start, TZ).hour >= 17), "includes a weeknight slot");
  assert.ok(res.slots.some((s) => s.durationMinutes === 60) && res.slots.some((s) => s.durationMinutes === 120), "both durations represented");
  for (const s of res.slots) {
    assert.ok(s.reason.length > 0);
    assert.deepEqual(s.missingMemberIds, []);
    assert.equal(s.source, "computed");
  }
  // No two slots overlap.
  const sorted = res.slots.slice().sort((a, b) => a.start - b.start);
  for (let i = 1; i < sorted.length; i++) assert.ok(sorted[i].start >= sorted[i - 1].end);
});

test("horizon extends to 30 days when nothing fits in 14", () => {
  // Everyone busy for 20 days, then free.
  const busy = [{ start: NOW - DAYS(1), end: NOW + DAYS(20) }];
  const res = computeSlots({ members: [member("a", busy), member("b")], durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ });
  assert.equal(res.horizonDays, 30);
  assert.equal(res.fallback, false);
  assert.ok(res.slots.length > 0);
  for (const s of res.slots) assert.ok(s.start >= NOW + DAYS(20));
});

function DAYS(n) { return n * 24 * HOUR; }

test("all-but-one fallback when no full-group slot exists in 30 days", () => {
  const alwaysBusy = [{ start: NOW - DAYS(1), end: NOW + DAYS(40) }];
  const res = computeSlots({
    members: [member("a", [], 15, "Ann"), member("b", [], 15, "Ben"), member("mark", alwaysBusy, 15, "Mark")],
    durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ,
  });
  assert.equal(res.fallback, true);
  assert.equal(res.horizonDays, 14);
  assert.ok(res.slots.length > 0 && res.slots.length <= 8);
  for (const s of res.slots) {
    assert.deepEqual(s.missingMemberIds, ["mark"]);
    assert.equal(s.source, "fallback");
    assert.match(s.reason, /Mark/);
  }
});

test("no fallback for a group of two: nothing → empty, horizon 30", () => {
  const alwaysBusy = [{ start: NOW - DAYS(1), end: NOW + DAYS(40) }];
  const res = computeSlots({ members: [member("a"), member("b", alwaysBusy)], durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ });
  assert.deepEqual(res, { slots: [], horizonDays: 30, fallback: false });
});

test("fallback offers skip already-offered times", () => {
  const members = [member("a"), member("b"), member("c", [{ start: NOW, end: NOW + DAYS(10) }], 15, "Cy")];
  const first = computeFallbackOffers({ members, durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ });
  assert.ok(first.length > 0 && first.length <= 8);
  const again = computeFallbackOffers({ members, durationsMinutes: [60], durationAny: false, nowMs: NOW, ownerTimeZone: TZ, exclude: first });
  for (const s of again) assert.ok(!first.some((f) => f.start === s.start && f.end === s.end));
  assert.ok(first.some((s) => s.missingMemberIds.length === 1));
});
