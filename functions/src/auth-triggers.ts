import { user } from "firebase-functions/v1/auth";
import { logger } from "firebase-functions";
import { createUserProfile, deleteUserProfile } from "./spanner";

/**
 * Triggered when a new user signs up via Firebase Auth.
 * Creates a corresponding profile in Cloud Spanner.
 */
export const onUserCreated = user().onCreate(async (userRecord) => {
  logger.info("New user created", {
    uid: userRecord.uid,
    email: userRecord.email,
    displayName: userRecord.displayName,
  });

  try {
    await createUserProfile({
      userId: userRecord.uid,
      email: userRecord.email ?? "",
      displayName: userRecord.displayName ?? "",
      role: "responder",
      createdAt:
        userRecord.metadata.creationTime ?? new Date().toISOString(),
    });

    logger.info("User profile created in Spanner", { uid: userRecord.uid });
  } catch (error) {
    logger.error("Failed to create user profile in Spanner", {
      uid: userRecord.uid,
      error,
    });
    throw error;
  }
});

/**
 * Triggered when a user is deleted from Firebase Auth.
 * Removes the user's profile and device records from Spanner.
 */
export const onUserDeleted = user().onDelete(async (userRecord) => {
  logger.info("User deleted, cleaning up Spanner records", {
    uid: userRecord.uid,
    email: userRecord.email,
  });

  try {
    await deleteUserProfile(userRecord.uid);
    logger.info("User records removed from Spanner", { uid: userRecord.uid });
  } catch (error) {
    logger.error("Failed to clean up Spanner records for deleted user", {
      uid: userRecord.uid,
      error,
    });
    throw error;
  }
});
