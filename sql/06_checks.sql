-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     06_checks.sql
-- Owner:    TODO name
-- Purpose:  The audit step of write, audit, publish. Run after 03,
--           04 and 05, and before anyone opens a dashboard. Builds
--           three views:
--             pipeline_checks      one row per check; every row
--                                  should say PASS
--             silver_rule_counts   one row per Silver rule with the
--                                  rows it fixed, kept, flagged or set
--                                  aside (Dashboard 2, "Can we trust it")
--             design_doc_numbers   every headline number in
--                                  docs/design_doc.md, recomputed from
--                                  Gold, next to the number in the doc
-- Run:      Creates the three views and reads them. Safe to rerun.
--           The views are recalculated every time they are read, so
--           the trust page always shows the current build.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24, following
--           the checks of the Chord project (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================

-- ------------------------------------------------------------
-- 1. Pipeline checks
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.pipeline_checks
COMMENT 'One row per pipeline check with its result. Every row should say PASS.'
AS

-- 1-4. Every raw row lands in Silver or in quarantine, never both,
--      never lost, for each table that has quarantine rules.
SELECT 1 AS check_no, 'orders: raw = silver + quarantine' AS check_name,
  CASE WHEN r.n = s.n + q.n THEN 'PASS' ELSE 'FAIL' END AS result,
  concat('raw ', r.n, ', silver ', s.n, ', quarantine ', q.n) AS detail
FROM (SELECT COUNT(*) n FROM olist.raw.orders) r
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.silver_orders) s
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.quarantine WHERE source_table = 'orders') q
UNION ALL
SELECT 2, 'order_items: raw = silver + quarantine',
  CASE WHEN r.n = s.n + q.n THEN 'PASS' ELSE 'FAIL' END,
  concat('raw ', r.n, ', silver ', s.n, ', quarantine ', q.n)
FROM (SELECT COUNT(*) n FROM olist.raw.order_items) r
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.silver_order_items) s
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.quarantine WHERE source_table = 'order_items') q
UNION ALL
SELECT 3, 'order_payments: raw = silver + quarantine',
  CASE WHEN r.n = s.n + q.n THEN 'PASS' ELSE 'FAIL' END,
  concat('raw ', r.n, ', silver ', s.n, ', quarantine ', q.n)
FROM (SELECT COUNT(*) n FROM olist.raw.order_payments) r
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.silver_order_payments) s
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.quarantine WHERE source_table = 'order_payments') q
UNION ALL
SELECT 4, 'order_reviews: raw = silver + quarantine',
  CASE WHEN r.n = s.n + q.n THEN 'PASS' ELSE 'FAIL' END,
  concat('raw ', r.n, ', silver ', s.n, ', quarantine ', q.n)
FROM (SELECT COUNT(*) n FROM olist.raw.order_reviews) r
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.silver_order_reviews) s
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.quarantine WHERE source_table = 'order_reviews') q

UNION ALL
-- 5. Quarantine rate against the class thresholds (warn 1%, escalate
--    3%, page 10%), over the four tables above.
SELECT 5, 'quarantine rate (orders, items, payments, reviews)',
  CASE WHEN 100.0 * q.n / r.n >= 10 THEN 'PAGE'
       WHEN 100.0 * q.n / r.n >= 3  THEN 'ESCALATE'
       WHEN 100.0 * q.n / r.n >= 1  THEN 'WARN'
       ELSE 'PASS' END,
  concat(q.n, ' of ', r.n, ' rows = ', ROUND(100.0 * q.n / r.n, 3), '%')
FROM (SELECT COUNT(*) n FROM olist.analytics.quarantine WHERE source_table <> 'geolocation') q
CROSS JOIN (SELECT (SELECT COUNT(*) FROM olist.raw.orders) + (SELECT COUNT(*) FROM olist.raw.order_items)
                 + (SELECT COUNT(*) FROM olist.raw.order_payments) + (SELECT COUNT(*) FROM olist.raw.order_reviews) AS n) r

UNION ALL
-- 6-12. Every key holds: one row per key in Silver and Gold.
SELECT 6, 'silver_orders: one row per order_id',
  CASE WHEN COUNT(*) = COUNT(DISTINCT order_id) THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' rows, ', COUNT(DISTINCT order_id), ' ids')
