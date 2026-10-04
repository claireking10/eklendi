import { test } from "node:test";
import assert from "node:assert/strict";
import { buildGroupPreferences, toPromptText, DEFAULT_TYPES } from "../lib-logic/preferences.js";

const QS = ["food", "active", "games", "arts", "nature", "markets", "events",
  "indoors", "outdoors", "priceLow", "priceMid", "priceHigh", "chill", "lively"];
const all = (a) => Object.fromEntries(QS.map((q) => [q, a]));

test("scores: yes +2, maybe +1, no -2, dontCare 0", () => {
  const p = buildGroupPreferences({
    a: { ...all("dontCare"), food: "yes" },
    b: { ...all("dontCare"), food: "maybe" },
    c: { ...all("dontCare"), food: "no" },
  }, []);
  assert.equal(p.scores.food.score, 1);
  assert.deepEqual([p.scores.food.yes, p.scores.food.maybe, p.scores.food.no, p.scores.food.dontCare], [1, 1, 1, 0]);
  assert.equal(p.scores.games.score, 0);
  assert.equal(p.scores.games.dontCare, 3);
  assert.equal(p.memberCount, 3);
});

test("everyone doesn't care -> sensible defaults, nothing constrained", () => {
  const p = buildGroupPreferences({ a: all("dontCare"), b: all("dontCare"), c: all("dontCare") }, []);
  assert.deepEqual(p.likedTypes, DEFAULT_TYPES);
  assert.deepEqual(p.avoidTypes, []);
  assert.equal(p.setting, "either");
  assert.equal(p.priceCeiling, "mid");
  assert.equal(p.maxPriceLevel, 2);
  assert.equal(p.vibe, "either");
  assert.deepEqual(p.defaultsApplied.sort(), ["price", "setting", "type", "vibe"]);
});

test("missing answers count as dontCare", () => {
  const p = buildGroupPreferences({ a: {}, b: { food: "yes" } }, []);
  assert.equal(p.scores.food.score, 2);
  assert.equal(p.scores.games.dontCare, 2);
});

test("dontCare is not a No: one yes + many dontCare still liked, never avoided", () => {
  const p = buildGroupPreferences({
    a: { ...all("dontCare"), games: "yes" },
    b: all("dontCare"), c: all("dontCare"), d: all("dontCare"),
  }, []);
  assert.ok(p.likedTypes.includes("games"));
  assert.equal(p.likedTypes[0], "games");
  assert.deepEqual(p.avoidTypes, []);
});

test("liked types ranked by score; majority no -> avoided", () => {
  const base = { ...all("maybe") };
  const p = buildGroupPreferences({
    a: { ...base, food: "yes", games: "yes", nature: "no" },
    b: { ...base, food: "yes", games: "maybe", nature: "no" },
    c: { ...base, food: "yes", games: "maybe", nature: "maybe" },
  }, []);
  assert.equal(p.likedTypes[0], "food");
  assert.equal(p.likedTypes[1], "games");
  assert.ok(p.avoidTypes.includes("nature"));
  assert.ok(!p.likedTypes.includes("nature"));
  assert.ok(!p.defaultsApplied.includes("type"));
});

test("price ceiling: highest tier nobody said no to", () => {
  const p1 = buildGroupPreferences({
    a: { ...all("yes"), priceHigh: "no" },
    b: all("yes"),
  }, []);
  assert.equal(p1.priceCeiling, "mid");
  assert.equal(p1.maxPriceLevel, 2);
  const p2 = buildGroupPreferences({
    a: { ...all("yes"), priceHigh: "no", priceMid: "no" },
    b: all("yes"),
  }, []);
  assert.equal(p2.priceCeiling, "low");
  const p3 = buildGroupPreferences({ a: all("yes"), b: all("maybe") }, []);
  assert.equal(p3.priceCeiling, "high");
  assert.equal(p3.maxPriceLevel, 4);
});

test("price dontCare from most of group -> default mid; a single care doesn't flip it", () => {
  const p = buildGroupPreferences({
    a: { ...all("yes"), priceLow: "dontCare", priceMid: "dontCare", priceHigh: "yes" },
    b: { ...all("yes"), priceLow: "dontCare", priceMid: "dontCare", priceHigh: "dontCare" },
    c: { ...all("yes"), priceLow: "dontCare", priceMid: "dontCare", priceHigh: "dontCare" },
  }, []);
  assert.ok(p.defaultsApplied.includes("price"));
  assert.equal(p.priceCeiling, "mid");
});

test("setting: outdoors disliked -> indoor; indoors disliked -> outdoor; mixed -> either", () => {
  const indoor = buildGroupPreferences({
    a: { ...all("yes"), outdoors: "no" }, b: { ...all("yes"), outdoors: "no" },
  }, []);
  assert.equal(indoor.setting, "indoor");
  const outdoor = buildGroupPreferences({
    a: { ...all("yes"), indoors: "no" }, b: { ...all("yes"), indoors: "maybe" },
  }, []);
  assert.equal(outdoor.setting, "outdoor");
  const either = buildGroupPreferences({ a: all("yes"), b: all("maybe") }, []);
  assert.equal(either.setting, "either");
});

test("vibe: chill vs lively", () => {
  const chill = buildGroupPreferences({
    a: { ...all("yes"), lively: "no" }, b: { ...all("yes"), lively: "maybe" },
  }, []);
  assert.equal(chill.vibe, "chill");
  const lively = buildGroupPreferences({
    a: { ...all("yes"), chill: "no" }, b: { ...all("yes"), chill: "no" },
  }, []);
  assert.equal(lively.vibe, "lively");
});

test("everything vetoed still yields some types (never empty)", () => {
  const p = buildGroupPreferences({ a: all("no"), b: all("no") }, []);
  assert.ok(p.likedTypes.length > 0);
});

test("interests are a soft signal: kept as text, don't change type scores", () => {
  const answers = { a: all("dontCare"), b: all("dontCare") };
  const without = buildGroupPreferences(answers, []);
  const withI = buildGroupPreferences(answers, ["  I love hiking and live music ", "", "   "]);
  assert.deepEqual(withI.interests, ["I love hiking and live music"]);
  assert.deepEqual(withI.likedTypes, without.likedTypes);
  const text = toPromptText(withI);
  assert.match(text, /hiking and live music/);
  assert.match(text, /soft hint/);
});

test("toPromptText mentions size, budget, setting, defaults", () => {
  const p = buildGroupPreferences({ a: { ...all("yes"), outdoors: "no" }, b: all("dontCare"), c: all("dontCare") }, []);
  const t = toPromptText(p);
  assert.match(t, /Group size: 3/);
  assert.match(t, /Budget:/);
  assert.match(t, /Setting:/);
});

test("empty group doesn't crash", () => {
  const p = buildGroupPreferences({}, []);
  assert.equal(p.memberCount, 0);
  assert.ok(p.likedTypes.length > 0);
  assert.equal(typeof toPromptText(p), "string");
});
