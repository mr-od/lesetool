--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4 (Debian 17.4-1.pgdg120+2)
-- Dumped by pg_dump version 17.4 (Debian 17.4-1.pgdg120+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: f_battery_base(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_battery_base(_spot_vs_ave_lower numeric, _spot_vs_ave_upper numeric, _charge_max numeric, _discharge_max numeric, _rte numeric, _capacity numeric, _round_trip_pct numeric, _total numeric, _lcc_code text, _moving_ave_row_count integer) RETURNS TABLE("timestamp" timestamp with time zone, spot_price numeric, forward_moving_average numeric, row_num bigint, group_num bigint, rank_helper numeric, moving_ave numeric, spot_per_ave numeric, capacity_degraded numeric, ad numeric, rank_max integer, operation text, rank_charge bigint, rank_discharge bigint, revenue_discharge numeric, bb numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN QUERY
	select
		v.*,
		case
			when v.spot_per_ave > _spot_vs_ave_lower and v.spot_per_ave < _spot_vs_ave_upper then 'Hold'
			when v.spot_per_ave < _spot_vs_ave_upper then 'Charge'
			else 'Discharge'
		end as operation,
		rank() over (partition by v.group_num order by v.rank_helper asc) as rank_charge,
		rank() over (partition by v.group_num order by v.rank_helper desc) as rank_discharge,
		_discharge_max * v.spot_price as revenue_discharge,
		v.capacity_degraded / _discharge_max / _rte as BB
	from
	(
		select
			t.*,
			u.fixed_avg as moving_ave,
			t.spot_price / u.fixed_avg as spot_per_ave,
			_capacity * (1.0-(((cast(t.row_num as numeric) % _total) - 1)/ _total) * (1.0 - _round_trip_pct)) as capacity_degraded,
			da.ad,
			24 as rank_max --u.rank_max
		from 
		(
			select
				sp.timestamp,
				sp.spot_price,
				AVG(sp.spot_price) OVER (
					ORDER BY sp.timestamp
					ROWS BETWEEN CURRENT ROW AND _moving_ave_row_count - 1 FOLLOWING
				) AS forward_moving_average,
				ROW_NUMBER() over (order by sp.timestamp) as row_num,
				case
					when (ROW_NUMBER() OVER (ORDER BY sp.timestamp) % _moving_ave_row_count) = 0 then
						ROW_NUMBER() OVER (ORDER BY sp.timestamp) / _moving_ave_row_count
					else
						(ROW_NUMBER() OVER (ORDER BY sp.timestamp) / _moving_ave_row_count) + 1
				end as group_num,
				sp.spot_price + (ROW_NUMBER() over ( order by sp.timestamp )::numeric + 6.0) / 10000000.0 as rank_helper
			FROM spot_price_jg sp
				left join lcc l on l.timestamp = sp.timestamp and lcc_code = _lcc_code
			where EXTRACT(YEAR FROM sp.timestamp) >= 2024 -- todo: remove when spot_prices_gen are up to date
			order by sp.timestamp
		) t
		left join discharge_amount da on t.timestamp = da.timestamp
		left join
		(
			select
				row_number() over (order by (n - 1)/(_moving_ave_row_count)) as group_num,
				avg(x.spot_price) as fixed_avg,
				count(*) as cnt
			from (
			  select
				sp.timestamp,
				sp.spot_price,
				row_number() over (order by sp.timestamp) as n
			  from spot_price_jg sp
			  order by sp.timestamp
			) x (timestamp, spot_price, n)
			group by (n - 1)/(_moving_ave_row_count)
			order by (n - 1)/(_moving_ave_row_count)
		) u on u.group_num = t.group_num
	) v	
	order by v.row_num;
END
$$;


--
-- Name: f_battery_calc(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_battery_calc(_spot_vs_ave_lower numeric, _spot_vs_ave_upper numeric, _charge_max numeric, _discharge_max numeric, _rte numeric, _capacity numeric, _round_trip_pct numeric, _total numeric, _lcc_code text, _moving_ave_row_count integer) RETURNS TABLE(row_num bigint, "timestamp" timestamp with time zone, soc_start numeric, capacity_degraded numeric, rtf numeric, battery_charge_kwh numeric, battery_discharge_kwh numeric, soc_end numeric, spot_price numeric, operation text, rank_charge bigint, rank_discharge bigint, bb numeric, af numeric, ad numeric, group_num bigint, spot_per_ave numeric, moving_ave numeric, forward_moving_ave numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
	drop table if exists tmp_battery_base;
	
	create temporary table tmp_battery_base as
	select * from f_battery_base
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
	
	CREATE INDEX IF NOT EXISTS idx_row_num_tmp_battery_base ON tmp_battery_base
	USING btree (row_num ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
	
	CREATE INDEX IF NOT EXISTS idx_timestamp_tmp_battery_base ON tmp_battery_base
	USING btree ("timestamp" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
	
	ANALYZE tmp_battery_base;
	
	RETURN QUERY
	WITH RECURSIVE battery_30min AS (
	    SELECT
			cast(1 as bigint) as row_num,
	        b.timestamp,
	        0.0 as soc_start,
			b.capacity_degraded,
			b.capacity_degraded as rtf,
			case
				when b.operation = 'Charge' then
					case
						when b.rank_charge <= floor(b.bb) + 1.0 then least(b.capacity_degraded, _charge_max)
						else 0.0
					end
				else 0.0
			end as battery_charge_kwh,
			0.0 as battery_discharge_kwh,
			0.0 + _rte * case
				when b.operation = 'Charge' then
					case
						when b.rank_charge <= floor(b.bb) + 1.0 then least(b.capacity_degraded, _charge_max)
						else 0.0
					end
				else 0.0 
			end as soc_end,
			b.spot_price,
			b.operation,
			b.rank_charge,
			b.rank_discharge,
			b.bb,
			case
				when to_char(b.timestamp, 'HH24MI') in ('0700', '1130', '1700', '0000') and b.operation = 'Charge'
				then floor(b.capacity_degraded / _charge_max)
				else 0.0
			end as af,
			0.0 as ad,
			b.group_num,
			b.spot_per_ave,
			b.moving_ave,
			b.forward_moving_average
	    FROM
	        tmp_battery_base b
	    WHERE
	        b.row_num = (SELECT MIN(b2.row_num) FROM tmp_battery_base b2)
	
	    UNION ALL
	    
	    
	    SELECT
			t.row_num,
	        t.timestamp,
	        prev_row.soc_end as soc_start,
			t.capacity_degraded,
			t.capacity_degraded - prev_row.soc_end as rtf,
			case
				when prev_row.soc_end < t.capacity_degraded and t.operation = 'Charge' then
					case
						when t.rank_charge <= floor(t.bb) + 1.0 then
							least
							(
								t.capacity_degraded - prev_row.soc_end, 
								case
									when t.rank_charge = floor(t.bb) + 1.0 then
										t.capacity_degraded -
										(
											_charge_max * 
											case
												when to_char(t.timestamp, 'HH24MI') in ('0700', '1130', '1700', '0000') then
													case
														when t.operation = 'Charge' then floor((t.capacity_degraded - prev_row.soc_end) / _charge_max)
														when t.operation = 'Discharge' then floor(prev_row.soc_end / _discharge_max)
														else prev_row.af
													end
												else prev_row.af
											end
										)
									else _charge_max
								end
							)
						else 0.0
					end
				else 0.0
			end as battery_charge_kwh,
			case
				when prev_row.soc_end > 0.0 then
					case
						when t.operation = 'Discharge' and t.rank_discharge <= floor(t.bb) + 1.0 then
							least
							(
								case
									when floor(t.bb) + 1.0 = t.rank_discharge then
										t.capacity_degraded -
										(
											_charge_max * 
											case
												when to_char(t.timestamp, 'HH24MI') in ('0700', '1130', '1700', '0000') then
													case
														when t.operation = 'Charge' then floor((t.capacity_degraded - prev_row.soc_end) / _charge_max)
														when t.operation = 'Discharge' then floor(prev_row.soc_end / _discharge_max)
														else prev_row.af
													end
												else prev_row.af
											end
										)
									else _discharge_max
								end,
								prev_row.soc_end
							)
						else 0.0
					end
				else 0.0
			end as battery_discharge_kwh,
	        prev_row.soc_end
			+ (
				case
					when prev_row.soc_end < t.capacity_degraded and t.operation = 'Charge' then
						case
							when t.rank_charge <= floor(t.bb) + 1.0 then
								least
								(
									t.capacity_degraded - prev_row.soc_end, 
									case
										when t.rank_charge = floor(t.bb) + 1.0 then
											t.capacity_degraded -
											(
												_charge_max * 
												case
													when to_char(t.timestamp, 'HH24MI') in ('0700', '1130', '1700', '0000') then
														case
															when t.operation = 'Charge' then floor((t.capacity_degraded - prev_row.soc_end) / _charge_max)
															when t.operation = 'Discharge' then floor(prev_row.soc_end / _discharge_max)
															else prev_row.af
														end
													else prev_row.af
												end
											)
										else _charge_max
									end
								)
							else 0.0
						end
					else 0.0
				end
				* _rte
			) - 
			(
				case
					when prev_row.soc_end > 0.0 then
						case
							when t.operation = 'Discharge' and t.rank_discharge <= floor(t.bb) + 1.0 then
								least(case when floor(t.bb) + 1.0 = t.rank_discharge then (t.capacity_degraded - (_charge_max * 
									case
										when to_char(t.timestamp, 'HH24MI') in ('0700', '1130', '1700', '0000') then
											case
												when t.operation = 'Charge' then floor((t.capacity_degraded - prev_row.soc_end) / _charge_max)
												when t.operation = 'Discharge' then floor(prev_row.soc_end / _discharge_max)
												else prev_row.af
											end
										else prev_row.af
									end)) else _discharge_max end, prev_row.soc_end)
							else 0.0
						end
					else 0.0
				end
				/ _rte
			) AS soc_end,
			t.spot_price,
			t.operation,
			t.rank_charge,
			t.rank_discharge,
			t.bb,
			case
				when to_char(t.timestamp, 'HH24MI') in ('0700', '1130', '1700', '0000') then
					case
						when t.operation = 'Charge' then floor((t.capacity_degraded - prev_row.soc_end) / _charge_max)
						when t.operation = 'Discharge' then floor(prev_row.soc_end / _discharge_max)
						else prev_row.af
					end
				else prev_row.af
			end as af,
			t.capacity_degraded -
			(
				_charge_max * 
				case
					when to_char(t.timestamp, 'HH24MI') in ('0700', '1130', '1700', '0000') then
						case
							when t.operation = 'Charge' then floor((t.capacity_degraded - prev_row.soc_end) / _charge_max)
							when t.operation = 'Discharge' then floor(prev_row.soc_end / _discharge_max)
							else prev_row.af
						end
					else prev_row.af
				end
			) as ad,
			t.group_num,
			t.spot_per_ave,
			t.moving_ave,
			t.forward_moving_average
	    FROM
	        tmp_battery_base t
	    JOIN
	        battery_30min prev_row ON t.row_num = prev_row.row_num + 1 -- Join to the previous row in the CTE
	)
	SELECT
		b3.row_num,
	    b3.timestamp,
	    ROUND(b3.soc_start, 11) as soc_start,
		ROUND(b3.capacity_degraded, 11) as capacity_degraded,
		ROUND(b3.rtf, 11) as rtf,
		ROUND(b3.battery_charge_kwh, 11) as battery_charge_kwh,
		ROUND(b3.battery_discharge_kwh, 11) as battery_discharge_kwh,
	    ROUND(b3.soc_end, 11) as soc_end,
		ROUND(b3.spot_price, 11) as spot_price,
		b3.operation,
		b3.rank_charge,
		b3.rank_discharge,
		b3.bb,
		b3.af,
		b3.ad,
		b3.group_num,
		b3.spot_per_ave,
		b3.moving_ave,
		b3.forward_moving_average
	FROM
	    battery_30min b3
	ORDER BY
	    b3."timestamp";
END
$$;


--
-- Name: f_summary_month(text, numeric, numeric, numeric, text, text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_summary_month(_site_code text, _num_houses numeric, _solar_scale numeric, _yearly_bill numeric, _solar_code text, _lcc_code text, _lcr_code text, _pcr_code text, _spot_vs_ave_lower numeric, _spot_vs_ave_upper numeric, _charge_max numeric, _discharge_max numeric, _rte numeric, _capacity numeric, _round_trip_pct numeric, _total numeric, _moving_ave_row_count integer, _separate_meter boolean) RETURNS TABLE(summary_id integer, metric text, site_code text, "2024-01" numeric, "2024-02" numeric, "2024-03" numeric, "2024-04" numeric, "2024-05" numeric, "2024-06" numeric, "2024-07" numeric, "2024-08" numeric, "2024-09" numeric, "2024-10" numeric, "2024-11" numeric, "2024-12" numeric, "2025-01" numeric, "2025-02" numeric, "2025-03" numeric, "2025-04" numeric, "2025-05" numeric, "2025-06" numeric, "2025-07" numeric, "2025-08" numeric, "2025-09" numeric, "2025-10" numeric, "2025-11" numeric, "2025-12" numeric, "2026-01" numeric, "2026-02" numeric, "2026-03" numeric, "2026-04" numeric, "2026-05" numeric, "2026-06" numeric, "2026-07" numeric, "2026-08" numeric, "2026-09" numeric, "2026-10" numeric, "2026-11" numeric, "2026-12" numeric, "2027-01" numeric, "2027-02" numeric, "2027-03" numeric, "2027-04" numeric, "2027-05" numeric, "2027-06" numeric, "2027-07" numeric, "2027-08" numeric, "2027-09" numeric, "2027-10" numeric, "2027-11" numeric, "2027-12" numeric, "2028-01" numeric, "2028-02" numeric, "2028-03" numeric, "2028-04" numeric, "2028-05" numeric, "2028-06" numeric, "2028-07" numeric, "2028-08" numeric, "2028-09" numeric, "2028-10" numeric, "2028-11" numeric, "2028-12" numeric, "2029-01" numeric, "2029-02" numeric, "2029-03" numeric, "2029-04" numeric, "2029-05" numeric, "2029-06" numeric, "2029-07" numeric, "2029-08" numeric, "2029-09" numeric, "2029-10" numeric, "2029-11" numeric, "2029-12" numeric, "2030-01" numeric, "2030-02" numeric, "2030-03" numeric, "2030-04" numeric, "2030-05" numeric, "2030-06" numeric, "2030-07" numeric, "2030-08" numeric, "2030-09" numeric, "2030-10" numeric, "2030-11" numeric, "2030-12" numeric, "2031-01" numeric, "2031-02" numeric, "2031-03" numeric, "2031-04" numeric, "2031-05" numeric, "2031-06" numeric, "2031-07" numeric, "2031-08" numeric, "2031-09" numeric, "2031-10" numeric, "2031-11" numeric, "2031-12" numeric, "2032-01" numeric, "2032-02" numeric, "2032-03" numeric, "2032-04" numeric, "2032-05" numeric, "2032-06" numeric, "2032-07" numeric, "2032-08" numeric, "2032-09" numeric, "2032-10" numeric, "2032-11" numeric, "2032-12" numeric, "2033-01" numeric, "2033-02" numeric, "2033-03" numeric, "2033-04" numeric, "2033-05" numeric, "2033-06" numeric, "2033-07" numeric, "2033-08" numeric, "2033-09" numeric, "2033-10" numeric, "2033-11" numeric, "2033-12" numeric, "2034-01" numeric, "2034-02" numeric, "2034-03" numeric, "2034-04" numeric, "2034-05" numeric, "2034-06" numeric, "2034-07" numeric, "2034-08" numeric, "2034-09" numeric, "2034-10" numeric, "2034-11" numeric, "2034-12" numeric, "2035-01" numeric, "2035-02" numeric, "2035-03" numeric, "2035-04" numeric, "2035-05" numeric, "2035-06" numeric, "2035-07" numeric, "2035-08" numeric, "2035-09" numeric, "2035-10" numeric, "2035-11" numeric, "2035-12" numeric, "2036-01" numeric, "2036-02" numeric, "2036-03" numeric, "2036-04" numeric, "2036-05" numeric, "2036-06" numeric, "2036-07" numeric, "2036-08" numeric, "2036-09" numeric, "2036-10" numeric, "2036-11" numeric, "2036-12" numeric)
    LANGUAGE plpgsql
    AS $$BEGIN
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
			consumption_code::text as site_code,
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-01' then pc.main_site_consumption_kwh else 0 end) as "2024-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-02' then pc.main_site_consumption_kwh else 0 end) as "2024-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-03' then pc.main_site_consumption_kwh else 0 end) as "2024-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-04' then pc.main_site_consumption_kwh else 0 end) as "2024-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-05' then pc.main_site_consumption_kwh else 0 end) as "2024-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-06' then pc.main_site_consumption_kwh else 0 end) as "2024-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-07' then pc.main_site_consumption_kwh else 0 end) as "2024-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-08' then pc.main_site_consumption_kwh else 0 end) as "2024-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-09' then pc.main_site_consumption_kwh else 0 end) as "2024-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-10' then pc.main_site_consumption_kwh else 0 end) as "2024-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-11' then pc.main_site_consumption_kwh else 0 end) as "2024-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-12' then pc.main_site_consumption_kwh else 0 end) as "2024-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-01' then pc.main_site_consumption_kwh else 0 end) as "2025-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-02' then pc.main_site_consumption_kwh else 0 end) as "2025-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-03' then pc.main_site_consumption_kwh else 0 end) as "2025-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-04' then pc.main_site_consumption_kwh else 0 end) as "2025-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-05' then pc.main_site_consumption_kwh else 0 end) as "2025-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-06' then pc.main_site_consumption_kwh else 0 end) as "2025-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-07' then pc.main_site_consumption_kwh else 0 end) as "2025-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-08' then pc.main_site_consumption_kwh else 0 end) as "2025-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-09' then pc.main_site_consumption_kwh else 0 end) as "2025-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-10' then pc.main_site_consumption_kwh else 0 end) as "2025-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-11' then pc.main_site_consumption_kwh else 0 end) as "2025-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-12' then pc.main_site_consumption_kwh else 0 end) as "2025-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-01' then pc.main_site_consumption_kwh else 0 end) as "2026-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-02' then pc.main_site_consumption_kwh else 0 end) as "2026-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-03' then pc.main_site_consumption_kwh else 0 end) as "2026-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-04' then pc.main_site_consumption_kwh else 0 end) as "2026-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-05' then pc.main_site_consumption_kwh else 0 end) as "2026-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-06' then pc.main_site_consumption_kwh else 0 end) as "2026-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-07' then pc.main_site_consumption_kwh else 0 end) as "2026-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-08' then pc.main_site_consumption_kwh else 0 end) as "2026-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-09' then pc.main_site_consumption_kwh else 0 end) as "2026-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-10' then pc.main_site_consumption_kwh else 0 end) as "2026-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-11' then pc.main_site_consumption_kwh else 0 end) as "2026-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-12' then pc.main_site_consumption_kwh else 0 end) as "2026-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-01' then pc.main_site_consumption_kwh else 0 end) as "2027-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-02' then pc.main_site_consumption_kwh else 0 end) as "2027-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-03' then pc.main_site_consumption_kwh else 0 end) as "2027-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-04' then pc.main_site_consumption_kwh else 0 end) as "2027-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-05' then pc.main_site_consumption_kwh else 0 end) as "2027-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-06' then pc.main_site_consumption_kwh else 0 end) as "2027-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-07' then pc.main_site_consumption_kwh else 0 end) as "2027-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-08' then pc.main_site_consumption_kwh else 0 end) as "2027-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-09' then pc.main_site_consumption_kwh else 0 end) as "2027-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-10' then pc.main_site_consumption_kwh else 0 end) as "2027-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-11' then pc.main_site_consumption_kwh else 0 end) as "2027-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-12' then pc.main_site_consumption_kwh else 0 end) as "2027-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-01' then pc.main_site_consumption_kwh else 0 end) as "2028-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-02' then pc.main_site_consumption_kwh else 0 end) as "2028-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-03' then pc.main_site_consumption_kwh else 0 end) as "2028-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-04' then pc.main_site_consumption_kwh else 0 end) as "2028-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-05' then pc.main_site_consumption_kwh else 0 end) as "2028-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-06' then pc.main_site_consumption_kwh else 0 end) as "2028-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-07' then pc.main_site_consumption_kwh else 0 end) as "2028-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-08' then pc.main_site_consumption_kwh else 0 end) as "2028-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-09' then pc.main_site_consumption_kwh else 0 end) as "2028-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-10' then pc.main_site_consumption_kwh else 0 end) as "2028-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-11' then pc.main_site_consumption_kwh else 0 end) as "2028-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-12' then pc.main_site_consumption_kwh else 0 end) as "2028-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-01' then pc.main_site_consumption_kwh else 0 end) as "2029-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-02' then pc.main_site_consumption_kwh else 0 end) as "2029-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-03' then pc.main_site_consumption_kwh else 0 end) as "2029-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-04' then pc.main_site_consumption_kwh else 0 end) as "2029-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-05' then pc.main_site_consumption_kwh else 0 end) as "2029-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-06' then pc.main_site_consumption_kwh else 0 end) as "2029-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-07' then pc.main_site_consumption_kwh else 0 end) as "2029-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-08' then pc.main_site_consumption_kwh else 0 end) as "2029-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-09' then pc.main_site_consumption_kwh else 0 end) as "2029-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-10' then pc.main_site_consumption_kwh else 0 end) as "2029-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-11' then pc.main_site_consumption_kwh else 0 end) as "2029-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-12' then pc.main_site_consumption_kwh else 0 end) as "2029-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-01' then pc.main_site_consumption_kwh else 0 end) as "2030-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-02' then pc.main_site_consumption_kwh else 0 end) as "2030-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-03' then pc.main_site_consumption_kwh else 0 end) as "2030-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-04' then pc.main_site_consumption_kwh else 0 end) as "2030-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-05' then pc.main_site_consumption_kwh else 0 end) as "2030-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-06' then pc.main_site_consumption_kwh else 0 end) as "2030-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-07' then pc.main_site_consumption_kwh else 0 end) as "2030-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-08' then pc.main_site_consumption_kwh else 0 end) as "2030-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-09' then pc.main_site_consumption_kwh else 0 end) as "2030-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-10' then pc.main_site_consumption_kwh else 0 end) as "2030-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-11' then pc.main_site_consumption_kwh else 0 end) as "2030-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-12' then pc.main_site_consumption_kwh else 0 end) as "2030-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-01' then pc.main_site_consumption_kwh else 0 end) as "2031-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-02' then pc.main_site_consumption_kwh else 0 end) as "2031-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-03' then pc.main_site_consumption_kwh else 0 end) as "2031-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-04' then pc.main_site_consumption_kwh else 0 end) as "2031-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-05' then pc.main_site_consumption_kwh else 0 end) as "2031-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-06' then pc.main_site_consumption_kwh else 0 end) as "2031-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-07' then pc.main_site_consumption_kwh else 0 end) as "2031-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-08' then pc.main_site_consumption_kwh else 0 end) as "2031-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-09' then pc.main_site_consumption_kwh else 0 end) as "2031-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-10' then pc.main_site_consumption_kwh else 0 end) as "2031-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-11' then pc.main_site_consumption_kwh else 0 end) as "2031-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-12' then pc.main_site_consumption_kwh else 0 end) as "2031-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-01' then pc.main_site_consumption_kwh else 0 end) as "2032-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-02' then pc.main_site_consumption_kwh else 0 end) as "2032-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-03' then pc.main_site_consumption_kwh else 0 end) as "2032-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-04' then pc.main_site_consumption_kwh else 0 end) as "2032-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-05' then pc.main_site_consumption_kwh else 0 end) as "2032-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-06' then pc.main_site_consumption_kwh else 0 end) as "2032-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-07' then pc.main_site_consumption_kwh else 0 end) as "2032-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-08' then pc.main_site_consumption_kwh else 0 end) as "2032-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-09' then pc.main_site_consumption_kwh else 0 end) as "2032-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-10' then pc.main_site_consumption_kwh else 0 end) as "2032-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-11' then pc.main_site_consumption_kwh else 0 end) as "2032-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-12' then pc.main_site_consumption_kwh else 0 end) as "2032-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-01' then pc.main_site_consumption_kwh else 0 end) as "2033-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-02' then pc.main_site_consumption_kwh else 0 end) as "2033-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-03' then pc.main_site_consumption_kwh else 0 end) as "2033-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-04' then pc.main_site_consumption_kwh else 0 end) as "2033-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-05' then pc.main_site_consumption_kwh else 0 end) as "2033-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-06' then pc.main_site_consumption_kwh else 0 end) as "2033-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-07' then pc.main_site_consumption_kwh else 0 end) as "2033-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-08' then pc.main_site_consumption_kwh else 0 end) as "2033-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-09' then pc.main_site_consumption_kwh else 0 end) as "2033-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-10' then pc.main_site_consumption_kwh else 0 end) as "2033-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-11' then pc.main_site_consumption_kwh else 0 end) as "2033-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-12' then pc.main_site_consumption_kwh else 0 end) as "2033-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-01' then pc.main_site_consumption_kwh else 0 end) as "2034-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-02' then pc.main_site_consumption_kwh else 0 end) as "2034-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-03' then pc.main_site_consumption_kwh else 0 end) as "2034-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-04' then pc.main_site_consumption_kwh else 0 end) as "2034-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-05' then pc.main_site_consumption_kwh else 0 end) as "2034-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-06' then pc.main_site_consumption_kwh else 0 end) as "2034-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-07' then pc.main_site_consumption_kwh else 0 end) as "2034-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-08' then pc.main_site_consumption_kwh else 0 end) as "2034-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-09' then pc.main_site_consumption_kwh else 0 end) as "2034-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-10' then pc.main_site_consumption_kwh else 0 end) as "2034-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-11' then pc.main_site_consumption_kwh else 0 end) as "2034-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-12' then pc.main_site_consumption_kwh else 0 end) as "2034-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-01' then pc.main_site_consumption_kwh else 0 end) as "2035-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-02' then pc.main_site_consumption_kwh else 0 end) as "2035-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-03' then pc.main_site_consumption_kwh else 0 end) as "2035-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-04' then pc.main_site_consumption_kwh else 0 end) as "2035-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-05' then pc.main_site_consumption_kwh else 0 end) as "2035-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-06' then pc.main_site_consumption_kwh else 0 end) as "2035-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-07' then pc.main_site_consumption_kwh else 0 end) as "2035-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-08' then pc.main_site_consumption_kwh else 0 end) as "2035-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-09' then pc.main_site_consumption_kwh else 0 end) as "2035-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-10' then pc.main_site_consumption_kwh else 0 end) as "2035-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-11' then pc.main_site_consumption_kwh else 0 end) as "2035-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-12' then pc.main_site_consumption_kwh else 0 end) as "2035-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-01' then pc.main_site_consumption_kwh else 0 end) as "2036-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-02' then pc.main_site_consumption_kwh else 0 end) as "2036-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-03' then pc.main_site_consumption_kwh else 0 end) as "2036-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-04' then pc.main_site_consumption_kwh else 0 end) as "2036-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-05' then pc.main_site_consumption_kwh else 0 end) as "2036-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-06' then pc.main_site_consumption_kwh else 0 end) as "2036-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-07' then pc.main_site_consumption_kwh else 0 end) as "2036-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-08' then pc.main_site_consumption_kwh else 0 end) as "2036-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-09' then pc.main_site_consumption_kwh else 0 end) as "2036-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-10' then pc.main_site_consumption_kwh else 0 end) as "2036-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-11' then pc.main_site_consumption_kwh else 0 end) as "2036-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-12' then pc.main_site_consumption_kwh else 0 end) as "2036-12"
		from power_consumption pc
		where consumption_code = _site_code
		group by consumption_code
		union
		select
			2 as summary_id,
			'Energy',
			consumption_code::text as site_code,
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2024-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2025-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2026-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2027-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2028-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2029-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2030-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2031-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2032-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2033-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2034-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2035-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-01' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-02' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-03' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-04' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-05' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-06' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-07' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-08' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-09' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-10' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-11' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-12' then pc.main_site_consumption_kwh * ppc.ppc_kw else 0 end) as "2036-12"
		from power_consumption pc
			left join ppc on ppc.timestamp = pc.timestamp and ppc_code = consumption_code
		where consumption_code = _site_code
		group by consumption_code
		union
		select
			3 as summary_id,
			'Variable Lines (ex GST)',
			_site_code as site_code,
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2024-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2024-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2025-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2025-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2026-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2026-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2027-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2027-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2028-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2028-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2029-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2029-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2030-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2030-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2031-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2031-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2032-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2032-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2033-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2033-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2034-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2034-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2035-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2035-12",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-01' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-01",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-02' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-02",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-03' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-03",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-04' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-04",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-05' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-05",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-06' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-06",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-07' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-07",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-08' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-08",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-09' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-09",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-10' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-10",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-11' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-11",
			sum(case when not _separate_meter and to_char(pc.timestamp, 'YYYY-MM') = '2036-12' then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) as "2036-12"
		from power_consumption pc
			left join solar s on solar_code = _solar_code and pc.timestamp = s.timestamp
			left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
			left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
		where consumption_code = _site_code
		group by consumption_code
		union
		select
			4 as summary_id,
			'Cost (credit) of energy used after Solar generated at main site @ spot',
			_site_code as site_code,
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2024-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2025-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2026-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2027-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2028-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2029-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2030-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2031-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2032-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2033-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2034-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2035-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-01' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-02' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-03' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-04' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-05' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-06' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-07' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-08' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-09' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-10' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-11' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-12' then (pc.main_site_consumption_kwh - (solar_production_kwh * _solar_scale)) * sp.spot_price else 0 end) as "2036-12"
		from power_consumption pc
			left join solar s on solar_code = _solar_code and pc.timestamp = s.timestamp
			left join spot_prices_gen sp on sp.timestamp = pc.timestamp
			left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
			left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
		where consumption_code = _site_code
		group by consumption_code
		union
		select
			5 as summary_id,
			'Revenue from battery discharge - charge @ spot',
			_site_code,
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2024-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2025-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2026-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2027-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2028-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2029-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2030-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2031-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2032-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2033-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2034-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2035-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-01' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-02' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-03' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-04' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-05' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-06' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-07' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-08' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-09' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-10' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-11' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-12' then (battery_discharge_kwh * sp.spot_price) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.spot_price)) else 0 end) as "2036-12"
			from power_consumption pc
				left join spot_prices_gen sp on sp.timestamp = pc.timestamp
				left join tmp_battery_calc bs on bs.timestamp = pc.timestamp
				left join lcc l on l.timestamp = pc.timestamp and lcc_code = _lcc_code
			where consumption_code = _site_code
			group by consumption_code
			union
		select
			6 as summary_id,
			'Average power bill x number clients',
			pc.consumption_code::text as site_code,
			_yearly_bill * _num_houses AS "2024-01",
			0 as "2024-02",
			0 as "2024-03",
			0 as "2024-04",
			0 as "2024-05",
			0 as "2024-06",
			0 as "2024-07",
			0 as "2024-08",
			0 as "2024-09",
			0 as "2024-10",
			0 as "2024-11",
			0 as "2024-12",
			0 as "2025-01",
			0 as "2025-02",
			0 as "2025-03",
			0 as "2025-04",
			0 as "2025-05",
			0 as "2025-06",
			0 as "2025-07",
			0 as "2025-08",
			0 as "2025-09",
			0 as "2025-10",
			0 as "2025-11",
			0 as "2025-12",
			0 as "2026-01",
			0 as "2026-02",
			0 as "2026-03",
			0 as "2026-04",
			0 as "2026-05",
			0 as "2026-06",
			0 as "2026-07",
			0 as "2026-08",
			0 as "2026-09",
			0 as "2026-10",
			0 as "2026-11",
			0 as "2026-12",
			0 as "2027-01",
			0 as "2027-02",
			0 as "2027-03",
			0 as "2027-04",
			0 as "2027-05",
			0 as "2027-06",
			0 as "2027-07",
			0 as "2027-08",
			0 as "2027-09",
			0 as "2027-10",
			0 as "2027-11",
			0 as "2027-12",
			0 as "2028-01",
			0 as "2028-02",
			0 as "2028-03",
			0 as "2028-04",
			0 as "2028-05",
			0 as "2028-06",
			0 as "2028-07",
			0 as "2028-08",
			0 as "2028-09",
			0 as "2028-10",
			0 as "2028-11",
			0 as "2028-12",
			0 as "2029-01",
			0 as "2029-02",
			0 as "2029-03",
			0 as "2029-04",
			0 as "2029-05",
			0 as "2029-06",
			0 as "2029-07",
			0 as "2029-08",
			0 as "2029-09",
			0 as "2029-10",
			0 as "2029-11",
			0 as "2029-12",
			0 as "2030-01",
			0 as "2030-02",
			0 as "2030-03",
			0 as "2030-04",
			0 as "2030-05",
			0 as "2030-06",
			0 as "2030-07",
			0 as "2030-08",
			0 as "2030-09",
			0 as "2030-10",
			0 as "2030-11",
			0 as "2030-12",
			0 as "2031-01",
			0 as "2031-02",
			0 as "2031-03",
			0 as "2031-04",
			0 as "2031-05",
			0 as "2031-06",
			0 as "2031-07",
			0 as "2031-08",
			0 as "2031-09",
			0 as "2031-10",
			0 as "2031-11",
			0 as "2031-12",
			0 as "2032-01",
			0 as "2032-02",
			0 as "2032-03",
			0 as "2032-04",
			0 as "2032-05",
			0 as "2032-06",
			0 as "2032-07",
			0 as "2032-08",
			0 as "2032-09",
			0 as "2032-10",
			0 as "2032-11",
			0 as "2032-12",
			0 as "2033-01",
			0 as "2033-02",
			0 as "2033-03",
			0 as "2033-04",
			0 as "2033-05",
			0 as "2033-06",
			0 as "2033-07",
			0 as "2033-08",
			0 as "2033-09",
			0 as "2033-10",
			0 as "2033-11",
			0 as "2033-12",
			0 as "2034-01",
			0 as "2034-02",
			0 as "2034-03",
			0 as "2034-04",
			0 as "2034-05",
			0 as "2034-06",
			0 as "2034-07",
			0 as "2034-08",
			0 as "2034-09",
			0 as "2034-10",
			0 as "2034-11",
			0 as "2034-12",
			0 as "2035-01",
			0 as "2035-02",
			0 as "2035-03",
			0 as "2035-04",
			0 as "2035-05",
			0 as "2035-06",
			0 as "2035-07",
			0 as "2035-08",
			0 as "2035-09",
			0 as "2035-10",
			0 as "2035-11",
			0 as "2035-12",
			0 as "2036-01",
			0 as "2036-02",
			0 as "2036-03",
			0 as "2036-04",
			0 as "2036-05",
			0 as "2036-06",
			0 as "2036-07",
			0 as "2036-08",
			0 as "2036-09",
			0 as "2036-10",
			0 as "2036-11",
			0 as "2036-12"
		from power_consumption pc
		where pc.consumption_code = _site_code
		group by pc.consumption_code
		union
		select
			7 as summary_id,
			'Cost of energy used houses @ spot',
			_site_code as site_code,
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2024-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2024-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2025-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2025-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2026-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2026-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2027-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2027-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2028-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2028-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2029-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2029-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2030-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2030-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2031-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2031-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2032-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2032-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2033-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2033-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2034-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2034-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2035-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2035-12",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-01' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-01",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-02' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-02",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-03' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-03",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-04' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-04",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-05' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-05",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-06' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-06",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-07' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-07",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-08' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-08",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-09' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-09",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-10' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-10",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-11' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-11",
			sum(case when to_char(pc.timestamp, 'YYYY-MM') = '2036-12' then client_site_consumption * _num_houses * spot_price else 0 end) as "2036-12"
		from power_consumption pc
			left join spot_prices_gen sp on sp.timestamp = pc.timestamp
			left join power_consumption_res pcr on pcr.consumption_code_res = _pcr_code and pc.timestamp = pcr.timestamp
		where consumption_code = _site_code
		group by consumption_code
		union
		select
			8 as summary_id,
			'Lines charges for homes - variable',
			_site_code as site_code,
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2024-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2024-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2025-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2025-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2026-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2026-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2027-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2027-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2028-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2028-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2029-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2029-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2030-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2030-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2031-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2031-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2032-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2032-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2033-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2033-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2034-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2034-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2035-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2035-12",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-01' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-01",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-02' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-02",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-03' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-03",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-04' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-04",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-05' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-05",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-06' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-06",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-07' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-07",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-08' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-08",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-09' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-09",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-10' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-10",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-11' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-11",
			sum(case when to_char(l.timestamp, 'YYYY-MM') = '2036-12' then client_site_consumption * _num_houses * lcr_cost else 0 end) as "2036-12"
		from lcr l
			left join power_consumption_res pcr on pcr.consumption_code_res = _pcr_code and l.timestamp = pcr.timestamp
		where lcr_code = _lcr_code
		group by lcr_code
	) s
	where s.site_code = _site_code
	order by summary_id;
