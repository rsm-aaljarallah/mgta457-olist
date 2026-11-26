-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     09_alert_sp_rj.sql
-- Owner:    TODO name
-- Purpose:  The query behind the Databricks SQL alert "Olist: Sao
--           Paulo > Rio de Janeiro breaks twice the national rate".
--           It compares the route's broken-promise rate in the latest
--           month of the data with the national rate in that month.
--           The alert fires when the route breaks at least twice the
--           national rate: the same yardstick as the busy-month rule
--           in 04_gold.sql (a month is busy at twice the median).
--           Looking back, it would have fired for orders bought from
--           November 2017 to March 2018 (2.2 to 3.6 times the
--           national rate) and in no other month (at most 1.6 times).
--           On the latest month, August 2018, it reads 0.87: no alert.
-- Run:      By the alert, every Monday at 7:00 Pacific time, an hour
--           after the rebuild job. Read-only. tools/deploy_job.py
--           creates the alert from this file and jobs/alert_sp_rj.json.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-26
--           (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================
WITH latest AS (
  -- the latest purchase month in Gold
  SELECT MAX(month_start) AS month_start FROM olist.analytics.gold_months
),
route AS (
  SELECT MEASURE(judged_orders) AS judged_orders, MEASURE(broken_rate) AS broken_rate
  FROM olist.analytics.delivery_metrics
  WHERE route = 'SP > RJ' AND purchase_month = (SELECT month_start FROM latest)
),
national AS (
  SELECT MEASURE(broken_rate) AS broken_rate
  FROM olist.analytics.delivery_metrics
  WHERE purchase_month = (SELECT month_start FROM latest)
)
SELECT
  (SELECT month_start FROM latest) AS month_start,
  route.judged_orders              AS route_orders,
  route.broken_rate                AS route_rate,
  national.broken_rate             AS national_rate,
  -- Empty under 100 orders, where a rate is not reliable (the same
  -- 100-order rule as the route list), so the alert stays quiet.
  CASE WHEN route.judged_orders >= 100
       THEN ROUND(route.broken_rate / national.broken_rate, 2) END AS times_national_rate
FROM route CROSS JOIN national
