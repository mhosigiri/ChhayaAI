import { defineString } from "firebase-functions/params";

// Set these before deploying:
//   firebase functions:secrets:set CLOUD_RUN_AGENT_URL
// Or provide them in .env inside functions/:
//   CLOUD_RUN_AGENT_URL=https://chhayaai-agent-us-central1-chhayaai.a.run.app

export const CLOUD_RUN_AGENT_URL = defineString("CLOUD_RUN_AGENT_URL", {
  description: "Base URL of the Cloud Run AI Agent service (e.g. https://chhayaai-agent-us-central1-chhayaai.a.run.app)",
  default: "",
});

export const SPANNER_INSTANCE_ID = defineString("SPANNER_INSTANCE_ID", {
  description: "Cloud Spanner instance ID",
  default: "chhaya-instance",
});

export const SPANNER_DATABASE_ID = defineString("SPANNER_DATABASE_ID", {
  description: "Cloud Spanner database ID",
  default: "chhaya-db",
});
