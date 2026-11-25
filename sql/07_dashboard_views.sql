-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     07_dashboard_views.sql
-- Owner:    TODO name
-- Purpose:  The small views the dashboards read besides the metric
--           view. route_list and state_view pick, rename and round
--           columns of a Gold table; region_fairness asks the metric
--           view; deliveries_per_month and quarantine_summary count
--           rows of Gold and of the quarantine. So the dashboards
--           themselves never calculate. Percentages arrive on a 0 to
--           100 scale for tables, as in the Chord project.
-- Run:      After 06_checks.sql. Safe to rerun.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24
--           (see docs/ai_usage.md).
--           Revised with Claude, 2026-11-24, after an audit: two views
--           now read the metric view and Gold dates, and route_list
--           shows a dash for the margin of routes under 100 orders.
--           Reviewed and understood by: TODO name
-- ============================================================

-- Dashboard 2, table 1: the routes to fix first. Only routes with
-- more broken promises than the national rate predicts.
CREATE OR REPLACE VIEW olist.analytics.route_list
COMMENT 'Dashboard 2. Routes with excess broken promises, ranked, with rate, margin, fix type and first step.'
AS
SELECT
  excess_rank,
  route,
  seller_state,
  customer_state,
  customer_region,
  orders,
  broken_orders,
  ROUND(100 * broken_rate, 1)   AS broken_pct,
  -- The margin formula is not reliable on a handful of orders (it is
  -- 0 when every order broke), so under 100 orders, the same floor as
  -- the fix type, the table shows a dash instead. The column is text so
  -- that the dashboard prints the dash, not the word "null".
  CASE WHEN orders >= 100 THEN CAST(ROUND(100 * margin, 1) AS STRING) ELSE '–' END AS margin_pts,
  ROUND(excess_broken, 0)       AS excess_broken,
  ROUND(100 * rate_other, 1)    AS broken_pct_outside_busy_months,
  fix_type,
  first_step
FROM olist.analytics.gold_routes
WHERE excess_broken > 0;

-- Dashboard 2, page 2: rows set aside, by table and reason.
CREATE OR REPLACE VIEW olist.analytics.quarantine_summary
COMMENT 'Dashboard 2, trust page. Rows set aside in Silver, by table and reason.'
AS
SELECT concat(source_table, ': ', reason) AS table_and_reason, COUNT(*) AS row_count
FROM olist.analytics.quarantine
GROUP BY source_table, reason;

-- Dashboard 2, page 2: deliveries recorded per month, every month in
-- the data. This is why the analysis stops in August 2018. It counts
-- the delivery days stored in Gold, so the result does not depend on
-- the time zone of the session that reads it.
CREATE OR REPLACE VIEW olist.analytics.deliveries_per_month
COMMENT 'Dashboard 2, trust page. Orders delivered per calendar month of delivery, all months in the data.'
AS
SELECT CAST(date_trunc('month', delivered_date) AS DATE) AS delivery_month,
       COUNT(*) AS deliveries
FROM olist.analytics.fact_orders
WHERE delivered_date IS NOT NULL
GROUP BY 1;

-- Dashboard 2, page 2: the fairness check. Broken-promise rate of
-- each customer region with its 95% margin. It asks the metric view,
-- so the rate and its margin have one definition, not two.
CREATE OR REPLACE VIEW olist.analytics.region_fairness
COMMENT 'Dashboard 2, trust page. Broken-promise rate by customer region with its 95% margin, in points.'
AS
SELECT
  customer_region                               AS region,
  MEASURE(judged_orders)                        AS judged_orders,
  MEASURE(broken_orders)                        AS broken_orders,
  ROUND(100 * MEASURE(broken_rate), 1)          AS broken_pct,
  ROUND(100 * MEASURE(broken_rate_margin), 1)   AS margin_pts
FROM olist.analytics.delivery_metrics
GROUP BY customer_region;

-- Dashboard 3: one row per state, percentages on a 0 to 100 scale.
CREATE OR REPLACE VIEW olist.analytics.state_view
COMMENT 'Dashboard 3. One row per state: orders per 100,000 residents, broken rate, sellers per million, and shares of orders, sellers and funnel recruits.'
AS
SELECT
  state,
  state_name,
  region,
  ROUND(orders_per_100k_12m, 1)                 AS orders_per_100k,
  ROUND(100 * broken_rate, 1)                   AS broken_pct,
  ROUND(active_sellers_per_million_12m, 1)      AS active_sellers_per_million,
  ROUND(100 * share_from_other_state_12m, 1)    AS pct_orders_from_other_state,
  ROUND(100 * share_of_orders_12m, 1)           AS pct_of_orders,
  ROUND(100 * share_of_sellers, 1)              AS pct_of_sellers,
  ROUND(100 * share_of_funnel_sellers, 1)       AS pct_of_funnel_recruits
FROM olist.analytics.gold_states;

SELECT * FROM olist.analytics.route_list ORDER BY excess_rank LIMIT 12;
SELECT * FROM olist.analytics.region_fairness ORDER BY broken_pct DESC;
SELECT * FROM olist.analytics.state_view ORDER BY pct_of_orders DESC LIMIT 8;
