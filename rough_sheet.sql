SELECT
  DATE_TRUNC('month', timestamp) AS month,
  COUNT(*) AS record_count
FROM
  power_consumption
GROUP BY
  month
ORDER BY
  month;


SELECT * FROM energy_summary_mv;
