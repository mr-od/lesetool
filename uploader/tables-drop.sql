-- Drop all tables in reverse dependency order to avoid foreign key constraint errors
DROP TABLE IF EXISTS scenario CASCADE;
DROP TABLE IF EXISTS power_consumption CASCADE;
DROP TABLE IF EXISTS solar CASCADE;
DROP TABLE IF EXISTS battery_scenario_sim CASCADE;
DROP TABLE IF EXISTS spot_prices_gen CASCADE;
DROP TABLE IF EXISTS site CASCADE;
