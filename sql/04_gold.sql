-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     04_gold.sql
-- Owner:    TODO name
-- Purpose:  Silver -> Gold. A star schema for the three dashboards:
--             fact_orders       one row per order
--             fact_order_items  one row per item line
--             dim_date, dim_state, dim_seller, dim_product
--           and three small Gold tables that hold the business
--           rules the dashboards read but must not calculate:
--             gold_months   which months are busy months
--             gold_routes   ranked routes with their fix type
--             gold_states   population-based measures by state
-- Run:      After 03_silver.sql. Rebuilds every Gold table. Safe to
--           rerun. Then 05_metric_view.sql and 06_checks.sql.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24. Every
--           definition was tested against the numbers in
--           docs/design_doc.md before it was written here
--           (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================

-- The definitions every table below shares (docs/design_doc.md,
-- "Metric definitions"):
--   In window     bought from 2017-01-01 and promised by 2018-08-31.
--                 The deliveries stop being recorded after August
--                 2018, so a promise is judged only once its day has
--                 passed inside the data (assumption A7, rule 9).
--   Judged        in window, not canceled or unavailable, and not one
--                 of the 8 delivered orders without a delivery date
--                 (rule 4). 95,901 orders.
--   Broken        judged, and not delivered by the end of the promised
--                 day: delivered on a later calendar day (rule 3), or
--                 not delivered at all.
--   Route         seller state > customer state, only for orders whose
--                 items all come from one seller (rule 13).

-- ------------------------------------------------------------
-- 1. dim_state: one row per state (27), from IBGE.
--    area splits the Southeast into Rio and the rest, because Rio
--    behaves like a different region in every chart.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.dim_state
COMMENT 'Gold dimension. One row per Brazilian state: name, region, area (Southeast split into Rio and the rest) and 2018 IBGE population.'
AS
SELECT
  state,
  state_name,
  state_code,
  region,
  CASE
    WHEN state = 'RJ'         THEN 'Rio de Janeiro'
    WHEN region = 'Southeast' THEN 'Southeast without Rio'
    ELSE region
  END AS area,
  population_2018
FROM olist.analytics.silver_states;

-- ------------------------------------------------------------
-- 2. dim_seller: one row per seller, with the funnel channel for
--    the 380 sellers who came through the marketing funnel.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.dim_seller
COMMENT 'Gold dimension. One row per seller: state, city, and the funnel channel and segment for sellers who came through the marketing funnel.'
AS
SELECT
  s.seller_id,
  s.state                       AS seller_state,
  s.city                        AS seller_city,
  d.mql_id IS NOT NULL          AS came_through_funnel,
  l.origin                      AS funnel_origin,
  d.business_segment            AS funnel_segment,
  d.lead_type                   AS funnel_lead_type,
  to_date(d.won_ts)             AS funnel_won_date
FROM olist.analytics.silver_sellers AS s
LEFT JOIN olist.analytics.silver_closed_deals AS d ON d.seller_id = s.seller_id
LEFT JOIN olist.analytics.silver_leads        AS l ON l.mql_id   = d.mql_id;

-- ------------------------------------------------------------
-- 3. dim_product: one row per product, with the English category.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.dim_product
COMMENT 'Gold dimension. One row per product, with its category in English (Portuguese when no translation exists, unknown when blank).'
AS
SELECT product_id, category, category_pt, product_weight_g
FROM olist.analytics.silver_products;

-- ------------------------------------------------------------
-- 4. fact_order_items: one row per item line.
--    Key: order_id + order_item_id. Carries the seller's deadline to
--    hand the item to the carrier (assumption A3).
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.fact_order_items
COMMENT 'Gold fact. One row per item line (order_id + order_item_id): product, seller, price, freight and the seller''s deadline to hand the item to the carrier.'
AS
SELECT
  i.order_id,
  i.order_item_id,
  i.product_id,
  i.seller_id,
  se.state                          AS seller_state,
  c.state                           AS customer_state,
  to_date(o.purchase_ts)            AS purchase_date,
  i.shipping_limit_ts,
  i.price,
  i.freight_value,
  i.flag_deadline_after_2018,
  o.flag_several_sellers
FROM olist.analytics.silver_order_items AS i
JOIN olist.analytics.silver_orders    AS o  ON o.order_id    = i.order_id
JOIN olist.analytics.silver_customers AS c  ON c.customer_id = o.customer_id
JOIN olist.analytics.silver_sellers   AS se ON se.seller_id  = i.seller_id;

-- ------------------------------------------------------------
-- 5. fact_orders: one row per order. Key: order_id.
--    Each CTE adds one piece at the order grain BEFORE the join, so
--    no join can repeat an order (the +4.6% trap of rule 15):
--      items     item count, value, sellers and the seller deadline
--      payments  total paid
--      review    the latest review only (rule 18)
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.fact_orders
COMMENT 'Gold fact. One row per order: promise, delivery, broken-promise outcome, latest review, route (single-seller orders) and the flags that keep a measure honest.'
AS
WITH items AS (
  SELECT
    i.order_id,
    COUNT(*)                         AS item_count,
    SUM(i.price)                     AS item_value,
    SUM(i.freight_value)             AS freight_value,
    COUNT(DISTINCT i.seller_id)      AS seller_count,
    -- the seller and the deadline only mean something when one seller
    -- shipped the whole order (rule 13)
    CASE WHEN COUNT(DISTINCT i.seller_id) = 1 THEN MIN(i.seller_id) END AS seller_id,
    -- rule 12: a deadline in 2019 or later is not used
    CASE WHEN COUNT(DISTINCT i.seller_id) = 1 AND NOT MAX(i.flag_deadline_after_2018)
         THEN MAX(i.shipping_limit_ts) END                              AS seller_deadline_ts
  FROM olist.analytics.silver_order_items AS i
  GROUP BY i.order_id
),
payments AS (
  -- rule 15: one row per order before any join
  SELECT order_id, SUM(payment_value) AS payment_value
  FROM olist.analytics.silver_order_payments
  GROUP BY order_id
),
first_item AS (
  -- An order can hold products from several categories. The category
  -- filter on Dashboards 1 and 3 uses the category of the first item
  -- line, so an order is counted once, in one category.
  SELECT i.order_id, p.category
  FROM olist.analytics.silver_order_items AS i
  JOIN olist.analytics.silver_products AS p ON p.product_id = i.product_id
  WHERE i.order_item_id = 1
),
review AS (
  SELECT order_id, review_id, review_score, review_creation_date, review_answer_ts
  FROM olist.analytics.silver_order_reviews
  WHERE is_latest_for_order
),
base AS (
  SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.state                                        AS customer_state,
    o.order_status,
    o.purchase_ts,
    to_date(o.purchase_ts)                         AS purchase_date,
    o.approved_ts,
    o.carrier_ts,
    o.delivered_ts,
    to_date(o.delivered_ts)                        AS delivered_date,
    o.promised_date,
    COALESCE(it.item_count, 0)                     AS item_count,
    it.item_value,
    it.freight_value,
    p.payment_value,
    COALESCE(it.seller_count, 0)                   AS seller_count,
    it.seller_id,
    se.state                                       AS seller_state,
    it.seller_deadline_ts,
    fi.category,
    r.review_id,
    r.review_score,
    r.review_creation_date,
    r.review_answer_ts,
    o.flag_several_sellers,
    o.flag_delivered_without_date,
    o.flag_canceled_with_delivery,
    o.flag_carrier_before_purchase,
    o.flag_carrier_before_approval,
    o.flag_delivered_before_carrier,
    o.flag_outside_full_months,
    -- In window: see the top of this file
    o.purchase_ts >= TIMESTAMP '2017-01-01'
      AND o.promised_date <= DATE '2018-08-31'     AS is_in_window
  FROM olist.analytics.silver_orders AS o
  JOIN olist.analytics.silver_customers AS c ON c.customer_id = o.customer_id
  LEFT JOIN items    AS it ON it.order_id = o.order_id
  LEFT JOIN payments AS p  ON p.order_id  = o.order_id
  LEFT JOIN first_item AS fi ON fi.order_id = o.order_id
  LEFT JOIN review   AS r  ON r.order_id  = o.order_id
  LEFT JOIN olist.analytics.silver_sellers AS se ON se.seller_id = it.seller_id
),
judged AS (
  SELECT
    b.*,
    -- Judged: see the top of this file
    b.is_in_window
      AND b.order_status NOT IN ('canceled', 'unavailable')
      AND NOT b.flag_delivered_without_date        AS is_judged
  FROM base AS b
)
SELECT
  j.*,
  -- 1/0 rather than true/false, so a measure can SUM it
  CASE WHEN j.is_judged
        AND (j.delivered_date > j.promised_date OR j.delivered_ts IS NULL)
       THEN 1 ELSE 0 END                                         AS is_broken,
  -- the same test with a promise 3 days later (Dashboard 2, chart 3)
  CASE WHEN j.is_judged
        AND (j.delivered_date > date_add(j.promised_date, 3) OR j.delivered_ts IS NULL)
       THEN 1 ELSE 0 END                                         AS is_broken_if_3_days_later,
  -- days after (+) or before (-) the promised day; empty if not delivered
  datediff(j.delivered_date, j.promised_date)                    AS days_vs_promise,
  -- days from purchase to delivery
  datediff(j.delivered_date, j.purchase_date)                    AS delivery_days,
  -- Dashboard 2, chart 4, where the days go. Each part is left empty
  -- when its two dates are in an impossible order (rules 6 and 8).
  CASE WHEN NOT j.flag_carrier_before_purchase
       THEN datediff(to_date(j.carrier_ts), j.purchase_date) END   AS days_to_carrier,
  CASE WHEN NOT j.flag_delivered_before_carrier
       THEN datediff(j.delivered_date, to_date(j.carrier_ts)) END  AS days_carrier_to_customer,
  -- days the customer was promised at checkout
  datediff(j.promised_date, j.purchase_date)                     AS promised_days,
  -- Dashboard 1, chart 4: the groups of days before or after the
  -- promised day. Early orders are grouped by week, because their
  -- score barely moves (4.20 to 4.32); late orders get finer groups
  -- because the score drops fast. The _order column sorts the axis.
  CASE
    WHEN j.delivered_ts IS NULL                                    THEN NULL
    WHEN datediff(j.delivered_date, j.promised_date) <= -15        THEN '15+ days early'
    WHEN datediff(j.delivered_date, j.promised_date) <= -8         THEN '8-14 days early'
    WHEN datediff(j.delivered_date, j.promised_date) <= -1         THEN '1-7 days early'
    WHEN datediff(j.delivered_date, j.promised_date) = 0           THEN 'On the day'
    WHEN datediff(j.delivered_date, j.promised_date) <= 3          THEN '1-3 days late'
    WHEN datediff(j.delivered_date, j.promised_date) <= 7          THEN '4-7 days late'
    WHEN datediff(j.delivered_date, j.promised_date) <= 14         THEN '8-14 days late'
    ELSE '15+ days late'
  END                                                            AS promise_bucket,
  CASE
    WHEN j.delivered_ts IS NULL                                    THEN NULL
    WHEN datediff(j.delivered_date, j.promised_date) <= -15        THEN 1
    WHEN datediff(j.delivered_date, j.promised_date) <= -8         THEN 2
    WHEN datediff(j.delivered_date, j.promised_date) <= -1         THEN 3
    WHEN datediff(j.delivered_date, j.promised_date) = 0           THEN 4
    WHEN datediff(j.delivered_date, j.promised_date) <= 3          THEN 5
    WHEN datediff(j.delivered_date, j.promised_date) <= 7          THEN 6
    WHEN datediff(j.delivered_date, j.promised_date) <= 14         THEN 7
    ELSE 8
  END                                                            AS promise_bucket_order,
  -- Dashboard 1, chart 5: delivery time in weeks, so on-time and late
  -- orders are compared at the same speed. The labels start with the
  -- week so they sort in order on a chart axis.
  CASE
    WHEN j.delivered_ts IS NULL                                    THEN NULL
    WHEN datediff(j.delivered_date, j.purchase_date) <= 7          THEN 'Week 1 (0-7 days)'
    WHEN datediff(j.delivered_date, j.purchase_date) <= 14         THEN 'Week 2 (8-14 days)'
    WHEN datediff(j.delivered_date, j.purchase_date) <= 21         THEN 'Week 3 (15-21 days)'
    WHEN datediff(j.delivered_date, j.purchase_date) <= 28         THEN 'Week 4 (22-28 days)'
    ELSE 'Week 5+ (29+ days)'
  END                                                            AS delivery_time_band,
  CASE WHEN j.seller_count = 1 THEN concat(j.seller_state, ' > ', j.customer_state) END AS route,
  CASE WHEN j.seller_count = 1 THEN j.seller_state = j.customer_state END             AS is_local_seller,
  -- 1 or 2 stars (Low review)
  CASE WHEN j.review_score <= 2 THEN 1 ELSE 0 END                AS is_low_review,
  -- answered the review before the parcel arrived; only measured for
  -- delivered orders, since an undelivered parcel has no arrival
  CASE WHEN j.delivered_ts IS NOT NULL AND j.review_answer_ts IS NOT NULL
       THEN j.review_answer_ts < j.delivered_ts END              AS reviewed_before_arrival,
  -- handed to the carrier by the seller's deadline. Not measured when
  -- the carrier date comes before the purchase (rule 6) or for orders
  -- shared by several sellers (rule 13, the deadline is then empty)
  CASE WHEN j.carrier_ts IS NOT NULL AND j.seller_deadline_ts IS NOT NULL
        AND NOT j.flag_carrier_before_purchase
       THEN j.carrier_ts <= j.seller_deadline_ts END             AS handed_over_by_deadline
FROM judged AS j;

-- ------------------------------------------------------------
-- 6. gold_months: one row per month from January 2017 to August
--    2018, with the national broken-promise rate and the busy-month
--    rule: a month is busy when its rate is at least twice the
--    median month. The rule lives here, once, and the dashboards
--    and gold_routes read the result.
--    We found these months by looking at the same data, so the rule
--    has to be judged again on new months (design doc, limits).
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.gold_months
COMMENT 'Gold. One row per purchase month, Jan 2017 to Aug 2018: judged orders, broken promises, rate, the median month and the busy-month flag.'
AS
WITH m AS (
  SELECT
    CAST(date_trunc('month', purchase_ts) AS DATE)  AS month_start,
    SUM(CASE WHEN is_judged THEN 1 ELSE 0 END)      AS judged_orders,
    SUM(is_broken)                                  AS broken_orders,
    SUM(is_broken) / SUM(CASE WHEN is_judged THEN 1 ELSE 0 END) AS broken_rate
  FROM olist.analytics.fact_orders
  WHERE is_judged
  GROUP BY 1
),
med AS (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY broken_rate) AS median_rate FROM m)
SELECT
  m.*,
  med.median_rate,
  m.broken_rate >= 2 * med.median_rate AS is_busy_month
