import { test } from "node:test";
import assert from "node:assert/strict";
import { centroid, haversineMiles } from "../lib-logic/geo.js";

test("centroid of empty is null", () => {
  assert.equal(centroid([]), null);
  assert.equal(centroid([null, undefined]), null);
});

test("centroid of one point is that point", () => {
  assert.deepEqual(centroid([{ lat: 41.79, lng: -87.6 }]), { lat: 41.79, lng: -87.6 });
});

test("centroid is the mean, skipping invalid points", () => {
  const c = centroid([{ lat: 40, lng: -88 }, { lat: 42, lng: -86 }, null, { lat: NaN, lng: 1 }]);
  assert.deepEqual(c, { lat: 41, lng: -87 });
});

test("haversine: same point is 0", () => {
  assert.equal(haversineMiles({ lat: 41.8, lng: -87.6 }, { lat: 41.8, lng: -87.6 }), 0);
});

test("haversine: Chicago to NYC is about 711 miles", () => {
  const d = haversineMiles({ lat: 41.8781, lng: -87.6298 }, { lat: 40.7128, lng: -74.006 });
  assert.ok(Math.abs(d - 711) < 10, `got ${d}`);
});

test("haversine: one degree of latitude is about 69 miles and symmetric", () => {
  const a = { lat: 41, lng: -87 }, b = { lat: 42, lng: -87 };
  const d = haversineMiles(a, b);
  assert.ok(Math.abs(d - 69.1) < 0.5, `got ${d}`);
  assert.equal(d, haversineMiles(b, a));
});
