CREATE OR REPLACE FUNCTION f_summary_year(
    _spot_vs_ave_lower numeric,
    _spot_vs_ave_upper numeric,
    _charge_max numeric,
    _discharge_max numeric,
    _rte numeric,
    _capacity numeric,
    _round_trip_pct numeric,
    _total numeric,
    _lcc_code varchar,
    _moving_ave_row_count integer,
    _consumption_code varchar,
    _ppc_code varchar,
    _separate_meter boolean,
    _solar_code varchar,
    _solar_scale numeric,
    _yearly_bill numeric,
    _num_houses numeric,
    _pcr_code varchar,
    _lcr_code varchar
)
RETURNS TABLE(
    summary_id numeric,
    description text,
    consumption_code text,
    "2024" numeric,
    "2025" numeric,
    "2026" numeric,
    "2027" numeric,
    "2028" numeric,
    "2029" numeric,
    "2030" numeric,
    "2031" numeric,
    "2032" numeric,
    "2033" numeric,
    "2034" numeric,
    "2035" numeric,
    "2036" numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
	drop table if exists tmp_battery_calc;
	
	create temporary table tmp_battery_calc as
	select * from f_battery_calc
	(
		_spot_vs_ave_lower,
		_spot_vs_ave_upper,
		_charge_max,
		_discharge_max,
		_rte,
		_capacity,
		_round_trip_pct,
		_total,
		_lcc_code,
		_moving_ave_row_count
	);
	
	CREATE INDEX IF NOT EXISTS idx_row_num_tmp_battery_calc ON tmp_battery_calc
	USING btree (row_num ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

	CREATE INDEX IF NOT EXISTS idx_timestamp_tmp_battery_calc ON tmp_battery_calc
	USING btree ("timestamp" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

	ANALYZE tmp_battery_calc;

	RETURN QUERY
	select * from
	(
		select
			1 as summary_id,
			'Net Meter Usage',
			pc.consumption_code::text,
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2024 then pc.main_site_consumption_kwh else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2025 then pc.main_site_consumption_kwh else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2026 then pc.main_site_consumption_kwh else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2027 then pc.main_site_consumption_kwh else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2028 then pc.main_site_consumption_kwh else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2029 then pc.main_site_consumption_kwh else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2030 then pc.main_site_consumption_kwh else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2031 then pc.main_site_consumption_kwh else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2032 then pc.main_site_consumption_kwh else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2033 then pc.main_site_consumption_kwh else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2034 then pc.main_site_consumption_kwh else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2035 then pc.main_site_consumption_kwh else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2036 then pc.main_site_consumption_kwh else 0 end) AS "2036"
		from spot_price_jg sp
			left join power_consumption pc on sp.timestamp = pc.timestamp
		where pc.consumption_code = _consumption_code
		group by pc.consumption_code
		union
		select
			2 as summary_id,
			'Energy',
			pc.consumption_code::text,
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) AS "2036"
		from power_consumption pc
			left join ppc on ppc.timestamp = pc.timestamp and ppc_code = _ppc_code
		where pc.consumption_code = _consumption_code
		group by pc.consumption_code
		union
		select
			3 as summary_id,
			'Variable Lines (ex GST)',
			_consumption_code,
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2024 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2024",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2025 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2025",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2026 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2026",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2027 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2027",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2028 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2028",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2029 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2029",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2030 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2030",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2031 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2031",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2032 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2032",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2033 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2033",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2034 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2034",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2035 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2035",
			SUM(case when not _separate_meter and EXTRACT(YEAR FROM pc.timestamp) = 2036 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2036"
		from power_consumption pc
			left join solar s on solar_code = _solar_code and pc.timestamp = s.timestamp
			left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
			left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
		where pc.consumption_code = _consumption_code
		group by pc.consumption_code
		union
		select
			3.5 as summary_id,
			'Vairable Lines Main Site',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then pc.main_site_consumption_kwh * lcc_cost else 0 end) AS "2036"
		from power_consumption pc
			left join solar s on solar_code = _solar_code and pc.timestamp = s.timestamp
			left join spot_price_jg sp on sp.timestamp = pc.timestamp
			left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
			left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
		where pc.consumption_code = _consumption_code
		group by pc.consumption_code
		union
		select
			4 as summary_id,
			'Cost of energy used at main site @ spot',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) AS "2036"
		from power_consumption pc
			left join solar s on solar_code = _solar_code and pc.timestamp = s.timestamp
			left join spot_price_jg sp on sp.timestamp = pc.timestamp
			left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
			left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
		where pc.consumption_code = _consumption_code
		group by pc.consumption_code
		union
		select
			5 as summary_id,
			'Credit of Solar generated at main site @ spot',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2036"
		from power_consumption pc
			left join solar s on solar_code = _solar_code and pc.timestamp = s.timestamp
			left join spot_price_jg sp on sp.timestamp = pc.timestamp
			left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
			left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
		where pc.consumption_code = _consumption_code
		group by pc.consumption_code
		union
		select
			6 as summary_id,
			'Cost (credit) of energy used after Solar generated at main site @ spot',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then pc.main_site_consumption_kwh * sp.spot_price else 0 end) - SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then solar_production_kwh * _solar_scale * sp.spot_price else 0 end) AS "2036"
		from power_consumption pc
			left join solar s on solar_code = _solar_code and pc.timestamp = s.timestamp
			left join spot_price_jg sp on sp.timestamp = pc.timestamp
			left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
			left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
		where pc.consumption_code = _consumption_code
		group by pc.consumption_code
		union
		select
	7 as summary_id,
	'Battery charge kwh',
		_consumption_code,
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2024 then battery_charge_kwh else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2025 then battery_charge_kwh else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2026 then battery_charge_kwh else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2027 then battery_charge_kwh else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2028 then battery_charge_kwh else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2029 then battery_charge_kwh else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2030 then battery_charge_kwh else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2031 then battery_charge_kwh else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2032 then battery_charge_kwh else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2033 then battery_charge_kwh else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2034 then battery_charge_kwh else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2035 then battery_charge_kwh else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2036 then battery_charge_kwh else 0 end) AS "2036"
	from tmp_battery_calc bs
	union
	select
		8 as summary_id,
		'Battery discharge kwh',
		_consumption_code,
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2024 then battery_discharge_kwh else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2025 then battery_discharge_kwh else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2026 then battery_discharge_kwh else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2027 then battery_discharge_kwh else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2028 then battery_discharge_kwh else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2029 then battery_discharge_kwh else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2030 then battery_discharge_kwh else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2031 then battery_discharge_kwh else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2032 then battery_discharge_kwh else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2033 then battery_discharge_kwh else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2034 then battery_discharge_kwh else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2035 then battery_discharge_kwh else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM bs.timestamp) = 2036 then battery_discharge_kwh else 0 end) AS "2036"
	from tmp_battery_calc bs
	union
		select
			9 as summary_id,
			'Sum spot price',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2024 then sp.spot_price else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2025 then sp.spot_price else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2026 then sp.spot_price else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2027 then sp.spot_price else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2028 then sp.spot_price else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2029 then sp.spot_price else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2030 then sp.spot_price else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2031 then sp.spot_price else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2032 then sp.spot_price else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2033 then sp.spot_price else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2034 then sp.spot_price else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2035 then sp.spot_price else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM sp.timestamp) = 2036 then sp.spot_price else 0 end) AS "2036"
		from lcc l
			left join spot_price_jg sp on sp.timestamp = l.timestamp
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			10 as summary_id,
			'Sum lcc cost',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then lcc_cost else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then lcc_cost else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then lcc_cost else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then lcc_cost else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then lcc_cost else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then lcc_cost else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then lcc_cost else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then lcc_cost else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then lcc_cost else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then lcc_cost else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then lcc_cost else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then lcc_cost else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then lcc_cost else 0 end) AS "2036"
		from lcc l
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			12 as summary_id,
			'Cost of lcc * charge',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then battery_charge_kwh * lcc_cost else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then battery_charge_kwh * lcc_cost else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then battery_charge_kwh * lcc_cost else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then battery_charge_kwh * lcc_cost else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then battery_charge_kwh * lcc_cost else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then battery_charge_kwh * lcc_cost else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then battery_charge_kwh * lcc_cost else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then battery_charge_kwh * lcc_cost else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then battery_charge_kwh * lcc_cost else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then battery_charge_kwh * lcc_cost else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then battery_charge_kwh * lcc_cost else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then battery_charge_kwh * lcc_cost else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then battery_charge_kwh * lcc_cost else 0 end) AS "2036"
		from lcc l
			left join spot_price_jg sp on sp.timestamp = l.timestamp
			left join tmp_battery_calc bs on bs.timestamp = l.timestamp
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			11 as summary_id,
			'Cost of battery charge @ spot',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then (battery_charge_kwh * sp.spot_price) else 0 end) AS "2036"
		from lcc l
			left join spot_price_jg sp on sp.timestamp = l.timestamp
			left join tmp_battery_calc bs on bs.timestamp = l.timestamp
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			13 as summary_id,
			'Revenue from battery discharge @ spot',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then battery_discharge_kwh * sp.spot_price else 0 end) AS "2036"
		from lcc l
			left join spot_price_jg sp on sp.timestamp = l.timestamp
			left join tmp_battery_calc bs on bs.timestamp = l.timestamp
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			14 as summary_id,
			'Revenue from battery discharge - charge @ spot',
			_consumption_code,
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2024",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2025",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2026",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2027",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2028",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2029",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2030",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2031",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2032",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2033",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2034",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2035",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2036"
		from lcc l
			left join spot_price_jg sp on sp.timestamp = l.timestamp
			left join tmp_battery_calc bs on bs.timestamp = l.timestamp
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			15 as summary_id,
			'Average power bill x number clients',
			_consumption_code,
			_yearly_bill * _num_houses AS "2024",
			0 AS "2025",
			0 AS "2026",
			0 AS "2027",
			0 AS "2028",
			0 AS "2029",
			0 AS "2030",
			0 AS "2031",
			0 AS "2032",
			0 AS "2033",
			0 AS "2034",
			0 AS "2035",
			0 AS "2036"
		union
		select
			16 as summary_id,
			'Cost of energy used houses @ spot',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2024 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2025 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2026 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2027 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2028 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2029 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2030 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2031 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2032 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2033 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2034 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2035 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pcr.timestamp) = 2036 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2036"
		from power_consumption_res pcr
			left join spot_price_jg sp on sp.timestamp = pcr.timestamp
		where pcr.consumption_code_res = _pcr_code
		group by pcr.consumption_code_res
		union
		select
			17 as summary_id,
			'Lines charges for homes - variable',
			_consumption_code,
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then client_site_consumption * _num_houses * lcr_cost else 0 end) AS "2036"
		from lcr l
			left join power_consumption_res pcr on pcr.consumption_code_res = _pcr_code and l.timestamp = pcr.timestamp
		where lcr_code = _lcr_code
		group by lcr_code
	) s
	where s.consumption_code = _consumption_code
	order by summary_id;
END
$$;