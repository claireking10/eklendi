// Locality helpers (CLAUDE.md "Location": search area is the centroid of starting locations).
// Pure: no imports outside src/logic.
import { LatLng } from "./types";

function valid(p: LatLng | null | undefined): p is LatLng {
  return !!p && Number.isFinite(p.lat) && Number.isFinite(p.lng);
}

/** Mean lat/lng of the valid points; null when there are none. */
export function centroid(points: (LatLng | null | undefined)[]): LatLng | null {
  const ok = points.filter(valid);
  if (ok.length === 0) return null;
  let lat = 0;
  let lng = 0;
  for (const p of ok) {
    lat += p.lat;
    lng += p.lng;
  }
  return { lat: lat / ok.length, lng: lng / ok.length };
}

const EARTH_RADIUS_MILES = 3958.8;

/** Great-circle distance in miles. */
export function haversineMiles(a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_MILES * Math.asin(Math.min(1, Math.sqrt(h)));
}
