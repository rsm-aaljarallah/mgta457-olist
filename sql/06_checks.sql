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
--           the trust page always shows the current build. The last
--           statement is a gate: it fails the run if any pipeline
--           check is not PASS.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24, following
--           the checks of the Chord project. Revised with Claude,
--           2026-11-24, after an audit: checks 5, 7, 8, 9, 13 and 14
--           hardened, checks 22 to 24 added, 17 design-document
--           numbers added (see docs/ai_usage.md). Revised with
--           Claude, 2026-11-24: check 14 covers every declared key,
--           and the gate (section 4) was added.
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
--    3%, page 10%), over the four tables above. Empty raw tables are a
--    FAIL, and NULLIF keeps the division from stopping the view.
SELECT 5, 'quarantine rate (orders, items, payments, reviews)',
  CASE WHEN r.n = 0                         THEN 'FAIL'
       WHEN 100.0 * q.n / r.n >= 10         THEN 'PAGE'
       WHEN 100.0 * q.n / r.n >= 3          THEN 'ESCALATE'
       WHEN 100.0 * q.n / r.n >= 1          THEN 'WARN'
       ELSE 'PASS' END,
  concat(q.n, ' of ', r.n, ' rows = ', COALESCE(CAST(ROUND(100.0 * q.n / NULLIF(r.n, 0), 3) AS STRING), 'n/a'), '%')
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
-- 7. The keys of items, payments and reviews hold. A row with an empty
--    key part is not counted among the distinct keys, so it fails too.
SELECT 7, 'silver items, payments and reviews: one row per key',
  CASE WHEN i.n = i.k AND p.n = p.k AND r.n = r.k THEN 'PASS' ELSE 'FAIL' END,
  concat('items ', i.n, ' rows, ', i.k, ' keys; payments ', p.n, ', ', p.k,
         '; reviews ', r.n, ', ', r.k)
FROM (SELECT COUNT(*) n, COUNT(DISTINCT order_id, order_item_id) k FROM olist.analytics.silver_order_items) i
CROSS JOIN (SELECT COUNT(*) n, COUNT(DISTINCT order_id, payment_sequential) k FROM olist.analytics.silver_order_payments) p
CROSS JOIN (SELECT COUNT(*) n, COUNT(DISTINCT review_id, order_id) k FROM olist.analytics.silver_order_reviews) r
UNION ALL
-- 8. Each reviewed order has one latest review (rule 18), and no other
--    review of that order was answered later.
SELECT 8, 'silver_order_reviews: one latest review per reviewed order, the last answered',
  CASE WHEN l.n = l.orders AND x.n = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(l.n, ' latest reviews, ', l.orders, ' orders, ', x.n, ' with a later answer elsewhere')
FROM (SELECT SUM(CASE WHEN is_latest_for_order THEN 1 ELSE 0 END) n, COUNT(DISTINCT order_id) orders
      FROM olist.analytics.silver_order_reviews) l
CROSS JOIN (SELECT COUNT(*) n FROM (
              SELECT order_id, MAX(review_answer_ts) AS max_ts,
                     MAX(CASE WHEN is_latest_for_order THEN review_answer_ts END) AS latest_ts
              FROM olist.analytics.silver_order_reviews GROUP BY order_id)
            WHERE NOT (latest_ts <=> max_ts)) x
UNION ALL
-- 9. One row per zip prefix, and every distinct point is either kept in
--    a prefix's average or set aside in the quarantine (rule 25).
SELECT 9, 'silver_geolocation: one row per zip prefix, every point kept or set aside',
  CASE WHEN g.n = g.k AND g.pts + q.n = s.n THEN 'PASS' ELSE 'FAIL' END,
  concat(g.n, ' rows, ', g.k, ' prefixes; ', g.pts, ' points kept + ', q.n,
         ' set aside, of ', s.n, ' distinct points')
FROM (SELECT COUNT(*) n, COUNT(DISTINCT zip_prefix) k, SUM(distinct_points) pts FROM olist.analytics.silver_geolocation) g
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.quarantine WHERE source_table = 'geolocation') q
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.stg_geolocation) s
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
-- 13. No join inflated money: the price, freight and payment totals in
--     Gold equal Silver, at the item grain and at the order grain (the
--     +4.6% trap of joining items to payments).
SELECT 13, 'price, freight and payment totals are the same in Silver and Gold',
  CASE WHEN s.price = i.price AND s.price = o.price
        AND s.freight = i.freight AND s.freight = o.freight
        AND p.paid = o.paid THEN 'PASS' ELSE 'FAIL' END,
  concat('price ', s.price, ' / ', i.price, ' / ', o.price,
         '; freight ', s.freight, ' / ', i.freight, ' / ', o.freight,
         '; payments ', p.paid, ' / ', o.paid, ' (Silver / items / orders)')
