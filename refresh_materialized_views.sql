-- ✅ Finalized Script (Fixed: FROM-clause ordering issue with alias 'sc')

-- Step 1: Drop the materialized view and refresh function
DROP MATERIALIZED VIEW IF EXISTS joined_energy_data_mv;
DROP FUNCTION IF EXISTS refresh_joined_energy_data_mv CASCADE;

-- Step 2: Create the materialized view
CREATE MATERIALIZED VIEW joined_energy_data_mv AS
SELECT
  ROW_NUMBER() OVER () AS id,
  pc.timestamp,
  pc.main_site_consumption_kwh,
  s.solar_production_kwh,
  bs.battery_charge_kwh,
  bs.battery_discharge_kwh,
  sp.spot_price,
  sc.scenario_code,
  sc.site_code,
  sc.scenario_preferred,
  sc.solar_capacity_kw,
  sc.battery_usable_capacity_kwh,
  sc.connection_import_capacity_kw,
  sc.connection_export_capacity_kw
FROM power_consumption pc
JOIN scenario sc
  ON pc.consumption_code = sc.consumption_code
JOIN solar s
  ON pc.timestamp = s.timestamp AND sc.solar_code = s.solar_code
JOIN battery_scenario_sim bs
  ON pc.timestamp = bs.timestamp AND sc.battery_code = bs.battery_code
JOIN spot_prices_gen sp
  ON pc.timestamp = sp.timestamp AND sc.spot_code = sp.spot_code;

-- Step 3: Create a unique index required for CONCURRENTLY
CREATE UNIQUE INDEX idx_joined_energy_data_mv_id ON joined_energy_data_mv (id);

-- Step 4: Create the refresh function
CREATE OR REPLACE FUNCTION refresh_joined_energy_data_mv()
RETURNS trigger AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY joined_energy_data_mv;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Create triggers to auto-refresh the view
CREATE TRIGGER trg_refresh_mv_power_consumption
AFTER INSERT OR UPDATE OR DELETE ON power_consumption
FOR EACH STATEMENT EXECUTE FUNCTION refresh_joined_energy_data_mv();

CREATE TRIGGER trg_refresh_mv_solar
AFTER INSERT OR UPDATE OR DELETE ON solar
FOR EACH STATEMENT EXECUTE FUNCTION refresh_joined_energy_data_mv();

CREATE TRIGGER trg_refresh_mv_battery
AFTER INSERT OR UPDATE OR DELETE ON battery_scenario_sim
FOR EACH STATEMENT EXECUTE FUNCTION refresh_joined_energy_data_mv();

CREATE TRIGGER trg_refresh_mv_spot
AFTER INSERT OR UPDATE OR DELETE ON spot_prices_gen
FOR EACH STATEMENT EXECUTE FUNCTION refresh_joined_energy_data_mv();

CREATE TRIGGER trg_refresh_mv_scenario
AFTER INSERT OR UPDATE OR DELETE ON scenario
FOR EACH STATEMENT EXECUTE FUNCTION refresh_joined_energy_data_mv();