FROM olist.analytics.silver_orders
UNION ALL
SELECT 7, 'silver_order_items: one row per order_id + order_item_id',
  CASE WHEN COUNT(*) = COUNT(DISTINCT order_id, order_item_id) THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' rows, ', COUNT(DISTINCT order_id, order_item_id), ' keys')
FROM olist.analytics.silver_order_items
UNION ALL
SELECT 8, 'silver_order_reviews: one latest review per reviewed order',
  CASE WHEN SUM(CASE WHEN is_latest_for_order THEN 1 ELSE 0 END) = COUNT(DISTINCT order_id) THEN 'PASS' ELSE 'FAIL' END,
  concat(SUM(CASE WHEN is_latest_for_order THEN 1 ELSE 0 END), ' latest reviews, ', COUNT(DISTINCT order_id), ' orders')
FROM olist.analytics.silver_order_reviews
UNION ALL
SELECT 9, 'silver_geolocation: one row per zip prefix',
  CASE WHEN COUNT(*) = COUNT(DISTINCT zip_prefix) THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' rows, ', COUNT(DISTINCT zip_prefix), ' prefixes')
FROM olist.analytics.silver_geolocation
UNION ALL
SELECT 10, 'fact_orders: one row per Silver order',
  CASE WHEN f.n = f.d AND f.n = s.n THEN 'PASS' ELSE 'FAIL' END,
  concat('fact ', f.n, ' rows (', f.d, ' ids), silver ', s.n)
FROM (SELECT COUNT(*) n, COUNT(DISTINCT order_id) d FROM olist.analytics.fact_orders) f
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.silver_orders) s
UNION ALL
SELECT 11, 'fact_order_items: one row per Silver item line',
  CASE WHEN f.n = s.n THEN 'PASS' ELSE 'FAIL' END,
  concat('fact ', f.n, ', silver ', s.n)
FROM (SELECT COUNT(*) n FROM olist.analytics.fact_order_items) f
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.silver_order_items) s
UNION ALL
SELECT 12, 'dimensions: one row per key',
  CASE WHEN (SELECT COUNT(*) - COUNT(DISTINCT state) FROM olist.analytics.dim_state) = 0
        AND (SELECT COUNT(*) - COUNT(DISTINCT seller_id) FROM olist.analytics.dim_seller) = 0
        AND (SELECT COUNT(*) - COUNT(DISTINCT product_id) FROM olist.analytics.dim_product) = 0
        AND (SELECT COUNT(*) - COUNT(DISTINCT date_key) FROM olist.analytics.dim_date) = 0
       THEN 'PASS' ELSE 'FAIL' END,
  'dim_state, dim_seller, dim_product, dim_date'

UNION ALL
-- 13. No join inflated money: item value in Gold equals Silver, and
--     the order-level item value adds up to the same total (the +4.6%
--     trap of joining items to payments).
SELECT 13, 'item value is the same in Silver, fact_order_items and fact_orders',
  CASE WHEN s.v = i.v AND s.v = o.v THEN 'PASS' ELSE 'FAIL' END,
  concat('silver ', s.v, ', items ', i.v, ', orders ', o.v)
FROM (SELECT SUM(price) v FROM olist.analytics.silver_order_items) s
CROSS JOIN (SELECT SUM(price) v FROM olist.analytics.fact_order_items) i
CROSS JOIN (SELECT SUM(item_value) v FROM olist.analytics.fact_orders) o

UNION ALL
-- 14. Every order and every seller points to a state in dim_state.
SELECT 14, 'every customer and seller state is in dim_state',
  CASE WHEN c.n = 0 AND s.n = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(c.n, ' orders and ', s.n, ' sellers without a known state')
FROM (SELECT COUNT(*) n FROM olist.analytics.fact_orders f LEFT ANTI JOIN olist.analytics.dim_state d ON d.state = f.customer_state) c
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.dim_seller x LEFT ANTI JOIN olist.analytics.dim_state d ON d.state = x.seller_state) s

