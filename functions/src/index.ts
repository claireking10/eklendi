// Cloud Functions entry point. Owned by the backend agent (state machine, scheduling)
// and the integrations agent (gemini.ts, places.ts, geocode). See docs/ARCHITECTURE.md.
import { initializeApp } from "firebase-admin/app";

initializeApp();

// Exports are added by the agents, e.g.:
// export { onMemberWrite, onTimeVoteWrite, onSurveyWrite, onCardVoteWrite, onHangoutWrite } from "./triggers";
// export { suggestTime, startNewRound, geocodeLocation } from "./callables";