FROM (SELECT SUM(price) price, SUM(freight_value) freight FROM olist.analytics.silver_order_items) s
CROSS JOIN (SELECT SUM(price) price, SUM(freight_value) freight FROM olist.analytics.fact_order_items) i
CROSS JOIN (SELECT SUM(item_value) price, SUM(freight_value) freight, SUM(payment_value) paid FROM olist.analytics.fact_orders) o
CROSS JOIN (SELECT SUM(payment_value) paid FROM olist.analytics.silver_order_payments) p

UNION ALL
-- 14. The star schema holds (04_gold.sql, section 10). Every one of the
--     15 foreign keys finds its row, and so does every seller's state;
--     an empty seller or route key, for an order with no single seller,
--     is allowed. The keys of the three rule tables and of the item
--     lines are not repeated (checks 10 and 12 cover the other tables).
--     And the 9 primary and 15 foreign keys are declared: a rebuild of
--     a table drops them, so a build that stopped before section 10
--     fails here. Unity Catalog does not enforce declared keys, so this
--     check does: the metric view joins on them, and an order without
--     a match would drop out of a filter.
SELECT 14, 'every key in Gold finds its row, and the 24 keys are declared',
  CASE WHEN o.n = 0 AND d.n = 0 AND c.pk = 9 AND c.fk = 15 THEN 'PASS' ELSE 'FAIL' END,
  concat(o.n, ' keys without a row, ', d.n, ' repeated keys; ',
         c.pk, ' primary and ', c.fk, ' foreign keys declared')
FROM (SELECT SUM(n) AS n FROM (
        SELECT COUNT(*) AS n FROM olist.analytics.fact_orders f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.customer_state
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_orders f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.seller_state WHERE f.seller_state IS NOT NULL
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_orders f LEFT ANTI JOIN olist.analytics.dim_seller x ON x.seller_id = f.seller_id WHERE f.seller_id IS NOT NULL
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_orders f LEFT ANTI JOIN olist.analytics.dim_date x ON x.date_key = f.purchase_date
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_orders f LEFT ANTI JOIN olist.analytics.dim_date x ON x.date_key = f.promised_date WHERE f.promised_date IS NOT NULL
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_orders f LEFT ANTI JOIN olist.analytics.dim_date x ON x.date_key = f.delivered_date WHERE f.delivered_date IS NOT NULL
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_order_items f LEFT ANTI JOIN olist.analytics.fact_orders x ON x.order_id = f.order_id
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_order_items f LEFT ANTI JOIN olist.analytics.dim_product x ON x.product_id = f.product_id
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_order_items f LEFT ANTI JOIN olist.analytics.dim_seller x ON x.seller_id = f.seller_id
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_order_items f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.seller_state
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_order_items f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.customer_state
        UNION ALL SELECT COUNT(*) FROM olist.analytics.fact_order_items f LEFT ANTI JOIN olist.analytics.dim_date x ON x.date_key = f.purchase_date
        UNION ALL SELECT COUNT(*) FROM olist.analytics.gold_routes f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.seller_state
        UNION ALL SELECT COUNT(*) FROM olist.analytics.gold_routes f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.customer_state
        UNION ALL SELECT COUNT(*) FROM olist.analytics.gold_states f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.state
        UNION ALL SELECT COUNT(*) FROM olist.analytics.dim_seller f LEFT ANTI JOIN olist.analytics.dim_state x ON x.state = f.seller_state)) o
CROSS JOIN (SELECT SUM(n) AS n FROM (
        SELECT COUNT(*) - COUNT(DISTINCT order_id, order_item_id) AS n FROM olist.analytics.fact_order_items
        UNION ALL SELECT COUNT(*) - COUNT(DISTINCT month_start) FROM olist.analytics.gold_months
        UNION ALL SELECT COUNT(*) - COUNT(DISTINCT route) FROM olist.analytics.gold_routes
        UNION ALL SELECT COUNT(*) - COUNT(DISTINCT state) FROM olist.analytics.gold_states)) d
CROSS JOIN (SELECT COUNT_IF(constraint_type = 'PRIMARY KEY') AS pk, COUNT_IF(constraint_type = 'FOREIGN KEY') AS fk
            FROM olist.information_schema.table_constraints WHERE table_schema = 'analytics') c

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
WHERE is_judged AND promised_date > DATE '2018-08-31'

