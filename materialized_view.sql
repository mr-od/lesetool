-- Active: 1752189674258@@postgres@5432@directus
CREATE MATERIALIZED VIEW joined_energy_data_mv AS
SELECT
  pc.timestamp,
  pc.main_site_consumption_kwh,
  s.solar_production_kwh,
  bss.battery_charge_kwh,
  bss.battery_discharge_kwh,
  spg.spot_price
FROM power_consumption pc
JOIN solar s
  ON pc.timestamp = s.timestamp
JOIN battery_scenario_sim bss
  ON pc.timestamp = bss.timestamp
JOIN spot_prices_gen spg
  ON pc.timestamp = spg.timestamp;


SELECT * FROM joined_energy_data_mv;


DROP TABLE IF EXISTS joined_energy_data_mv;
DROP MATERIALIZED VIEW IF EXISTS joined_energy_data_mv;


CREATE UNLOGGED TABLE joined_energy_data_mv AS
SELECT
  pc.timestamp,
  pc.main_site_consumption_kwh,
  s.solar_production_kwh,
  bss.battery_charge_kwh,
  bss.battery_discharge_kwh,
  spg.spot_price
FROM power_consumption pc
JOIN solar s ON pc.timestamp = s.timestamp
JOIN battery_scenario_sim bss ON pc.timestamp = bss.timestamp
JOIN spot_prices_gen spg ON pc.timestamp = spg.timestamp;

-- Add a primary key for Directus compatibility
ALTER TABLE joined_energy_data_mv ADD COLUMN id SERIAL PRIMARY KEY;

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton
) VALUES (
  'joined_energy_data_mv', 'table', 'Aggregated energy data', '{{timestamp}}', false, false
);

ALTER TABLE joined_energy_data_mv
ALTER COLUMN timestamp TYPE timestamp with time zone;


DROP TABLE IF EXISTS joined_energy_data_mv;

CREATE UNLOGGED TABLE joined_energy_data_mv AS
SELECT
  pc.timestamp::timestamptz AS timestamp,
  pc.main_site_consumption_kwh,
  s.solar_production_kwh,
  bss.battery_charge_kwh,
  bss.battery_discharge_kwh,
  spg.spot_price
FROM power_consumption pc
JOIN solar s ON pc.timestamp = s.timestamp
JOIN battery_scenario_sim bss ON pc.timestamp = bss.timestamp
JOIN spot_prices_gen spg ON pc.timestamp = spg.timestamp;

ALTER TABLE joined_energy_data_mv ADD COLUMN id SERIAL PRIMARY KEY;

SELECT COUNT(*) FROM joined_energy_data_mv WHERE timestamp IS NULL;

SELECT * 
FROM directus_fields 
WHERE collection = 'joined_energy_data_mv' 
  AND field = 'timestamp';




