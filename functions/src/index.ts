// Cloud Functions entry point (firebase-functions v6, v2 API). See docs/ARCHITECTURE.md.
// Triggers run the idempotent state machine in advance.ts; callables live in callables.ts.
import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";

import { advanceHangout, onHangoutChanged } from "./advance";
import { suggestTimeImpl, startNewRoundImpl, geocodeLocationImpl } from "./callables";
import { demoVenuesImpl } from "./demo";

initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// Read by gemini.ts / places.ts via process.env once bound to a function.
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const GOOGLE_PLACES_API_KEY = defineSecret("GOOGLE_PLACES_API_KEY");
const secrets = [GEMINI_API_KEY, GOOGLE_PLACES_API_KEY];

// Any trigger may end up generating cards (Gemini + Places), so all get the secrets and time.
const heavy = { secrets, timeoutSeconds: 300, memory: "512MiB" as const };

async function safeAdvance(hangoutId: string, source: string): Promise<void> {
  try {
    await advanceHangout(hangoutId);
  } catch (e) {
    logger.error(`${source}: advanceHangout(${hangoutId}) failed`, e);
  }
}

export const onMemberWrite = onDocumentWritten(
  { document: "hangouts/{hangoutId}/members/{uid}", ...heavy },
  async (event) => { await safeAdvance(event.params.hangoutId, "onMemberWrite"); },
);

export const onTimeVoteWrite = onDocumentWritten(
  { document: "hangouts/{hangoutId}/timeVotes/{uid}", ...heavy },
  async (event) => { await safeAdvance(event.params.hangoutId, "onTimeVoteWrite"); },
);

export const onSurveyWrite = onDocumentWritten(
  { document: "hangouts/{hangoutId}/surveyAnswers/{uid}", ...heavy },
  async (event) => { await safeAdvance(event.params.hangoutId, "onSurveyWrite"); },
);

export const onCardVoteWrite = onDocumentWritten(
  { document: "hangouts/{hangoutId}/cardVotes/{voteId}", ...heavy },
  async (event) => { await safeAdvance(event.params.hangoutId, "onCardVoteWrite"); },
);

export const onHangoutWrite = onDocumentWritten(
  { document: "hangouts/{hangoutId}", ...heavy },
  async (event) => {
    const hangoutId = event.params.hangoutId;
    try {
      const before = event.data?.before?.exists ? event.data.before.data() : undefined;
      const after = event.data?.after?.exists ? event.data.after.data() : undefined;
      await onHangoutChanged(hangoutId, before, after);
    } catch (e) {
      logger.error(`onHangoutWrite: ${hangoutId} failed`, e);
    }
  },
);

export const suggestTime = onCall({ ...heavy }, async (request) => {
  return suggestTimeImpl(request.auth?.uid, request.data);
});

export const startNewRound = onCall({ ...heavy }, async (request) => {
  return startNewRoundImpl(request.auth?.uid, request.data);
});

export const geocodeLocation = onCall({ secrets, timeoutSeconds: 30 }, async (request) => {
  return geocodeLocationImpl(request.auth?.uid, request.data);
});

// Demo mode (no signed-in user): real venues + photos for a fixed allowlist only.
export const demoVenues = onCall(
  { secrets: [GOOGLE_PLACES_API_KEY], timeoutSeconds: 60, maxInstances: 2 },
  async () => demoVenuesImpl(),
);