UNION ALL
-- 22. The rates stored in Gold for a rule (months, routes, states) count
--     the same judged and broken orders as the metric view, and so does
--     each route's split between busy and other months, which decides
--     its fix type. A month, route or state missing on either side
--     counts as a difference. (The per-resident measures have no
--     counterpart in the metric view, so they are not compared.)
SELECT 22, 'stored month, route and state rates agree with the metric view',
  CASE WHEN m.bad + r.bad + rs.bad + s.bad = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(m.n, ' months, ', r.n, ' routes with their busy-month split, ', s.n, ' states compared; ',
         m.bad + r.bad + rs.bad + s.bad, ' differ')
FROM (SELECT COUNT(*) n,
             SUM(CASE WHEN g.judged_orders <=> v.j AND g.broken_orders <=> v.b THEN 0 ELSE 1 END) bad
      FROM olist.analytics.gold_months g
      FULL OUTER JOIN (SELECT * FROM (SELECT purchase_month k, MEASURE(judged_orders) j, MEASURE(broken_orders) b
                                      FROM olist.analytics.delivery_metrics GROUP BY purchase_month)
                       WHERE j > 0) v
        ON v.k = g.month_start) m
CROSS JOIN (SELECT COUNT(*) n,
             SUM(CASE WHEN g.orders <=> v.j AND g.broken_orders <=> v.b THEN 0 ELSE 1 END) bad
      FROM olist.analytics.gold_routes g
      FULL OUTER JOIN (SELECT * FROM (SELECT route k, MEASURE(judged_orders) j, MEASURE(broken_orders) b
                                      FROM olist.analytics.delivery_metrics GROUP BY route)
                       WHERE k IS NOT NULL AND j > 0) v
        ON v.k = g.route) r
CROSS JOIN (SELECT COUNT(*) n,
             SUM(CASE WHEN g.orders_busy <=> COALESCE(v.jb, 0) AND g.broken_busy <=> COALESCE(v.bb, 0)
                       AND g.orders_other <=> COALESCE(v.jo, 0) AND g.broken_other <=> COALESCE(v.bo, 0)
                      THEN 0 ELSE 1 END) bad
      FROM olist.analytics.gold_routes g
      LEFT JOIN (SELECT route k,
                        SUM(CASE WHEN busy THEN j ELSE 0 END) jb, SUM(CASE WHEN busy THEN b ELSE 0 END) bb,
                        SUM(CASE WHEN NOT busy THEN j ELSE 0 END) jo, SUM(CASE WHEN NOT busy THEN b ELSE 0 END) bo
                 FROM (SELECT route, is_busy_month AS busy, MEASURE(judged_orders) j, MEASURE(broken_orders) b
                       FROM olist.analytics.delivery_metrics GROUP BY route, is_busy_month)
                 WHERE route IS NOT NULL
                 GROUP BY route) v
        ON v.k = g.route) rs
CROSS JOIN (SELECT COUNT(*) n,
             SUM(CASE WHEN g.judged_orders <=> v.j AND g.broken_orders <=> v.b THEN 0 ELSE 1 END) bad
      FROM olist.analytics.gold_states g
      FULL OUTER JOIN (SELECT * FROM (SELECT customer_state k, MEASURE(judged_orders) j, MEASURE(broken_orders) b
                                      FROM olist.analytics.delivery_metrics GROUP BY customer_state)
                       WHERE j > 0) v
        ON v.k = g.state) s

UNION ALL
-- 23. Typing lost nothing: no value that was written in a raw file became
--     empty when Silver read it as a number or a date. Columns with a
--     quarantine rule of their own (purchase date, price, payment amount,
--     review score) are covered by that rule instead. The stg_ views keep
--     each raw row as JSON, so the raw text and the typed value sit side
--     by side; a raw blank is absent from the JSON, so it is not counted.
SELECT 23, 'nothing readable was lost when Silver typed the columns',
  CASE WHEN o.n + i.n + p.n + r.n + l.n + d.n + pr.n = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(o.n + i.n + p.n + r.n + l.n + d.n + pr.n, ' rows lost a value (orders ', o.n, ', items ', i.n,
         ', payments ', p.n, ', reviews ', r.n, ', leads ', l.n, ', deals ', d.n, ', products ', pr.n, ')')