UNION ALL
-- 15. IBGE: 27 states, every one with a population, 208,494,900 in all.
SELECT 15, 'dim_state: 27 states with their 2018 population',
  CASE WHEN COUNT(*) = 27 AND COUNT(population_2018) = 27 AND SUM(population_2018) = 208494900 THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' states, ', SUM(population_2018), ' people')
FROM olist.analytics.dim_state

UNION ALL
-- 16. "Late" is counted by calendar day: no judged order delivered on
--     its promised day is counted as broken.
SELECT 16, 'no order delivered on the promised day counts as broken',
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' orders')
FROM olist.analytics.fact_orders
WHERE is_broken = 1 AND delivered_date = promised_date

UNION ALL
-- 17. Only judged orders can be broken.
SELECT 17, 'only judged orders are counted as broken',
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' orders')
FROM olist.analytics.fact_orders
WHERE is_broken = 1 AND NOT is_judged

UNION ALL
-- 18. Routes exist only for single-seller orders (rule 13).
SELECT 18, 'no route on an order shipped by several sellers',
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' orders')
FROM olist.analytics.fact_orders
WHERE seller_count <> 1 AND route IS NOT NULL

UNION ALL
-- 19. The metric view agrees with fact_orders.
SELECT 19, 'delivery_metrics matches fact_orders',
  CASE WHEN v.j = f.j AND v.b = f.b THEN 'PASS' ELSE 'FAIL' END,
  concat('metric view ', v.j, ' judged / ', v.b, ' broken; fact ', f.j, ' / ', f.b)
FROM (SELECT MEASURE(judged_orders) j, MEASURE(broken_orders) b FROM olist.analytics.delivery_metrics) v
CROSS JOIN (SELECT SUM(CASE WHEN is_judged THEN 1 ELSE 0 END) j, SUM(is_broken) b FROM olist.analytics.fact_orders) f

UNION ALL
-- 20. Every route in gold_routes adds up to the judged single-seller
--     orders in fact_orders.
SELECT 20, 'gold_routes adds up to fact_orders',
  CASE WHEN r.n = f.n AND r.b = f.b THEN 'PASS' ELSE 'FAIL' END,
  concat('routes ', r.n, ' orders / ', r.b, ' broken; fact ', f.n, ' / ', f.b)
FROM (SELECT SUM(orders) n, SUM(broken_orders) b FROM olist.analytics.gold_routes) r
CROSS JOIN (SELECT COUNT(*) n, SUM(is_broken) b FROM olist.analytics.fact_orders WHERE is_judged AND seller_count = 1) f

UNION ALL
-- 21. The data window: no judged order was promised after the last
--     month with full delivery records.
SELECT 21, 'no judged order promised after 2018-08-31',
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' orders')
FROM olist.analytics.fact_orders
WHERE is_judged AND promised_date > DATE '2018-08-31';

SELECT * FROM olist.analytics.pipeline_checks ORDER BY check_no;

-- ------------------------------------------------------------
-- 2. Silver rule counts: one row per rule of
--    docs/data_quality_log.md, with the rows it touched today.
--    Dashboard 2, "Can we trust it", shows this table.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.silver_rule_counts
COMMENT 'One row per Silver rule: table, rule, action (FIX, KEEP, FLAG, QUARANTINE) and the rows it touched in the current build.'
AS
SELECT 1 AS rule_no, 'orders' AS table_name, 'Unreadable purchase date set aside' AS rule, 'QUARANTINE' AS action,
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'unreadable purchase date') AS row_count
UNION ALL SELECT 2, 'orders', 'Unknown order status set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'unknown order status')
UNION ALL SELECT 3, 'orders', 'Late counted by calendar day: delivered orders late by day', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE order_status = 'delivered' AND to_date(delivered_ts) > promised_date)
UNION ALL SELECT 4, 'orders', 'Delivered without a delivery date', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_delivered_without_date)
UNION ALL SELECT 5, 'orders', 'Canceled but has a delivery date', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_canceled_with_delivery)
UNION ALL SELECT 6, 'orders', 'Carrier date before purchase', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_carrier_before_purchase)
UNION ALL SELECT 7, 'orders', 'Carrier date before approval', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_carrier_before_approval)
UNION ALL SELECT 8, 'orders', 'Delivered before the carrier date', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_delivered_before_carrier)
UNION ALL SELECT 9, 'orders', 'Bought outside January 2017 to August 2018', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_outside_full_months)
UNION ALL SELECT 10, 'order_items', 'Repeated item line set aside', 'KEEP',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'repeated item line')
UNION ALL SELECT 11, 'order_items', 'Price missing or not above 0 set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'price missing, unreadable or not above 0')
UNION ALL SELECT 12, 'order_items', 'Seller deadline in 2019 or later', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_order_items WHERE flag_deadline_after_2018)
UNION ALL SELECT 13, 'orders', 'Items from two or more sellers', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_several_sellers)
UNION ALL SELECT 14, 'order_payments', 'Payment type not_defined set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'payment type not_defined')
UNION ALL SELECT 15, 'order_payments', 'Payments summed to one row per order before joining', 'KEEP',
       (SELECT COUNT(*) FROM olist.analytics.silver_order_payments)
