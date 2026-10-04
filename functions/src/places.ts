// Google Places API (New): real venues + photos for hangout cards, and geocoding for
// home/start locations. Key = GOOGLE_PLACES_API_KEY function secret.
//
// SECURITY (public repo + public app): never store or return a URL that contains the API key.
// Photos are resolved with skipHttpRedirect=true to a googleusercontent photoUri, which has no key.
import { LatLng } from "./logic/types";
import { Idea, envVar, fetchJson, logWarn } from "./gemini";

const PLACES_TIMEOUT_MS = 10_000;
const SEARCH_URL = "https://places.googleapis.com/v1/places:searchText";

export interface Venue {
  venueName: string;
  address: string;
  lat: number;
  lng: number;
  priceLevel: number | null;
  photoUrl: string | null;
  placeId: string;
}

interface PlaceResult {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  priceLevel?: string;
  photos?: { name?: string }[];
}

const PRICE_LEVELS: Record<string, number | null> = {
  PRICE_LEVEL_FREE: 1,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
  PRICE_LEVEL_UNSPECIFIED: null,
};

/** PRICE_LEVEL_* enum string → 1–4 (null if unknown). Exported for tests. */
export function priceLevelToNumber(v: unknown): number | null {
  if (typeof v === "number" && v >= 0 && v <= 4) return v === 0 ? 1 : v;
  if (typeof v !== "string") return null;
  return v in PRICE_LEVELS ? PRICE_LEVELS[v] : null;
}

async function searchText(textQuery: string, fieldMask: string, center: LatLng | null, radiusMeters: number): Promise<PlaceResult[] | null> {
  const key = envVar("GOOGLE_PLACES_API_KEY");
  if (!key) {
    logWarn("[places] GOOGLE_PLACES_API_KEY not set");
    return null;
  }
  const body: Record<string, unknown> = { textQuery, maxResultCount: 1 };
  if (center) {
    body.locationBias = { circle: { center: { latitude: center.lat, longitude: center.lng }, radius: radiusMeters } };
  }
  const data = await fetchJson(
    SEARCH_URL,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Goog-Api-Key": key, "X-Goog-FieldMask": fieldMask },
      body: JSON.stringify(body),
    },
    PLACES_TIMEOUT_MS,
    "places.searchText",
  );
  const places = (data as { places?: PlaceResult[] } | null)?.places;
  return Array.isArray(places) ? places : data ? [] : null;
}

/** Resolves a photo resource name to a key-free photoUri. */
async function photoUri(photoName: string): Promise<string | null> {
  const key = envVar("GOOGLE_PLACES_API_KEY");
  if (!key || !/^places\/[^?#]+\/photos\/[^?#]+$/.test(photoName)) return null;
  const data = await fetchJson(
    `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=900&skipHttpRedirect=true`,
    { method: "GET", headers: { "X-Goog-Api-Key": key } },
    PLACES_TIMEOUT_MS,
    "places.photo",
  );
  const uri = (data as { photoUri?: unknown } | null)?.photoUri;
  if (typeof uri !== "string" || !/^https:\/\//.test(uri)) return null;
  // Belt and braces: never let anything carrying the key out.
  if (uri.includes(key) || /[?&]key=/i.test(uri)) return null;
  return uri;
}

/** Finds the real venue for an idea near the group's centroid. null on any failure. */
export async function resolveVenue(idea: Idea, center: LatLng | null): Promise<Venue | null> {
  try {
    const query = idea.searchQuery.trim() || idea.activity;
    const places = await searchText(
      query,
      "places.id,places.displayName,places.formattedAddress,places.location,places.priceLevel,places.photos",
      center,
      15000,
    );
    const p = places?.[0];
    const lat = p?.location?.latitude;
    const lng = p?.location?.longitude;
    const name = p?.displayName?.text?.trim();
    if (!p || !p.id || !name || typeof lat !== "number" || typeof lng !== "number") return null;
    const photoName = p.photos?.[0]?.name;
    const photoUrl = photoName ? await photoUri(photoName) : null;
    return {
      venueName: name,
      address: p.formattedAddress ?? "",
      lat,
      lng,
      priceLevel: priceLevelToNumber(p.priceLevel),
      photoUrl,
      placeId: p.id,
    };
  } catch (e) {
    logWarn(`[places] resolveVenue failed: ${e instanceof Error ? e.message : String(e)}`);
    return null;
  }
}

/** Geocodes a user-entered approximate location. Returns the user's own text with coarse coordinates. */
export async function geocode(text: string): Promise<{ text: string; lat: number; lng: number } | null> {
  const t = (text ?? "").trim();
  if (!t) return null;
  try {
    const places = await searchText(t, "places.location,places.formattedAddress", null, 0);
    const loc = places?.[0]?.location;
    if (!loc || typeof loc.latitude !== "number" || typeof loc.longitude !== "number") return null;
    // Coarse (~100 m) so we never store a precise home position.
    const round = (n: number) => Math.round(n * 1000) / 1000;
    return { text: t, lat: round(loc.latitude), lng: round(loc.longitude) };
  } catch (e) {
    logWarn(`[places] geocode failed: ${e instanceof Error ? e.message : String(e)}`);
    return null;
  }
}
