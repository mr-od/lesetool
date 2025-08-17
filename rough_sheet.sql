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


SELECT
  tc.constraint_name,
  kcu.table_name   AS source_table,
  kcu.column_name  AS source_column,
  ccu.table_name   AS target_table,
  ccu.column_name  AS target_column,
  rc.update_rule,
  rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema   = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema   = tc.table_schema
JOIN information_schema.referential_constraints rc
  ON rc.constraint_name = tc.constraint_name
  AND rc.constraint_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND (kcu.table_name = 'scenario'  -- outgoing FKs
       OR ccu.table_name = 'scenario') -- incoming FKs
ORDER BY
  CASE WHEN kcu.table_name = 'scenario' THEN 1 ELSE 2 END,
  source_table;
