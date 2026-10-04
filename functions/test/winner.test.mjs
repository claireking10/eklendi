import { test } from "node:test";
import assert from "node:assert/strict";
import { pickWinner, topOptions, tallyOption } from "../lib-logic/winner.js";

const P = ["a", "b", "c"];
const opt = (id, start, excludedVoters) => ({ id, start, excludedVoters });

test("tier 1: yes from everyone wins over more popular maybes", () => {
  const options = [opt("s1", 100), opt("s2", 200)];
  const votes = {
    a: { s1: "yes", s2: "yes" },
    b: { s1: "maybe", s2: "yes" },
    c: { s1: "yes", s2: "yes" },
  };
  const w = pickWinner(options, P, votes);
  assert.equal(w.id, "s2");
  assert.equal(w.tier, "allYes");
});

test("tier 1 tie → earliest start", () => {
  const options = [opt("late", 300), opt("early", 100)];
  const votes = { a: { late: "yes", early: "yes" }, b: { late: "yes", early: "yes" }, c: { late: "yes", early: "yes" } };
  assert.equal(pickWinner(options, P, votes).id, "early");
});

test("tier 2: yes-or-maybe from everyone, most yes wins", () => {
  const options = [opt("x", 100), opt("y", 200), opt("z", 50)];
  const votes = {
    a: { x: "yes", y: "yes", z: "no" },
    b: { x: "maybe", y: "yes", z: "yes" },
    c: { x: "maybe", y: "maybe", z: "yes" },
  };
  const w = pickWinner(options, P, votes);
  assert.equal(w.id, "y");
  assert.equal(w.tier, "yesOrMaybe");
});

test("tier 2 ties: most yes → fewest maybe → earliest", () => {
  // 4 participants so fewest-maybe can differ at equal yes.
  const P4 = ["a", "b", "c", "d"];
  const options = [opt("p", 100), opt("q", 50), opt("r", 10)];
  const votes = {
    a: { p: "yes", q: "yes", r: "yes" },
    b: { p: "yes", q: "yes", r: "maybe" },
    c: { p: "maybe", q: "maybe", r: "maybe" },
    d: { p: "maybe", q: "maybe", r: "maybe" },
  };
  // p and q tie on yes(2) and maybe(2) → earliest is q. r has fewer yes.
  assert.equal(pickWinner(options, P4, votes).id, "q");
  // fewest maybe: make p have one "no"→ ineligible; instead compare equal-yes with fewer maybes requires a no… use exclusion:
  const options2 = [opt("m1", 10), opt("m2", 20, ["d"])];
  const votes2 = {
    a: { m1: "yes", m2: "yes" }, b: { m1: "yes", m2: "yes" },
    c: { m1: "maybe", m2: "maybe" }, d: { m1: "maybe" },
  };
  // m1: 2 yes 2 maybe; m2 (d excluded): 2 yes 1 maybe → m2 wins despite later start.
  assert.equal(pickWinner(options2, P4, votes2).id, "m2");
});

test("no option passes → null; missing votes count as no", () => {
  const options = [opt("s1", 100), opt("s2", 200)];
  const votes = { a: { s1: "yes", s2: "no" }, b: { s1: "no", s2: "yes" }, c: { s1: "yes", s2: "yes" } };
  assert.equal(pickWinner(options, P, votes), null);
  const missing = { a: { s1: "yes" }, b: { s1: "yes" } }; // c never voted
  assert.equal(pickWinner([opt("s1", 1)], P, missing), null);
});

test("declined members are not participants; all-but-one slot excludes the missing member", () => {
  const options = [opt("s1", 100, ["c"])];
  const votes = { a: { s1: "yes" }, b: { s1: "yes" }, c: { s1: "no" } };
  assert.equal(pickWinner(options, P, votes).id, "s1");
  // c declined → only a, b participate
  assert.equal(pickWinner([opt("s2", 1)], ["a", "b"], { a: { s2: "yes" }, b: { s2: "yes" }, c: { s2: "no" } }).id, "s2");
});

test("garbage vote values are treated as no", () => {
  const t = tallyOption(opt("s", 1), ["a", "b"], { a: { s: "YES" }, b: { s: "yes" } });
  assert.equal(t.yes, 1);
  assert.equal(t.no, 1);
  assert.equal(t.votes.a, null);
});

test("topOptions: top 3 most-agreed with per-member votes", () => {
  const options = [opt("c1", 1), opt("c2", 2), opt("c3", 3), opt("c4", 4)];
  const votes = {
    a: { c1: "yes", c2: "yes", c3: "yes", c4: "no" },
    b: { c1: "yes", c2: "no", c3: "maybe", c4: "no" },
    c: { c1: "yes", c2: "yes", c3: "maybe", c4: "maybe" },
    d: { c1: "no", c2: "yes", c3: "no", c4: "no" },
  };
  const top = topOptions(options, ["a", "b", "c", "d"], votes, 3);
  assert.deepEqual(top.map((t) => t.id), ["c1", "c2", "c3"]); // c1/c2 3 yes (c1 earlier), c3 1 yes 2 maybe
  assert.deepEqual(top[0].votes, { a: "yes", b: "yes", c: "yes", d: "no" });
  assert.equal(top[2].maybe, 2);
});
