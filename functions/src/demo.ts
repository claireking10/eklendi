// Demo mode: real venues + photos for the app's built-in demo cards (the app runs on mock
// data, so there's no signed-in Firebase user). Only this fixed allowlist is ever searched,
// so the endpoint can't be used to run arbitrary Places queries.
import { HttpsError } from "firebase-functions/v2/https";
import { LatLng } from "./logic/types";
import { Venue, resolveVenue } from "./places";

/** Demo venue id → Places text query. Ids match the iOS demo card pool (MockStore.swift). */
export const DEMO_VENUE_QUERIES: Record<string, string> = {
  coffee: "Halcyon Southtown coffee San Antonio TX",
  bowling: "bowling alley San Antonio TX",
  picnic: "Brackenridge Park San Antonio TX",
  boardgames: "board game cafe San Antonio TX",
  tacos: "La Gloria Pearl San Antonio TX",
  minigolf: "Cool Crest Miniature Golf San Antonio TX",
  trivia: "trivia night bar San Antonio TX",
  arcade: "arcade bar San Antonio TX",
  market: "Pearl Farmers Market San Antonio TX",
  icecream: "Lick Honest Ice Creams Pearl San Antonio TX",
  climbing: "rock climbing gym San Antonio TX",
  rubycity: "Ruby City contemporary art San Antonio TX",
  mcnay: "McNay Art Museum San Antonio TX",
  movie: "Alamo Drafthouse Cinema San Antonio TX",
  brunch: "The Guenther House San Antonio TX",
};

const SAN_ANTONIO: LatLng = { lat: 29.4241, lng: -98.4936 };
const CACHE_MS = 6 * 60 * 60 * 1000;

let cache: { at: number; venues: Record<string, Venue> } | null = null;

/** Resolves every demo venue (cached per instance for 6 h). Missing ids = not found. */
export async function demoVenuesImpl(): Promise<{ venues: Record<string, Venue> }> {
  if (cache && Date.now() - cache.at < CACHE_MS) return { venues: cache.venues };
  const ids = Object.keys(DEMO_VENUE_QUERIES);
  const results = await Promise.all(
    ids.map((id) =>
      resolveVenue(
        { activity: id, description: "", category: "", searchQuery: DEMO_VENUE_QUERIES[id], tags: [] },
        SAN_ANTONIO,
      ),
    ),
  );
  const venues: Record<string, Venue> = {};
  ids.forEach((id, i) => {
    const v = results[i];
    if (v) venues[id] = v;
  });
  if (Object.keys(venues).length === 0) {
    throw new HttpsError("unavailable", "Couldn't reach Google Places");
  }
  // Only cache a complete-enough answer so a transient failure is retried next time.
  if (Object.keys(venues).length >= ids.length / 2) cache = { at: Date.now(), venues };
  return { venues };
}
