CREATE TABLE "site" (
  "id" serial PRIMARY KEY,
  "site_code" varchar UNIQUE NOT NULL,
  "site_name" varchar NOT NULL,
  "site_address" varchar NOT NULL
);

CREATE TABLE "spot_dataset" (
  "id" serial PRIMARY KEY,
  "spot_code" varchar UNIQUE NOT NULL,
  "description" text
);

CREATE TABLE "spot_prices_gen" (
  "id" serial PRIMARY KEY,
  "timestamp" timestamptz NOT NULL,
  "spot_code" varchar NOT NULL,
  "spot_price" numeric NOT NULL,
  "avg_spot_price_midnight_to_midday" numeric NOT NULL,
  "avg_spot_price_midday_to_midnight" numeric NOT NULL,
  "action_flag" varchar NOT NULL,
  "charge_rank" int NOT NULL,
  "discharge_rank" int NOT NULL
);

CREATE TABLE "battery_dataset" (
  "id" serial PRIMARY KEY,
  "battery_code" varchar UNIQUE NOT NULL,
  "description" text
);

CREATE TABLE "battery_scenario_sim" (
  "id" serial PRIMARY KEY,
  "timestamp" timestamptz NOT NULL,
  "battery_code" varchar NOT NULL,
  "battery_capacity_now_kwh" numeric NOT NULL,
  "available_import_capacity_kw" numeric NOT NULL,
  "soc_start_kwh" numeric NOT NULL,
  "battery_charge_kwh" numeric NOT NULL,
  "battery_discharge_kwh" numeric NOT NULL,
  "soc_end_kwh" numeric NOT NULL,
  "net_energy_cost" numeric NOT NULL
);

CREATE TABLE "solar_dataset" (
  "id" serial PRIMARY KEY,
  "solar_code" varchar UNIQUE NOT NULL,
  "description" text
);

CREATE TABLE "solar" (
  "id" serial PRIMARY KEY,
  "timestamp" timestamptz NOT NULL,
  "solar_code" varchar NOT NULL,
  "solar_production_kwh" numeric NOT NULL
);

CREATE TABLE "consumption_dataset" (
  "id" serial PRIMARY KEY,
  "consumption_code" varchar UNIQUE NOT NULL,
  "description" text
);

CREATE TABLE "power_consumption" (
  "id" serial PRIMARY KEY,
  "timestamp" timestamptz NOT NULL,
  "main_site_consumption_kwh" numeric NOT NULL,
  "consumption_code" varchar NOT NULL
);

CREATE TABLE "scenario" (
  "id" serial PRIMARY KEY,
  "site_code" varchar,
  "scenario_code" varchar UNIQUE NOT NULL,
  "spot_code" varchar NOT NULL,
  "consumption_code" varchar NOT NULL,
  "consumption_scale" varchar NOT NULL,
  "solar_code" varchar NOT NULL,
  "solar_scale" varchar NOT NULL,
  "battery_code" varchar NOT NULL,
  "scenario_preferred" boolean NOT NULL,
  "solar_capacity_kw" numeric NOT NULL,
  "solar_production_yr_kwh" numeric NOT NULL,
  "inverter_max_charge_kw" numeric NOT NULL,
  "inverter_max_discharge_kw" numeric NOT NULL,
  "battery_initial_capacity_kwh" numeric NOT NULL,
  "battery_usable_capacity_kwh" numeric NOT NULL,
  "connection_import_capacity_kw" numeric NOT NULL,
  "connection_export_capacity_kw" numeric NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT 'now()',
  "updated_at" timestamptz NOT NULL DEFAULT 'now()'
);

CREATE INDEX ON "spot_prices_gen" ("spot_code");

CREATE INDEX ON "spot_prices_gen" ("timestamp");

CREATE UNIQUE INDEX ON "spot_prices_gen" ("spot_code", "timestamp");

CREATE INDEX ON "battery_scenario_sim" ("battery_code");

CREATE INDEX ON "battery_scenario_sim" ("timestamp");

CREATE UNIQUE INDEX ON "battery_scenario_sim" ("battery_code", "timestamp");

CREATE INDEX ON "solar" ("solar_code");

CREATE INDEX ON "solar" ("timestamp");

CREATE UNIQUE INDEX ON "solar" ("solar_code", "timestamp");

CREATE INDEX ON "power_consumption" ("consumption_code");

CREATE INDEX ON "power_consumption" ("timestamp");

CREATE UNIQUE INDEX ON "power_consumption" ("consumption_code", "timestamp");

CREATE INDEX ON "scenario" ("site_code");

CREATE INDEX ON "scenario" ("spot_code");

CREATE INDEX ON "scenario" ("consumption_code");

CREATE INDEX ON "scenario" ("solar_code");

CREATE INDEX ON "scenario" ("battery_code");

ALTER TABLE "spot_prices_gen" ADD FOREIGN KEY ("spot_code") REFERENCES "spot_dataset" ("spot_code");

ALTER TABLE "battery_scenario_sim" ADD FOREIGN KEY ("battery_code") REFERENCES "battery_dataset" ("battery_code");

ALTER TABLE "solar" ADD FOREIGN KEY ("solar_code") REFERENCES "solar_dataset" ("solar_code");

ALTER TABLE "power_consumption" ADD FOREIGN KEY ("consumption_code") REFERENCES "consumption_dataset" ("consumption_code");

ALTER TABLE "scenario" ADD FOREIGN KEY ("site_code") REFERENCES "site" ("site_code");

ALTER TABLE "scenario" ADD FOREIGN KEY ("spot_code") REFERENCES "spot_dataset" ("spot_code");

ALTER TABLE "scenario" ADD FOREIGN KEY ("consumption_code") REFERENCES "consumption_dataset" ("consumption_code");

ALTER TABLE "scenario" ADD FOREIGN KEY ("solar_code") REFERENCES "solar_dataset" ("solar_code");

ALTER TABLE "scenario" ADD FOREIGN KEY ("battery_code") REFERENCES "battery_dataset" ("battery_code");