END
$$;


--
-- Name: f_summary_year(text, numeric, numeric, numeric, text, text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_summary_year(_consumption_code text, _num_houses numeric, _solar_scale numeric, _yearly_bill numeric, _solar_code text, _lcc_code text, _lcr_code text, _pcr_code text, _spot_vs_ave_lower numeric, _spot_vs_ave_upper numeric, _charge_max numeric, _discharge_max numeric, _rte numeric, _capacity numeric, _round_trip_pct numeric, _total numeric, _moving_ave_row_count integer, _separate_meter boolean, _ppc_code text) RETURNS TABLE(summary_id numeric, metric text, consumption_code text, "2024" numeric, "2025" numeric, "2026" numeric, "2027" numeric, "2028" numeric, "2029" numeric, "2030" numeric, "2031" numeric, "2032" numeric, "2033" numeric, "2034" numeric, "2035" numeric, "2036" numeric)
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


--
-- Name: f_summary_year(text, numeric, numeric, numeric, text, text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_summary_year(_site_code text, _num_houses numeric, _solar_scale numeric, _yearly_bill numeric, _solar_code text, _lcc_code text, _lcr_code text, _pcr_code text, _spot_vs_ave_lower numeric, _spot_vs_ave_upper numeric, _charge_max numeric, _discharge_max numeric, _rte numeric, _capacity numeric, _round_trip_pct numeric, _total numeric, _moving_ave_row_count integer, _separate_meter boolean, _ppc_code text, _consumption_code text) RETURNS TABLE(summary_id integer, metric text, site_code text, "2024" numeric, "2025" numeric, "2026" numeric, "2027" numeric, "2028" numeric, "2029" numeric, "2030" numeric, "2031" numeric, "2032" numeric, "2033" numeric, "2034" numeric, "2035" numeric, "2036" numeric)
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
			consumption_code::text as site_code,
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then pc.main_site_consumption_kwh else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then pc.main_site_consumption_kwh else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then pc.main_site_consumption_kwh else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then pc.main_site_consumption_kwh else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then pc.main_site_consumption_kwh else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then pc.main_site_consumption_kwh else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then pc.main_site_consumption_kwh else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then pc.main_site_consumption_kwh else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then pc.main_site_consumption_kwh else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then pc.main_site_consumption_kwh else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then pc.main_site_consumption_kwh else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then pc.main_site_consumption_kwh else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then pc.main_site_consumption_kwh else 0 end) AS "2036"
		from power_consumption pc
		where consumption_code = _consumption_code
		group by consumption_code
		union
		select
			2 as summary_id,
			'Energy',
			consumption_code::text as site_code,
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
		where consumption_code = _consumption_code
		group by consumption_code
		union
		select
			3 as summary_id,
			'Variable Lines (ex GST)',
			_site_code as site_code,
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
		where consumption_code = _consumption_code
		group by consumption_code
		union
		select
			3.5 as summary_id,
			'Vairable Lines Main Site',
			_site_code as site_code,
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
		where consumption_code = _consumption_code
		group by consumption_code
		union
		select
			4 as summary_id,
			'Cost of energy used at main site @ spot',
			_site_code as site_code,
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
		where consumption_code = _consumption_code
		group by consumption_code
		union
		select
			5 as summary_id,
			'Credit of Solar generated at main site @ spot',
			_site_code as site_code,
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
		where consumption_code = _consumption_code
		group by consumption_code
		union
		select
			6 as summary_id,
			'Cost (credit) of energy used after Solar generated at main site @ spot',
			_site_code as site_code,
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
		where consumption_code = _consumption_code
		group by consumption_code
		union
		select
	7 as summary_id,
	'Battery charge kwh',
		_site_code,
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
		_site_code,
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
			_site_code,
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
			left join spot_price_jg sp on sp.timestamp = pc.timestamp
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			10 as summary_id,
			'Sum lcc cost',
			_site_code,
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
			_site_code,
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
			_site_code,
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
			_site_code,
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
		group by consumption_code
		union
		select
			14 as summary_id,
			'Revenue from battery discharge - charge @ spot',
			_site_code,
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2024",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2025",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2026",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2027",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2028",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2029",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2030",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2031",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2032",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2033",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2034",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2035",
			sum(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then battery_discharge_kwh * sp.spot_price else 0 end) - (sum(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then battery_charge_kwh * lcc_cost else 0 end) + sum(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then battery_charge_kwh * sp.spot_price else 0 end)) AS "2036"
		from lcc l
			left join spot_price_jg sp on sp.timestamp = l.timestamp
			left join tmp_battery_calc bs on bs.timestamp = l.timestamp
		where lcc_code = _lcc_code
		group by lcc_code
		union
		select
			15 as summary_id,
			'Average power bill x number clients',
			_site_code as site_code,
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
			_site_code as site_code,
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2024",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2025",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2026",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2027",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2028",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2029",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2030",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2031",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2032",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2033",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2034",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2035",
			SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then client_site_consumption * _num_houses * spot_price else 0 end) AS "2036"
		from power_consumption_res pcr
			left join spot_price_jg sp on sp.timestamp = pcr.timestamp
		where pcr.consumption_code_res = _pcr_code
		group by pcr.consumption_code_res
		union
		select
			17 as summary_id,
			'Lines charges for homes - variable',
			_site_code as site_code,
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
	where s.site_code = _site_code
	order by summary_id;
