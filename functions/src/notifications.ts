import { https } from "firebase-functions/v2";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { getUserFcmTokens, getNearbyUserTokens } from "./spanner";

const ALLOWED_SERVICE_ACCOUNTS = [
  "chhayaai@appspot.gserviceaccount.com",
  "chhayaai-agent@chhayaai.iam.gserviceaccount.com",
];

function assertServiceAccount(request: https.CallableRequest): void {
  if (!request.auth) {
    throw new https.HttpsError(
      "unauthenticated",
      "Must be authenticated"
    );
  }

  const email = request.auth.token.email ?? "";
  const isServiceAccount = ALLOWED_SERVICE_ACCOUNTS.includes(email);
  const isAdmin = request.auth.token.admin === true;

  if (!isServiceAccount && !isAdmin) {
    throw new https.HttpsError(
      "permission-denied",
      "Only backend services can send notifications"
    );
  }
}

interface AlertPayload {
  alertId: string;
  title: string;
  body: string;
  severity: "info" | "warning" | "critical";
  lat?: number;
  lng?: number;
  radiusKm?: number;
  targetUserIds?: string[];
}

interface DispatchPayload {
  dispatchId: string;
  ambulanceId: string;
  requesterId: string;
  eta: string;
  status: "dispatched" | "en_route" | "arriving" | "arrived" | "completed";
}

/**
 * Called by Cloud Run agents when a new alert is created.
 * Restricted to backend service accounts — not callable from client apps.
 * Sends push notifications to affected users via FCM.
 */
export const sendAlertNotification = https.onCall(
  { enforceAppCheck: false },
  async (request) => {
    assertServiceAccount(request);

    const data = request.data as AlertPayload;

    if (!data.alertId || !data.title || !data.body) {
      throw new https.HttpsError(
        "invalid-argument",
        "alertId, title, and body are required"
      );
    }

    logger.info("Sending alert notification", {
      alertId: data.alertId,
      severity: data.severity,
    });

    let tokens: string[] = [];

    try {
      if (data.targetUserIds && data.targetUserIds.length > 0) {
        tokens = await getUserFcmTokens(data.targetUserIds);
      } else if (
        data.lat !== undefined &&
        data.lng !== undefined &&
        data.radiusKm
      ) {
        tokens = await getNearbyUserTokens(data.lat, data.lng, data.radiusKm);
      }
    } catch (error) {
      logger.warn("Failed to fetch FCM tokens from Spanner, skipping push", {
        error,
      });
      return { sent: 0, alertId: data.alertId };
    }

    if (tokens.length === 0) {
      logger.info("No FCM tokens found for alert", {
        alertId: data.alertId,
      });
      return { sent: 0, alertId: data.alertId };
    }

    const badgeColor =
      data.severity === "critical"
        ? "#DC2828"
        : data.severity === "warning"
          ? "#DB7706"
          : "#2A9D90";

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: data.title,
        body: data.body,
      },
      data: {
        alertId: data.alertId,
        severity: data.severity,
        type: "alert",
      },
      apns: {
        payload: {
          aps: {
            sound: data.severity === "critical" ? "critical_alert.caf" : "default",
            badge: 1,
            "interruption-level":
              data.severity === "critical" ? "critical" : "active",
          },
        },
        fcmOptions: {},
      },
      android: {
        priority: data.severity === "critical" ? "high" : "normal",
        notification: {
          color: badgeColor,
          channelId:
            data.severity === "critical"
              ? "critical_alerts"
              : "general_alerts",
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    logger.info("Alert notifications sent", {
      alertId: data.alertId,
      success: response.successCount,
      failure: response.failureCount,
    });

    return {
      sent: response.successCount,
      failed: response.failureCount,
      alertId: data.alertId,
    };
  }
);

/**
 * Called by Cloud Run agents when an ambulance dispatch status changes.
 * Restricted to backend service accounts — not callable from client apps.
 * Sends a targeted push notification to the requester.
 */
export const sendDispatchUpdate = https.onCall(
  { enforceAppCheck: false },
  async (request) => {
    assertServiceAccount(request);

    const data = request.data as DispatchPayload;

    if (!data.dispatchId || !data.requesterId || !data.ambulanceId) {
      throw new https.HttpsError(
        "invalid-argument",
        "dispatchId, requesterId, and ambulanceId are required"
      );
    }

    logger.info("Sending dispatch update", {
      dispatchId: data.dispatchId,
      status: data.status,
    });

    let tokens: string[] = [];
    try {
      tokens = await getUserFcmTokens([data.requesterId]);
    } catch (error) {
      logger.warn("Failed to fetch requester FCM token", { error });
      return { sent: 0, dispatchId: data.dispatchId };
    }

    if (tokens.length === 0) {
      return { sent: 0, dispatchId: data.dispatchId };
    }

    const statusMessages: Record<string, { title: string; body: string }> = {
      dispatched: {
        title: "Ambulance Dispatched",
        body: `${data.ambulanceId} is on the way. ETA: ${data.eta}`,
      },
      en_route: {
        title: "Ambulance En Route",
        body: `${data.ambulanceId} is heading to your location. ETA: ${data.eta}`,
      },
      arriving: {
        title: "Ambulance Arriving",
        body: `${data.ambulanceId} is almost at your location.`,
      },
      arrived: {
        title: "Ambulance Arrived",
        body: `${data.ambulanceId} has reached your location.`,
      },
      completed: {
        title: "Dispatch Completed",
        body: `Emergency response by ${data.ambulanceId} is complete.`,
      },
    };

    const msg = statusMessages[data.status] ?? {
      title: "Dispatch Update",
      body: `${data.ambulanceId} status: ${data.status}`,
    };

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: msg.title,
        body: msg.body,
      },
      data: {
        dispatchId: data.dispatchId,
        ambulanceId: data.ambulanceId,
        status: data.status,
        type: "dispatch",
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            "interruption-level": "time-sensitive",
          },
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    logger.info("Dispatch update sent", {
      dispatchId: data.dispatchId,
      success: response.successCount,
    });

    return {
      sent: response.successCount,
      dispatchId: data.dispatchId,
    };
  }
);
