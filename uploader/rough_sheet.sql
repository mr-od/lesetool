-- Active: 1752189674258@@postgres@5432@directus
TRUNCATE TABLE battery_simulator RESTART IDENTITY;

UPDATE solar_production
SET
    timestamp = timestamp - INTERVAL '13 hours';

SELECT populate_battery_simulator ();

DROP TABLE IF EXISTS "spot_price" CASCADE;

CREATE TABLE "spot_price" (
  "id" bigserial PRIMARY KEY,
  "gxp_id" bigint NOT NULL,
  "timestamp" timestamptz NOT NULL,
  "price_per_kwh" numeric(12,5) NOT NULL
);

ALTER TABLE battery_action
ALTER COLUMN battery_kwh TYPE numeric(12,5);

DROP TABLE IF EXISTS "solar_production" CASCADE;

DROP TABLE IF EXISTS "scenario" CASCADE;
DROP TABLE IF EXISTS "spot_price" CASCADE;
DROP TABLE IF EXISTS "power_usage" CASCADE;
DROP TABLE IF EXISTS "solar_production" CASCADE;
DROP TABLE IF EXISTS "battery_action" CASCADE;
DROP TABLE IF EXISTS "sites" CASCADE;
DROP TABLE IF EXISTS "grid_exit_point" CASCADE;

DROP INDEX IF EXISTS power_usage_name_timestamp_idx;


CREATE TABLE "ppc_dataset" (
  "id" serial PRIMARY KEY,
  "ppc_code" varchar UNIQUE NOT NULL,
  "description" text
);

CREATE TABLE "ppc" (
  "id" serial PRIMARY KEY,
  "timestamp" timestamptz NOT NULL,
  "ppc_code" varchar NOT NULL,
  "ppc_kw" numeric NOT NULL
);


CREATE INDEX ON "ppc" ("ppc_code");

CREATE INDEX ON "ppc" ("timestamp");
