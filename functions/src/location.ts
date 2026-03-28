import { https } from "firebase-functions/v2";
import { logger } from "firebase-functions";
import { updateUserLocation } from "./spanner";

interface LocationPayload {
  lat: number;
  lng: number;
}

/**
 * Called by the iOS app to update the user's last known location.
 * Used for geo-targeted alert notifications (getNearbyUserTokens).
 */
export const updateLocation = https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new https.HttpsError(
        "unauthenticated",
        "Must be signed in to update location"
      );
    }

    const data = request.data as LocationPayload;

    if (data.lat === undefined || data.lng === undefined) {
      throw new https.HttpsError(
        "invalid-argument",
        "lat and lng are required"
      );
    }

    if (data.lat < -90 || data.lat > 90 || data.lng < -180 || data.lng > 180) {
      throw new https.HttpsError(
        "invalid-argument",
        "lat must be [-90, 90] and lng must be [-180, 180]"
      );
    }

    const uid = request.auth.uid;

    try {
      await updateUserLocation(uid, data.lat, data.lng);

      logger.info("User location updated", { uid, lat: data.lat, lng: data.lng });

      return { success: true };
    } catch (error) {
      logger.error("Failed to update user location", { uid, error });
      throw new https.HttpsError("internal", "Failed to update location");
    }
  }
);
