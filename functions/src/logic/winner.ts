// Winner rules (CLAUDE.md "Deciding a winner", docs/ARCHITECTURE.md "Winner rules").
// 1. Options with yes from every participating member → best of those.
// 2. Else options where everyone said yes or maybe → best of those.
// 3. Else none.
// Best = most yes, then fewest maybe, then earliest start (then input order).
// A missing vote counts as "no" (the member never agreed to it).

import { Vote } from "./types";

export interface VoteOption {
  id: string;
  /** epoch ms; used for the "earliest" tie-break */
  start: number;
  /** Members who don't count for this option (e.g. the missing member of an "all but one" slot). */
  excludedVoters?: string[];
}

/** votes[uid][optionId] */
export type VotesByMember = Record<string, Record<string, Vote | string | undefined> | undefined>;

export interface OptionTally {
  id: string;
  start: number;
  yes: number;
  maybe: number;
  no: number;
  voters: string[];
  /** Each voter's vote; null when they didn't vote. */
  votes: Record<string, Vote | null>;
}

export type WinnerTier = "allYes" | "yesOrMaybe";

export interface WinnerResult {
  id: string;
  tier: WinnerTier;
  tally: OptionTally;
}

function asVote(v: unknown): Vote | null {
  return v === "yes" || v === "maybe" || v === "no" ? v : null;
}

export function tallyOption(option: VoteOption, participants: string[], votes: VotesByMember): OptionTally {
  const excluded = new Set(option.excludedVoters ?? []);
  const voters = participants.filter((uid) => !excluded.has(uid));
  const t: OptionTally = { id: option.id, start: option.start, yes: 0, maybe: 0, no: 0, voters, votes: {} };
  for (const uid of voters) {
    const v = asVote(votes[uid]?.[option.id]);
    t.votes[uid] = v;
    if (v === "yes") t.yes++;
    else if (v === "maybe") t.maybe++;
    else t.no++;
  }
  return t;
}

function compareBest(a: { t: OptionTally; i: number }, b: { t: OptionTally; i: number }): number {
  return b.t.yes - a.t.yes || a.t.maybe - b.t.maybe || a.t.start - b.t.start || a.i - b.i;
}

export function pickWinner(options: VoteOption[], participants: string[], votes: VotesByMember): WinnerResult | null {
  const tallies = options
    .map((o, i) => ({ t: tallyOption(o, participants, votes), i }))
    .filter((x) => x.t.voters.length > 0);
  const tier1 = tallies.filter((x) => x.t.yes === x.t.voters.length).sort(compareBest);
  if (tier1.length > 0) return { id: tier1[0].t.id, tier: "allYes", tally: tier1[0].t };
  const tier2 = tallies.filter((x) => x.t.yes + x.t.maybe === x.t.voters.length).sort(compareBest);
  if (tier2.length > 0) return { id: tier2[0].t.id, tier: "yesOrMaybe", tally: tier2[0].t };
  return null;
}

/**
 * The "Not everyone agrees" list: the n options the most people agreed to
 * (most yes, then most maybe, then fewest no, then earliest).
 */
export function topOptions(options: VoteOption[], participants: string[], votes: VotesByMember, n = 3): OptionTally[] {
  return options
    .map((o, i) => ({ t: tallyOption(o, participants, votes), i }))
    .sort((a, b) => b.t.yes - a.t.yes || b.t.maybe - a.t.maybe || a.t.no - b.t.no || a.t.start - b.t.start || a.i - b.i)
    .slice(0, n)
    .map((x) => x.t);
}
