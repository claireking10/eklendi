// Shared types for the pure logic modules. Mirrors docs/ARCHITECTURE.md.
// Times are epoch milliseconds (UTC) inside the logic layer; glue code converts Firestore Timestamps.

export type Vote = "yes" | "maybe" | "no";
export type SurveyAnswer = Vote | "dontCare";

export interface Interval { start: number; end: number }

export interface MemberAvailability {
  uid: string;
  name: string;
  busy: Interval[];
  bufferMinutes: number;
}

export interface LatLng { lat: number; lng: number }

export const SURVEY_QUESTION_IDS = [
  "food", "active", "games", "arts", "nature", "markets", "events",
  "indoors", "outdoors", "priceLow", "priceMid", "priceHigh", "chill", "lively",
] as const;
export type SurveyQuestionId = typeof SURVEY_QUESTION_IDS[number];

export const MAX_SLOTS = 8;
export const DEFAULT_BUFFER_MINUTES = 15;
export const HORIZON_DAYS = 14;
export const EXTENDED_HORIZON_DAYS = 30;
export const MIN_GROUP = 2;
export const MAX_GROUP = 8;
export const CARDS_PER_PERSON = 3;