FROM m CROSS JOIN med;

-- ------------------------------------------------------------
-- 7. dim_date: one row per day from 2016-09-01 to 2018-12-31.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.dim_date
COMMENT 'Gold dimension. One row per day, September 2016 to December 2018, with month, year and the busy-month flag from gold_months.'
AS
SELECT
  d                                          AS date_key,
  CAST(date_trunc('month', d) AS DATE)       AS month_start,
  year(d)                                    AS year,
  month(d)                                   AS month,
  date_format(d, 'MMM yyyy')                 AS month_label,
  -- monthly views cover January 2017 to August 2018 only (rule 9)
  d BETWEEN DATE '2017-01-01' AND DATE '2018-08-31' AS is_full_month,
  COALESCE(g.is_busy_month, false)           AS is_busy_month
FROM (SELECT explode(sequence(DATE '2016-09-01', DATE '2018-12-31', INTERVAL 1 DAY)) AS d) AS days
LEFT JOIN olist.analytics.gold_months AS g
  ON g.month_start = CAST(date_trunc('month', d) AS DATE);

-- ------------------------------------------------------------
-- 8. gold_routes: one row per route, ranked by excess broken
--    promises, with its margin and fix type. Only judged,
--    single-seller orders (rule 13).
--      excess        broken minus what the national rate predicts
--                    for the route's number of orders
--      margin        95% interval of the rate: 1.96 x sqrt(p(1-p)/n)
--      lasting fix   the route's rate outside busy months, minus its
--                    margin, is still above the national rate outside
--                    busy months (6.4%): it breaks in ordinary months
--      busy-season   its excess in busy months, against the national
--                    busy-month rate, is larger than its excess in the
--                    other months, against the national rate there
--    The fix type compares busy months with the rest of the year, so
--    it ignores the dashboard's month filter (design doc, filters).
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.gold_routes
COMMENT 'Gold. One row per route (seller state > customer state, single-seller orders): orders, broken rate, margin, excess broken promises, rank and fix type.'
AS
WITH o AS (
  SELECT f.route, f.seller_state, f.customer_state, f.is_broken, d.is_busy_month
  FROM olist.analytics.fact_orders AS f
  JOIN olist.analytics.dim_date AS d ON d.date_key = f.purchase_date
  WHERE f.is_judged AND f.seller_count = 1
),
national AS (
  SELECT
    AVG(is_broken)                                          AS rate_all,
    AVG(CASE WHEN is_busy_month     THEN is_broken END)     AS rate_busy,
    AVG(CASE WHEN NOT is_busy_month THEN is_broken END)     AS rate_other
  FROM o
),
r AS (
  SELECT
    o.route, o.seller_state, o.customer_state,
    COUNT(*)                                                         AS orders,
    SUM(o.is_broken)                                                 AS broken_orders,
    SUM(CASE WHEN o.is_busy_month THEN 1 ELSE 0 END)                 AS orders_busy,
    SUM(CASE WHEN o.is_busy_month THEN o.is_broken ELSE 0 END)       AS broken_busy,
    SUM(CASE WHEN NOT o.is_busy_month THEN 1 ELSE 0 END)             AS orders_other,
    SUM(CASE WHEN NOT o.is_busy_month THEN o.is_broken ELSE 0 END)   AS broken_other
  FROM o
  GROUP BY o.route, o.seller_state, o.customer_state
),
measured AS (
  SELECT
    r.*,
    n.rate_all  AS national_rate,
    n.rate_busy AS national_rate_busy,
    n.rate_other AS national_rate_other,
    r.broken_orders / r.orders                                        AS broken_rate,
    1.96 * sqrt((r.broken_orders / r.orders) * (1 - r.broken_orders / r.orders) / r.orders) AS margin,
    r.broken_orders - r.orders * n.rate_all                           AS excess_broken,
    r.broken_other / NULLIF(r.orders_other, 0)                        AS rate_other,
    1.96 * sqrt((r.broken_other / NULLIF(r.orders_other, 0))
                * (1 - r.broken_other / NULLIF(r.orders_other, 0)) / NULLIF(r.orders_other, 0)) AS margin_other,
    r.broken_busy  - r.orders_busy  * n.rate_busy                     AS excess_busy,
    r.broken_other - r.orders_other * n.rate_other                    AS excess_other
  FROM r CROSS JOIN national AS n
),
labeled AS (
  SELECT
    m.*,
    COALESCE(m.rate_other - m.margin_other > m.national_rate_other, false) AS needs_lasting_fix,
    m.excess_busy > m.excess_other                                         AS needs_busy_season_plan
  FROM measured AS m
)
SELECT
  l.*,
  ROW_NUMBER() OVER (ORDER BY l.excess_broken DESC, l.route) AS excess_rank,
  CASE
    WHEN l.excess_broken <= 0                             THEN 'No fix needed'
    WHEN l.needs_lasting_fix AND l.needs_busy_season_plan THEN 'Both'
    WHEN l.needs_lasting_fix                              THEN 'Lasting fix'
    WHEN l.needs_busy_season_plan                         THEN 'Busy-season plan'
    ELSE 'Watch'
  END AS fix_type,
  CASE
    WHEN l.excess_broken <= 0                             THEN NULL
    WHEN l.needs_lasting_fix AND l.needs_busy_season_plan THEN 'Review the carrier and transit days on this route, and book extra capacity before busy months'
    WHEN l.needs_lasting_fix                              THEN 'Review the carrier and transit days on this route'
    WHEN l.needs_busy_season_plan                         THEN 'Book extra carrier capacity before busy months'
    ELSE 'Too few orders to tell; check again next quarter'
  END AS first_step,
  cs.region AS customer_region