END
$$;


--
-- Name: is_leap_year(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_leap_year(y integer) RETURNS boolean
    LANGUAGE sql STABLE STRICT
    RETURN (date_part('day'::text, (make_date(y, 3, 1) - '1 day'::interval)) = (29)::double precision);


--
-- Name: is_leap_year(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_leap_year(timestamp without time zone) RETURNS boolean
    LANGUAGE sql STABLE STRICT
    RETURN public.is_leap_year((date_part('year'::text, $1))::integer);


--
-- Name: le_rep_summary_year(text, integer, numeric); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.le_rep_summary_year(IN p_site_code text, IN p_num_houses integer, IN p_solar_scale numeric)
    LANGUAGE sql
    AS $$
select * from
(
	select
		1 as summary_id,
		'Net Meter Usage',
		consumption_code as site_code,
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then pc.main_site_consumption_kwh else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then pc.main_site_consumption_kwh else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then pc.main_site_consumption_kwh else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then pc.main_site_consumption_kwh else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then pc.main_site_consumption_kwh else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then pc.main_site_consumption_kwh else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then pc.main_site_consumption_kwh else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then pc.main_site_consumption_kwh else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then pc.main_site_consumption_kwh else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then pc.main_site_consumption_kwh else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then pc.main_site_consumption_kwh else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then pc.main_site_consumption_kwh else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then pc.main_site_consumption_kwh else 0 end) AS "2036"
	from power_consumption pc
	where consumption_code = p_site_code
	group by consumption_code
	union
	select
		2 as summary_id,
		'Energy',
		consumption_code as site_code,
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
		left join ppc on ppc.timestamp = pc.timestamp and ppc_code = consumption_code
	where consumption_code = p_site_code
	group by consumption_code
	union
	select
		3 as summary_id,
		'Variable Lines (ex GST)',
		p_site_code as site_code,
		--		   																					o7						                    t7						u7
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then case when ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) > 0 then ((pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) + battery_charge_kwh - battery_discharge_kwh) * lcc_cost else 0 end else 0 end) AS "2036"
	from power_consumption pc
		left join solar s on solar_code = 'Akl100kwActual_PukeStad_M' and pc.timestamp = s.timestamp -- todo: is solar provided for all years (scale one year for all years?)
		left join battery_scenario_sim bs on battery_code = pc.consumption_code and bs.timestamp = pc.timestamp
		left join lcc l on l.timestamp = pc.timestamp and lcc_code = 'VECTOR'
	where consumption_code = p_site_code
	group by consumption_code
	union
	select
		4 as summary_id,
		'Cost (credit) of energy used after Solar generated at main site @ spot',
		p_site_code as site_code,
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then (pc.main_site_consumption_kwh - (solar_production_kwh * 2.4523)) * sp.price_per_kwh else 0 end) AS "2036"
	from power_consumption pc
		left join solar s on solar_code = 'Akl100kwActual_PukeStad_M' and pc.timestamp = s.timestamp -- todo: is solar provided for all years (scale one year for all years?)
		left join spot_price sp on sp.timestamp = pc.timestamp
		left join battery_scenario_sim bs on battery_code = pc.consumption_code and bs.timestamp = pc.timestamp
		left join lcc l on l.timestamp = pc.timestamp and lcc_code = 'VECTOR'
	where consumption_code = 'YMCA_North'
	group by consumption_code
	union
	select
		5 as summary_id,
		'Revenue from battery discharge - charge @ spot',
		p_site_code,
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then (battery_discharge_kwh) else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then (battery_discharge_kwh * sp.price_per_kwh) - ((battery_charge_kwh * lcc_cost) + (battery_charge_kwh * sp.price_per_kwh)) else 0 end) AS "2036"
	from power_consumption pc
		left join spot_price sp on sp.timestamp = pc.timestamp
		left join battery_scenario_sim bs on battery_code = pc.consumption_code and bs.timestamp = pc.timestamp
		left join lcc l on l.timestamp = pc.timestamp and lcc_code = 'VECTOR'
	where consumption_code = p_site_code
	group by consumption_code
	union
	select
		7 as summary_id,
		'Average power bill x number clients',
		pc.consumption_code as site_code,
		2418 * 301 AS "2024",
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
	from power_consumption pc
		left join scenario sc on pc.consumption_code = sc.site_code
	where pc.consumption_code = p_site_code
	group by pc.consumption_code, sc.number_houses
	union
	select
		8 as summary_id,
		'Cost of energy used houses @ spot',
		p_site_code as site_code,
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2024 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2025 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2026 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2027 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2028 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2029 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2030 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2031 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2032 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2033 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2034 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2035 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM pc.timestamp) = 2036 then client_site_consumption * 301 * price_per_kwh else 0 end) AS "2036"
	from power_consumption pc
		left join spot_price sp on sp.timestamp = pc.timestamp
		left join power_consumption_res pcr on pcr.consumption_code_res = 'Auckland' and pc.timestamp = pcr.timestamp
	where consumption_code = p_site_code
	group by consumption_code
	union
	select
		9 as summary_id,
		'Lines charges for homes - variable',
		p_site_code as site_code,
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2024 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2024",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2025 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2025",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2026 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2026",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2027 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2027",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2028 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2028",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2029 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2029",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2030 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2030",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2031 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2031",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2032 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2032",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2033 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2033",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2034 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2034",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2035 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2035",
		SUM(case when EXTRACT(YEAR FROM l.timestamp) = 2036 then client_site_consumption * 301 * lcr_cost else 0 end) AS "2036"
	from lcr l
		left join power_consumption_res pcr on pcr.consumption_code_res = 'Auckland' and l.timestamp = pcr.timestamp
	where lcr_code = 'VECTOR'
	group by lcr_code
) s
where site_code = p_site_code
order by summary_id
$$;


