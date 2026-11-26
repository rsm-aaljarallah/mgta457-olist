-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     08_robustness.sql
-- Owner:    TODO name
-- Purpose:  Two questions a reader is likely to ask about the
--           findings, answered from Gold. Read-only: it creates
--           nothing, and each query lists the value we expect.
--             1. Is Sao Paulo to Rio's excess the route, or what Rio
--                buys and when? (docs/metric_dictionary.md, the
--                sensitivity table)
--             2. Do customers whose promise broke come back less?
--                Tested, and not claimed on any dashboard.
-- Run:      After 07_dashboard_views.sql, any time. Safe to rerun.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24
--           (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================

-- ------------------------------------------------------------
-- 1. Route or mix? gold_routes expects a route's broken promises
--    from one national rate (8.7%). Here each order expects the
--    national rate of its own product category in its own purchase
--    month instead, so a route that sells slow categories, or sells
--    in the busy months, expects more broken promises. The route's
--    own orders are part of those national rates, so the test leans
--    against the route. Judged single-seller orders, as in
--    gold_routes.
--    Expected: SP > RJ 678.4 with one national rate and 659.8 after
--    the adjustment, first either way; the next nine routes together
--    637.1 and 619.4. Ranks 2 to 9 hold the same eight routes (SP > AL
--    and SP > PE swap), and MG > RJ replaces SP > PA in tenth place.
-- ------------------------------------------------------------
WITH o AS (
  SELECT f.route, f.is_broken, f.category, date_trunc('month', f.purchase_date) AS m
  FROM olist.analytics.fact_orders AS f
  WHERE f.is_judged AND f.seller_count = 1
),
cell AS (
  SELECT category, m, AVG(is_broken) AS cell_rate
  FROM o GROUP BY category, m
),
nat AS (SELECT AVG(is_broken) AS rate_all FROM o),
r AS (
  SELECT o.route, COUNT(*) AS orders, SUM(o.is_broken) AS broken,
         SUM(c.cell_rate) AS expected_mix
  FROM o JOIN cell AS c ON c.category <=> o.category AND c.m = o.m
  GROUP BY o.route
),
ranked AS (
  SELECT r.route, r.orders, r.broken,
         r.broken - r.orders * n.rate_all AS excess_crude,
         r.broken - r.expected_mix        AS excess_mix,
         ROW_NUMBER() OVER (ORDER BY r.broken - r.orders * n.rate_all DESC, r.route) AS rank_crude,
         ROW_NUMBER() OVER (ORDER BY r.broken - r.expected_mix DESC, r.route)        AS rank_mix
  FROM r CROSS JOIN nat AS n
)
SELECT
  ROUND(MAX(CASE WHEN route = 'SP > RJ' THEN excess_crude END), 1)          AS sp_rj_one_rate,
  ROUND(MAX(CASE WHEN route = 'SP > RJ' THEN excess_mix END), 1)            AS sp_rj_adjusted,
  ROUND(SUM(CASE WHEN rank_crude BETWEEN 2 AND 10 THEN excess_crude END), 1) AS next_nine_one_rate,
  ROUND(SUM(CASE WHEN rank_mix BETWEEN 2 AND 10 THEN excess_mix END), 1)     AS next_nine_adjusted,
  array_join(transform(sort_array(collect_list(CASE WHEN rank_mix <= 10 THEN struct(rank_mix, route) END)),
                       s -> concat(s.rank_mix, ' ', s.route)), ', ')  AS top_ten_adjusted
FROM ranked;

-- ------------------------------------------------------------
-- 2. Repeat purchases. Each person's first order (customer_unique_id,
--    earliest purchase), if it is judged and was promised by
--    2018-02-28, so that 180 days after the promised day fall inside
--    the data. A return is another order bought after the promised
--    day, within 180 days of it, not canceled or unavailable. The
--    clock starts at the promised day, when the customer knows
--    whether the promise held.
--    Expected: kept 46,015 customers, 769 came back (1.67%); broken
--    3,789, 48 came back (1.27%). By region, the Southeast holds the
--    whole gap (1.81% against 1.05%); in the four other regions the
--    customers whose promise broke came back slightly more often. So
--    we do not claim a cost in repeat business: fewer than 2 in 100
--    customers return at all, and the gap is not consistent.
-- ------------------------------------------------------------
WITH o AS (
  SELECT f.order_id, f.customer_unique_id, f.purchase_ts, f.promised_date,
         f.is_judged, f.is_broken, f.order_status, s.region,
         ROW_NUMBER() OVER (PARTITION BY f.customer_unique_id
                            ORDER BY f.purchase_ts, f.order_id) AS rn
  FROM olist.analytics.fact_orders AS f
  LEFT JOIN olist.analytics.dim_state AS s ON s.state = f.customer_state
),
firsts AS (
  SELECT * FROM o WHERE rn = 1 AND is_judged AND promised_date <= DATE '2018-02-28'
),
rep AS (
  SELECT fr.customer_unique_id, fr.is_broken, fr.region,
         MAX(CASE WHEN o2.order_id IS NOT NULL THEN 1 ELSE 0 END) AS came_back
  FROM firsts AS fr
  LEFT JOIN o AS o2
    ON o2.customer_unique_id = fr.customer_unique_id
   AND o2.rn > 1
   AND to_date(o2.purchase_ts) > fr.promised_date
   AND to_date(o2.purchase_ts) <= date_add(fr.promised_date, 180)
   AND o2.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY fr.customer_unique_id, fr.is_broken, fr.region
)
SELECT COALESCE(region, 'All') AS region,
       CASE WHEN is_broken = 1 THEN 'Broken' ELSE 'Kept' END AS first_promise,
       COUNT(*) AS customers, SUM(came_back) AS came_back,
       ROUND(100 * AVG(came_back), 2) AS pct_came_back
FROM rep
GROUP BY GROUPING SETS ((is_broken), (region, is_broken))
ORDER BY region, first_promise DESC;