FROM labeled AS l
JOIN olist.analytics.dim_state AS cs ON cs.state = l.customer_state;

-- ------------------------------------------------------------
-- 9. gold_states: one row per customer state, for Dashboard 3.
--    Demand measures use every order bought in the 12 months to
--    August 2018 (September 2017 to August 2018), whatever its
--    status: an order is demand even when it was canceled, and one
--    full year compares fairly with the 2018 population
--    (assumption A5). The broken rate uses judged orders, as
--    everywhere else.
--      active seller   sold at least one order in those 12 months
--      funnel seller   came through the marketing funnel and sold at
--                      least one order (380 of the 842 deals)
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.gold_states
COMMENT 'Gold. One row per state: 12-month orders per 100,000 residents, active sellers per million, share of orders from another state, broken rate, and shares of orders, sellers and funnel recruits.'
AS
WITH last12 AS (
  SELECT * FROM olist.analytics.fact_orders
  WHERE purchase_date BETWEEN DATE '2017-09-01' AND DATE '2018-08-31'
),
cust AS (
  SELECT customer_state AS state,
         COUNT(*)                                                     AS orders_12m,
         SUM(CASE WHEN seller_count = 1 AND NOT is_local_seller THEN 1 ELSE 0 END)
           / SUM(CASE WHEN seller_count = 1 THEN 1 ELSE 0 END)        AS share_from_other_state_12m
  FROM last12 GROUP BY customer_state
),
active AS (
  SELECT i.seller_state AS state, COUNT(DISTINCT i.seller_id) AS active_sellers_12m
  FROM olist.analytics.fact_order_items AS i
  JOIN last12 AS f ON f.order_id = i.order_id
  GROUP BY i.seller_state
),
window_orders AS (
  SELECT customer_state AS state, COUNT(*) AS judged_orders, SUM(is_broken) AS broken_orders
  FROM olist.analytics.fact_orders WHERE is_judged GROUP BY customer_state
),
all_sellers AS (
  SELECT seller_state AS state, COUNT(*) AS sellers FROM olist.analytics.dim_seller GROUP BY seller_state
),
funnel AS (
  SELECT seller_state AS state, COUNT(*) AS funnel_sellers_who_sold
  FROM olist.analytics.dim_seller AS s
  WHERE s.came_through_funnel
    AND EXISTS (SELECT 1 FROM olist.analytics.fact_order_items i WHERE i.seller_id = s.seller_id)
  GROUP BY seller_state
)
SELECT
  st.state, st.state_name, st.region, st.area, st.population_2018,
  COALESCE(c.orders_12m, 0)                                           AS orders_12m,
  100000 * COALESCE(c.orders_12m, 0) / st.population_2018             AS orders_per_100k_12m,
  COALESCE(a.active_sellers_12m, 0)                                   AS active_sellers_12m,
  1000000 * COALESCE(a.active_sellers_12m, 0) / st.population_2018    AS active_sellers_per_million_12m,
  c.share_from_other_state_12m,
  w.judged_orders,
  w.broken_orders,
  w.broken_orders / w.judged_orders                                   AS broken_rate,
  COALESCE(c.orders_12m, 0) / SUM(c.orders_12m) OVER ()              AS share_of_orders_12m,
  COALESCE(s.sellers, 0) / SUM(s.sellers) OVER ()                     AS share_of_sellers,
  COALESCE(fu.funnel_sellers_who_sold, 0)
    / SUM(fu.funnel_sellers_who_sold) OVER ()                         AS share_of_funnel_sellers
FROM olist.analytics.dim_state AS st
LEFT JOIN cust          AS c  ON c.state  = st.state
LEFT JOIN active        AS a  ON a.state  = st.state
LEFT JOIN window_orders AS w  ON w.state  = st.state
LEFT JOIN all_sellers   AS s  ON s.state  = st.state
LEFT JOIN funnel        AS fu ON fu.state = st.state;
