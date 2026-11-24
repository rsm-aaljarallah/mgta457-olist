-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     05_metric_view.sql
-- Owner:    TODO name
-- Purpose:  One Unity Catalog metric view, delivery_metrics, that
--           holds every rate the dashboards show. Each measure is
--           defined once here, and Databricks recalculates it for
--           whatever filters and groupings a dashboard uses.
-- Run:      After 04_gold.sql. Rebuilds the metric view. Safe to
--           rerun. 06_checks.sql tests it against fact_orders.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24, following
--           the metric view of the Chord project
--           (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================

-- Why a metric view and not a normal view: a rate such as broken
-- promises / judged orders cannot be stored at one grain and then
-- filtered. If a normal view held one rate per month, a filter on
-- customer region could not change it. A metric view stores the
-- formula, not the answer, so the rate is recalculated for each
-- filter and grouping.
--
-- Three kinds of order appear below (see the top of 04_gold.sql):
--   all orders     every order in fact_orders
--   in window      bought from Jan 2017 and promised by Aug 31, 2018
--   judged         in window, not canceled or unavailable, delivery
--                  date known. Every broken-promise rate uses these.
-- The low-review measures count every order in the window, canceled
-- ones too, because a bad review of a canceled order is still part
-- of the bad-review pile the Head of Customer Experience owns.
--
-- Every rate uses TRY_DIVIDE, which gives an empty value instead of an
-- error when a filter leaves no order to divide by (for example 2016,
-- which has no judged order).
--
-- The join key 'on' is in quotes because YAML 1.1 readers take the
-- bare word on as the value true (same as in the Chord project).

CREATE OR REPLACE VIEW olist.analytics.delivery_metrics
WITH METRICS
LANGUAGE YAML
AS $$
  version: 1.1
  comment: "Olist delivery-promise metrics. Grain of the source: one row per order (fact_orders)."
  source: olist.analytics.fact_orders

  joins:
    - name: customer_geo
      source: olist.analytics.dim_state
      'on': source.customer_state = customer_geo.state
    - name: seller_geo
      source: olist.analytics.dim_state
      'on': source.seller_state = seller_geo.state
    - name: dates
      source: olist.analytics.dim_date
      'on': source.purchase_date = dates.date_key

  dimensions:
    - name: purchase_month
      expr: dates.month_start
      comment: "First day of the month the order was bought"
    - name: purchase_year
      expr: dates.year
      comment: "Year the order was bought"
    - name: is_busy_month
      expr: dates.is_busy_month
      comment: "Bought in a busy month (gold_months): Nov 2017, Feb 2018, Mar 2018"
    - name: customer_state
      expr: source.customer_state
      comment: "Customer state, two letters"
    - name: customer_region
      expr: customer_geo.region
      comment: "Customer region (IBGE): North, Northeast, Southeast, South, Center-West"
    - name: customer_area
      expr: customer_geo.area
      comment: "Customer region with the Southeast split into Rio de Janeiro and the rest"
    - name: seller_state
      expr: source.seller_state
      comment: "Seller state; empty for orders shipped by several sellers"
    - name: seller_region
      expr: seller_geo.region
      comment: "Seller region; empty for orders shipped by several sellers"
    - name: route
      expr: source.route
      comment: "Seller state > customer state; single-seller orders only"
    - name: seller_location
      expr: "CASE WHEN source.seller_count <> 1 THEN 'Several sellers' WHEN source.is_local_seller THEN 'Same state as customer' WHEN source.seller_state = 'SP' THEN 'Sao Paulo' ELSE 'Other state' END"
      comment: "Where the seller is, seen from the customer"
    - name: category
      expr: source.category
      comment: "Product category (English) of the order's first item"
    - name: order_status
      expr: source.order_status
      comment: "Order status as recorded"
    - name: promise_outcome
      expr: "CASE WHEN NOT source.is_judged THEN 'Not judged' WHEN source.is_broken = 1 THEN 'Broken' ELSE 'Kept' END"
      comment: "Broken or kept, for judged orders"
    - name: promise_bucket
      expr: source.promise_bucket
      comment: "Days before or after the promised day, grouped"
    - name: promise_bucket_order
      expr: source.promise_bucket_order
      comment: "Sort order of promise_bucket, early to late"
    - name: promise_bucket_label
      expr: "COALESCE(CONCAT(CAST(source.promise_bucket_order AS STRING), '. ', source.promise_bucket), '9. Not delivered')"
      comment: "promise_bucket with its sort number in front, so a chart axis runs from early to late; orders never delivered come last"
    - name: delivery_time_band
      expr: "COALESCE(source.delivery_time_band, 'Not delivered')"
      comment: "Days from purchase to delivery, by week"

  measures:
    - name: orders
      expr: COUNT(1)
      comment: "All orders"
    - name: judged_orders
      expr: SUM(CASE WHEN source.is_judged THEN 1 ELSE 0 END)
      comment: "Orders whose promise can be judged"
    - name: broken_orders
      expr: SUM(source.is_broken)
      comment: "Judged orders not delivered by the end of the promised day"
    - name: broken_rate
      expr: TRY_DIVIDE(SUM(source.is_broken), SUM(CASE WHEN source.is_judged THEN 1 ELSE 0 END))
      comment: "Broken promises divided by judged orders"
    - name: broken_rate_margin
      expr: "1.96 * SQRT(TRY_DIVIDE(TRY_DIVIDE(SUM(source.is_broken), SUM(CASE WHEN source.is_judged THEN 1 ELSE 0 END)) * (1 - TRY_DIVIDE(SUM(source.is_broken), SUM(CASE WHEN source.is_judged THEN 1 ELSE 0 END))), SUM(CASE WHEN source.is_judged THEN 1 ELSE 0 END)))"
      comment: "95% margin of error of broken_rate, as a fraction (0.008 = plus or minus 0.8 points)"
    - name: broken_rate_if_3_days_later
      expr: TRY_DIVIDE(SUM(source.is_broken_if_3_days_later), SUM(CASE WHEN source.is_judged THEN 1 ELSE 0 END))
      comment: "The broken rate if every promise had been 3 days later"
    - name: share_broken_missed_by_1_to_3_days
      expr: TRY_DIVIDE(SUM(CASE WHEN source.is_broken = 1 AND source.days_vs_promise BETWEEN 1 AND 3 THEN 1 ELSE 0 END), SUM(source.is_broken))
      comment: "Share of broken promises that arrived 1 to 3 days late"
    - name: median_days_late
      expr: PERCENTILE(CASE WHEN source.is_broken = 1 THEN source.days_vs_promise END, 0.5)
      comment: "Median days late of broken promises that were delivered"
    - name: low_reviews
      expr: SUM(CASE WHEN source.is_in_window THEN source.is_low_review ELSE 0 END)
      comment: "Orders in the window whose latest review gives 1 or 2 stars"
    - name: low_reviews_after_broken_promise
      expr: SUM(CASE WHEN source.is_in_window AND source.is_broken = 1 THEN source.is_low_review ELSE 0 END)
      comment: "Of those, orders whose promise was broken"
    - name: share_low_reviews_after_broken_promise
      expr: TRY_DIVIDE(SUM(CASE WHEN source.is_in_window AND source.is_broken = 1 THEN source.is_low_review ELSE 0 END), SUM(CASE WHEN source.is_in_window THEN source.is_low_review ELSE 0 END))
      comment: "Share of 1-2 star reviews that follow a broken promise"
    - name: avg_review_score
      expr: AVG(CASE WHEN source.is_judged THEN source.review_score END)
      comment: "Average latest review score of judged orders"
    - name: avg_score_kept
      expr: AVG(CASE WHEN source.is_judged AND source.is_broken = 0 THEN source.review_score END)
      comment: "Average latest review score of judged orders that kept their promise"
    - name: avg_score_broken
      expr: AVG(CASE WHEN source.is_broken = 1 THEN source.review_score END)
      comment: "Average latest review score of broken promises"
    - name: share_late_reviewed_before_arrival
      expr: AVG(CASE WHEN source.is_broken = 1 THEN CAST(source.reviewed_before_arrival AS INT) END)
      comment: "Of delivered broken promises with a review, the share answered before the parcel arrived"
    - name: avg_score_late_before_arrival
      expr: AVG(CASE WHEN source.is_broken = 1 AND source.reviewed_before_arrival THEN source.review_score END)
      comment: "Average score of late orders reviewed before arrival"
    - name: avg_score_late_after_arrival
      expr: AVG(CASE WHEN source.is_broken = 1 AND NOT source.reviewed_before_arrival THEN source.review_score END)
      comment: "Average score of late orders reviewed after arrival"
    - name: share_late_handed_over_by_deadline
      expr: AVG(CASE WHEN source.is_broken = 1 AND source.delivered_ts IS NOT NULL THEN CAST(source.handed_over_by_deadline AS INT) END)
      comment: "Of delivered broken promises, the share the seller handed to the carrier by the deadline"
    - name: avg_days_to_carrier
      expr: AVG(CASE WHEN source.is_judged THEN source.days_to_carrier END)
      comment: "Average days from purchase to the carrier, judged orders"
    - name: avg_days_carrier_to_customer
      expr: AVG(CASE WHEN source.is_judged THEN source.days_carrier_to_customer END)
      comment: "Average days from the carrier to the customer, judged orders"
    - name: median_delivery_days
      expr: PERCENTILE(CASE WHEN source.is_judged THEN source.delivery_days END, 0.5)
      comment: "Median days from purchase to delivery, judged orders"
    - name: median_promised_days
      expr: PERCENTILE(CASE WHEN source.is_judged THEN source.promised_days END, 0.5)
      comment: "Median days promised at checkout, judged orders"
$$;

-- ------------------------------------------------------------
-- Check: the metric view must agree with fact_orders. A metric
-- view is queried with MEASURE(), not SELECT *.
-- Expected: 95,901 judged orders, 8,227 broken (8.58%).
-- ------------------------------------------------------------
SELECT
  'delivery_metrics matches fact_orders' AS check_name,
  CASE WHEN v.judged = f.judged AND v.broken = f.broken THEN 'PASS' ELSE 'FAIL' END AS result,
  v.judged AS metric_view_judged, f.judged AS fact_judged,
  v.broken AS metric_view_broken, f.broken AS fact_broken,
  ROUND(v.rate, 4) AS broken_rate
FROM (SELECT MEASURE(judged_orders) AS judged, MEASURE(broken_orders) AS broken, MEASURE(broken_rate) AS rate
      FROM olist.analytics.delivery_metrics) AS v
CROSS JOIN (SELECT SUM(CASE WHEN is_judged THEN 1 ELSE 0 END) AS judged, SUM(is_broken) AS broken
            FROM olist.analytics.fact_orders) AS f;

-- Example: the query behind Dashboard 2's line chart.
SELECT purchase_month, customer_area, MEASURE(broken_rate) AS broken_rate
FROM olist.analytics.delivery_metrics
WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY purchase_month, customer_area
ORDER BY purchase_month, customer_area;
