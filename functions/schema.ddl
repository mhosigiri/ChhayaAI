-- ChhayaAI Cloud Spanner Schema
-- Run against your Spanner database before deploying functions:
--   gcloud spanner databases ddl update chhaya-db \
--     --instance=chhaya-instance \
--     --ddl-file=functions/schema.ddl

CREATE TABLE Users (
  UserId     STRING(128) NOT NULL,
  Email      STRING(320) NOT NULL,
  DisplayName STRING(256) NOT NULL,
  Role       STRING(64)  NOT NULL,
  LastLat    FLOAT64,
  LastLng    FLOAT64,
  CreatedAt  TIMESTAMP   NOT NULL,
  UpdatedAt  TIMESTAMP   NOT NULL,
) PRIMARY KEY(UserId);

CREATE TABLE UserDevices (
  UserId     STRING(128) NOT NULL,
  DeviceId   STRING(256) NOT NULL,
  FcmToken   STRING(4096),
  Platform   STRING(16),
  UpdatedAt  TIMESTAMP   NOT NULL,
) PRIMARY KEY(UserId, DeviceId),
  INTERLEAVE IN PARENT Users ON DELETE CASCADE;

CREATE INDEX UserDevicesByToken ON UserDevices(FcmToken);

CREATE INDEX UsersByLocation ON Users(LastLat, LastLng)
  STORING (UserId);
