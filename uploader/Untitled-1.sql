ALTER TABLE "battery_action"
ALTER COLUMN "battery_kwh" TYPE numeric(12,4);

CREATE OR REPLACE FUNCTION populate_battery_simulator(
    p_scenario_id INT,
    p_initial_soc_kwh NUMERIC,
    p_charge_limit_kwh NUMERIC,
    p_inverter_limit_kwh NUMERIC
)
RETURNS VOID AS
$$
DECLARE
    v_battery_action RECORD;
    v_battery_soc_start_kwh NUMERIC := p_initial_soc_kwh;
    v_battery_rtf_kwh NUMERIC;
    v_battery_charge_kwh NUMERIC;
    v_battery_discharge_kwh NUMERIC := 0;
    v_battery_soc_end_kwh NUMERIC;
BEGIN
    -- Create battery_simulator table if it doesn't exist
    EXECUTE '
        CREATE TABLE IF NOT EXISTS battery_simulator (
            id SERIAL PRIMARY KEY,
            timestamp TIMESTAMP,
            battery_soc_start_kwh NUMERIC,
            battery_rtf_kwh NUMERIC,
            battery_charge_kwh NUMERIC,
            battery_discharge_kwh NUMERIC,
            battery_soc_end_kwh NUMERIC,
            scenario_id INT
        );
    ';

    -- Loop through battery_action table ordered by timestamp
    FOR v_battery_action IN
        SELECT * 
        FROM battery_action 
        WHERE scenario_id = p_scenario_id
        ORDER BY timestamp
    LOOP
        -- Calculate Remaining to Full
        v_battery_rtf_kwh := v_battery_action.battery_kwh - v_battery_soc_start_kwh;
        IF v_battery_rtf_kwh < 0 THEN
            v_battery_rtf_kwh := 0;
        END IF;

        -- Determine charge amount
        IF TRIM(LOWER(v_battery_action.battery_action)) = 'charge' AND v_battery_action.battery_kwh > 0 THEN
            v_battery_charge_kwh := LEAST(p_charge_limit_kwh, v_battery_rtf_kwh);
        ELSE
            v_battery_charge_kwh := 0;
        END IF;

        -- Calculate end SOC
        v_battery_soc_end_kwh := v_battery_soc_start_kwh + v_battery_charge_kwh - v_battery_discharge_kwh;

        -- Insert into battery_simulator
        INSERT INTO battery_simulator (
            timestamp,
            battery_soc_start_kwh,
            battery_rtf_kwh,
            battery_charge_kwh,
            battery_discharge_kwh,
            battery_soc_end_kwh,
            scenario_id
        ) VALUES (
            v_battery_action.timestamp,
            v_battery_soc_start_kwh,
            v_battery_rtf_kwh,
            v_battery_charge_kwh,
            v_battery_discharge_kwh,
            v_battery_soc_end_kwh,
            p_scenario_id
        );

        -- Update for next iteration
        v_battery_soc_start_kwh := v_battery_soc_end_kwh;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT populate_battery_simulator(
    1,        
    500,     
    10,      
    10      
);