FROM (SELECT COUNT(*) n FROM olist.analytics.stg_orders
      WHERE quarantine_reason IS NULL
        AND ((get_json_object(raw_row, '$.order_approved_at') IS NOT NULL AND approved_ts IS NULL)
          OR (get_json_object(raw_row, '$.order_delivered_carrier_date') IS NOT NULL AND carrier_ts IS NULL)
          OR (get_json_object(raw_row, '$.order_delivered_customer_date') IS NOT NULL AND delivered_ts IS NULL)
          OR (get_json_object(raw_row, '$.order_estimated_delivery_date') IS NOT NULL AND promised_date IS NULL))) o
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.stg_order_items
      WHERE quarantine_reason IS NULL
        AND ((get_json_object(raw_row, '$.order_item_id') IS NOT NULL AND order_item_id IS NULL)
          OR (get_json_object(raw_row, '$.shipping_limit_date') IS NOT NULL AND shipping_limit_ts IS NULL)
          OR (get_json_object(raw_row, '$.freight_value') IS NOT NULL AND freight_value IS NULL))) i
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.stg_order_payments
      WHERE quarantine_reason IS NULL
        AND ((get_json_object(raw_row, '$.payment_sequential') IS NOT NULL AND payment_sequential IS NULL)
          OR (get_json_object(raw_row, '$.payment_installments') IS NOT NULL AND payment_installments IS NULL))) p
CROSS JOIN (SELECT COUNT(*) n FROM olist.analytics.stg_order_reviews
      WHERE quarantine_reason IS NULL
        AND ((get_json_object(raw_row, '$.review_creation_date') IS NOT NULL AND review_creation_date IS NULL)
          OR (get_json_object(raw_row, '$.review_answer_timestamp') IS NOT NULL AND review_answer_ts IS NULL))) r
CROSS JOIN (SELECT COUNT(*) n FROM olist.raw.leads x JOIN olist.analytics.silver_leads y ON y.mql_id = x.mql_id
      WHERE x.first_contact_date IS NOT NULL AND y.first_contact_date IS NULL) l
CROSS JOIN (SELECT COUNT(*) n FROM olist.raw.closed_deals x JOIN olist.analytics.silver_closed_deals y ON y.mql_id = x.mql_id
      WHERE (x.won_date IS NOT NULL AND y.won_ts IS NULL)
         OR (x.declared_monthly_revenue IS NOT NULL AND TRY_CAST(x.declared_monthly_revenue AS DOUBLE) IS NULL)) d
CROSS JOIN (SELECT COUNT(*) n FROM olist.raw.products x JOIN olist.analytics.silver_products y ON y.product_id = x.product_id
      WHERE (x.product_name_lenght IS NOT NULL AND y.product_name_length IS NULL)
         OR (x.product_description_lenght IS NOT NULL AND y.product_description_length IS NULL)
         OR (x.product_photos_qty IS NOT NULL AND y.product_photos_qty IS NULL)
         OR (x.product_weight_g IS NOT NULL AND y.product_weight_g IS NULL)
         OR (x.product_length_cm IS NOT NULL AND y.product_length_cm IS NULL)
         OR (x.product_height_cm IS NOT NULL AND y.product_height_cm IS NULL)
         OR (x.product_width_cm IS NOT NULL AND y.product_width_cm IS NULL)) pr

UNION ALL
-- 24. The days in Gold are the days written in the files (assumption A4):
--     the purchase, promised and delivery days of every order equal the
--     first ten characters of the raw text. A session in another time
--     zone could otherwise shift a day when a timestamp is turned into a
--     date, and move an order between on time and late.
SELECT 24, 'purchase, promised and delivery days in Gold are the days written in the files',
  CASE WHEN SUM(CASE WHEN f.purchase_date <=> TRY_CAST(substr(r.order_purchase_timestamp, 1, 10) AS DATE)
                      AND f.promised_date <=> TRY_CAST(substr(r.order_estimated_delivery_date, 1, 10) AS DATE)
                      AND f.delivered_date <=> TRY_CAST(substr(r.order_delivered_customer_date, 1, 10) AS DATE)
                     THEN 0 ELSE 1 END) = 0 THEN 'PASS' ELSE 'FAIL' END,
  concat(COUNT(*), ' orders, ',
         SUM(CASE WHEN f.purchase_date <=> TRY_CAST(substr(r.order_purchase_timestamp, 1, 10) AS DATE)
                   AND f.promised_date <=> TRY_CAST(substr(r.order_estimated_delivery_date, 1, 10) AS DATE)
                   AND f.delivered_date <=> TRY_CAST(substr(r.order_delivered_customer_date, 1, 10) AS DATE)
                  THEN 0 ELSE 1 END), ' with a different day')