UNION ALL SELECT 16, 'order_payments', 'Vouchers of 0.00 and 0 installments kept as they are', 'KEEP',
       (SELECT COUNT(*) FROM olist.analytics.silver_order_payments WHERE payment_value = 0 OR payment_installments = 0)
UNION ALL SELECT 17, 'order_reviews', 'A review covering several orders stays on each', 'KEEP',
       (SELECT COUNT(*) FROM (SELECT review_id FROM olist.analytics.silver_order_reviews GROUP BY review_id HAVING COUNT(*) > 1))
UNION ALL SELECT 18, 'order_reviews', 'Orders with several reviews keep the latest', 'KEEP',
       (SELECT COUNT(*) FROM (SELECT order_id FROM olist.analytics.silver_order_reviews GROUP BY order_id HAVING COUNT(*) > 1))
UNION ALL SELECT 19, 'order_reviews', 'Score outside 1 to 5 set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'review score not 1 to 5')
UNION ALL SELECT 20, 'customers', 'Zip prefix kept as 5-character text (starts with 0)', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_customers WHERE zip_prefix LIKE '0%')
-- Rule 21: customer and seller cities carry no accents in this data,
-- so today the rule changes no row there; the accents (73,442 raw rows)
-- are all in geolocation, whose city Silver does not keep. The count
-- is kept so the trust page shows if a new file brings accents in.
UNION ALL SELECT 21, 'customers, sellers', 'City matched without accents (customer and seller cities changed)', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_customers WHERE city_match <> lower(trim(city)))
       + (SELECT COUNT(*) FROM olist.analytics.silver_sellers WHERE city_match <> lower(trim(city)))
UNION ALL SELECT 22, 'products', 'Two misspelled column names renamed', 'FIX', 2
UNION ALL SELECT 23, 'products', 'Blank category becomes unknown', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_products WHERE category_pt = 'unknown')
UNION ALL SELECT 24, 'products', 'Category without English name keeps its Portuguese name', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_products p
        LEFT ANTI JOIN olist.raw.category_translation t ON t.product_category_name = p.category_pt
        WHERE p.category_pt <> 'unknown')
UNION ALL SELECT 25, 'geolocation', 'Exact copies removed', 'KEEP',
       (SELECT COUNT(*) FROM olist.raw.geolocation) - (SELECT COUNT(*) FROM olist.analytics.stg_geolocation)
UNION ALL SELECT 25, 'geolocation', 'Distinct points outside Brazil set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE source_table = 'geolocation')
UNION ALL SELECT 26, 'customers', 'Zip prefix not in geolocation', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_customers WHERE flag_zip_not_in_geolocation)
UNION ALL SELECT 26, 'sellers', 'Zip prefix not in geolocation', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_sellers WHERE flag_zip_not_in_geolocation)
UNION ALL SELECT 27, 'geolocation', 'State taken from customers and sellers, not geolocation', 'KEEP',
       (SELECT COUNT(*) FROM (SELECT zip_prefix FROM olist.analytics.stg_geolocation GROUP BY zip_prefix HAVING COUNT(DISTINCT state) > 1))
UNION ALL SELECT 28, 'leads', 'Blank origin becomes unknown', 'FIX',
       (SELECT COUNT(*) FROM olist.raw.leads WHERE origin IS NULL OR trim(origin) = '')
