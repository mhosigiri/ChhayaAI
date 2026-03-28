import * as admin from "firebase-admin";

admin.initializeApp();

// Auth triggers — fires when users sign up or are deleted
export { onUserCreated, onUserDeleted } from "./auth-triggers";

// Device registration — iOS app registers/removes FCM push tokens
export { registerDevice, removeDevice } from "./device-registration";

// Location updates — iOS app reports user position for geo-targeted alerts
export { updateLocation } from "./location";

// Push notification functions — called by Cloud Run agents
export { sendAlertNotification, sendDispatchUpdate } from "./notifications";

// Agent relay — proxies iOS app requests to Cloud Run AI service
export { relayToAgent, agentHealthCheck } from "./agent-relay";