--
-- Name: populate_year_lcr(text, text, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.populate_year_lcr(IN _from_lcr_code text, IN _to_lcr_code text, IN _from_year integer, IN _to_year integer)
    LANGUAGE sql
    AS $$
 -- todo: if data exists for site_code, then drop
insert into lcr (timestamp, lcr_code, lcr_cost)
select
	(_to_year::text || '-' || to_char(l.timestamp, 'MM') || '-' || to_char(l.timestamp, 'dd'))::timestamp +
		EXTRACT(HOUR FROM l.timestamp) * INTERVAL '1 HOUR' +
		EXTRACT(MINUTE FROM l.timestamp) * INTERVAL '1 MINUTE' +
		EXTRACT(SECOND FROM l.timestamp) * INTERVAL '1 SECOND',
	_to_lcr_code,
	l.lcr_cost
from lcr l
where lcr_code = _from_lcr_code
and EXTRACT(YEAR FROM timestamp) = _from_year
	and (is_leap_year(_to_year) or date_part('day'::text, l.timestamp)::integer <> 29)
$$;


--
-- Name: populate_year_pcr(text, text, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.populate_year_pcr(IN _from_pcr_code text, IN _to_pcr_code text, IN _from_year integer, IN _to_year integer)
    LANGUAGE sql
    AS $$
 -- todo: if data exists for site_code, then drop
insert into power_consumption_res (timestamp, consumption_code_res, client_site_consumption)
select
	(_to_year::text || '-' || to_char(pcr.timestamp, 'MM') || '-' || to_char(pcr.timestamp, 'dd'))::timestamp +
		EXTRACT(HOUR FROM pcr.timestamp) * INTERVAL '1 HOUR' +
		EXTRACT(MINUTE FROM pcr.timestamp) * INTERVAL '1 MINUTE' +
		EXTRACT(SECOND FROM pcr.timestamp) * INTERVAL '1 SECOND',
	_to_pcr_code,
	pcr.client_site_consumption
from power_consumption_res pcr
where consumption_code_res = _from_pcr_code
and EXTRACT(YEAR FROM timestamp) = _from_year
	and (is_leap_year(_to_year) or date_part('day'::text, pcr.timestamp)::integer <> 29)
$$;


--
-- Name: refresh_energy_summary_mv(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_energy_summary_mv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY energy_summary_mv;
  RETURN NULL;
END;
$$;


--
-- Name: refresh_joined_energy_data_mv(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_joined_energy_data_mv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY joined_energy_data_mv;
  RETURN NULL;
END;
$$;


--
-- Name: run_battery_simulation_by_site(integer, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.run_battery_simulation_by_site(p_site_id integer, p_initial_soc_kwh numeric, p_charge_limit_kwh numeric) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_battery_action RECORD;
    v_battery_soc_start_kwh NUMERIC := p_initial_soc_kwh;
    v_battery_rtf_kwh NUMERIC;
    v_battery_charge_kwh NUMERIC;
    v_battery_discharge_kwh NUMERIC := 0;
    v_battery_soc_end_kwh NUMERIC;
BEGIN
    EXECUTE 'DROP TABLE IF EXISTS battery_simulator';

    EXECUTE '
        CREATE TABLE battery_simulator (
            id SERIAL PRIMARY KEY,
            site_id INT,
            timestamp TIMESTAMP,
            battery_soc_start_kwh NUMERIC,
            battery_rtf_kwh NUMERIC,
            battery_charge_kwh NUMERIC,
            battery_discharge_kwh NUMERIC,
            battery_soc_end_kwh NUMERIC
        );
    ';

    FOR v_battery_action IN
        SELECT * FROM battery_action
        WHERE site_id = p_site_id
        ORDER BY timestamp
    LOOP
        v_battery_rtf_kwh := v_battery_action.battery_kwh - v_battery_soc_start_kwh;
        IF v_battery_rtf_kwh < 0 THEN
            v_battery_rtf_kwh := 0;
        END IF;

        IF TRIM(LOWER(v_battery_action.battery_action)) = 'charge' AND v_battery_action.battery_kwh > 0 THEN
            v_battery_charge_kwh := LEAST(p_charge_limit_kwh, v_battery_rtf_kwh);
        ELSE
            v_battery_charge_kwh := 0;
        END IF;

        v_battery_soc_end_kwh := v_battery_soc_start_kwh + v_battery_charge_kwh - v_battery_discharge_kwh;

        INSERT INTO battery_simulator (
            site_id,
            timestamp,
            battery_soc_start_kwh,
            battery_rtf_kwh,
            battery_charge_kwh,
            battery_discharge_kwh,
            battery_soc_end_kwh
        ) VALUES (
            p_site_id,
            v_battery_action.timestamp,
            v_battery_soc_start_kwh,
            v_battery_rtf_kwh,
            v_battery_charge_kwh,
            v_battery_discharge_kwh,
            v_battery_soc_end_kwh
        );

        v_battery_soc_start_kwh := v_battery_soc_end_kwh;
    END LOOP;
END;
$$;


--
-- Name: scale_scenario(character varying, character varying, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.scale_scenario(IN from_site_code character varying, IN to_site_code character varying, IN from_year integer, IN to_year integer)
    LANGUAGE sql
    AS $$ -- todo: if data exists for site_code, then drop
insert into solar (timestamp, solar_code, solar_production_kwh)
select
	(to_year::text || '-' || to_char(so.timestamp, 'MM') || '-' || to_char(so.timestamp, 'dd'))::timestamp +
		EXTRACT(HOUR FROM so.timestamp) * INTERVAL '1 HOUR' +
		EXTRACT(MINUTE FROM so.timestamp) * INTERVAL '1 MINUTE' +
		EXTRACT(SECOND FROM so.timestamp) * INTERVAL '1 SECOND',
	to_site_code,
	so.solar_production_kwh
from scenario sc
	left join solar so on so.solar_code = from_site_code
where EXTRACT(YEAR FROM timestamp) = from_year
	and (is_leap_year(to_year) or date_part('day'::text, so.timestamp)::integer <> 29)
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bat_calc_tmp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bat_calc_tmp (
    row_num bigint,
    "timestamp" timestamp with time zone,
    soc_start numeric,
    capacity_degraded numeric,
    rtf numeric,
    battery_charge_kwh numeric,
    battery_discharge_kwh numeric,
    soc_end numeric,
    spot_price numeric,
    operation text,
    rank_charge bigint,
    rank_discharge bigint,
    bb numeric,
    af numeric,
    ad numeric,
    group_num bigint,
    spot_per_ave numeric,
    moving_ave numeric,
    forward_moving_ave numeric
);


--
-- Name: bat_calc_tmp2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bat_calc_tmp2 (
    row_num bigint,
    "timestamp" timestamp with time zone,
    soc_start numeric,
    capacity_degraded numeric,
    rtf numeric,
    battery_charge_kwh numeric,
    battery_discharge_kwh numeric,
    soc_end numeric,
    spot_price numeric,
    operation text,
    rank_charge bigint,
    rank_discharge bigint,
    bb numeric,
    af numeric,
    ad numeric,
    group_num double precision,
    spot_per_ave numeric
);


--
-- Name: battery_base; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.battery_base (
    "timestamp" timestamp with time zone,
    spot_price numeric,
    forward_moving_average numeric,
    row_num bigint,
    group_num double precision,
    rank_helper numeric,
    moving_ave numeric,
    spot_per_ave numeric,
    capacity_degraded numeric,
    ad numeric,
    rank_max integer,
    operation text,
    rank_charge bigint,
    rank_discharge bigint,
    revenue_discharge numeric,
    bb numeric,
    effective_revenue_discharge numeric
);


--
-- Name: battery_calc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.battery_calc (
    row_num bigint,
    "timestamp" timestamp with time zone,
    soc_start numeric,
    capacity_degraded numeric,
    rtf numeric,
    battery_charge_kwh numeric,
    battery_discharge_kwh numeric,
    soc_end numeric,
    spot_price numeric,
    operation text,
    rank_charge bigint,
    rank_discharge bigint,
    bb numeric,
    af numeric
);


--
-- Name: battery_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.battery_dataset (
    battery_code text NOT NULL,
    description text
);


--
-- Name: battery_scenario_sim; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.battery_scenario_sim (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    battery_code text NOT NULL,
    battery_capacity_now_kwh numeric NOT NULL,
    soc_start_kwh numeric NOT NULL,
    battery_charge_kwh numeric NOT NULL,
    battery_discharge_kwh numeric NOT NULL,
    soc_end_kwh numeric NOT NULL,
    rtf numeric NOT NULL
);


--
-- Name: battery_scenario_sim_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.battery_scenario_sim_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: battery_scenario_sim_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.battery_scenario_sim_id_seq OWNED BY public.battery_scenario_sim.id;


--
-- Name: block_button; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_button (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    type character varying(255) DEFAULT NULL::character varying,
    page uuid,
    post uuid,
    external_url character varying(255) DEFAULT NULL::character varying,
    label character varying(255) DEFAULT NULL::character varying,
    color character varying(255) DEFAULT 'primary'::character varying,
    variant character varying(255) DEFAULT 'solid'::character varying,
    button_group uuid
);


--
-- Name: block_button_group; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_button_group (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    alignment character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_columns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_columns (
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_columns_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_columns_rows (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    block_columns uuid,
    title character varying(255) DEFAULT NULL::character varying,
    headline text,
    image uuid,
    image_position character varying(255) DEFAULT NULL::character varying,
    content text,
    button_group uuid
);


--
-- Name: block_cta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_cta (
    content text,
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    button_group uuid
);


--
-- Name: block_divider; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_divider (
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_faqs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_faqs (
    faqs json,
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    alignment character varying(255) DEFAULT 'center'::character varying
);


--
-- Name: block_form; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_form (
    form uuid,
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_gallery; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_gallery (
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_gallery_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_gallery_files (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    block_gallery_id uuid,
    directus_files_id uuid
);


--
-- Name: block_hero; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_hero (
    content text,
    headline text,
    id uuid NOT NULL,
    image uuid,
    title character varying(255) DEFAULT NULL::character varying,
    image_position character varying(255) DEFAULT NULL::character varying,
    button_group uuid
);


--
-- Name: block_html; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_html (
    id uuid NOT NULL,
    raw_html text DEFAULT 'null'::text
);


--
-- Name: block_logocloud; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_logocloud (
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_logocloud_logos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_logocloud_logos (
    id uuid NOT NULL,
    sort integer,
    block_logocloud_id uuid,
    directus_files_id uuid
);


--
-- Name: block_quote; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_quote (
    content text,
    id uuid NOT NULL,
    subtitle character varying(255) DEFAULT NULL::character varying,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_richtext; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_richtext (
    content text,
    headline character varying(255) DEFAULT NULL::character varying,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    alignment character varying(255) DEFAULT 'center'::character varying
);


--
-- Name: block_step_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_step_items (
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    image uuid,
    content text,
    block_steps uuid,
    sort integer,
    button_group uuid
);


--
-- Name: block_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_steps (
    alternate_image_position boolean DEFAULT false NOT NULL,
    headline text,
    id uuid NOT NULL,
    show_step_numbers boolean DEFAULT true,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_team; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_team (
    content text,
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_testimonial_slider_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_testimonial_slider_items (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    block_testimonial_slider_id uuid,
    testimonials_id uuid
);


--
-- Name: block_testimonials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_testimonials (
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: block_video; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.block_video (
    headline text,
    id uuid NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    type character varying(255) DEFAULT NULL::character varying,
    video_file uuid,
    video_url character varying(255) DEFAULT NULL::character varying
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    color character varying(255) DEFAULT NULL::character varying,
    headline text,
    id uuid NOT NULL,
    seo uuid,
    slug character varying(255) DEFAULT NULL::character varying,
    sort integer,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: consumption_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consumption_dataset (
    consumption_code text NOT NULL,
    description text
);


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    first_name character varying(255) DEFAULT NULL::character varying,
    last_name character varying(255) DEFAULT NULL::character varying,
    "user" uuid,
    email character varying(255) DEFAULT NULL::character varying,
    phone character varying(255) DEFAULT NULL::character varying,
    job_title character varying(255) DEFAULT NULL::character varying,
    contact_notes text
);


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    visitor_id character varying(36) DEFAULT NULL::character varying,
    item character varying(255) DEFAULT NULL::character varying,
    collection character varying(255) DEFAULT NULL::character varying,
    user_created uuid,
    user_updated uuid,
    organization uuid
);


--
-- Name: directus_access; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_access (
    id uuid NOT NULL,
    role uuid,
    "user" uuid,
    policy uuid NOT NULL,
    sort integer
);


--
-- Name: directus_activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_activity (
    id integer NOT NULL,
    action character varying(45) NOT NULL,
    "user" uuid,
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ip character varying(50),
    user_agent text,
    collection character varying(64) NOT NULL,
    item character varying(255) NOT NULL,
    origin character varying(255)
);


--
-- Name: directus_activity_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_activity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_activity_id_seq OWNED BY public.directus_activity.id;


--
-- Name: directus_collections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_collections (
    collection character varying(64) NOT NULL,
    icon character varying(64),
    note text,
    display_template character varying(255),
    hidden boolean DEFAULT false NOT NULL,
    singleton boolean DEFAULT false NOT NULL,
    translations json,
    archive_field character varying(64),
    archive_app_filter boolean DEFAULT true NOT NULL,
    archive_value character varying(255),
    unarchive_value character varying(255),
    sort_field character varying(64),
    accountability character varying(255) DEFAULT 'all'::character varying,
    color character varying(255),
    item_duplication_fields json,
    sort integer,
    "group" character varying(64),
    collapse character varying(255) DEFAULT 'open'::character varying NOT NULL,
    preview_url character varying(255),
    versioning boolean DEFAULT false NOT NULL
);


--
-- Name: directus_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_comments (
    id uuid NOT NULL,
    collection character varying(64) NOT NULL,
    item character varying(255) NOT NULL,
    comment text NOT NULL,
    date_created timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    date_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    user_created uuid,
    user_updated uuid
);


--
-- Name: directus_dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_dashboards (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    icon character varying(64) DEFAULT 'dashboard'::character varying NOT NULL,
    note text,
    date_created timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    user_created uuid,
    color character varying(255)
);


--
-- Name: directus_extensions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_extensions (
    enabled boolean DEFAULT true NOT NULL,
    id uuid NOT NULL,
    folder character varying(255) NOT NULL,
    source character varying(255) NOT NULL,
    bundle uuid
);


--
-- Name: directus_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_fields (
    id integer NOT NULL,
    collection character varying(64) NOT NULL,
    field character varying(64) NOT NULL,
    special character varying(64),
    interface character varying(64),
    options json,
    display character varying(64),
    display_options json,
    readonly boolean DEFAULT false NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    sort integer,
    width character varying(30) DEFAULT 'full'::character varying,
    translations json,
    note text,
    conditions json,
    required boolean DEFAULT false,
    "group" character varying(64),
    validation json,
    validation_message text
);


--
-- Name: directus_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_fields_id_seq OWNED BY public.directus_fields.id;


--
-- Name: directus_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_files (
    id uuid NOT NULL,
    storage character varying(255) NOT NULL,
    filename_disk character varying(255),
    filename_download character varying(255) NOT NULL,
    title character varying(255),
    type character varying(255),
    folder uuid,
    uploaded_by uuid,
    created_on timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_by uuid,
    modified_on timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    charset character varying(50),
    filesize bigint,
    width integer,
    height integer,
    duration integer,
    embed character varying(200),
    description text,
    location text,
    tags text,
    metadata json,
    focal_point_x integer,
    focal_point_y integer,
    tus_id character varying(64),
    tus_data json,
    uploaded_on timestamp with time zone
);


--
-- Name: directus_flows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_flows (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    icon character varying(64),
    color character varying(255),
    description text,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    trigger character varying(255),
    accountability character varying(255) DEFAULT 'all'::character varying,
    options json,
    operation uuid,
    date_created timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    user_created uuid
);


--
-- Name: directus_folders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_folders (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    parent uuid
);


--
-- Name: directus_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_migrations (
    version character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: directus_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_notifications (
    id integer NOT NULL,
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(255) DEFAULT 'inbox'::character varying,
    recipient uuid NOT NULL,
    sender uuid,
    subject character varying(255) NOT NULL,
    message text,
    collection character varying(64),
    item character varying(255)
);


--
-- Name: directus_notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_notifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_notifications_id_seq OWNED BY public.directus_notifications.id;


--
-- Name: directus_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_operations (
    id uuid NOT NULL,
    name character varying(255),
    key character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    position_x integer NOT NULL,
    position_y integer NOT NULL,
    options json,
    resolve uuid,
    reject uuid,
    flow uuid NOT NULL,
    date_created timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    user_created uuid
);


--
-- Name: directus_panels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_panels (
    id uuid NOT NULL,
    dashboard uuid NOT NULL,
    name character varying(255),
    icon character varying(64) DEFAULT NULL::character varying,
    color character varying(10),
    show_header boolean DEFAULT false NOT NULL,
    note text,
    type character varying(255) NOT NULL,
    position_x integer NOT NULL,
    position_y integer NOT NULL,
    width integer NOT NULL,
    height integer NOT NULL,
    options json,
    date_created timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    user_created uuid
);


--
-- Name: directus_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_permissions (
    id integer NOT NULL,
    collection character varying(64) NOT NULL,
    action character varying(10) NOT NULL,
    permissions json,
    validation json,
    presets json,
    fields text,
    policy uuid NOT NULL
);


--
-- Name: directus_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_permissions_id_seq OWNED BY public.directus_permissions.id;


--
-- Name: directus_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_policies (
    id uuid NOT NULL,
    name character varying(100) NOT NULL,
    icon character varying(64) DEFAULT 'badge'::character varying NOT NULL,
    description text,
    ip_access text,
    enforce_tfa boolean DEFAULT false NOT NULL,
    admin_access boolean DEFAULT false NOT NULL,
    app_access boolean DEFAULT false NOT NULL
);


--
-- Name: directus_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_presets (
    id integer NOT NULL,
    bookmark character varying(255),
    "user" uuid,
    role uuid,
    collection character varying(64),
    search character varying(100),
    layout character varying(100) DEFAULT 'tabular'::character varying,
    layout_query json,
    layout_options json,
    refresh_interval integer,
    filter json,
    icon character varying(64) DEFAULT 'bookmark'::character varying,
    color character varying(255)
);


--
-- Name: directus_presets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_presets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_presets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_presets_id_seq OWNED BY public.directus_presets.id;


--
-- Name: directus_relations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_relations (
    id integer NOT NULL,
    many_collection character varying(64) NOT NULL,
    many_field character varying(64) NOT NULL,
    one_collection character varying(64),
    one_field character varying(64),
    one_collection_field character varying(64),
    one_allowed_collections text,
    junction_field character varying(64),
    sort_field character varying(64),
    one_deselect_action character varying(255) DEFAULT 'nullify'::character varying NOT NULL
);


--
-- Name: directus_relations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_relations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_relations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_relations_id_seq OWNED BY public.directus_relations.id;


--
-- Name: directus_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_revisions (
    id integer NOT NULL,
    activity integer NOT NULL,
    collection character varying(64) NOT NULL,
    item character varying(255) NOT NULL,
    data json,
    delta json,
    parent integer,
    version uuid
);


--
-- Name: directus_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_revisions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_revisions_id_seq OWNED BY public.directus_revisions.id;


--
-- Name: directus_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_roles (
    id uuid NOT NULL,
    name character varying(100) NOT NULL,
    icon character varying(64) DEFAULT 'supervised_user_circle'::character varying NOT NULL,
    description text,
    parent uuid
);


--
-- Name: directus_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_sessions (
    token character varying(64) NOT NULL,
    "user" uuid,
    expires timestamp with time zone NOT NULL,
    ip character varying(255),
    user_agent text,
    share uuid,
    origin character varying(255),
    next_token character varying(64)
);


--
-- Name: directus_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_settings (
    id integer NOT NULL,
    project_name character varying(100) DEFAULT 'Directus'::character varying NOT NULL,
    project_url character varying(255),
    project_color character varying(255) DEFAULT '#6644FF'::character varying NOT NULL,
    project_logo uuid,
    public_foreground uuid,
    public_background uuid,
    public_note text,
    auth_login_attempts integer DEFAULT 25,
    auth_password_policy character varying(100),
    storage_asset_transform character varying(7) DEFAULT 'all'::character varying,
    storage_asset_presets json,
    custom_css text,
    storage_default_folder uuid,
    basemaps json,
    mapbox_key character varying(255),
    module_bar json,
    project_descriptor character varying(100),
    default_language character varying(255) DEFAULT 'en-US'::character varying NOT NULL,
    custom_aspect_ratios json,
    public_favicon uuid,
    default_appearance character varying(255) DEFAULT 'auto'::character varying NOT NULL,
    default_theme_light character varying(255),
    theme_light_overrides json,
    default_theme_dark character varying(255),
    theme_dark_overrides json,
    report_error_url character varying(255),
    report_bug_url character varying(255),
    report_feature_url character varying(255),
    public_registration boolean DEFAULT false NOT NULL,
    public_registration_verify_email boolean DEFAULT true NOT NULL,
    public_registration_role uuid,
    public_registration_email_filter json,
    visual_editor_urls json,
    accepted_terms boolean DEFAULT false,
    project_id uuid
);


--
-- Name: directus_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_settings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_settings_id_seq OWNED BY public.directus_settings.id;


--
-- Name: directus_shares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_shares (
    id uuid NOT NULL,
    name character varying(255),
    collection character varying(64) NOT NULL,
    item character varying(255) NOT NULL,
    role uuid,
    password character varying(255),
    user_created uuid,
    date_created timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    date_start timestamp with time zone,
    date_end timestamp with time zone,
    times_used integer DEFAULT 0,
    max_uses integer
);


--
-- Name: directus_translations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_translations (
    id uuid NOT NULL,
    language character varying(255) NOT NULL,
    key character varying(255) NOT NULL,
    value text NOT NULL
);


--
-- Name: directus_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_users (
    id uuid NOT NULL,
    first_name character varying(50),
    last_name character varying(50),
    email character varying(128),
    password character varying(255),
    location character varying(255),
    title character varying(50),
    description text,
    tags json,
    avatar uuid,
    language character varying(255) DEFAULT NULL::character varying,
    tfa_secret character varying(255),
    status character varying(16) DEFAULT 'active'::character varying NOT NULL,
    role uuid,
    token character varying(255),
    last_access timestamp with time zone,
    last_page character varying(255),
    provider character varying(128) DEFAULT 'default'::character varying NOT NULL,
    external_identifier character varying(255),
    auth_data json,
    email_notifications boolean DEFAULT true,
    appearance character varying(255),
    theme_dark character varying(255),
    theme_light character varying(255),
    theme_light_overrides json,
    theme_dark_overrides json
);


--
-- Name: directus_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_versions (
    id uuid NOT NULL,
    key character varying(64) NOT NULL,
    name character varying(255),
    collection character varying(64) NOT NULL,
    item character varying(255) NOT NULL,
    hash character varying(255),
    date_created timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    date_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    user_created uuid,
    user_updated uuid,
    delta json
);


--
-- Name: directus_webhooks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.directus_webhooks (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    method character varying(10) DEFAULT 'POST'::character varying NOT NULL,
    url character varying(255) NOT NULL,
    status character varying(10) DEFAULT 'active'::character varying NOT NULL,
    data boolean DEFAULT true NOT NULL,
    actions character varying(100) NOT NULL,
    collections character varying(255) NOT NULL,
    headers json,
    was_active_before_deprecation boolean DEFAULT false NOT NULL,
    migrated_flow uuid
);


--
-- Name: directus_webhooks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.directus_webhooks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: directus_webhooks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.directus_webhooks_id_seq OWNED BY public.directus_webhooks.id;


--
-- Name: spot_price_jg_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.spot_price_jg_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: discharge_amount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.discharge_amount (
    id bigint DEFAULT nextval('public.spot_price_jg_id_seq'::regclass) NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    ad numeric NOT NULL
);


--
-- Name: forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forms (
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id uuid NOT NULL,
    key character varying(255) DEFAULT NULL::character varying,
    on_success character varying(255) DEFAULT NULL::character varying,
    redirect_url character varying(255) DEFAULT NULL::character varying,
    schema json,
    sort integer,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    submit_label character varying(255) DEFAULT NULL::character varying,
    success_message text,
    title character varying(255) DEFAULT NULL::character varying,
    user_created uuid,
    user_updated uuid
);


--
-- Name: globals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.globals (
    address_country character varying(255) DEFAULT NULL::character varying,
    address_locality character varying(255) DEFAULT NULL::character varying,
    address_region character varying(255) DEFAULT NULL::character varying,
    build_hook_url character varying(255) DEFAULT NULL::character varying,
    description text,
    email character varying(255) DEFAULT NULL::character varying,
    id uuid NOT NULL,
    og_image uuid,
    phone character varying(255) DEFAULT NULL::character varying,
    postal_code character varying(255) DEFAULT NULL::character varying,
    social_links json DEFAULT '[]'::json,
    street_address character varying(255) DEFAULT NULL::character varying,
    tagline character varying(255) DEFAULT NULL::character varying,
    title character varying(255) DEFAULT NULL::character varying,
    url character varying(255) DEFAULT NULL::character varying,
    logo_on_dark_bg uuid,
    logo_on_light_bg uuid,
    theme json
);


--
-- Name: help_articles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.help_articles (
    content text,
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    help_collection uuid,
    id uuid NOT NULL,
    owner uuid,
    slug character varying(255) DEFAULT NULL::character varying,
    sort integer,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    summary text,
    title character varying(255) DEFAULT NULL::character varying,
    user_created uuid,
    user_updated uuid
);


--
-- Name: help_collections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.help_collections (
    description text,
    icon character varying(255) DEFAULT NULL::character varying,
    id uuid NOT NULL,
    slug character varying(255) DEFAULT NULL::character varying,
    sort integer,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: help_feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.help_feedback (
    comments text,
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id uuid NOT NULL,
    rating integer,
    title character varying(255) DEFAULT NULL::character varying,
    url character varying(255) DEFAULT NULL::character varying,
    user_created uuid,
    user_updated uuid,
    visitor_id character varying(36) DEFAULT NULL::character varying
);


--
-- Name: inbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbox (
    data json DEFAULT '{}'::json,
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    form uuid,
    id uuid NOT NULL,
    sort integer,
    status character varying(255) DEFAULT 'new'::character varying,
    user_created uuid,
    user_updated uuid,
    project uuid,
    task uuid
);


--
-- Name: lcc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lcc (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    lcc_code character varying NOT NULL,
    lcc_cost numeric NOT NULL
);


--
-- Name: lcc_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lcc_dataset (
    lcc_code text NOT NULL,
    description text
);


--
-- Name: lcc_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lcc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lcc_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lcc_id_seq OWNED BY public.lcc.id;


--
-- Name: lcr; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lcr (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    lcr_code character varying NOT NULL,
    lcr_cost numeric NOT NULL
);


--
-- Name: lcr_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lcr_dataset (
    lcr_code text NOT NULL,
    description text
);


--
-- Name: lcr_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lcr_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lcr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lcr_id_seq OWNED BY public.lcr.id;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    conversation uuid,
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id uuid NOT NULL,
    text text,
    user_created uuid,
    user_updated uuid,
    visitor_id character varying(36) DEFAULT NULL::character varying,
    contact_id character varying(36) DEFAULT NULL::character varying
);


--
-- Name: navigation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.navigation (
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id character varying(255) DEFAULT NULL::character varying NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    user_created uuid,
    user_updated uuid
);


--
-- Name: navigation_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.navigation_items (
    has_children boolean DEFAULT false,
    icon character varying(255) DEFAULT NULL::character varying,
    id uuid NOT NULL,
    label text,
    navigation character varying(255) DEFAULT NULL::character varying,
    open_in_new_tab boolean DEFAULT false,
    page uuid,
    parent uuid,
    sort integer,
    title character varying(255) DEFAULT NULL::character varying,
    type character varying(255) DEFAULT NULL::character varying,
    url character varying(255) DEFAULT NULL::character varying
);


--
-- Name: organization_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_addresses (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    organization uuid,
    name character varying(255) DEFAULT NULL::character varying,
    street_address character varying(255) DEFAULT NULL::character varying,
    postal_code character varying(255) DEFAULT NULL::character varying,
    address_region character varying(255) DEFAULT NULL::character varying,
    address_country character varying(255) DEFAULT 'US'::character varying,
    address_locality character varying(255) DEFAULT NULL::character varying,
    is_primary_billing boolean DEFAULT false
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    website character varying(255) DEFAULT NULL::character varying,
    logo uuid,
    brand_color character varying(255) DEFAULT NULL::character varying,
    organization_notes text,
    email character varying(255) DEFAULT NULL::character varying,
    payment_terms uuid,
    owner uuid,
    phone character varying(255) DEFAULT NULL::character varying,
    folder uuid,
    stripe_customer_id character varying(255) DEFAULT NULL::character varying
);


--
-- Name: organizations_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations_contacts (
    id uuid NOT NULL,
    contacts_id uuid,
    organizations_id uuid,
    sort integer
);


--
-- Name: os_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_activities (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    deal uuid,
    activity_type character varying(255) DEFAULT NULL::character varying,
    activity_notes text,
    name character varying(255) DEFAULT NULL::character varying,
    organization uuid,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    due_date timestamp with time zone,
    assigned_to uuid
);


--
-- Name: os_activity_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_activity_contacts (
    id uuid NOT NULL,
    os_activities_id uuid,
    contacts_id uuid
);


--
-- Name: os_deal_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_deal_contacts (
    id uuid NOT NULL,
    "primary" boolean,
    os_deals_id uuid,
    contacts_id uuid,
    sort integer
);


--
-- Name: os_deal_stages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_deal_stages (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    color character varying(255) DEFAULT NULL::character varying
);


--
-- Name: os_deals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_deals (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    owner uuid,
    organization uuid,
    close_date date,
    deal_stage uuid,
    next_contact_date timestamp without time zone,
    deal_value integer,
    deal_notes text
);


--
-- Name: os_email_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_email_templates (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    subject character varying(255) DEFAULT NULL::character varying,
    body text,
    name character varying(255) DEFAULT NULL::character varying
);


--
-- Name: os_expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_expenses (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    category character varying(255) DEFAULT NULL::character varying,
    name character varying(255) DEFAULT NULL::character varying,
    cost numeric(10,2) DEFAULT NULL::numeric,
    description text,
    date timestamp with time zone,
    file uuid,
    project uuid,
    is_billable boolean DEFAULT false,
    invoice_item uuid,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    is_reimbursable boolean DEFAULT false,
    user_submitted uuid
);


--
-- Name: os_invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_invoice_items (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    invoice uuid,
    line_item_number integer,
    description text,
    tax_rate uuid,
    tax_amount numeric(10,2) DEFAULT NULL::numeric,
    unit_price numeric(10,2) DEFAULT NULL::numeric,
    quantity numeric(10,2) DEFAULT NULL::numeric,
    line_amount numeric(10,2) DEFAULT NULL::numeric,
    billable_expense uuid,
    item uuid,
    type character varying(255) DEFAULT 'item'::character varying,
    item_name character varying(255) DEFAULT NULL::character varying,
    override_unit_price boolean DEFAULT false
);


--
-- Name: os_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_invoices (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    invoice_number character varying(255) DEFAULT NULL::character varying,
    due_date timestamp with time zone,
    reference character varying(255) DEFAULT NULL::character varying,
    organization uuid,
    contact uuid,
    issue_date timestamp with time zone,
    project uuid,
    subtotal numeric(10,5) DEFAULT NULL::numeric,
    total_tax numeric(10,5) DEFAULT NULL::numeric,
    total numeric(10,5) DEFAULT NULL::numeric,
    amount_paid numeric(10,5) DEFAULT NULL::numeric,
    amount_due numeric(10,5) DEFAULT NULL::numeric
);


--
-- Name: os_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_items (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    description text,
    unit_price numeric(10,2) DEFAULT NULL::numeric,
    default_tax_rate uuid,
    icon character varying(255) DEFAULT NULL::character varying,
    unit_cost numeric(10,2) DEFAULT NULL::numeric
);


--
-- Name: os_payment_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_payment_terms (
    id uuid NOT NULL,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying
);


--
-- Name: os_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_payments (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    payment_date timestamp with time zone,
    amount numeric(10,2) DEFAULT NULL::numeric,
    stripe_payment_id character varying(255) DEFAULT NULL::character varying,
    organization uuid,
    contact uuid,
    invoice uuid,
    metadata json,
    payment_method_type character varying(255) DEFAULT NULL::character varying,
    receipt_url character varying(255) DEFAULT NULL::character varying
);


--
-- Name: os_project_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_project_contacts (
    id uuid NOT NULL,
    os_projects_id uuid,
    contacts_id uuid,
    sort integer
);


--
-- Name: os_project_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_project_templates (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    tasks json,
    description text
);


--
-- Name: os_project_updates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_project_updates (
    id uuid NOT NULL,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    project uuid,
    message text
);


--
-- Name: os_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_projects (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'new'::character varying,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    organization uuid,
    description text,
    owner uuid,
    start_date timestamp with time zone,
    due_date timestamp without time zone
);


--
-- Name: os_proposal_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_proposal_approvals (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    signature_text character varying(255) DEFAULT NULL::character varying,
    signature_image uuid,
    signature_type character varying(255) DEFAULT NULL::character varying,
    first_name character varying(255) DEFAULT NULL::character varying,
    last_name character varying(255) DEFAULT NULL::character varying,
    organization character varying(255) DEFAULT NULL::character varying,
    proposal uuid,
    email character varying(255) DEFAULT NULL::character varying,
    metadata json,
    ip_address character varying(255) DEFAULT NULL::character varying,
    esignature_agreement boolean DEFAULT false,
    contact uuid
);


--
-- Name: os_proposal_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_proposal_blocks (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    os_proposals_id uuid,
    item character varying(255) DEFAULT NULL::character varying,
    collection character varying(255) DEFAULT NULL::character varying
);


--
-- Name: os_proposal_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_proposal_contacts (
    id uuid NOT NULL,
    os_proposals_id uuid,
    contacts_id uuid,
    sort integer
);


--
-- Name: os_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_proposals (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    organization uuid,
    deal uuid,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    expiration_date timestamp with time zone
);


--
-- Name: os_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_settings (
    id uuid NOT NULL,
    next_invoice_number integer,
    next_proposal_number integer,
    organization_folder_root uuid
);


--
-- Name: os_task_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_task_files (
    id uuid NOT NULL,
    os_tasks_id uuid,
    directus_files_id uuid,
    sort integer
);


--
-- Name: os_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_tasks (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    project uuid,
    name character varying(255) DEFAULT NULL::character varying,
    description text,
    assigned_to uuid,
    due_date timestamp with time zone,
    is_visible_to_client boolean DEFAULT false NOT NULL,
    type character varying(255) DEFAULT 'tasks'::character varying NOT NULL,
    date_completed timestamp with time zone,
    responsibility character varying(255) DEFAULT NULL::character varying,
    start_date timestamp with time zone,
    embed_url character varying(255) DEFAULT NULL::character varying,
    form uuid
);


--
-- Name: os_tax_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_tax_rates (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    name character varying(255) DEFAULT NULL::character varying,
    rate numeric(10,5) DEFAULT NULL::numeric
);


--
-- Name: page_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.page_blocks (
    id uuid NOT NULL,
    sort integer,
    user_created uuid,
    date_created timestamp with time zone,
    user_updated uuid,
    date_updated timestamp with time zone,
    pages_id uuid,
    item character varying(255) DEFAULT NULL::character varying,
    collection character varying(255) DEFAULT NULL::character varying,
    hide_block boolean DEFAULT false
);


--
-- Name: pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pages (
    date_created timestamp without time zone,
    date_updated timestamp without time zone,
    id uuid NOT NULL,
    seo uuid,
    sort integer,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    title character varying(255) DEFAULT NULL::character varying,
    user_created character varying(36) DEFAULT NULL::character varying,
    user_updated character varying(36) DEFAULT NULL::character varying,
    permalink character varying(255) DEFAULT NULL::character varying
);


--
-- Name: pages_blog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pages_blog (
    featured_post uuid,
    headline text,
    id uuid NOT NULL,
    seo uuid,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: pages_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pages_projects (
    headline text,
    id uuid NOT NULL,
    seo uuid,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: pcr_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcr_dataset (
    pcr_code text NOT NULL,
    description text
);


--
-- Name: post_gallery_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_gallery_items (
    id uuid NOT NULL,
    posts_id uuid,
    directus_files_id uuid,
    sort integer
);


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    category uuid,
    content text,
    date_created timestamp without time zone,
    date_published timestamp without time zone,
    date_updated timestamp without time zone,
    id uuid NOT NULL,
    image uuid,
    seo uuid,
    slug character varying(255) DEFAULT NULL::character varying,
    sort integer,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    summary text,
    title character varying(255) DEFAULT NULL::character varying,
    user_created character varying(36) DEFAULT NULL::character varying,
    user_updated character varying(36) DEFAULT NULL::character varying,
    author uuid,
    client character varying(255) DEFAULT NULL::character varying,
    cost character varying(255) DEFAULT NULL::character varying,
    built_with json,
    type character varying(255) DEFAULT 'blog'::character varying,
    video_url character varying(255) DEFAULT NULL::character varying
);


--
-- Name: power_consumption; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.power_consumption (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    main_site_consumption_kwh numeric(14,9) NOT NULL,
    consumption_code text NOT NULL
);


--
-- Name: power_consumption_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.power_consumption_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: power_consumption_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.power_consumption_id_seq OWNED BY public.power_consumption.id;


--
-- Name: power_consumption_res; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.power_consumption_res (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    consumption_code_res text NOT NULL,
    client_site_consumption numeric NOT NULL
);


--
-- Name: power_consumption_res_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.power_consumption_res_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: power_consumption_res_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.power_consumption_res_id_seq OWNED BY public.power_consumption_res.id;


--
-- Name: ppc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ppc (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    ppc_code character varying(255) DEFAULT NULL::character varying,
    ppc_kw numeric NOT NULL
);


--
-- Name: ppc_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ppc_dataset (
    ppc_code text NOT NULL,
    description text
);


--
-- Name: ppc_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ppc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ppc_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ppc_id_seq OWNED BY public.ppc.id;


--
-- Name: redirects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.redirects (
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id uuid NOT NULL,
    response_code integer,
    url_new character varying(255) DEFAULT NULL::character varying,
    url_old character varying(255) DEFAULT NULL::character varying,
    user_created uuid,
    user_updated uuid
);


--
-- Name: scenario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scenario (
    id integer NOT NULL,
    scenario_code character varying(50) NOT NULL,
    spot_code text NOT NULL,
    consumption_code text,
    consumption_scale character varying(50),
    solar_code text NOT NULL,
    solar_scale numeric(10,2),
    scenario_preferred boolean,
    solar_capacity_kw numeric,
    solar_production_yr_kwh numeric,
    lcc_code text,
    lcr_code text,
    pcr_code text,
    inverter_max_charge_kw numeric,
    inverter_max_discharge_kw numeric,
    battery_initial_capacity_kwh numeric,
    battery_usable_capacity_kwh numeric,
    connection_import_capacity_kw numeric,
    connection_export_capacity_kw numeric,
    created_at timestamp with time zone DEFAULT '2025-08-09 10:33:49.360087+00'::timestamp with time zone NOT NULL,
    updated_at timestamp with time zone DEFAULT '2025-08-09 10:33:49.360087+00'::timestamp with time zone NOT NULL,
    ppc_code text,
    yearly_bill real,
    site integer,
    cost_equipment_solar numeric(10,5),
    cost_equipment_battery numeric(10,5),
    cost_equipment_sb numeric(10,5),
    cost_install_solar numeric(10,5),
    cost_install_battery numeric(10,5),
    cost_install_sb numeric(10,0) DEFAULT NULL::numeric,
    rte numeric(5,3),
    spot_vs_ave_lower numeric(10,3) DEFAULT 0.9,
    spot_vs_ave_upper numeric(10,3) DEFAULT 1.1,
    round_trip_pct numeric(5,3) DEFAULT 0.85,
    total numeric(30,4) DEFAULT '144000'::numeric,
    moving_ave_row_count integer DEFAULT 24,
    separate_meter boolean DEFAULT false,
    battery_cycle numeric,
    battery_percentage_cycle_max numeric,
    num_houses integer,
    solar_total_costs numeric(10,5) DEFAULT NULL::numeric,
    battery_total_costs numeric(10,5) DEFAULT NULL::numeric,
    solar_battery_installation_total_costs numeric(10,5) DEFAULT NULL::numeric
);


--
-- Name: COLUMN scenario.rte; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.scenario.rte IS 'This is the Round Trip Efficiency.';


--
-- Name: COLUMN scenario.num_houses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.scenario.num_houses IS 'This is the total number of houses for the site. NB This might be changed to the number_clients. ';


--
-- Name: scenario_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.scenario_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scenario_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.scenario_id_seq OWNED BY public.scenario.id;


--
-- Name: seo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seo (
    canonical_url character varying(255) DEFAULT NULL::character varying,
    id uuid NOT NULL,
    meta_description text,
    no_follow boolean DEFAULT false,
    no_index boolean DEFAULT false,
    sitemap_change_frequency character varying(255) DEFAULT 'hourly'::character varying,
    sitemap_priority real DEFAULT '0.5'::real,
    title character varying(255) DEFAULT NULL::character varying
);


--
-- Name: site; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.site (
    id integer NOT NULL,
    site_code character varying(50) NOT NULL,
    site_name character varying(50) NOT NULL,
    site_address character varying(50) NOT NULL,
    "Status" json,
    next_action character varying(255),
    "Process_checklist" json,
    "Priority" character varying(255),
    "Self_consumption" character varying(255),
    "Possible_EVs" character varying(255),
    "ICP_information" text,
    "Building_Owner" character varying(255),
    odoo_link character varying(255) DEFAULT NULL::character varying,
    "Date" date
);


--
-- Name: site_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.site_dataset (
    site_code text NOT NULL,
    description text
);


--
-- Name: site_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.site_files (
    id integer NOT NULL,
    site_id integer,
    directus_files_id uuid
);


--
-- Name: site_files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.site_files_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: site_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.site_files_id_seq OWNED BY public.site_files.id;


--
-- Name: site_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.site_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: site_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.site_id_seq OWNED BY public.site.id;


--
-- Name: solar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solar (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    solar_code character varying NOT NULL,
    solar_production_kwh numeric NOT NULL
);


--
-- Name: solar_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solar_dataset (
    solar_code text NOT NULL,
    description text,
    annual_production bigint
);


--
-- Name: solar_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solar_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solar_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solar_id_seq OWNED BY public.solar.id;


--
-- Name: spot_dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spot_dataset (
    spot_code text NOT NULL,
    description text
);


--
-- Name: spot_price_jg; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spot_price_jg (
    id bigint DEFAULT nextval('public.spot_price_jg_id_seq'::regclass) NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    spot_price numeric NOT NULL
);


--
-- Name: spot_prices_gen; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spot_prices_gen (
    id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    spot_code character varying NOT NULL,
    spot_price numeric NOT NULL,
    avg_spot_price_midnight_to_midday numeric(10,6) NOT NULL,
    avg_spot_price_midday_to_midnight numeric NOT NULL,
    action_flag character varying NOT NULL,
    charge_rank integer NOT NULL,
    discharge_rank integer NOT NULL
);


--
-- Name: spot_prices_gen_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.spot_prices_gen_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: spot_prices_gen_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.spot_prices_gen_id_seq OWNED BY public.spot_prices_gen.id;


--
-- Name: team; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team (
    bio text,
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id uuid NOT NULL,
    image uuid,
    job_title character varying(255) DEFAULT NULL::character varying,
    name character varying(255) DEFAULT NULL::character varying,
    social_media json,
    sort integer,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    user_created uuid,
    user_updated uuid
);


--
-- Name: testimonials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.testimonials (
    company character varying(255) DEFAULT NULL::character varying,
    company_logo uuid,
    content text,
    date_created timestamp with time zone,
    date_updated timestamp with time zone,
    id uuid NOT NULL,
    image uuid,
    link character varying(255) DEFAULT NULL::character varying,
    sort integer,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    subtitle character varying(255) DEFAULT NULL::character varying,
    title character varying(255) DEFAULT NULL::character varying,
    user_created uuid,
    user_updated uuid
);


--
-- Name: tmp_jg; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tmp_jg (
    i integer NOT NULL,
    c character(1) NOT NULL
);


--
-- Name: battery_scenario_sim id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.battery_scenario_sim ALTER COLUMN id SET DEFAULT nextval('public.battery_scenario_sim_id_seq'::regclass);


--
-- Name: directus_activity id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_activity ALTER COLUMN id SET DEFAULT nextval('public.directus_activity_id_seq'::regclass);


--
-- Name: directus_fields id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_fields ALTER COLUMN id SET DEFAULT nextval('public.directus_fields_id_seq'::regclass);


--
-- Name: directus_notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_notifications ALTER COLUMN id SET DEFAULT nextval('public.directus_notifications_id_seq'::regclass);


--
-- Name: directus_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_permissions ALTER COLUMN id SET DEFAULT nextval('public.directus_permissions_id_seq'::regclass);


--
-- Name: directus_presets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_presets ALTER COLUMN id SET DEFAULT nextval('public.directus_presets_id_seq'::regclass);


--
-- Name: directus_relations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_relations ALTER COLUMN id SET DEFAULT nextval('public.directus_relations_id_seq'::regclass);


--
-- Name: directus_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_revisions ALTER COLUMN id SET DEFAULT nextval('public.directus_revisions_id_seq'::regclass);


--
-- Name: directus_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings ALTER COLUMN id SET DEFAULT nextval('public.directus_settings_id_seq'::regclass);


--
-- Name: directus_webhooks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_webhooks ALTER COLUMN id SET DEFAULT nextval('public.directus_webhooks_id_seq'::regclass);


--
-- Name: lcc id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcc ALTER COLUMN id SET DEFAULT nextval('public.lcc_id_seq'::regclass);


--
-- Name: lcr id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcr ALTER COLUMN id SET DEFAULT nextval('public.lcr_id_seq'::regclass);


--
-- Name: power_consumption id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_consumption ALTER COLUMN id SET DEFAULT nextval('public.power_consumption_id_seq'::regclass);


--
-- Name: power_consumption_res id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_consumption_res ALTER COLUMN id SET DEFAULT nextval('public.power_consumption_res_id_seq'::regclass);


--
-- Name: ppc id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppc ALTER COLUMN id SET DEFAULT nextval('public.ppc_id_seq'::regclass);


--
-- Name: scenario id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario ALTER COLUMN id SET DEFAULT nextval('public.scenario_id_seq'::regclass);


--
-- Name: site id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site ALTER COLUMN id SET DEFAULT nextval('public.site_id_seq'::regclass);


--
-- Name: site_files id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_files ALTER COLUMN id SET DEFAULT nextval('public.site_files_id_seq'::regclass);


--
-- Name: solar id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solar ALTER COLUMN id SET DEFAULT nextval('public.solar_id_seq'::regclass);


--
-- Name: spot_prices_gen id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spot_prices_gen ALTER COLUMN id SET DEFAULT nextval('public.spot_prices_gen_id_seq'::regclass);


--
-- Name: battery_dataset battery_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.battery_dataset
    ADD CONSTRAINT battery_dataset_pkey PRIMARY KEY (battery_code);


--
-- Name: battery_scenario_sim battery_scenario_sim_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.battery_scenario_sim
    ADD CONSTRAINT battery_scenario_sim_pkey PRIMARY KEY (id);


--
-- Name: block_button_group block_button_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button_group
    ADD CONSTRAINT block_button_group_pkey PRIMARY KEY (id);


--
-- Name: block_button block_button_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button
    ADD CONSTRAINT block_button_pkey PRIMARY KEY (id);


--
-- Name: block_columns block_columns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_columns
    ADD CONSTRAINT block_columns_pkey PRIMARY KEY (id);


--
-- Name: block_columns_rows block_columns_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_columns_rows
    ADD CONSTRAINT block_columns_rows_pkey PRIMARY KEY (id);


--
-- Name: block_cta block_cta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_cta
    ADD CONSTRAINT block_cta_pkey PRIMARY KEY (id);


--
-- Name: block_divider block_divider_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_divider
    ADD CONSTRAINT block_divider_pkey PRIMARY KEY (id);


--
-- Name: block_faqs block_faqs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_faqs
    ADD CONSTRAINT block_faqs_pkey PRIMARY KEY (id);


--
-- Name: block_form block_form_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_form
    ADD CONSTRAINT block_form_pkey PRIMARY KEY (id);


--
-- Name: block_gallery_files block_gallery_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_gallery_files
    ADD CONSTRAINT block_gallery_files_pkey PRIMARY KEY (id);


--
-- Name: block_gallery block_gallery_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_gallery
    ADD CONSTRAINT block_gallery_pkey PRIMARY KEY (id);


--
-- Name: block_hero block_hero_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_hero
    ADD CONSTRAINT block_hero_pkey PRIMARY KEY (id);


--
-- Name: block_html block_html_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_html
    ADD CONSTRAINT block_html_pkey PRIMARY KEY (id);


--
-- Name: block_logocloud_logos block_logocloud_logos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_logocloud_logos
    ADD CONSTRAINT block_logocloud_logos_pkey PRIMARY KEY (id);


--
-- Name: block_logocloud block_logocloud_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_logocloud
    ADD CONSTRAINT block_logocloud_pkey PRIMARY KEY (id);


--
-- Name: block_quote block_quote_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_quote
    ADD CONSTRAINT block_quote_pkey PRIMARY KEY (id);


--
-- Name: block_richtext block_richtext_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_richtext
    ADD CONSTRAINT block_richtext_pkey PRIMARY KEY (id);


--
-- Name: block_step_items block_step_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_step_items
    ADD CONSTRAINT block_step_items_pkey PRIMARY KEY (id);


--
-- Name: block_steps block_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_steps
    ADD CONSTRAINT block_steps_pkey PRIMARY KEY (id);


--
-- Name: block_team block_team_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_team
    ADD CONSTRAINT block_team_pkey PRIMARY KEY (id);


--
-- Name: block_testimonial_slider_items block_testimonial_slider_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_testimonial_slider_items
    ADD CONSTRAINT block_testimonial_slider_items_pkey PRIMARY KEY (id);


--
-- Name: block_testimonials block_testimonials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_testimonials
    ADD CONSTRAINT block_testimonials_pkey PRIMARY KEY (id);


--
-- Name: block_video block_video_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_video
    ADD CONSTRAINT block_video_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: consumption_dataset consumption_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumption_dataset
    ADD CONSTRAINT consumption_dataset_pkey PRIMARY KEY (consumption_code);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: contacts contacts_user_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_user_unique UNIQUE ("user");


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: directus_access directus_access_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_access
    ADD CONSTRAINT directus_access_pkey PRIMARY KEY (id);


--
-- Name: directus_activity directus_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_activity
    ADD CONSTRAINT directus_activity_pkey PRIMARY KEY (id);


--
-- Name: directus_collections directus_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_collections
    ADD CONSTRAINT directus_collections_pkey PRIMARY KEY (collection);


--
-- Name: directus_comments directus_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_comments
    ADD CONSTRAINT directus_comments_pkey PRIMARY KEY (id);


--
-- Name: directus_dashboards directus_dashboards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_dashboards
    ADD CONSTRAINT directus_dashboards_pkey PRIMARY KEY (id);


--
-- Name: directus_extensions directus_extensions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_extensions
    ADD CONSTRAINT directus_extensions_pkey PRIMARY KEY (id);


--
-- Name: directus_fields directus_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_fields
    ADD CONSTRAINT directus_fields_pkey PRIMARY KEY (id);


--
-- Name: directus_files directus_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_files
    ADD CONSTRAINT directus_files_pkey PRIMARY KEY (id);


--
-- Name: directus_flows directus_flows_operation_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_flows
    ADD CONSTRAINT directus_flows_operation_unique UNIQUE (operation);


--
-- Name: directus_flows directus_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_flows
    ADD CONSTRAINT directus_flows_pkey PRIMARY KEY (id);


--
-- Name: directus_folders directus_folders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_folders
    ADD CONSTRAINT directus_folders_pkey PRIMARY KEY (id);


--
-- Name: directus_migrations directus_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_migrations
    ADD CONSTRAINT directus_migrations_pkey PRIMARY KEY (version);


--
-- Name: directus_notifications directus_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_notifications
    ADD CONSTRAINT directus_notifications_pkey PRIMARY KEY (id);


--
-- Name: directus_operations directus_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_operations
    ADD CONSTRAINT directus_operations_pkey PRIMARY KEY (id);


--
-- Name: directus_operations directus_operations_reject_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_operations
    ADD CONSTRAINT directus_operations_reject_unique UNIQUE (reject);


--
-- Name: directus_operations directus_operations_resolve_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_operations
    ADD CONSTRAINT directus_operations_resolve_unique UNIQUE (resolve);


--
-- Name: directus_panels directus_panels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_panels
    ADD CONSTRAINT directus_panels_pkey PRIMARY KEY (id);


--
-- Name: directus_permissions directus_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_permissions
    ADD CONSTRAINT directus_permissions_pkey PRIMARY KEY (id);


--
-- Name: directus_policies directus_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_policies
    ADD CONSTRAINT directus_policies_pkey PRIMARY KEY (id);


--
-- Name: directus_presets directus_presets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_presets
    ADD CONSTRAINT directus_presets_pkey PRIMARY KEY (id);


--
-- Name: directus_relations directus_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_relations
    ADD CONSTRAINT directus_relations_pkey PRIMARY KEY (id);


--
-- Name: directus_revisions directus_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_revisions
    ADD CONSTRAINT directus_revisions_pkey PRIMARY KEY (id);


--
-- Name: directus_roles directus_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_roles
    ADD CONSTRAINT directus_roles_pkey PRIMARY KEY (id);


--
-- Name: directus_sessions directus_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_sessions
    ADD CONSTRAINT directus_sessions_pkey PRIMARY KEY (token);


--
-- Name: directus_settings directus_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings
    ADD CONSTRAINT directus_settings_pkey PRIMARY KEY (id);


--
-- Name: directus_shares directus_shares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_shares
    ADD CONSTRAINT directus_shares_pkey PRIMARY KEY (id);


--
-- Name: directus_translations directus_translations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_translations
    ADD CONSTRAINT directus_translations_pkey PRIMARY KEY (id);


--
-- Name: directus_users directus_users_email_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_users
    ADD CONSTRAINT directus_users_email_unique UNIQUE (email);


--
-- Name: directus_users directus_users_external_identifier_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_users
    ADD CONSTRAINT directus_users_external_identifier_unique UNIQUE (external_identifier);


--
-- Name: directus_users directus_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_users
    ADD CONSTRAINT directus_users_pkey PRIMARY KEY (id);


--
-- Name: directus_users directus_users_token_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_users
    ADD CONSTRAINT directus_users_token_unique UNIQUE (token);


--
-- Name: directus_versions directus_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_versions
    ADD CONSTRAINT directus_versions_pkey PRIMARY KEY (id);


--
-- Name: directus_webhooks directus_webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_webhooks
    ADD CONSTRAINT directus_webhooks_pkey PRIMARY KEY (id);


--
-- Name: discharge_amount discharge_amount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discharge_amount
    ADD CONSTRAINT discharge_amount_pkey PRIMARY KEY (id);


--
-- Name: forms forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forms
    ADD CONSTRAINT forms_pkey PRIMARY KEY (id);


--
-- Name: globals globals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.globals
    ADD CONSTRAINT globals_pkey PRIMARY KEY (id);


--
-- Name: help_articles help_articles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_articles
    ADD CONSTRAINT help_articles_pkey PRIMARY KEY (id);


--
-- Name: help_collections help_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_collections
    ADD CONSTRAINT help_collections_pkey PRIMARY KEY (id);


--
-- Name: help_feedback help_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_feedback
    ADD CONSTRAINT help_feedback_pkey PRIMARY KEY (id);


--
-- Name: inbox inbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox
    ADD CONSTRAINT inbox_pkey PRIMARY KEY (id);


--
-- Name: lcc_dataset lcc_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcc_dataset
    ADD CONSTRAINT lcc_dataset_pkey PRIMARY KEY (lcc_code);


--
-- Name: lcc lcc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcc
    ADD CONSTRAINT lcc_pkey PRIMARY KEY (id);


--
-- Name: lcr_dataset lcr_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcr_dataset
    ADD CONSTRAINT lcr_dataset_pkey PRIMARY KEY (lcr_code);


--
-- Name: lcr lcr_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcr
    ADD CONSTRAINT lcr_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: navigation_items navigation_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navigation_items
    ADD CONSTRAINT navigation_items_pkey PRIMARY KEY (id);


--
-- Name: navigation navigation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navigation
    ADD CONSTRAINT navigation_pkey PRIMARY KEY (id);


--
-- Name: organization_addresses organization_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_addresses
    ADD CONSTRAINT organization_addresses_pkey PRIMARY KEY (id);


--
-- Name: organizations_contacts organizations_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations_contacts
    ADD CONSTRAINT organizations_contacts_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: os_activities os_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activities
    ADD CONSTRAINT os_activities_pkey PRIMARY KEY (id);


--
-- Name: os_activity_contacts os_activity_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activity_contacts
    ADD CONSTRAINT os_activity_contacts_pkey PRIMARY KEY (id);


--
-- Name: os_deal_contacts os_deal_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deal_contacts
    ADD CONSTRAINT os_deal_contacts_pkey PRIMARY KEY (id);


--
-- Name: os_deal_stages os_deal_stages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deal_stages
    ADD CONSTRAINT os_deal_stages_pkey PRIMARY KEY (id);


--
-- Name: os_deals os_deals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deals
    ADD CONSTRAINT os_deals_pkey PRIMARY KEY (id);


--
-- Name: os_email_templates os_email_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_email_templates
    ADD CONSTRAINT os_email_templates_pkey PRIMARY KEY (id);


--
-- Name: os_expenses os_expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_expenses
    ADD CONSTRAINT os_expenses_pkey PRIMARY KEY (id);


--
-- Name: os_invoice_items os_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoice_items
    ADD CONSTRAINT os_invoice_items_pkey PRIMARY KEY (id);


--
-- Name: os_invoices os_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoices
    ADD CONSTRAINT os_invoices_pkey PRIMARY KEY (id);


--
-- Name: os_items os_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_items
    ADD CONSTRAINT os_items_pkey PRIMARY KEY (id);


--
-- Name: os_payment_terms os_payment_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payment_terms
    ADD CONSTRAINT os_payment_terms_pkey PRIMARY KEY (id);


--
-- Name: os_payments os_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payments
    ADD CONSTRAINT os_payments_pkey PRIMARY KEY (id);


--
-- Name: os_project_contacts os_project_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_contacts
    ADD CONSTRAINT os_project_contacts_pkey PRIMARY KEY (id);


--
-- Name: os_project_templates os_project_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_templates
    ADD CONSTRAINT os_project_templates_pkey PRIMARY KEY (id);


--
-- Name: os_project_updates os_project_updates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_updates
    ADD CONSTRAINT os_project_updates_pkey PRIMARY KEY (id);


--
-- Name: os_projects os_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_projects
    ADD CONSTRAINT os_projects_pkey PRIMARY KEY (id);


--
-- Name: os_proposal_approvals os_proposal_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_approvals
    ADD CONSTRAINT os_proposal_approvals_pkey PRIMARY KEY (id);


--
-- Name: os_proposal_blocks os_proposal_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_blocks
    ADD CONSTRAINT os_proposal_blocks_pkey PRIMARY KEY (id);


--
-- Name: os_proposal_contacts os_proposal_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_contacts
    ADD CONSTRAINT os_proposal_contacts_pkey PRIMARY KEY (id);


--
-- Name: os_proposals os_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposals
    ADD CONSTRAINT os_proposals_pkey PRIMARY KEY (id);


--
-- Name: os_settings os_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_settings
    ADD CONSTRAINT os_settings_pkey PRIMARY KEY (id);


--
-- Name: os_task_files os_task_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_task_files
    ADD CONSTRAINT os_task_files_pkey PRIMARY KEY (id);


--
-- Name: os_tasks os_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tasks
    ADD CONSTRAINT os_tasks_pkey PRIMARY KEY (id);


--
-- Name: os_tax_rates os_tax_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tax_rates
    ADD CONSTRAINT os_tax_rates_pkey PRIMARY KEY (id);


--
-- Name: page_blocks page_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_blocks
    ADD CONSTRAINT page_blocks_pkey PRIMARY KEY (id);


--
-- Name: pages_blog pages_blog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pages_blog
    ADD CONSTRAINT pages_blog_pkey PRIMARY KEY (id);


--
-- Name: pages pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_pkey PRIMARY KEY (id);


--
-- Name: pages_projects pages_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pages_projects
    ADD CONSTRAINT pages_projects_pkey PRIMARY KEY (id);


--
-- Name: pcr_dataset pcr_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcr_dataset
    ADD CONSTRAINT pcr_dataset_pkey PRIMARY KEY (pcr_code);


--
-- Name: post_gallery_items post_gallery_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_gallery_items
    ADD CONSTRAINT post_gallery_items_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: power_consumption power_consumption_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_consumption
    ADD CONSTRAINT power_consumption_pkey PRIMARY KEY (id);


--
-- Name: power_consumption_res power_consumption_res_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_consumption_res
    ADD CONSTRAINT power_consumption_res_pkey PRIMARY KEY (id);


--
-- Name: ppc_dataset ppc_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppc_dataset
    ADD CONSTRAINT ppc_dataset_pkey PRIMARY KEY (ppc_code);


--
-- Name: ppc ppc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppc
    ADD CONSTRAINT ppc_pkey PRIMARY KEY (id);


--
-- Name: redirects redirects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redirects
    ADD CONSTRAINT redirects_pkey PRIMARY KEY (id);


--
-- Name: scenario scenario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_pkey PRIMARY KEY (id);


--
-- Name: scenario scenario_scenario_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_scenario_code_key UNIQUE (scenario_code);


--
-- Name: seo seo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo
    ADD CONSTRAINT seo_pkey PRIMARY KEY (id);


--
-- Name: site_dataset site_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_dataset
    ADD CONSTRAINT site_dataset_pkey PRIMARY KEY (site_code);


--
-- Name: site_files site_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_files
    ADD CONSTRAINT site_files_pkey PRIMARY KEY (id);


--
-- Name: site site_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site
    ADD CONSTRAINT site_pkey PRIMARY KEY (id);


--
-- Name: site site_site_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site
    ADD CONSTRAINT site_site_code_key UNIQUE (site_code);


--
-- Name: solar_dataset solar_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solar_dataset
    ADD CONSTRAINT solar_dataset_pkey PRIMARY KEY (solar_code);


--
-- Name: solar solar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solar
    ADD CONSTRAINT solar_pkey PRIMARY KEY (id);


--
-- Name: spot_dataset spot_dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spot_dataset
    ADD CONSTRAINT spot_dataset_pkey PRIMARY KEY (spot_code);


--
-- Name: spot_price_jg spot_price_jg_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spot_price_jg
    ADD CONSTRAINT spot_price_jg_pkey PRIMARY KEY (id);


--
-- Name: spot_prices_gen spot_prices_gen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spot_prices_gen
    ADD CONSTRAINT spot_prices_gen_pkey PRIMARY KEY (id);


--
-- Name: team team_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_pkey PRIMARY KEY (id);


--
-- Name: testimonials testimonials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.testimonials
    ADD CONSTRAINT testimonials_pkey PRIMARY KEY (id);


--
-- Name: battery_scenario_sim_battery_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX battery_scenario_sim_battery_code_idx ON public.battery_scenario_sim USING btree (battery_code);


--
-- Name: battery_scenario_sim_battery_code_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX battery_scenario_sim_battery_code_idx1 ON public.battery_scenario_sim USING btree (battery_code);


--
-- Name: battery_scenario_sim_battery_code_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX battery_scenario_sim_battery_code_timestamp_idx ON public.battery_scenario_sim USING btree (battery_code, "timestamp");


--
-- Name: battery_scenario_sim_battery_code_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX battery_scenario_sim_battery_code_timestamp_idx1 ON public.battery_scenario_sim USING btree (battery_code, "timestamp");


--
-- Name: battery_scenario_sim_battery_code_timestamp_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX battery_scenario_sim_battery_code_timestamp_idx2 ON public.battery_scenario_sim USING btree (battery_code, "timestamp");


--
-- Name: battery_scenario_sim_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX battery_scenario_sim_timestamp_idx ON public.battery_scenario_sim USING btree ("timestamp");


--
-- Name: battery_scenario_sim_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX battery_scenario_sim_timestamp_idx1 ON public.battery_scenario_sim USING btree ("timestamp");


--
-- Name: discharge_amount_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discharge_amount_timestamp_idx ON public.discharge_amount USING btree ("timestamp");


--
-- Name: idx_row_num_battery_calc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_row_num_battery_calc ON public.battery_calc USING btree (row_num) WITH (fillfactor='100', deduplicate_items='true');


--
-- Name: idx_row_num_tmp_battery_base; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_row_num_tmp_battery_base ON public.battery_base USING btree (row_num) WITH (fillfactor='100', deduplicate_items='true');


--
-- Name: idx_timestamp_battery_calc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_timestamp_battery_calc ON public.battery_calc USING btree ("timestamp") WITH (fillfactor='100', deduplicate_items='true');


--
-- Name: idx_timestamp_tmp_battery_base; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_timestamp_tmp_battery_base ON public.battery_base USING btree ("timestamp") WITH (fillfactor='100', deduplicate_items='true');


--
-- Name: lcc_lcc_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcc_lcc_code_idx ON public.lcc USING btree (lcc_code);


--
-- Name: lcc_lcc_code_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcc_lcc_code_idx1 ON public.lcc USING btree (lcc_code);


--
-- Name: lcc_lcc_code_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX lcc_lcc_code_timestamp_idx ON public.lcc USING btree (lcc_code, "timestamp");


--
-- Name: lcc_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcc_timestamp_idx ON public.lcc USING btree ("timestamp");


--
-- Name: lcc_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcc_timestamp_idx1 ON public.lcc USING btree ("timestamp");


--
-- Name: lcr_lcr_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcr_lcr_code_idx ON public.lcr USING btree (lcr_code);


--
-- Name: lcr_lcr_code_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcr_lcr_code_idx1 ON public.lcr USING btree (lcr_code);


--
-- Name: lcr_lcr_code_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX lcr_lcr_code_timestamp_idx ON public.lcr USING btree (lcr_code, "timestamp");


--
-- Name: lcr_lcr_code_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX lcr_lcr_code_timestamp_idx1 ON public.lcr USING btree (lcr_code, "timestamp");


--
-- Name: lcr_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcr_timestamp_idx ON public.lcr USING btree ("timestamp");


--
-- Name: lcr_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lcr_timestamp_idx1 ON public.lcr USING btree ("timestamp");


--
-- Name: power_consumption_consumption_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX power_consumption_consumption_code_idx ON public.power_consumption USING btree (consumption_code);


--
-- Name: power_consumption_consumption_code_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX power_consumption_consumption_code_idx1 ON public.power_consumption USING btree (consumption_code);


--
-- Name: power_consumption_consumption_code_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX power_consumption_consumption_code_timestamp_idx ON public.power_consumption USING btree (consumption_code, "timestamp");


--
-- Name: power_consumption_consumption_code_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX power_consumption_consumption_code_timestamp_idx1 ON public.power_consumption USING btree (consumption_code, "timestamp");


--
-- Name: power_consumption_res_consumption_code_res_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX power_consumption_res_consumption_code_res_idx ON public.power_consumption_res USING btree (consumption_code_res);


--
-- Name: power_consumption_res_consumption_code_res_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX power_consumption_res_consumption_code_res_timestamp_idx ON public.power_consumption_res USING btree (consumption_code_res, "timestamp");


--
-- Name: power_consumption_res_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX power_consumption_res_timestamp_idx ON public.power_consumption_res USING btree ("timestamp");


--
-- Name: power_consumption_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX power_consumption_timestamp_idx ON public.power_consumption USING btree ("timestamp");


--
-- Name: power_consumption_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX power_consumption_timestamp_idx1 ON public.power_consumption USING btree ("timestamp");


--
-- Name: ppc_ppc_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ppc_ppc_code_idx ON public.ppc USING btree (ppc_code);


--
-- Name: ppc_ppc_code_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ppc_ppc_code_idx1 ON public.ppc USING btree (ppc_code);


--
-- Name: ppc_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ppc_timestamp_idx ON public.ppc USING btree ("timestamp");


--
-- Name: ppc_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ppc_timestamp_idx1 ON public.ppc USING btree ("timestamp");


--
-- Name: scenario_consumption_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scenario_consumption_code_idx ON public.scenario USING btree (consumption_code);


--
-- Name: scenario_solar_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scenario_solar_code_idx ON public.scenario USING btree (solar_code);


--
-- Name: scenario_spot_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scenario_spot_code_idx ON public.scenario USING btree (spot_code);


--
-- Name: solar_solar_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX solar_solar_code_idx ON public.solar USING btree (solar_code);


--
-- Name: solar_solar_code_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX solar_solar_code_idx1 ON public.solar USING btree (solar_code);


--
-- Name: solar_solar_code_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX solar_solar_code_timestamp_idx ON public.solar USING btree (solar_code, "timestamp");


--
-- Name: solar_solar_code_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX solar_solar_code_timestamp_idx1 ON public.solar USING btree (solar_code, "timestamp");


--
-- Name: solar_solar_code_timestamp_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX solar_solar_code_timestamp_idx2 ON public.solar USING btree (solar_code, "timestamp");


--
-- Name: solar_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX solar_timestamp_idx ON public.solar USING btree ("timestamp");


--
-- Name: solar_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX solar_timestamp_idx1 ON public.solar USING btree ("timestamp");


--
-- Name: solar_timestamp_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX solar_timestamp_idx2 ON public.solar USING btree ("timestamp");


--
-- Name: spot_price_jg_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX spot_price_jg_timestamp_idx ON public.spot_price_jg USING btree ("timestamp");


--
-- Name: spot_prices_gen_spot_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX spot_prices_gen_spot_code_idx ON public.spot_prices_gen USING btree (spot_code);


--
-- Name: spot_prices_gen_spot_code_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX spot_prices_gen_spot_code_idx1 ON public.spot_prices_gen USING btree (spot_code);


--
-- Name: spot_prices_gen_spot_code_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX spot_prices_gen_spot_code_timestamp_idx ON public.spot_prices_gen USING btree (spot_code, "timestamp");


--
-- Name: spot_prices_gen_spot_code_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX spot_prices_gen_spot_code_timestamp_idx1 ON public.spot_prices_gen USING btree (spot_code, "timestamp");


--
-- Name: spot_prices_gen_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX spot_prices_gen_timestamp_idx ON public.spot_prices_gen USING btree ("timestamp");


--
-- Name: spot_prices_gen_timestamp_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX spot_prices_gen_timestamp_idx1 ON public.spot_prices_gen USING btree ("timestamp");


--
-- Name: spot_prices_gen trg_refresh_mv_spot; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_refresh_mv_spot AFTER INSERT OR DELETE OR UPDATE ON public.spot_prices_gen FOR EACH STATEMENT EXECUTE FUNCTION public.refresh_joined_energy_data_mv();


--
-- Name: battery_scenario_sim battery_scenario_sim_battery_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.battery_scenario_sim
    ADD CONSTRAINT battery_scenario_sim_battery_code_fkey FOREIGN KEY (battery_code) REFERENCES public.battery_dataset(battery_code);


--
-- Name: block_button block_button_button_group_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button
    ADD CONSTRAINT block_button_button_group_foreign FOREIGN KEY (button_group) REFERENCES public.block_button_group(id) ON DELETE SET NULL;


--
-- Name: block_button_group block_button_group_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button_group
    ADD CONSTRAINT block_button_group_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: block_button_group block_button_group_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button_group
    ADD CONSTRAINT block_button_group_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: block_button block_button_page_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button
    ADD CONSTRAINT block_button_page_foreign FOREIGN KEY (page) REFERENCES public.pages(id) ON DELETE SET NULL;


--
-- Name: block_button block_button_post_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button
    ADD CONSTRAINT block_button_post_foreign FOREIGN KEY (post) REFERENCES public.posts(id) ON DELETE SET NULL;


--
-- Name: block_button block_button_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button
    ADD CONSTRAINT block_button_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: block_button block_button_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_button
    ADD CONSTRAINT block_button_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: block_columns_rows block_columns_rows_block_columns_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_columns_rows
    ADD CONSTRAINT block_columns_rows_block_columns_foreign FOREIGN KEY (block_columns) REFERENCES public.block_columns(id);


--
-- Name: block_columns_rows block_columns_rows_button_group_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_columns_rows
    ADD CONSTRAINT block_columns_rows_button_group_foreign FOREIGN KEY (button_group) REFERENCES public.block_button_group(id) ON DELETE SET NULL;


--
-- Name: block_columns_rows block_columns_rows_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_columns_rows
    ADD CONSTRAINT block_columns_rows_image_foreign FOREIGN KEY (image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: block_columns_rows block_columns_rows_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_columns_rows
    ADD CONSTRAINT block_columns_rows_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: block_columns_rows block_columns_rows_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_columns_rows
    ADD CONSTRAINT block_columns_rows_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: block_cta block_cta_button_group_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_cta
    ADD CONSTRAINT block_cta_button_group_foreign FOREIGN KEY (button_group) REFERENCES public.block_button_group(id) ON DELETE SET NULL;


--
-- Name: block_form block_form_form_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_form
    ADD CONSTRAINT block_form_form_foreign FOREIGN KEY (form) REFERENCES public.forms(id);


--
-- Name: block_gallery_files block_gallery_files_block_gallery_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_gallery_files
    ADD CONSTRAINT block_gallery_files_block_gallery_id_foreign FOREIGN KEY (block_gallery_id) REFERENCES public.block_gallery(id) ON DELETE SET NULL;


--
-- Name: block_gallery_files block_gallery_files_directus_files_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_gallery_files
    ADD CONSTRAINT block_gallery_files_directus_files_id_foreign FOREIGN KEY (directus_files_id) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: block_gallery_files block_gallery_files_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_gallery_files
    ADD CONSTRAINT block_gallery_files_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: block_gallery_files block_gallery_files_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_gallery_files
    ADD CONSTRAINT block_gallery_files_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: block_hero block_hero_button_group_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_hero
    ADD CONSTRAINT block_hero_button_group_foreign FOREIGN KEY (button_group) REFERENCES public.block_button_group(id) ON DELETE SET NULL;


--
-- Name: block_hero block_hero_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_hero
    ADD CONSTRAINT block_hero_image_foreign FOREIGN KEY (image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: block_logocloud_logos block_logocloud_logos_block_logocloud_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_logocloud_logos
    ADD CONSTRAINT block_logocloud_logos_block_logocloud_id_foreign FOREIGN KEY (block_logocloud_id) REFERENCES public.block_logocloud(id) ON DELETE SET NULL;


--
-- Name: block_logocloud_logos block_logocloud_logos_directus_files_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_logocloud_logos
    ADD CONSTRAINT block_logocloud_logos_directus_files_id_foreign FOREIGN KEY (directus_files_id) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: block_step_items block_step_items_block_steps_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_step_items
    ADD CONSTRAINT block_step_items_block_steps_foreign FOREIGN KEY (block_steps) REFERENCES public.block_steps(id) ON DELETE SET NULL;


--
-- Name: block_step_items block_step_items_button_group_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_step_items
    ADD CONSTRAINT block_step_items_button_group_foreign FOREIGN KEY (button_group) REFERENCES public.block_button_group(id) ON DELETE SET NULL;


--
-- Name: block_step_items block_step_items_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_step_items
    ADD CONSTRAINT block_step_items_image_foreign FOREIGN KEY (image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: block_testimonial_slider_items block_testimonial_slider_items_block_testi__4af36ccf_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_testimonial_slider_items
    ADD CONSTRAINT block_testimonial_slider_items_block_testi__4af36ccf_foreign FOREIGN KEY (block_testimonial_slider_id) REFERENCES public.block_testimonials(id) ON DELETE SET NULL;


--
-- Name: block_testimonial_slider_items block_testimonial_slider_items_testimonials_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_testimonial_slider_items
    ADD CONSTRAINT block_testimonial_slider_items_testimonials_id_foreign FOREIGN KEY (testimonials_id) REFERENCES public.testimonials(id) ON DELETE SET NULL;


--
-- Name: block_testimonial_slider_items block_testimonial_slider_items_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_testimonial_slider_items
    ADD CONSTRAINT block_testimonial_slider_items_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: block_testimonial_slider_items block_testimonial_slider_items_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_testimonial_slider_items
    ADD CONSTRAINT block_testimonial_slider_items_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: block_video block_video_video_file_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.block_video
    ADD CONSTRAINT block_video_video_file_foreign FOREIGN KEY (video_file) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: categories categories_seo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_seo_foreign FOREIGN KEY (seo) REFERENCES public.seo(id) ON DELETE SET NULL;


--
-- Name: contacts contacts_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: contacts contacts_user_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_user_foreign FOREIGN KEY ("user") REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: contacts contacts_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: conversations conversations_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_access directus_access_policy_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_access
    ADD CONSTRAINT directus_access_policy_foreign FOREIGN KEY (policy) REFERENCES public.directus_policies(id) ON DELETE CASCADE;


--
-- Name: directus_access directus_access_role_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_access
    ADD CONSTRAINT directus_access_role_foreign FOREIGN KEY (role) REFERENCES public.directus_roles(id) ON DELETE CASCADE;


--
-- Name: directus_access directus_access_user_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_access
    ADD CONSTRAINT directus_access_user_foreign FOREIGN KEY ("user") REFERENCES public.directus_users(id) ON DELETE CASCADE;


--
-- Name: directus_collections directus_collections_group_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_collections
    ADD CONSTRAINT directus_collections_group_foreign FOREIGN KEY ("group") REFERENCES public.directus_collections(collection);


--
-- Name: directus_comments directus_comments_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_comments
    ADD CONSTRAINT directus_comments_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_comments directus_comments_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_comments
    ADD CONSTRAINT directus_comments_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: directus_dashboards directus_dashboards_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_dashboards
    ADD CONSTRAINT directus_dashboards_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_files directus_files_folder_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_files
    ADD CONSTRAINT directus_files_folder_foreign FOREIGN KEY (folder) REFERENCES public.directus_folders(id) ON DELETE SET NULL;


--
-- Name: directus_files directus_files_modified_by_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_files
    ADD CONSTRAINT directus_files_modified_by_foreign FOREIGN KEY (modified_by) REFERENCES public.directus_users(id);


--
-- Name: directus_files directus_files_uploaded_by_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_files
    ADD CONSTRAINT directus_files_uploaded_by_foreign FOREIGN KEY (uploaded_by) REFERENCES public.directus_users(id);


--
-- Name: directus_flows directus_flows_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_flows
    ADD CONSTRAINT directus_flows_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_folders directus_folders_parent_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_folders
    ADD CONSTRAINT directus_folders_parent_foreign FOREIGN KEY (parent) REFERENCES public.directus_folders(id);


--
-- Name: directus_notifications directus_notifications_recipient_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_notifications
    ADD CONSTRAINT directus_notifications_recipient_foreign FOREIGN KEY (recipient) REFERENCES public.directus_users(id) ON DELETE CASCADE;


--
-- Name: directus_notifications directus_notifications_sender_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_notifications
    ADD CONSTRAINT directus_notifications_sender_foreign FOREIGN KEY (sender) REFERENCES public.directus_users(id);


--
-- Name: directus_operations directus_operations_flow_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_operations
    ADD CONSTRAINT directus_operations_flow_foreign FOREIGN KEY (flow) REFERENCES public.directus_flows(id) ON DELETE CASCADE;


--
-- Name: directus_operations directus_operations_reject_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_operations
    ADD CONSTRAINT directus_operations_reject_foreign FOREIGN KEY (reject) REFERENCES public.directus_operations(id);


--
-- Name: directus_operations directus_operations_resolve_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_operations
    ADD CONSTRAINT directus_operations_resolve_foreign FOREIGN KEY (resolve) REFERENCES public.directus_operations(id);


--
-- Name: directus_operations directus_operations_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_operations
    ADD CONSTRAINT directus_operations_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_panels directus_panels_dashboard_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_panels
    ADD CONSTRAINT directus_panels_dashboard_foreign FOREIGN KEY (dashboard) REFERENCES public.directus_dashboards(id) ON DELETE CASCADE;


--
-- Name: directus_panels directus_panels_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_panels
    ADD CONSTRAINT directus_panels_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_permissions directus_permissions_policy_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_permissions
    ADD CONSTRAINT directus_permissions_policy_foreign FOREIGN KEY (policy) REFERENCES public.directus_policies(id) ON DELETE CASCADE;


--
-- Name: directus_presets directus_presets_role_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_presets
    ADD CONSTRAINT directus_presets_role_foreign FOREIGN KEY (role) REFERENCES public.directus_roles(id) ON DELETE CASCADE;


--
-- Name: directus_presets directus_presets_user_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_presets
    ADD CONSTRAINT directus_presets_user_foreign FOREIGN KEY ("user") REFERENCES public.directus_users(id) ON DELETE CASCADE;


--
-- Name: directus_revisions directus_revisions_activity_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_revisions
    ADD CONSTRAINT directus_revisions_activity_foreign FOREIGN KEY (activity) REFERENCES public.directus_activity(id) ON DELETE CASCADE;


--
-- Name: directus_revisions directus_revisions_parent_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_revisions
    ADD CONSTRAINT directus_revisions_parent_foreign FOREIGN KEY (parent) REFERENCES public.directus_revisions(id);


--
-- Name: directus_revisions directus_revisions_version_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_revisions
    ADD CONSTRAINT directus_revisions_version_foreign FOREIGN KEY (version) REFERENCES public.directus_versions(id) ON DELETE CASCADE;


--
-- Name: directus_roles directus_roles_parent_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_roles
    ADD CONSTRAINT directus_roles_parent_foreign FOREIGN KEY (parent) REFERENCES public.directus_roles(id);


--
-- Name: directus_sessions directus_sessions_share_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_sessions
    ADD CONSTRAINT directus_sessions_share_foreign FOREIGN KEY (share) REFERENCES public.directus_shares(id) ON DELETE CASCADE;


--
-- Name: directus_sessions directus_sessions_user_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_sessions
    ADD CONSTRAINT directus_sessions_user_foreign FOREIGN KEY ("user") REFERENCES public.directus_users(id) ON DELETE CASCADE;


--
-- Name: directus_settings directus_settings_project_logo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings
    ADD CONSTRAINT directus_settings_project_logo_foreign FOREIGN KEY (project_logo) REFERENCES public.directus_files(id);


--
-- Name: directus_settings directus_settings_public_background_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings
    ADD CONSTRAINT directus_settings_public_background_foreign FOREIGN KEY (public_background) REFERENCES public.directus_files(id);


--
-- Name: directus_settings directus_settings_public_favicon_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings
    ADD CONSTRAINT directus_settings_public_favicon_foreign FOREIGN KEY (public_favicon) REFERENCES public.directus_files(id);


--
-- Name: directus_settings directus_settings_public_foreground_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings
    ADD CONSTRAINT directus_settings_public_foreground_foreign FOREIGN KEY (public_foreground) REFERENCES public.directus_files(id);


--
-- Name: directus_settings directus_settings_public_registration_role_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings
    ADD CONSTRAINT directus_settings_public_registration_role_foreign FOREIGN KEY (public_registration_role) REFERENCES public.directus_roles(id) ON DELETE SET NULL;


--
-- Name: directus_settings directus_settings_storage_default_folder_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_settings
    ADD CONSTRAINT directus_settings_storage_default_folder_foreign FOREIGN KEY (storage_default_folder) REFERENCES public.directus_folders(id) ON DELETE SET NULL;


--
-- Name: directus_shares directus_shares_collection_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_shares
    ADD CONSTRAINT directus_shares_collection_foreign FOREIGN KEY (collection) REFERENCES public.directus_collections(collection) ON DELETE CASCADE;


--
-- Name: directus_shares directus_shares_role_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_shares
    ADD CONSTRAINT directus_shares_role_foreign FOREIGN KEY (role) REFERENCES public.directus_roles(id) ON DELETE CASCADE;


--
-- Name: directus_shares directus_shares_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_shares
    ADD CONSTRAINT directus_shares_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_users directus_users_role_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_users
    ADD CONSTRAINT directus_users_role_foreign FOREIGN KEY (role) REFERENCES public.directus_roles(id) ON DELETE SET NULL;


--
-- Name: directus_versions directus_versions_collection_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_versions
    ADD CONSTRAINT directus_versions_collection_foreign FOREIGN KEY (collection) REFERENCES public.directus_collections(collection) ON DELETE CASCADE;


--
-- Name: directus_versions directus_versions_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_versions
    ADD CONSTRAINT directus_versions_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: directus_versions directus_versions_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_versions
    ADD CONSTRAINT directus_versions_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: directus_webhooks directus_webhooks_migrated_flow_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.directus_webhooks
    ADD CONSTRAINT directus_webhooks_migrated_flow_foreign FOREIGN KEY (migrated_flow) REFERENCES public.directus_flows(id) ON DELETE SET NULL;


--
-- Name: forms forms_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forms
    ADD CONSTRAINT forms_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: forms forms_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forms
    ADD CONSTRAINT forms_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: globals globals_logo_on_dark_bg_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.globals
    ADD CONSTRAINT globals_logo_on_dark_bg_foreign FOREIGN KEY (logo_on_dark_bg) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: globals globals_logo_on_light_bg_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.globals
    ADD CONSTRAINT globals_logo_on_light_bg_foreign FOREIGN KEY (logo_on_light_bg) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: globals globals_og_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.globals
    ADD CONSTRAINT globals_og_image_foreign FOREIGN KEY (og_image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: help_articles help_articles_help_collection_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_articles
    ADD CONSTRAINT help_articles_help_collection_foreign FOREIGN KEY (help_collection) REFERENCES public.help_collections(id) ON DELETE SET NULL;


--
-- Name: help_articles help_articles_owner_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_articles
    ADD CONSTRAINT help_articles_owner_foreign FOREIGN KEY (owner) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: help_articles help_articles_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_articles
    ADD CONSTRAINT help_articles_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: help_articles help_articles_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_articles
    ADD CONSTRAINT help_articles_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: help_feedback help_feedback_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_feedback
    ADD CONSTRAINT help_feedback_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: help_feedback help_feedback_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_feedback
    ADD CONSTRAINT help_feedback_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: inbox inbox_form_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox
    ADD CONSTRAINT inbox_form_foreign FOREIGN KEY (form) REFERENCES public.forms(id) ON DELETE SET NULL;


--
-- Name: inbox inbox_project_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox
    ADD CONSTRAINT inbox_project_foreign FOREIGN KEY (project) REFERENCES public.os_projects(id) ON DELETE SET NULL;


--
-- Name: inbox inbox_task_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox
    ADD CONSTRAINT inbox_task_foreign FOREIGN KEY (task) REFERENCES public.os_tasks(id) ON DELETE SET NULL;


--
-- Name: inbox inbox_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox
    ADD CONSTRAINT inbox_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: inbox inbox_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox
    ADD CONSTRAINT inbox_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: lcc lcc_lcc_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcc
    ADD CONSTRAINT lcc_lcc_code_fkey FOREIGN KEY (lcc_code) REFERENCES public.lcc_dataset(lcc_code);


--
-- Name: lcr lcr_lcr_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lcr
    ADD CONSTRAINT lcr_lcr_code_fkey FOREIGN KEY (lcr_code) REFERENCES public.lcr_dataset(lcr_code);


--
-- Name: messages messages_conversation_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_conversation_foreign FOREIGN KEY (conversation) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: messages messages_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: messages messages_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: navigation_items navigation_items_navigation_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navigation_items
    ADD CONSTRAINT navigation_items_navigation_foreign FOREIGN KEY (navigation) REFERENCES public.navigation(id) ON DELETE SET NULL;


--
-- Name: navigation_items navigation_items_page_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navigation_items
    ADD CONSTRAINT navigation_items_page_foreign FOREIGN KEY (page) REFERENCES public.pages(id) ON DELETE SET NULL;


--
-- Name: navigation_items navigation_items_parent_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navigation_items
    ADD CONSTRAINT navigation_items_parent_foreign FOREIGN KEY (parent) REFERENCES public.navigation_items(id);


--
-- Name: navigation navigation_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navigation
    ADD CONSTRAINT navigation_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: navigation navigation_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.navigation
    ADD CONSTRAINT navigation_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: organization_addresses organization_addresses_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_addresses
    ADD CONSTRAINT organization_addresses_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organization_addresses organization_addresses_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_addresses
    ADD CONSTRAINT organization_addresses_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: organization_addresses organization_addresses_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_addresses
    ADD CONSTRAINT organization_addresses_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: organizations_contacts organizations_contacts_contacts_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations_contacts
    ADD CONSTRAINT organizations_contacts_contacts_id_foreign FOREIGN KEY (contacts_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: organizations_contacts organizations_contacts_organizations_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations_contacts
    ADD CONSTRAINT organizations_contacts_organizations_id_foreign FOREIGN KEY (organizations_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organizations organizations_folder_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_folder_foreign FOREIGN KEY (folder) REFERENCES public.directus_folders(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_logo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_logo_foreign FOREIGN KEY (logo) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_owner_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_owner_foreign FOREIGN KEY (owner) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_payment_terms_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_payment_terms_foreign FOREIGN KEY (payment_terms) REFERENCES public.os_payment_terms(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: organizations organizations_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_activities os_activities_assigned_to_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activities
    ADD CONSTRAINT os_activities_assigned_to_foreign FOREIGN KEY (assigned_to) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: os_activities os_activities_deal_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activities
    ADD CONSTRAINT os_activities_deal_foreign FOREIGN KEY (deal) REFERENCES public.os_deals(id) ON DELETE SET NULL;


--
-- Name: os_activities os_activities_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activities
    ADD CONSTRAINT os_activities_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: os_activities os_activities_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activities
    ADD CONSTRAINT os_activities_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_activities os_activities_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activities
    ADD CONSTRAINT os_activities_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_activity_contacts os_activity_contacts_contacts_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activity_contacts
    ADD CONSTRAINT os_activity_contacts_contacts_id_foreign FOREIGN KEY (contacts_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: os_activity_contacts os_activity_contacts_os_activities_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_activity_contacts
    ADD CONSTRAINT os_activity_contacts_os_activities_id_foreign FOREIGN KEY (os_activities_id) REFERENCES public.os_activities(id) ON DELETE CASCADE;


--
-- Name: os_deal_contacts os_deal_contacts_contacts_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deal_contacts
    ADD CONSTRAINT os_deal_contacts_contacts_id_foreign FOREIGN KEY (contacts_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: os_deal_contacts os_deal_contacts_os_deals_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deal_contacts
    ADD CONSTRAINT os_deal_contacts_os_deals_id_foreign FOREIGN KEY (os_deals_id) REFERENCES public.os_deals(id) ON DELETE CASCADE;


--
-- Name: os_deal_stages os_deal_stages_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deal_stages
    ADD CONSTRAINT os_deal_stages_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_deal_stages os_deal_stages_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deal_stages
    ADD CONSTRAINT os_deal_stages_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_deals os_deals_deal_stage_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deals
    ADD CONSTRAINT os_deals_deal_stage_foreign FOREIGN KEY (deal_stage) REFERENCES public.os_deal_stages(id) ON DELETE SET NULL;


--
-- Name: os_deals os_deals_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deals
    ADD CONSTRAINT os_deals_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: os_deals os_deals_owner_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deals
    ADD CONSTRAINT os_deals_owner_foreign FOREIGN KEY (owner) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: os_deals os_deals_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deals
    ADD CONSTRAINT os_deals_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_deals os_deals_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_deals
    ADD CONSTRAINT os_deals_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_email_templates os_email_templates_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_email_templates
    ADD CONSTRAINT os_email_templates_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_email_templates os_email_templates_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_email_templates
    ADD CONSTRAINT os_email_templates_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_expenses os_expenses_file_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_expenses
    ADD CONSTRAINT os_expenses_file_foreign FOREIGN KEY (file) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: os_expenses os_expenses_invoice_item_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_expenses
    ADD CONSTRAINT os_expenses_invoice_item_foreign FOREIGN KEY (invoice_item) REFERENCES public.os_invoice_items(id);


--
-- Name: os_expenses os_expenses_project_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_expenses
    ADD CONSTRAINT os_expenses_project_foreign FOREIGN KEY (project) REFERENCES public.os_projects(id) ON DELETE SET NULL;


--
-- Name: os_expenses os_expenses_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_expenses
    ADD CONSTRAINT os_expenses_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_expenses os_expenses_user_submitted_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_expenses
    ADD CONSTRAINT os_expenses_user_submitted_foreign FOREIGN KEY (user_submitted) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: os_expenses os_expenses_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_expenses
    ADD CONSTRAINT os_expenses_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_invoice_items os_invoice_items_billable_expense_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoice_items
    ADD CONSTRAINT os_invoice_items_billable_expense_foreign FOREIGN KEY (billable_expense) REFERENCES public.os_expenses(id) ON DELETE SET NULL;


--
-- Name: os_invoice_items os_invoice_items_invoice_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoice_items
    ADD CONSTRAINT os_invoice_items_invoice_foreign FOREIGN KEY (invoice) REFERENCES public.os_invoices(id) ON DELETE CASCADE;


--
-- Name: os_invoice_items os_invoice_items_item_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoice_items
    ADD CONSTRAINT os_invoice_items_item_foreign FOREIGN KEY (item) REFERENCES public.os_items(id);


--
-- Name: os_invoice_items os_invoice_items_tax_rate_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoice_items
    ADD CONSTRAINT os_invoice_items_tax_rate_foreign FOREIGN KEY (tax_rate) REFERENCES public.os_tax_rates(id) ON DELETE SET NULL;


--
-- Name: os_invoice_items os_invoice_items_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoice_items
    ADD CONSTRAINT os_invoice_items_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_invoice_items os_invoice_items_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoice_items
    ADD CONSTRAINT os_invoice_items_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_invoices os_invoices_contact_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoices
    ADD CONSTRAINT os_invoices_contact_foreign FOREIGN KEY (contact) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: os_invoices os_invoices_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoices
    ADD CONSTRAINT os_invoices_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: os_invoices os_invoices_project_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoices
    ADD CONSTRAINT os_invoices_project_foreign FOREIGN KEY (project) REFERENCES public.os_projects(id) ON DELETE SET NULL;


--
-- Name: os_invoices os_invoices_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoices
    ADD CONSTRAINT os_invoices_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_invoices os_invoices_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_invoices
    ADD CONSTRAINT os_invoices_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_items os_items_default_tax_rate_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_items
    ADD CONSTRAINT os_items_default_tax_rate_foreign FOREIGN KEY (default_tax_rate) REFERENCES public.os_tax_rates(id) ON DELETE SET NULL;


--
-- Name: os_items os_items_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_items
    ADD CONSTRAINT os_items_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_items os_items_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_items
    ADD CONSTRAINT os_items_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_payment_terms os_payment_terms_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payment_terms
    ADD CONSTRAINT os_payment_terms_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_payment_terms os_payment_terms_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payment_terms
    ADD CONSTRAINT os_payment_terms_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_payments os_payments_contact_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payments
    ADD CONSTRAINT os_payments_contact_foreign FOREIGN KEY (contact) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: os_payments os_payments_invoice_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payments
    ADD CONSTRAINT os_payments_invoice_foreign FOREIGN KEY (invoice) REFERENCES public.os_invoices(id) ON DELETE SET NULL;


--
-- Name: os_payments os_payments_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payments
    ADD CONSTRAINT os_payments_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: os_payments os_payments_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payments
    ADD CONSTRAINT os_payments_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_payments os_payments_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_payments
    ADD CONSTRAINT os_payments_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_project_contacts os_project_contacts_contacts_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_contacts
    ADD CONSTRAINT os_project_contacts_contacts_id_foreign FOREIGN KEY (contacts_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: os_project_contacts os_project_contacts_os_projects_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_contacts
    ADD CONSTRAINT os_project_contacts_os_projects_id_foreign FOREIGN KEY (os_projects_id) REFERENCES public.os_projects(id) ON DELETE CASCADE;


--
-- Name: os_project_templates os_project_templates_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_templates
    ADD CONSTRAINT os_project_templates_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_project_templates os_project_templates_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_templates
    ADD CONSTRAINT os_project_templates_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_project_updates os_project_updates_project_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_updates
    ADD CONSTRAINT os_project_updates_project_foreign FOREIGN KEY (project) REFERENCES public.os_projects(id) ON DELETE SET NULL;


--
-- Name: os_project_updates os_project_updates_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_updates
    ADD CONSTRAINT os_project_updates_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_project_updates os_project_updates_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_project_updates
    ADD CONSTRAINT os_project_updates_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_projects os_projects_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_projects
    ADD CONSTRAINT os_projects_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: os_projects os_projects_owner_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_projects
    ADD CONSTRAINT os_projects_owner_foreign FOREIGN KEY (owner) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: os_projects os_projects_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_projects
    ADD CONSTRAINT os_projects_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_projects os_projects_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_projects
    ADD CONSTRAINT os_projects_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_proposal_approvals os_proposal_approvals_contact_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_approvals
    ADD CONSTRAINT os_proposal_approvals_contact_foreign FOREIGN KEY (contact) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: os_proposal_approvals os_proposal_approvals_proposal_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_approvals
    ADD CONSTRAINT os_proposal_approvals_proposal_foreign FOREIGN KEY (proposal) REFERENCES public.os_proposals(id) ON DELETE CASCADE;


--
-- Name: os_proposal_approvals os_proposal_approvals_signature_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_approvals
    ADD CONSTRAINT os_proposal_approvals_signature_image_foreign FOREIGN KEY (signature_image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: os_proposal_approvals os_proposal_approvals_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_approvals
    ADD CONSTRAINT os_proposal_approvals_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_proposal_approvals os_proposal_approvals_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_approvals
    ADD CONSTRAINT os_proposal_approvals_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_proposal_blocks os_proposal_blocks_os_proposals_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_blocks
    ADD CONSTRAINT os_proposal_blocks_os_proposals_id_foreign FOREIGN KEY (os_proposals_id) REFERENCES public.os_proposals(id) ON DELETE SET NULL;


--
-- Name: os_proposal_blocks os_proposal_blocks_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_blocks
    ADD CONSTRAINT os_proposal_blocks_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_proposal_blocks os_proposal_blocks_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_blocks
    ADD CONSTRAINT os_proposal_blocks_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_proposal_contacts os_proposal_contacts_contacts_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_contacts
    ADD CONSTRAINT os_proposal_contacts_contacts_id_foreign FOREIGN KEY (contacts_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: os_proposal_contacts os_proposal_contacts_os_proposals_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposal_contacts
    ADD CONSTRAINT os_proposal_contacts_os_proposals_id_foreign FOREIGN KEY (os_proposals_id) REFERENCES public.os_proposals(id) ON DELETE CASCADE;


--
-- Name: os_proposals os_proposals_deal_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposals
    ADD CONSTRAINT os_proposals_deal_foreign FOREIGN KEY (deal) REFERENCES public.os_deals(id) ON DELETE SET NULL;


--
-- Name: os_proposals os_proposals_organization_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposals
    ADD CONSTRAINT os_proposals_organization_foreign FOREIGN KEY (organization) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: os_proposals os_proposals_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposals
    ADD CONSTRAINT os_proposals_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_proposals os_proposals_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_proposals
    ADD CONSTRAINT os_proposals_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_settings os_settings_organization_folder_root_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_settings
    ADD CONSTRAINT os_settings_organization_folder_root_foreign FOREIGN KEY (organization_folder_root) REFERENCES public.directus_folders(id) ON DELETE SET NULL;


--
-- Name: os_task_files os_task_files_directus_files_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_task_files
    ADD CONSTRAINT os_task_files_directus_files_id_foreign FOREIGN KEY (directus_files_id) REFERENCES public.directus_files(id) ON DELETE CASCADE;


--
-- Name: os_task_files os_task_files_os_tasks_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_task_files
    ADD CONSTRAINT os_task_files_os_tasks_id_foreign FOREIGN KEY (os_tasks_id) REFERENCES public.os_tasks(id) ON DELETE CASCADE;


--
-- Name: os_tasks os_tasks_assigned_to_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tasks
    ADD CONSTRAINT os_tasks_assigned_to_foreign FOREIGN KEY (assigned_to) REFERENCES public.directus_users(id) ON DELETE SET NULL;


--
-- Name: os_tasks os_tasks_form_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tasks
    ADD CONSTRAINT os_tasks_form_foreign FOREIGN KEY (form) REFERENCES public.forms(id) ON DELETE SET NULL;


--
-- Name: os_tasks os_tasks_project_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tasks
    ADD CONSTRAINT os_tasks_project_foreign FOREIGN KEY (project) REFERENCES public.os_projects(id) ON DELETE CASCADE;


--
-- Name: os_tasks os_tasks_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tasks
    ADD CONSTRAINT os_tasks_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_tasks os_tasks_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tasks
    ADD CONSTRAINT os_tasks_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: os_tax_rates os_tax_rates_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tax_rates
    ADD CONSTRAINT os_tax_rates_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: os_tax_rates os_tax_rates_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_tax_rates
    ADD CONSTRAINT os_tax_rates_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: page_blocks page_blocks_pages_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_blocks
    ADD CONSTRAINT page_blocks_pages_id_foreign FOREIGN KEY (pages_id) REFERENCES public.pages(id) ON DELETE SET NULL;


--
-- Name: page_blocks page_blocks_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_blocks
    ADD CONSTRAINT page_blocks_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: page_blocks page_blocks_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_blocks
    ADD CONSTRAINT page_blocks_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: pages_blog pages_blog_featured_post_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pages_blog
    ADD CONSTRAINT pages_blog_featured_post_foreign FOREIGN KEY (featured_post) REFERENCES public.posts(id) ON DELETE SET NULL;


--
-- Name: pages_blog pages_blog_seo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pages_blog
    ADD CONSTRAINT pages_blog_seo_foreign FOREIGN KEY (seo) REFERENCES public.seo(id) ON DELETE SET NULL;


--
-- Name: pages_projects pages_projects_seo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pages_projects
    ADD CONSTRAINT pages_projects_seo_foreign FOREIGN KEY (seo) REFERENCES public.seo(id) ON DELETE SET NULL;


--
-- Name: pages pages_seo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_seo_foreign FOREIGN KEY (seo) REFERENCES public.seo(id) ON DELETE SET NULL;


--
-- Name: post_gallery_items post_gallery_items_directus_files_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_gallery_items
    ADD CONSTRAINT post_gallery_items_directus_files_id_foreign FOREIGN KEY (directus_files_id) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: post_gallery_items post_gallery_items_posts_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_gallery_items
    ADD CONSTRAINT post_gallery_items_posts_id_foreign FOREIGN KEY (posts_id) REFERENCES public.posts(id) ON DELETE SET NULL;


--
-- Name: posts posts_author_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_author_foreign FOREIGN KEY (author) REFERENCES public.team(id) ON DELETE SET NULL;


--
-- Name: posts posts_category_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_category_foreign FOREIGN KEY (category) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- Name: posts posts_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_image_foreign FOREIGN KEY (image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: posts posts_seo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_seo_foreign FOREIGN KEY (seo) REFERENCES public.seo(id) ON DELETE SET NULL;


--
-- Name: power_consumption power_consumption_consumption_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_consumption
    ADD CONSTRAINT power_consumption_consumption_code_fkey FOREIGN KEY (consumption_code) REFERENCES public.consumption_dataset(consumption_code);


--
-- Name: power_consumption_res power_consumption_res_consumption_code_res_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_consumption_res
    ADD CONSTRAINT power_consumption_res_consumption_code_res_fkey FOREIGN KEY (consumption_code_res) REFERENCES public.pcr_dataset(pcr_code);


--
-- Name: ppc ppc_ppc_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppc
    ADD CONSTRAINT ppc_ppc_code_fkey FOREIGN KEY (ppc_code) REFERENCES public.ppc_dataset(ppc_code);


--
-- Name: ppc ppc_ppc_code_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppc
    ADD CONSTRAINT ppc_ppc_code_fkey1 FOREIGN KEY (ppc_code) REFERENCES public.ppc_dataset(ppc_code);


--
-- Name: redirects redirects_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redirects
    ADD CONSTRAINT redirects_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: redirects redirects_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redirects
    ADD CONSTRAINT redirects_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: scenario scenario_consumption_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_consumption_code_fkey FOREIGN KEY (consumption_code) REFERENCES public.consumption_dataset(consumption_code);


--
-- Name: scenario scenario_lcc_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_lcc_code_fkey FOREIGN KEY (lcc_code) REFERENCES public.lcc_dataset(lcc_code);


--
-- Name: scenario scenario_lcr_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_lcr_code_fkey FOREIGN KEY (lcr_code) REFERENCES public.lcr_dataset(lcr_code);


--
-- Name: scenario scenario_pcr_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_pcr_code_fkey FOREIGN KEY (pcr_code) REFERENCES public.pcr_dataset(pcr_code);


--
-- Name: scenario scenario_ppc_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_ppc_code_fkey FOREIGN KEY (ppc_code) REFERENCES public.ppc_dataset(ppc_code);


--
-- Name: scenario scenario_site_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_site_foreign FOREIGN KEY (site) REFERENCES public.site(id) ON DELETE SET NULL;


--
-- Name: scenario scenario_solar_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_solar_code_fkey FOREIGN KEY (solar_code) REFERENCES public.solar_dataset(solar_code);


--
-- Name: scenario scenario_spot_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scenario
    ADD CONSTRAINT scenario_spot_code_fkey FOREIGN KEY (spot_code) REFERENCES public.spot_dataset(spot_code);


--
-- Name: site_files site_files_directus_files_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_files
    ADD CONSTRAINT site_files_directus_files_id_foreign FOREIGN KEY (directus_files_id) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: site_files site_files_site_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_files
    ADD CONSTRAINT site_files_site_id_foreign FOREIGN KEY (site_id) REFERENCES public.site(id) ON DELETE SET NULL;


--
-- Name: solar solar_solar_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solar
    ADD CONSTRAINT solar_solar_code_fkey FOREIGN KEY (solar_code) REFERENCES public.solar_dataset(solar_code);


--
-- Name: spot_prices_gen spot_prices_gen_spot_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spot_prices_gen
    ADD CONSTRAINT spot_prices_gen_spot_code_fkey FOREIGN KEY (spot_code) REFERENCES public.spot_dataset(spot_code);


--
-- Name: team team_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_image_foreign FOREIGN KEY (image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: team team_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: team team_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- Name: testimonials testimonials_company_logo_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.testimonials
    ADD CONSTRAINT testimonials_company_logo_foreign FOREIGN KEY (company_logo) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: testimonials testimonials_image_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.testimonials
    ADD CONSTRAINT testimonials_image_foreign FOREIGN KEY (image) REFERENCES public.directus_files(id) ON DELETE SET NULL;


--
-- Name: testimonials testimonials_user_created_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.testimonials
    ADD CONSTRAINT testimonials_user_created_foreign FOREIGN KEY (user_created) REFERENCES public.directus_users(id);


--
-- Name: testimonials testimonials_user_updated_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.testimonials
    ADD CONSTRAINT testimonials_user_updated_foreign FOREIGN KEY (user_updated) REFERENCES public.directus_users(id);


--
-- PostgreSQL database dump complete
--

