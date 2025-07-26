-- ✅ Transposed Yearly Summary: Main Site Consumption + Solar Production (Auto-refreshable)

-- Step 1: Drop view & refresh function if they exist
DROP MATERIALIZED VIEW IF EXISTS energy_summary_mv;
DROP FUNCTION IF EXISTS refresh_energy_summary_mv CASCADE;

-- Step 2: Create materialized view
CREATE MATERIALIZED VIEW energy_summary_mv AS
WITH year_data AS (
  SELECT
    EXTRACT(YEAR FROM pc.timestamp)::INT AS year,
    SUM(pc.main_site_consumption_kwh) AS main_consumption,
    SUM(s.solar_production_kwh) AS solar_production
  FROM power_consumption pc
  JOIN solar s ON pc.timestamp = s.timestamp
  GROUP BY EXTRACT(YEAR FROM pc.timestamp)
),
transposed AS (
  SELECT 'Main Site Consumption' AS summary_metric,
    MAX(CASE WHEN year = 2014 THEN main_consumption END) AS "2014",
    MAX(CASE WHEN year = 2015 THEN main_consumption END) AS "2015",
    MAX(CASE WHEN year = 2016 THEN main_consumption END) AS "2016",
    MAX(CASE WHEN year = 2017 THEN main_consumption END) AS "2017",
    MAX(CASE WHEN year = 2018 THEN main_consumption END) AS "2018",
    MAX(CASE WHEN year = 2019 THEN main_consumption END) AS "2019",
    MAX(CASE WHEN year = 2020 THEN main_consumption END) AS "2020",
    MAX(CASE WHEN year = 2021 THEN main_consumption END) AS "2021",
    MAX(CASE WHEN year = 2022 THEN main_consumption END) AS "2022",
    MAX(CASE WHEN year = 2023 THEN main_consumption END) AS "2023",
    MAX(CASE WHEN year = 2024 THEN main_consumption END) AS "2024"
  FROM year_data
  UNION ALL
  SELECT 'Solar Production' AS summary_metric,
    MAX(CASE WHEN year = 2014 THEN solar_production END),
    MAX(CASE WHEN year = 2015 THEN solar_production END),
    MAX(CASE WHEN year = 2016 THEN solar_production END),
    MAX(CASE WHEN year = 2017 THEN solar_production END),
    MAX(CASE WHEN year = 2018 THEN solar_production END),
    MAX(CASE WHEN year = 2019 THEN solar_production END),
    MAX(CASE WHEN year = 2020 THEN solar_production END),
    MAX(CASE WHEN year = 2021 THEN solar_production END),
    MAX(CASE WHEN year = 2022 THEN solar_production END),
    MAX(CASE WHEN year = 2023 THEN solar_production END),
    MAX(CASE WHEN year = 2024 THEN solar_production END)
  FROM year_data
)
SELECT * FROM transposed;

-- Step 3: Create refresh function
CREATE OR REPLACE FUNCTION refresh_energy_summary_mv()
RETURNS trigger AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY energy_summary_mv;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Step 4: Set up triggers
CREATE TRIGGER trg_refresh_summary_mv_pc
AFTER INSERT OR UPDATE OR DELETE ON power_consumption
FOR EACH STATEMENT EXECUTE FUNCTION refresh_energy_summary_mv();

CREATE TRIGGER trg_refresh_summary_mv_solar
AFTER INSERT OR UPDATE OR DELETE ON solar
FOR EACH STATEMENT EXECUTE FUNCTION refresh_energy_summary_mv();


SELECT * FROM energy_summary_mv;