FROM olist.analytics.fact_orders f
JOIN olist.raw.orders r ON r.order_id = f.order_id;

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
UNION ALL SELECT 2, 'orders', 'Missing or unknown order status set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'unknown order status')
-- Rule 3 counts with the delivery day stored in Gold, so the count does
-- not depend on the time zone of the session that reads this view.
UNION ALL SELECT 3, 'orders', 'Late counted by calendar day: delivered orders late by day', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.fact_orders WHERE order_status = 'delivered' AND delivered_date > promised_date)
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
UNION ALL SELECT 10, 'order_items', 'Repeated item line: one copy kept, the others set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'repeated item line')
UNION ALL SELECT 11, 'order_items', 'Price missing or not above 0 set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason = 'price missing, unreadable or not above 0')
UNION ALL SELECT 12, 'order_items', 'Seller deadline in 2019 or later', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_order_items WHERE flag_deadline_after_2018)
UNION ALL SELECT 13, 'orders', 'Items from two or more sellers', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_orders WHERE flag_several_sellers)
UNION ALL SELECT 14, 'order_payments', 'Payment type not_defined, or an unreadable amount, set aside', 'QUARANTINE',
       (SELECT COUNT(*) FROM olist.analytics.quarantine WHERE reason IN ('payment type not_defined', 'unreadable payment value'))
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
-- Rule 21: the rule changes no customer city and 3 seller cities: one
-- "sao paulo" typed with a separate accent mark, and two "santa barbara
-- d'oeste" with an accent where the apostrophe belongs. Most accents
-- (73,442 raw rows) are in geolocation, whose city Silver does not keep.
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
UNION ALL SELECT 28, 'leads, closed_deals', 'Blank origin, segment or lead type becomes unknown', 'FIX',
       (SELECT COUNT(*) FROM olist.raw.leads WHERE origin IS NULL OR trim(origin) = '')
       + (SELECT COUNT(*) FROM olist.raw.closed_deals WHERE business_segment IS NULL OR lead_type IS NULL)
UNION ALL SELECT 29, 'closed_deals', 'Deal seller with no orders in the data', 'FLAG',
       (SELECT COUNT(*) FROM olist.analytics.silver_closed_deals WHERE flag_no_orders_in_data)
UNION ALL SELECT 30, 'closed_deals', 'Declared monthly revenue of 0 becomes empty', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_closed_deals WHERE declared_monthly_revenue IS NULL)
UNION ALL SELECT 31, 'ibge', 'Population unnested and joined to the state list', 'FIX',
       (SELECT COUNT(*) FROM olist.analytics.silver_states WHERE population_2018 IS NOT NULL);

SELECT * FROM olist.analytics.silver_rule_counts ORDER BY rule_no;

