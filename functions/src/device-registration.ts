import { https } from "firebase-functions/v2";
import { logger } from "firebase-functions";
import { upsertDeviceToken, removeDeviceToken } from "./spanner";

interface RegisterDevicePayload {
  deviceId: string;
  fcmToken: string;
  platform: "ios" | "android";
}

/**
 * Called by the iOS app after obtaining an FCM token.
 * Stores or updates the device's push token in Spanner
 * so notifications can be routed to this device.
 */
export const registerDevice = https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new https.HttpsError(
        "unauthenticated",
        "Must be signed in to register a device"
      );
    }

    const data = request.data as RegisterDevicePayload;

    if (!data.deviceId || !data.fcmToken || !data.platform) {
      throw new https.HttpsError(
        "invalid-argument",
        "deviceId, fcmToken, and platform are required"
      );
    }

    const uid = request.auth.uid;

    try {
      await upsertDeviceToken(uid, data.deviceId, data.fcmToken, data.platform);

      logger.info("Device registered", {
        uid,
        deviceId: data.deviceId,
        platform: data.platform,
      });

      return { success: true };
    } catch (error) {
      logger.error("Failed to register device", { uid, error });
      throw new https.HttpsError("internal", "Failed to register device");
    }
  }
);

/**
 * Called when the user signs out or the app needs to unregister
 * a device from push notifications.
 */
export const removeDevice = https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new https.HttpsError(
        "unauthenticated",
        "Must be signed in to remove a device"
      );
    }

    const { deviceId } = request.data as { deviceId: string };

    if (!deviceId) {
      throw new https.HttpsError(
        "invalid-argument",
        "deviceId is required"
      );
    }

    const uid = request.auth.uid;

    try {
      await removeDeviceToken(uid, deviceId);

      logger.info("Device removed", { uid, deviceId });

      return { success: true };
    } catch (error) {
      logger.error("Failed to remove device", { uid, error });
      throw new https.HttpsError("internal", "Failed to remove device");
    }
  }
);