UNION ALL SELECT 29, 'closed_deals', 'Deal seller with no orders in the data', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_closed_deals WHERE flag_no_orders_in_data)
UNION ALL SELECT 30, 'closed_deals', 'Declared monthly revenue of 0 becomes empty', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_closed_deals WHERE declared_monthly_revenue IS NULL)
UNION ALL SELECT 31, 'ibge', 'Population unnested and joined to the state list', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_states WHERE population_2018 IS NOT NULL);

SELECT * FROM olist.analytics.silver_rule_counts ORDER BY rule_no;

-- ------------------------------------------------------------
-- 3. Design document numbers, recomputed from Gold.
--    doc_value is the number as printed in docs/design_doc.md
--    (2026-11-19). gold_value is today's build, rounded the same
--    way. MATCH means they agree; DIFFERS lists a number the doc
--    should be updated to (the conclusion is unchanged; see note).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.design_doc_numbers
COMMENT 'Every headline number of the design document, recomputed from Gold, next to the printed value.'
AS
WITH m AS (
  SELECT
    MEASURE(judged_orders)                          AS judged,
    MEASURE(broken_rate)                            AS rate,
    MEASURE(low_reviews)                            AS low,
    MEASURE(share_low_reviews_after_broken_promise) AS low_share,
    MEASURE(share_late_reviewed_before_arrival)     AS before_share,
    MEASURE(avg_score_late_before_arrival)          AS score_before,
    MEASURE(avg_score_late_after_arrival)           AS score_after,
    MEASURE(broken_rate_if_3_days_later)            AS rate3,
    MEASURE(share_broken_missed_by_1_to_3_days)     AS miss13,
    MEASURE(share_late_handed_over_by_deadline)     AS handed
  FROM olist.analytics.delivery_metrics
),
region AS (
  SELECT customer_region, MEASURE(broken_rate) AS rate, MEASURE(median_days_late) AS med_late
  FROM olist.analytics.delivery_metrics GROUP BY customer_region
),
quiet AS (
  SELECT customer_area, purchase_year, MEASURE(broken_rate) AS rate
  FROM olist.analytics.delivery_metrics WHERE NOT is_busy_month GROUP BY customer_area, purchase_year
),
bucket AS (
  SELECT promise_bucket, MEASURE(avg_review_score) AS score
  FROM olist.analytics.delivery_metrics GROUP BY promise_bucket
),
rio_local AS (
  SELECT seller_location, MEASURE(broken_rate) AS rate, MEASURE(broken_rate_margin) AS margin,
         MEASURE(median_delivery_days) AS days, MEASURE(judged_orders) AS n
  FROM olist.analytics.delivery_metrics WHERE customer_state = 'RJ' GROUP BY seller_location
),
route1 AS (SELECT * FROM olist.analytics.gold_routes WHERE excess_rank = 1),
months AS (
  SELECT MAX(median_rate) AS median_rate,
         SUM(CASE WHEN is_busy_month THEN judged_orders END) / SUM(judged_orders) AS busy_orders,
         SUM(CASE WHEN is_busy_month THEN broken_orders END) / SUM(broken_orders) AS busy_broken
  FROM olist.analytics.gold_months
),
v AS (
  SELECT 'Judged orders in the window' AS number, '95,901' AS doc_value, format_number(judged, 0) AS gold_value FROM m
  UNION ALL SELECT 'Broken-promise rate', '8.6%', concat(ROUND(100 * rate, 1), '%') FROM m
  UNION ALL SELECT '1-2 star reviews in the window', '14,205', format_number(low, 0) FROM m
  UNION ALL SELECT 'Share of 1-2 star reviews after a broken promise', '36.7%', concat(ROUND(100 * low_share, 1), '%') FROM m
  UNION ALL SELECT 'Late orders reviewed before arrival', '70.1%', concat(ROUND(100 * before_share, 1), '%') FROM m
  UNION ALL SELECT 'Score of late orders reviewed before arrival', '1.65', CAST(ROUND(score_before, 2) AS STRING) FROM m
  UNION ALL SELECT 'Score of late orders reviewed after arrival', '3.72', CAST(ROUND(score_after, 2) AS STRING) FROM m
  UNION ALL SELECT 'Score, delivered on the promised day', '4.03', (SELECT CAST(ROUND(score, 2) AS STRING) FROM bucket WHERE promise_bucket = 'On the day')
  UNION ALL SELECT 'Score, 1-3 days late', '3.29', (SELECT CAST(ROUND(score, 2) AS STRING) FROM bucket WHERE promise_bucket = '1-3 days late')
  UNION ALL SELECT 'Score, 4-7 days late', '2.10', (SELECT CAST(ROUND(score, 2) AS STRING) FROM bucket WHERE promise_bucket = '4-7 days late')
  UNION ALL SELECT 'Score range of early orders', '4.20 to 4.32',
    (SELECT concat(format_number(MIN(score), 2), ' to ', format_number(MAX(score), 2)) FROM bucket WHERE promise_bucket LIKE '%early')
  UNION ALL SELECT 'Top route', 'SP > RJ', route FROM route1
  UNION ALL SELECT 'Top route: orders', '8,071', format_number(orders, 0) FROM route1
  UNION ALL SELECT 'Top route: broken rate and margin', '17.1% +/- 0.8', concat(ROUND(100 * broken_rate, 1), '% +/- ', ROUND(100 * margin, 1)) FROM route1
  UNION ALL SELECT 'Top route: excess broken promises', '678', format_number(excess_broken, 0) FROM route1
  UNION ALL SELECT 'Top route: fix type', 'Both', fix_type FROM route1
  UNION ALL SELECT 'Next nine routes: excess together', '629',
    (SELECT format_number(SUM(excess_broken), 0) FROM olist.analytics.gold_routes WHERE excess_rank BETWEEN 2 AND 10)
  UNION ALL SELECT 'National rate, single-seller orders', '8.7%', concat(ROUND(100 * national_rate, 1), '%') FROM route1
  UNION ALL SELECT 'National rate outside busy months, single-seller', '6.4%', concat(ROUND(100 * national_rate_other, 1), '%') FROM route1
  UNION ALL SELECT 'Fix types named in the doc', 'BA, PE, PI lasting; PR > RJ, SP > SC busy-season',
    (SELECT concat_ws('; ', collect_list(concat(route, ' ', fix_type))) FROM olist.analytics.gold_routes
      WHERE route IN ('SP > BA', 'SP > PE', 'SP > PI', 'PR > RJ', 'SP > SC'))
  UNION ALL SELECT 'Median month', '6.85%', concat(ROUND(100 * median_rate, 2), '%') FROM months
  UNION ALL SELECT 'Busy months', 'Nov 2017, Feb 2018, Mar 2018',
    (SELECT concat_ws(', ', sort_array(collect_list(date_format(month_start, 'yyyy-MM')))) FROM olist.analytics.gold_months WHERE is_busy_month)
  UNION ALL SELECT 'Busy months: share of orders', '22.2%', concat(ROUND(100 * busy_orders, 1), '%') FROM months
  UNION ALL SELECT 'Busy months: share of broken promises', '42.9%', concat(ROUND(100 * busy_broken, 1), '%') FROM months
  UNION ALL SELECT 'Northeast, outside busy months, 2017 / 2018', '11.7% / 13.2%',
    (SELECT concat(ROUND(100 * MAX(CASE WHEN purchase_year = 2017 THEN rate END), 1), '% / ',
                   ROUND(100 * MAX(CASE WHEN purchase_year = 2018 THEN rate END), 1), '%')
     FROM quiet WHERE customer_area = 'Northeast')
  UNION ALL SELECT 'Southeast without Rio, outside busy months, 2017 / 2018', '4.8% / 5.1%',
    (SELECT concat(ROUND(100 * MAX(CASE WHEN purchase_year = 2017 THEN rate END), 1), '% / ',
                   ROUND(100 * MAX(CASE WHEN purchase_year = 2018 THEN rate END), 1), '%')
     FROM quiet WHERE customer_area = 'Southeast without Rio')
  UNION ALL SELECT 'Promise 3 days later: broken rate', '6.6%', concat(ROUND(100 * rate3, 1), '%') FROM m
  UNION ALL SELECT 'Broken promises missed by 1 to 3 days', '22.7%', concat(ROUND(100 * miss13, 1), '%') FROM m
  UNION ALL SELECT 'Late deliveries handed over by the seller deadline', '72.2%', concat(ROUND(100 * handed, 1), '%') FROM m
  UNION ALL SELECT 'Northeast vs Southeast broken rate', '15.6% vs 7.8%',
    concat((SELECT ROUND(100 * rate, 1) FROM region WHERE customer_region = 'Northeast'), '% vs ',
           (SELECT ROUND(100 * rate, 1) FROM region WHERE customer_region = 'Southeast'), '%')
  UNION ALL SELECT 'Northeast: median days late', '8', (SELECT CAST(CAST(med_late AS INT) AS STRING) FROM region WHERE customer_region = 'Northeast')
  UNION ALL SELECT 'Rio vs Sao Paulo: orders per 100,000 (12 months)', '56.4 vs 71.7',
    concat((SELECT ROUND(orders_per_100k_12m, 1) FROM olist.analytics.gold_states WHERE state = 'RJ'), ' vs ',
           (SELECT ROUND(orders_per_100k_12m, 1) FROM olist.analytics.gold_states WHERE state = 'SP'))
  UNION ALL SELECT 'Rio vs Sao Paulo: active sellers per million', '8.5 vs 35.2',
    concat((SELECT ROUND(active_sellers_per_million_12m, 1) FROM olist.analytics.gold_states WHERE state = 'RJ'), ' vs ',
           (SELECT ROUND(active_sellers_per_million_12m, 1) FROM olist.analytics.gold_states WHERE state = 'SP'))
  UNION ALL SELECT 'Rio: orders from another state', '91.5%',
    (SELECT concat(ROUND(100 * share_from_other_state_12m, 1), '%') FROM olist.analytics.gold_states WHERE state = 'RJ')
  UNION ALL SELECT 'Rio: local sellers broken rate and margin', '7.7% +/- 1.7',
    (SELECT concat(ROUND(100 * rate, 1), '% +/- ', ROUND(100 * margin, 1)) FROM rio_local WHERE seller_location = 'Same state as customer')
  UNION ALL SELECT 'Rio: median days, local vs Sao Paulo sellers', '5 vs 13',
    concat((SELECT CAST(days AS INT) FROM rio_local WHERE seller_location = 'Same state as customer'), ' vs ',
           (SELECT CAST(days AS INT) FROM rio_local WHERE seller_location = 'Sao Paulo'))
  UNION ALL SELECT 'Rio: share of single-seller orders from local sellers', '7.8%',
    concat(ROUND(100 * (SELECT n FROM rio_local WHERE seller_location = 'Same state as customer')
                 / (SELECT SUM(n) FROM rio_local WHERE seller_location <> 'Several sellers'), 1), '%')
  UNION ALL SELECT 'Sao Paulo: share of funnel sellers who sold / of all sellers', '61.1% / 59.7%',
    (SELECT concat(ROUND(100 * share_of_funnel_sellers, 1), '% / ', ROUND(100 * share_of_sellers, 1), '%') FROM olist.analytics.gold_states WHERE state = 'SP')
  UNION ALL SELECT 'Rio: share of orders / of funnel sellers', '12.7% / 6.8%',
    (SELECT concat(ROUND(100 * share_of_orders_12m, 1), '% / ', ROUND(100 * share_of_funnel_sellers, 1), '%') FROM olist.analytics.gold_states WHERE state = 'RJ')
)
SELECT
  number, doc_value, gold_value,
  CASE WHEN replace(doc_value, ',', '') = replace(gold_value, ',', '')
         OR (number = 'Fix types named in the doc'
             AND gold_value LIKE '%SP > BA Lasting fix%' AND gold_value LIKE '%SP > PE Lasting fix%'
             AND gold_value LIKE '%SP > PI Lasting fix%' AND gold_value LIKE '%PR > RJ Busy-season plan%'
             AND gold_value LIKE '%SP > SC Busy-season plan%')
         OR (number = 'Busy months' AND gold_value = '2017-11, 2018-02, 2018-03')
         OR (number = 'Score, 4-7 days late' AND gold_value = '2.1')
       THEN 'MATCH' ELSE 'DIFFERS' END AS result
FROM v;

SELECT * FROM olist.analytics.design_doc_numbers;
