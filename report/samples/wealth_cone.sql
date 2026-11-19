SELECT to_char(DATE '2026-01-05' + (k * 7), 'YYYY-MM-DD') AS week_dt,
       round((w0 * exp(mu * t))::numeric, 2)::float8 AS median,
       CASE WHEN k <= 10
            THEN round((w0 * exp(mu * t + 0.012 * sin(k * 1.3) - 0.003 * k))::numeric, 2)::float8
       END AS actual,
       round((w0 * exp(mu * t - 1.00 * sigma * sqrt(t)))::numeric, 2)::float8 AS p66_lo,
       round((w0 * exp(mu * t + 1.00 * sigma * sqrt(t)))::numeric, 2)::float8 AS p66_hi,
       round((w0 * exp(mu * t - 1.96 * sigma * sqrt(t)))::numeric, 2)::float8 AS p95_lo,
       round((w0 * exp(mu * t + 1.96 * sigma * sqrt(t)))::numeric, 2)::float8 AS p95_hi
FROM (SELECT k, k / 52.0 AS t, 1220000.0 AS w0, 0.05 AS mu, 0.08 AS sigma
      FROM generate_series(0, 52) AS g(k)) p
ORDER BY k
