SELECT
  s.store_state,
  COUNT(DISTINCT s.store_id)::int AS store_count,
  CAST(SUM(sf.unit_sales) AS DECIMAL(18,2)) AS unit_sales,
  CAST(SUM(sf.store_sales) AS DECIMAL(18,2)) AS total_sales,
  CAST(SUM(sf.store_sales - sf.store_cost) AS DECIMAL(18,2)) AS gross_profit
FROM sales_fact_1998 sf
JOIN store s ON sf.store_id = s.store_id
WHERE s.store_state IS NOT NULL
GROUP BY s.store_state
ORDER BY total_sales DESC
