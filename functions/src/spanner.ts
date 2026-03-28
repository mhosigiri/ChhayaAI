import { Spanner } from "@google-cloud/spanner";
import { SPANNER_INSTANCE_ID, SPANNER_DATABASE_ID } from "./config";

let spannerClient: Spanner | null = null;

function getSpanner() {
  if (!spannerClient) {
    spannerClient = new Spanner();
  }
  return spannerClient;
}

export function getDatabase() {
  const spanner = getSpanner();
  const instance = spanner.instance(SPANNER_INSTANCE_ID.value());
  return instance.database(SPANNER_DATABASE_ID.value());
}

export interface UserProfile {
  userId: string;
  email: string;
  displayName: string;
  role: string;
  createdAt: string;
}

export async function createUserProfile(profile: UserProfile): Promise<void> {
  const database = getDatabase();

  await database.table("Users").insert({
    UserId: profile.userId,
    Email: profile.email,
    DisplayName: profile.displayName,
    Role: profile.role,
    CreatedAt: profile.createdAt,
    UpdatedAt: new Date().toISOString(),
  });
}

export async function deleteUserProfile(userId: string): Promise<void> {
  const database = getDatabase();

  await database.runTransactionAsync(async (transaction) => {
    transaction.deleteRows("UserDevices", [[userId]]);
    transaction.deleteRows("Users", [[userId]]);
    await transaction.commit();
  });
}

export async function upsertDeviceToken(
  userId: string,
  deviceId: string,
  fcmToken: string,
  platform: string
): Promise<void> {
  const database = getDatabase();

  await database.table("UserDevices").upsert({
    UserId: userId,
    DeviceId: deviceId,
    FcmToken: fcmToken,
    Platform: platform,
    UpdatedAt: new Date().toISOString(),
  });
}

export async function removeDeviceToken(
  userId: string,
  deviceId: string
): Promise<void> {
  const database = getDatabase();

  await database.table("UserDevices").deleteRows([[userId, deviceId]]);
}

export async function updateUserLocation(
  userId: string,
  lat: number,
  lng: number
): Promise<void> {
  const database = getDatabase();

  await database.table("Users").update({
    UserId: userId,
    LastLat: lat,
    LastLng: lng,
    UpdatedAt: new Date().toISOString(),
  });
}

export async function getUserFcmTokens(
  userIds: string[]
): Promise<string[]> {
  if (userIds.length === 0) return [];

  const database = getDatabase();

  const [rows] = await database.run({
    sql: `SELECT FcmToken FROM UserDevices
          WHERE UserId IN UNNEST(@userIds)
            AND FcmToken IS NOT NULL`,
    params: { userIds },
  });

  return rows.map((row) => {
    const json = row.toJSON();
    return json.FcmToken as string;
  });
}

export async function getNearbyUserTokens(
  lat: number,
  lng: number,
  radiusKm: number
): Promise<string[]> {
  const database = getDatabase();

  const latDelta = radiusKm / 111.0;
  const lngDelta = radiusKm / (111.0 * Math.cos((lat * Math.PI) / 180));

  const [rows] = await database.run({
    sql: `SELECT ud.FcmToken
          FROM Users u
          JOIN UserDevices ud ON u.UserId = ud.UserId
          WHERE ud.FcmToken IS NOT NULL
            AND u.LastLat BETWEEN @latMin AND @latMax
            AND u.LastLng BETWEEN @lngMin AND @lngMax`,
    params: {
      latMin: lat - latDelta,
      latMax: lat + latDelta,
      lngMin: lng - lngDelta,
      lngMax: lng + lngDelta,
    },
  });

  return rows.map((row) => {
    const json = row.toJSON();
    return json.FcmToken as string;
  });
}
