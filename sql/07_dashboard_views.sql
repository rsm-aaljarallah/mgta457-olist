-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     07_dashboard_views.sql
-- Owner:    TODO name
-- Purpose:  The small views the dashboards read besides the metric
--           view. Each one only picks, renames and rounds columns
--           of a Gold table, so the dashboards themselves never
--           calculate. Percentages arrive on a 0 to 100 scale for
--           tables, as in the Chord project.
-- Run:      After 06_checks.sql. Safe to rerun.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24
--           (see docs/ai_usage.md).
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
  ROUND(100 * margin, 1)        AS margin_pts,
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
-- the data. This is why the analysis stops in August 2018.
CREATE OR REPLACE VIEW olist.analytics.deliveries_per_month
COMMENT 'Dashboard 2, trust page. Orders delivered per calendar month of delivery, all months in the data.'
AS
SELECT CAST(date_trunc('month', delivered_ts) AS DATE) AS delivery_month,
       COUNT(*) AS deliveries
FROM olist.analytics.silver_orders
WHERE delivered_ts IS NOT NULL
GROUP BY 1;

-- Dashboard 2, page 2: the fairness check. Broken-promise rate of
-- each customer region with its 95% margin.
CREATE OR REPLACE VIEW olist.analytics.region_fairness
COMMENT 'Dashboard 2, trust page. Broken-promise rate by customer region with its 95% margin, in points.'
AS
SELECT
  s.region,
  SUM(CASE WHEN f.is_judged THEN 1 ELSE 0 END)                       AS judged_orders,
  SUM(f.is_broken)                                                   AS broken_orders,
  ROUND(100 * SUM(f.is_broken) / SUM(CASE WHEN f.is_judged THEN 1 ELSE 0 END), 1) AS broken_pct,
  ROUND(100 * 1.96 * sqrt(
      (SUM(f.is_broken) / SUM(CASE WHEN f.is_judged THEN 1 ELSE 0 END))
    * (1 - SUM(f.is_broken) / SUM(CASE WHEN f.is_judged THEN 1 ELSE 0 END))
    / SUM(CASE WHEN f.is_judged THEN 1 ELSE 0 END)), 1)              AS margin_pts
FROM olist.analytics.fact_orders AS f
JOIN olist.analytics.dim_state AS s ON s.state = f.customer_state
GROUP BY s.region;

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