-- ------------------------------------------------------------
-- 3. Design document numbers, recomputed from Gold: every result the
--    design document prints (the facts about the raw data come from
--    02_profile_bronze.sql instead). doc_value is the number as printed
--    in docs/design_doc.md (version of 2026-11-24). gold_value is the
--    current build, rounded the same way. MATCH means they agree, and
--    DIFFERS means the document must be updated.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.design_doc_numbers
COMMENT 'Every result printed in the design document, recomputed from Gold, next to the printed value.'
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
-- Review scores of kept and broken promises, by delivery time (Dashboard 1)
band AS (
  SELECT delivery_time_band, MEASURE(avg_score_kept) AS kept, MEASURE(avg_score_broken) AS broken
  FROM olist.analytics.delivery_metrics GROUP BY delivery_time_band
),
-- Local against distant sellers, same customer state and product category,
-- outside Sao Paulo, where each side has at least 20 delivered orders
comparisons AS (
  SELECT customer_state, category,
         AVG(CASE WHEN is_local_seller THEN delivery_days END)     AS local_days,
         AVG(CASE WHEN NOT is_local_seller THEN delivery_days END) AS distant_days,
         SUM(CASE WHEN is_local_seller THEN 1 ELSE 0 END)          AS local_orders,
         SUM(CASE WHEN NOT is_local_seller THEN 1 ELSE 0 END)      AS distant_orders
  FROM olist.analytics.fact_orders
  WHERE is_judged AND seller_count = 1 AND delivery_days IS NOT NULL AND customer_state <> 'SP'
  GROUP BY customer_state, category
),
-- Deliveries per calendar month, from the delivery days in Gold
delivered_months AS (
  SELECT CAST(date_trunc('month', delivered_date) AS DATE) AS month_start, COUNT(*) AS deliveries
  FROM olist.analytics.fact_orders WHERE delivered_date IS NOT NULL GROUP BY 1
),
-- The routes again with the window ending a week earlier (promised by
-- 2018-08-24), to test that the top ten does not depend on the last week
early AS (
  SELECT route,
         SUM(is_broken) - COUNT(*) * (SELECT AVG(is_broken) FROM olist.analytics.fact_orders
                                      WHERE is_judged AND seller_count = 1 AND promised_date <= DATE '2018-08-24') AS excess
  FROM olist.analytics.fact_orders
  WHERE is_judged AND seller_count = 1 AND promised_date <= DATE '2018-08-24'
  GROUP BY route
),
early_top AS (SELECT route, ROW_NUMBER() OVER (ORDER BY excess DESC, route) AS rk FROM early),
-- Rio customers by seller location, busy months against the other months
rio_period AS (
  SELECT is_busy_month, seller_location, MEASURE(broken_rate) AS rate, MEASURE(median_delivery_days) AS days
  FROM olist.analytics.delivery_metrics WHERE customer_state = 'RJ' GROUP BY is_busy_month, seller_location
),
v AS (
  SELECT 'Judged orders in the window' AS number, '95,901' AS doc_value, format_number(judged, 0) AS gold_value FROM m
  UNION ALL SELECT 'Broken-promise rate', '8.6%', concat(ROUND(100 * rate, 1), '%') FROM m
  UNION ALL SELECT '1-2 star reviews in the window (orders, latest review)', '14,205', format_number(low, 0) FROM m
  UNION ALL SELECT 'Orders with a 1-2 star review: share after a broken promise', '36.7%', concat(ROUND(100 * low_share, 1), '%') FROM m
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
  UNION ALL SELECT 'Next nine routes: excess together', '637',
    (SELECT format_number(SUM(excess_broken), 0) FROM olist.analytics.gold_routes WHERE excess_rank BETWEEN 2 AND 10)
  UNION ALL SELECT 'National rate, single-seller orders', '8.7%', concat(ROUND(100 * national_rate, 1), '%') FROM route1
  UNION ALL SELECT 'National rate outside busy months, single-seller', '6.4%', concat(ROUND(100 * national_rate_other, 1), '%') FROM route1
  UNION ALL SELECT 'Top ten routes by fix type', '5 both, SP > RJ first; SP > AL, SP > BA, SP > PE lasting; PR > RJ, SP > SC busy-season',
    (SELECT concat(SUM(CASE WHEN fix_type = 'Both' THEN 1 ELSE 0 END), ' both, ',
                   CASE WHEN MAX(CASE WHEN excess_rank = 1 THEN fix_type END) = 'Both'
                        THEN concat(MAX(CASE WHEN excess_rank = 1 THEN route END), ' first') ELSE 'the first route is not Both' END, '; ',
                   concat_ws(', ', array_sort(collect_list(CASE WHEN fix_type = 'Lasting fix' THEN route END))), ' lasting; ',
                   concat_ws(', ', array_sort(collect_list(CASE WHEN fix_type = 'Busy-season plan' THEN route END))), ' busy-season')
     FROM olist.analytics.gold_routes WHERE excess_rank <= 10)
  UNION ALL SELECT 'Median month', '6.89%', concat(ROUND(100 * median_rate, 2), '%') FROM months
  UNION ALL SELECT 'Busy months', 'Nov 2017, Feb 2018, Mar 2018',
    (SELECT concat_ws(', ', sort_array(collect_list(date_format(month_start, 'yyyy-MM')))) FROM olist.analytics.gold_months WHERE is_busy_month)
  UNION ALL SELECT 'Busy months: share of orders', '22.1%', concat(ROUND(100 * busy_orders, 1), '%') FROM months
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
  UNION ALL SELECT 'Late deliveries from one seller handed over by the deadline', '72.2%', concat(ROUND(100 * handed, 1), '%') FROM m
  UNION ALL SELECT 'Northeast vs Southeast broken rate', '15.6% vs 7.8%',
    concat((SELECT ROUND(100 * rate, 1) FROM region WHERE customer_region = 'Northeast'), '% vs ',
           (SELECT ROUND(100 * rate, 1) FROM region WHERE customer_region = 'Southeast'), '%')
  UNION ALL SELECT 'Northeast: median days late', '8', (SELECT CAST(CAST(ROUND(med_late) AS INT) AS STRING) FROM region WHERE customer_region = 'Northeast')
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
    concat((SELECT CAST(ROUND(days) AS INT) FROM rio_local WHERE seller_location = 'Same state as customer'), ' vs ',
           (SELECT CAST(ROUND(days) AS INT) FROM rio_local WHERE seller_location = 'Sao Paulo'))
  UNION ALL SELECT 'Rio: share of judged single-seller orders from local sellers', '7.8%',
    concat(ROUND(100 * (SELECT n FROM rio_local WHERE seller_location = 'Same state as customer')
                 / (SELECT SUM(n) FROM rio_local WHERE seller_location <> 'Several sellers or no item'), 1), '%')
  UNION ALL SELECT 'Sao Paulo: share of funnel sellers who sold / of all sellers', '61.1% / 59.7%',
    (SELECT concat(ROUND(100 * share_of_funnel_sellers, 1), '% / ', ROUND(100 * share_of_sellers, 1), '%') FROM olist.analytics.gold_states WHERE state = 'SP')
  UNION ALL SELECT 'Rio: share of orders / of funnel sellers', '12.7% / 6.8%',
    (SELECT concat(ROUND(100 * share_of_orders_12m, 1), '% / ', ROUND(100 * share_of_funnel_sellers, 1), '%') FROM olist.analytics.gold_states WHERE state = 'RJ')
  -- The results added by the audit of 2026-11-24
  UNION ALL SELECT 'Broken promises: arrived late / shipped, never delivered / never reached a carrier', '6,531 / 1,094 / 602',
    (SELECT concat(format_number(SUM(CASE WHEN delivered_ts IS NOT NULL THEN 1 ELSE 0 END), 0), ' / ',
                   format_number(SUM(CASE WHEN delivered_ts IS NULL AND carrier_ts IS NOT NULL THEN 1 ELSE 0 END), 0), ' / ',
                   format_number(SUM(CASE WHEN delivered_ts IS NULL AND carrier_ts IS NULL THEN 1 ELSE 0 END), 0))
     FROM olist.analytics.fact_orders WHERE is_broken = 1)
  UNION ALL SELECT 'Window a week earlier: broken-promise rate, and the top ten routes', '8.7%; same top ten, SP > RJ first',
    concat((SELECT concat(ROUND(100 * SUM(is_broken) / COUNT(*), 1), '%') FROM olist.analytics.fact_orders
            WHERE is_judged AND promised_date <= DATE '2018-08-24'),
           '; ',
           CASE WHEN (SELECT COUNT(*) FROM early_top e JOIN olist.analytics.gold_routes g ON g.route = e.route
                      WHERE e.rk <= 10 AND g.excess_rank <= 10) = 10
                 AND (SELECT route FROM early_top WHERE rk = 1) = 'SP > RJ'
                THEN 'same top ten, SP > RJ first' ELSE 'the top ten changes' END)
  UNION ALL SELECT 'Fastest delivery band: late orders with a review', '74',
    (SELECT CAST(COUNT(*) AS STRING) FROM olist.analytics.fact_orders
     WHERE is_broken = 1 AND review_score IS NOT NULL AND delivery_time_band = 'Week 1 (0-7 days)')
  UNION ALL SELECT 'Fastest delivery band: score gap, on time minus late', '0.4',
    (SELECT format_number(kept - broken, 1) FROM band WHERE delivery_time_band = 'Week 1 (0-7 days)')
  UNION ALL SELECT 'Other delivery bands: score gap, on time minus late', '1.0 to 1.8',
    (SELECT concat(format_number(MIN(kept - broken), 1), ' to ', format_number(MAX(kept - broken), 1))
     FROM band WHERE delivery_time_band LIKE 'Week%' AND delivery_time_band <> 'Week 1 (0-7 days)')
  UNION ALL SELECT 'Top ten routes: into the Northeast / into Rio', '5 / 2',
    (SELECT concat(SUM(CASE WHEN customer_region = 'Northeast' THEN 1 ELSE 0 END), ' / ',
                   SUM(CASE WHEN customer_state = 'RJ' THEN 1 ELSE 0 END))
     FROM olist.analytics.gold_routes WHERE excess_rank <= 10)
  UNION ALL SELECT 'Sao Paulo to Minas Gerais: broken rate', '6.7%',
    (SELECT concat(ROUND(100 * broken_rate, 1), '%') FROM olist.analytics.gold_routes WHERE route = 'SP > MG')
  UNION ALL SELECT 'Busy months: national rate, in month order', '14.0% / 15.0% / 20.8%',
    (SELECT concat_ws(' / ', transform(array_sort(collect_list(struct(month_start, broken_rate))),
                                       x -> concat(format_number(100 * x.broken_rate, 1), '%')))
     FROM olist.analytics.gold_months WHERE is_busy_month)
  UNION ALL SELECT 'Rio: broken rate in busy months', '33.4%',
    (SELECT concat(ROUND(100 * MEASURE(broken_rate), 1), '%') FROM olist.analytics.delivery_metrics
     WHERE customer_state = 'RJ' AND is_busy_month)
  UNION ALL SELECT 'Rio: median promised days, busy vs other months', '24 vs 26',
    (SELECT concat(CAST(ROUND(MAX(CASE WHEN is_busy_month THEN d END)) AS INT), ' vs ',
                   CAST(ROUND(MAX(CASE WHEN NOT is_busy_month THEN d END)) AS INT))
     FROM (SELECT is_busy_month, MEASURE(median_promised_days) AS d FROM olist.analytics.delivery_metrics
           WHERE customer_state = 'RJ' GROUP BY is_busy_month))
  UNION ALL SELECT 'Northeast: broken promises a promise 3 days later would keep', '17.9%',
    (SELECT concat(ROUND(100 * (1 - r3 / r), 1), '%')
     FROM (SELECT MEASURE(broken_rate_if_3_days_later) AS r3, MEASURE(broken_rate) AS r
           FROM olist.analytics.delivery_metrics WHERE customer_region = 'Northeast'))
  UNION ALL SELECT 'Comparisons where local sellers deliver faster', '43 of 43 (6 states)',
    (SELECT concat(SUM(CASE WHEN local_days < distant_days THEN 1 ELSE 0 END), ' of ', COUNT(*),
                   ' (', COUNT(DISTINCT customer_state), ' states)')
     FROM comparisons WHERE local_orders >= 20 AND distant_orders >= 20)
  UNION ALL SELECT 'Deliveries recorded in Aug / Sep / Oct 2018', '8,314 / 56 / 3',
    (SELECT concat(format_number(MAX(CASE WHEN month_start = DATE '2018-08-01' THEN deliveries END), 0), ' / ',
                   format_number(MAX(CASE WHEN month_start = DATE '2018-09-01' THEN deliveries END), 0), ' / ',
                   format_number(MAX(CASE WHEN month_start = DATE '2018-10-01' THEN deliveries END), 0))
     FROM delivered_months)
  UNION ALL SELECT 'November 2017: broken promises above the busy-month threshold', '15',
    (SELECT CAST(broken_orders - CEIL(2 * median_rate * judged_orders) AS STRING)
     FROM olist.analytics.gold_months WHERE month_start = DATE '2017-11-01')
  UNION ALL SELECT 'Rio, busy months: broken rate, local vs Sao Paulo sellers', '4.1% vs 39.8%',
    concat((SELECT ROUND(100 * rate, 1) FROM rio_period WHERE is_busy_month AND seller_location = 'Same state as customer'), '% vs ',
           (SELECT ROUND(100 * rate, 1) FROM rio_period WHERE is_busy_month AND seller_location = 'Sao Paulo'), '%')
  UNION ALL SELECT 'Rio, other months: broken rate, local vs Sao Paulo sellers', '8.7% vs 10.0%',
    concat((SELECT ROUND(100 * rate, 1) FROM rio_period WHERE NOT is_busy_month AND seller_location = 'Same state as customer'), '% vs ',
           (SELECT ROUND(100 * rate, 1) FROM rio_period WHERE NOT is_busy_month AND seller_location = 'Sao Paulo'), '%')
  UNION ALL SELECT 'Rio, other months: median days, local vs Sao Paulo sellers', '5 vs 12',
    concat((SELECT CAST(ROUND(days) AS INT) FROM rio_period WHERE NOT is_busy_month AND seller_location = 'Same state as customer'), ' vs ',
           (SELECT CAST(ROUND(days) AS INT) FROM rio_period WHERE NOT is_busy_month AND seller_location = 'Sao Paulo'))
)
SELECT
  number, doc_value, gold_value,
  CASE WHEN replace(doc_value, ',', '') = replace(gold_value, ',', '')
         OR (number = 'Busy months' AND gold_value = '2017-11, 2018-02, 2018-03')
         OR (number = 'Score, 4-7 days late' AND gold_value = '2.1')
       THEN 'MATCH' ELSE 'DIFFERS' END AS result
FROM v;

SELECT * FROM olist.analytics.design_doc_numbers;

-- ------------------------------------------------------------
-- 4. The gate: this last statement stops the run with an error when
--    any pipeline check is not PASS. The rebuild job (README, "How to
--    run it") runs 07_dashboard_views.sql and refreshes the dashboards
--    only after this file succeeds, so the job never refreshes a
--    dashboard from a build that failed a check. It does not undo the
--    tables already rebuilt: the dashboards read them through views,
--    so a refresh by hand would show them. A design-document number
--    that DIFFERS does not stop the run: it means the document is out
--    of date, not the data.
-- ------------------------------------------------------------
SELECT CASE WHEN failed = 0 THEN concat('All ', checks, ' pipeline checks pass')
            ELSE raise_error(concat(failed, ' of ', checks,
                 ' pipeline checks did not pass: see olist.analytics.pipeline_checks'))
       END AS gate
FROM (SELECT COUNT(*) AS checks, COUNT_IF(result <> 'PASS') AS failed
      FROM olist.analytics.pipeline_checks);
