-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     03_silver.sql
-- Owner:    TODO name
-- Purpose:  Raw -> Silver. Type every column, apply the 31 rules
--           of docs/data_quality_log.md, keep one row per key, and
--           set aside the rows we cannot trust in one quarantine
--           table, each with its reason.
-- Run:      After 01_load_raw.sql. Rebuilds every Silver table from
--           olist.raw. Safe to rerun. 06_checks.sql tests the result.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-24
--           (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================

-- The four actions, as in the class tutorials:
--   FIX         correct a format or a definition; the row stays.
--   KEEP        choose one version of a record.
--   QUARANTINE  set the row aside in olist.analytics.quarantine with
--               the reason. It is not deleted, so it can be looked at.
--   FLAG        keep the row and mark it (a column named flag_...), so
--               a measure can leave it out.
-- "Rule n" below is the rule number in docs/data_quality_log.md.
--
-- The stg_ views hold the rules: each types the raw rows and gives a
-- quarantine_reason to a row that fails. The silver_ table takes the
-- rows without a reason, and the quarantine table takes the others,
-- so every raw row lands in exactly one of the two.
--
-- Why TRY_CAST and try_to_timestamp: they give NULL for a value they
-- cannot read instead of stopping the script, and a NULL is then
-- caught by a quarantine rule.
--
-- The team's answers to the three open questions in the data quality
-- log, as written in the design document:
--   1. Several reviews for one order: keep the latest (rule 18).
--   2. Dates in an impossible order: keep the order, and leave out only
--      the time we cannot measure (rules 6 to 8).
--   3. Geolocation: cleaned to one row per zip prefix (rule 25), but no
--      measure uses distance. Routes use states.

-- ------------------------------------------------------------
-- 1. States (IBGE). Rule 31.
--    IBGE names a state by number (35) and Olist by letters (SP).
--    The IBGE state list holds both, so it is the bridge. The
--    population answer is nested: one variable, with one series per
--    state inside it, so we explode it to one row per state.
--    Key: state (two letters). 27 rows.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.silver_states
COMMENT 'Silver. One row per Brazilian state: IBGE code, two-letter abbreviation, name, region and 2018 population.'
AS
WITH population AS (
  SELECT CAST(s.localidade.id AS INT)      AS state_code,
         CAST(s.serie.`2018` AS BIGINT)    AS population_2018
  FROM (SELECT explode(r.series) AS s
        FROM (SELECT explode(resultados) AS r FROM olist.raw.ibge_population_2018))
)
SELECT
  CAST(st.id AS INT)       AS state_code,
  st.sigla                 AS state,
  st.nome                  AS state_name,
  st.regiao.sigla          AS region_code,
  st.regiao.nome           AS region_name_pt,
  -- English names, for the dashboards
  CASE st.regiao.sigla
    WHEN 'N'  THEN 'North'
    WHEN 'NE' THEN 'Northeast'
    WHEN 'SE' THEN 'Southeast'
    WHEN 'S'  THEN 'South'
    WHEN 'CO' THEN 'Center-West'
  END                      AS region,
  p.population_2018
FROM olist.raw.ibge_states AS st
LEFT JOIN population AS p
  ON p.state_code = CAST(st.id AS INT);

-- ------------------------------------------------------------
-- 2. Geolocation. Rules 25 and 27.
--    The raw table has 52.6 rows per zip prefix on average, and
--    joining to it turns 99,441 customers into 15 million rows. Here
--    we drop exact copies, set aside points outside Brazil, then keep
--    one row per zip prefix with the average position.
--    The state is NOT taken from here (rule 27): 8 prefixes sit in
--    two states, so customers and sellers keep their own state.
--    Key: zip_prefix.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.stg_geolocation
COMMENT 'Staging. Distinct raw geolocation points, typed. Feeds silver_geolocation and the quarantine.'
AS
SELECT DISTINCT                     -- rule 25: drop the 261,831 exact copies
  geolocation_zip_code_prefix              AS zip_prefix,
  TRY_CAST(geolocation_lat AS DOUBLE)      AS lat,
  TRY_CAST(geolocation_lng AS DOUBLE)      AS lng,
  geolocation_city                         AS city,
  geolocation_state                        AS state
FROM olist.raw.geolocation;

CREATE OR REPLACE TABLE olist.analytics.silver_geolocation
COMMENT 'Silver. One row per zip code prefix: average latitude and longitude of its distinct points inside Brazil.'
AS
SELECT zip_prefix,
       ROUND(AVG(lat), 6) AS lat,
       ROUND(AVG(lng), 6) AS lng,
       COUNT(*)           AS distinct_points
FROM olist.analytics.stg_geolocation
-- a rough box around Brazil; the 42 points outside it go to quarantine
WHERE lat BETWEEN -33.8 AND 5.3
  AND lng BETWEEN -73.99 AND -34.7
GROUP BY zip_prefix;

-- ------------------------------------------------------------
-- 3. Customers. Rules 20, 21 and 26.
--    Key: customer_id (one account on one order). The person is
--    customer_unique_id (assumption A1).
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.silver_customers
COMMENT 'Silver. One row per customer_id (a customer record on one order); customer_unique_id is the person.'
AS
SELECT
  c.customer_id,
  c.customer_unique_id,
  -- rule 20: the zip prefix stays 5-character text; a number type would
  -- drop the leading zero of 23,995 customers and break the join
  c.customer_zip_code_prefix                                AS zip_prefix,
  c.customer_city                                           AS city,
  -- rule 21: lower case without accents, so "são paulo" = "sao paulo"
  translate(lower(trim(c.customer_city)),
            'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') AS city_match,
  upper(trim(c.customer_state))                             AS state,
  -- rule 26: 278 prefixes are not in geolocation; the customer stays
  g.zip_prefix IS NULL                                      AS flag_zip_not_in_geolocation
FROM olist.raw.customers AS c
LEFT JOIN olist.analytics.silver_geolocation AS g
  ON g.zip_prefix = c.customer_zip_code_prefix;

-- ------------------------------------------------------------
-- 4. Sellers. Rules 20, 21 and 26. Key: seller_id.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.silver_sellers
COMMENT 'Silver. One row per seller.'
AS
SELECT
  s.seller_id,
  s.seller_zip_code_prefix                                  AS zip_prefix,
  s.seller_city                                             AS city,
  translate(lower(trim(s.seller_city)),
            'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') AS city_match,
  upper(trim(s.seller_state))                               AS state,
  g.zip_prefix IS NULL                                      AS flag_zip_not_in_geolocation
FROM olist.raw.sellers AS s
LEFT JOIN olist.analytics.silver_geolocation AS g
  ON g.zip_prefix = s.seller_zip_code_prefix;

-- ------------------------------------------------------------
-- 5. Products. Rules 22, 23 and 24. Key: product_id.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.silver_products
COMMENT 'Silver. One row per product, with its category in Portuguese and English.'
AS
SELECT
  p.product_id,
  -- rule 23: 610 products have no category; they sold, so they stay
  COALESCE(p.product_category_name, 'unknown')               AS category_pt,
  -- rule 24: 2 categories have no English name; we keep the Portuguese
  -- one rather than invent a translation
  COALESCE(t.product_category_name_english,
           p.product_category_name, 'unknown')               AS category,
  -- rule 22: the source file spells these two columns "lenght"
  TRY_CAST(p.product_name_lenght AS INT)                     AS product_name_length,
  TRY_CAST(p.product_description_lenght AS INT)              AS product_description_length,
  TRY_CAST(p.product_photos_qty AS INT)                      AS product_photos_qty,
  TRY_CAST(p.product_weight_g AS INT)                        AS product_weight_g,
  TRY_CAST(p.product_length_cm AS INT)                       AS product_length_cm,
  TRY_CAST(p.product_height_cm AS INT)                       AS product_height_cm,
  TRY_CAST(p.product_width_cm AS INT)                        AS product_width_cm
FROM olist.raw.products AS p
LEFT JOIN olist.raw.category_translation AS t
  ON t.product_category_name = p.product_category_name;

-- ------------------------------------------------------------
-- 6. Orders. Rules 1 to 9 and 13.
--    Staging view first: every raw order, typed, with a quarantine
--    reason if it fails a rule. The rules live here only.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.stg_orders
COMMENT 'Staging. Every raw order, typed, with flags and a quarantine_reason if it fails a rule.'
AS
WITH typed AS (
  SELECT
    o.order_id,
    o.customer_id,
    lower(trim(o.order_status))                          AS order_status,
    -- rule 1: the five dates as timestamps
    try_to_timestamp(o.order_purchase_timestamp)         AS purchase_ts,
    try_to_timestamp(o.order_approved_at)                AS approved_ts,
    try_to_timestamp(o.order_delivered_carrier_date)     AS carrier_ts,
    try_to_timestamp(o.order_delivered_customer_date)    AS delivered_ts,
    -- rule 3: the promised date has no time of day (always midnight),
    -- so it is a DATE. Late is then decided by calendar day.
    to_date(try_to_timestamp(o.order_estimated_delivery_date)) AS promised_date,
    to_json(struct(o.*))                                 AS raw_row
  FROM olist.raw.orders AS o
),
sellers_per_order AS (
  SELECT order_id, COUNT(DISTINCT seller_id) AS n_sellers
  FROM olist.raw.order_items
  GROUP BY order_id
)
SELECT
  t.*,
  -- rule 13: one carrier date for items from several sellers
  COALESCE(s.n_sellers, 0) >= 2                                     AS flag_several_sellers,
  -- rule 4: a sale whose delivery time is unknown
  t.order_status = 'delivered' AND t.delivered_ts IS NULL           AS flag_delivered_without_date,
  -- rule 5: canceled stays canceled even with a delivery date
  t.order_status = 'canceled' AND t.delivered_ts IS NOT NULL        AS flag_canceled_with_delivery,
  -- rules 6 to 8: two dates in an impossible order; we cannot tell
  -- which one is wrong, so only the gap between them is not measured
  COALESCE(t.carrier_ts < t.purchase_ts, false)                     AS flag_carrier_before_purchase,
  COALESCE(t.carrier_ts < t.approved_ts, false)                     AS flag_carrier_before_approval,
  COALESCE(t.delivered_ts < t.carrier_ts, false)                    AS flag_delivered_before_carrier,
  -- rule 9: monthly views cover January 2017 to August 2018 only
  t.purchase_ts < TIMESTAMP '2017-01-01'
    OR t.purchase_ts >= TIMESTAMP '2018-09-01'                      AS flag_outside_full_months,
  CASE
    WHEN t.purchase_ts IS NULL THEN 'unreadable purchase date'      -- rule 1
    WHEN t.order_status NOT IN ('delivered', 'shipped', 'canceled', 'unavailable',
                                'invoiced', 'processing', 'created', 'approved')
      THEN 'unknown order status'                                   -- rule 2
  END AS quarantine_reason
FROM typed AS t
LEFT JOIN sellers_per_order AS s
  ON s.order_id = t.order_id;

CREATE OR REPLACE TABLE olist.analytics.silver_orders
COMMENT 'Silver. One row per order, dates typed, with flags for dates in an impossible order and for orders shared by several sellers.'
AS
SELECT * EXCEPT (raw_row, quarantine_reason)
FROM olist.analytics.stg_orders
WHERE quarantine_reason IS NULL;

-- ------------------------------------------------------------
-- 7. Order items. Rules 10, 11 and 12.
--    Key: order_id + order_item_id.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.stg_order_items
COMMENT 'Staging. Every raw item line, typed, with a quarantine_reason if it fails a rule.'
AS
WITH typed AS (
  SELECT
    i.order_id,
    TRY_CAST(i.order_item_id AS INT)                     AS order_item_id,
    i.product_id,
    i.seller_id,
    try_to_timestamp(i.shipping_limit_date)              AS shipping_limit_ts,
    -- rule 11: money as DECIMAL(10,2)
    TRY_CAST(i.price AS DECIMAL(10, 2))                  AS price,
    TRY_CAST(i.freight_value AS DECIMAL(10, 2))          AS freight_value,
    to_json(struct(i.*))                                 AS raw_row
  FROM olist.raw.order_items AS i
)
SELECT
  t.*,
  -- rule 12: 4 deadlines in 2019 or 2020, over a year after the last order
  COALESCE(t.shipping_limit_ts >= TIMESTAMP '2019-01-01', false) AS flag_deadline_after_2018,
  CASE
    WHEN t.price IS NULL OR t.price <= 0 THEN 'price missing, unreadable or not above 0'  -- rule 11
    WHEN ROW_NUMBER() OVER (PARTITION BY t.order_id, t.order_item_id
                            ORDER BY t.raw_row) > 1 THEN 'repeated item line'          -- rule 10
  END AS quarantine_reason
FROM typed AS t;

CREATE OR REPLACE TABLE olist.analytics.silver_order_items
COMMENT 'Silver. One row per item line of an order (order_id + order_item_id), price and freight as decimals.'
AS
SELECT * EXCEPT (raw_row, quarantine_reason)
FROM olist.analytics.stg_order_items
WHERE quarantine_reason IS NULL;

-- ------------------------------------------------------------
-- 8. Payments. Rules 14, 15 and 16.
--    Key: order_id + payment_sequential.
--    Rule 15 (sum payments to one row per order before any join to
--    items) is applied in Gold, where fact_orders takes the total.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.stg_order_payments
COMMENT 'Staging. Every raw payment, typed, with a quarantine_reason if it fails a rule.'
AS
SELECT
  p.order_id,
  TRY_CAST(p.payment_sequential AS INT)           AS payment_sequential,
  p.payment_type,
  -- rule 16: 0 installments kept as they are; not used in any measure
  TRY_CAST(p.payment_installments AS INT)         AS payment_installments,
  TRY_CAST(p.payment_value AS DECIMAL(10, 2))     AS payment_value,
  to_json(struct(p.*))                            AS raw_row,
  CASE
    WHEN p.payment_type = 'not_defined' THEN 'payment type not_defined'   -- rule 14
    WHEN TRY_CAST(p.payment_value AS DECIMAL(10, 2)) IS NULL THEN 'unreadable payment value'
  END AS quarantine_reason
FROM olist.raw.order_payments AS p;

CREATE OR REPLACE TABLE olist.analytics.silver_order_payments
COMMENT 'Silver. One row per payment of an order (order_id + payment_sequential). Sum to one row per order before joining to items.'
AS
SELECT * EXCEPT (raw_row, quarantine_reason)
FROM olist.analytics.stg_order_payments
WHERE quarantine_reason IS NULL;

-- ------------------------------------------------------------
-- 9. Reviews. Rules 17, 18 and 19.
--    Key: review_id + order_id. One review can cover several orders
--    bought together (789 review ids), so it stays on each of them,
--    and a count of reviews uses DISTINCT review_id (rule 17).
--    is_latest_for_order marks the one review per order that every
--    score measure uses (rule 18): the latest answer, then the latest
--    creation date, then review_id, so a rerun picks the same row.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW olist.analytics.stg_order_reviews
COMMENT 'Staging. Every raw review, typed, with a quarantine_reason if it fails a rule.'
AS
SELECT
  r.review_id,
  r.order_id,
  TRY_CAST(r.review_score AS INT)                    AS review_score,
  -- rule 19: a blank title or comment stays blank
  r.review_comment_title,
  r.review_comment_message,
  to_date(try_to_timestamp(r.review_creation_date))  AS review_creation_date,
  try_to_timestamp(r.review_answer_timestamp)        AS review_answer_ts,
  to_json(struct(r.*))                               AS raw_row,
  CASE
    WHEN TRY_CAST(r.review_score AS INT) IS NULL
      OR TRY_CAST(r.review_score AS INT) NOT BETWEEN 1 AND 5 THEN 'review score not 1 to 5'  -- rule 19
  END AS quarantine_reason
FROM olist.raw.order_reviews AS r;

CREATE OR REPLACE TABLE olist.analytics.silver_order_reviews
COMMENT 'Silver. One row per review on one order (review_id + order_id). is_latest_for_order marks the one review per order that score measures use.'
AS
SELECT
  * EXCEPT (raw_row, quarantine_reason),
  ROW_NUMBER() OVER (
    PARTITION BY order_id
    ORDER BY review_answer_ts DESC NULLS LAST, review_creation_date DESC NULLS LAST, review_id DESC
  ) = 1 AS is_latest_for_order
FROM olist.analytics.stg_order_reviews
WHERE quarantine_reason IS NULL;

-- ------------------------------------------------------------
-- 10. Marketing funnel. Rules 28, 29 and 30.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.silver_leads
COMMENT 'Silver. One row per seller who asked to join Olist (marketing-qualified lead), with the channel they came from.'
AS
SELECT
  mql_id,
  TRY_CAST(first_contact_date AS DATE)  AS first_contact_date,
  landing_page_id,
  -- rule 28: a blank origin and "unknown" both mean not recorded
  COALESCE(NULLIF(trim(origin), ''), 'unknown') AS origin
FROM olist.raw.leads;

CREATE OR REPLACE TABLE olist.analytics.silver_closed_deals
COMMENT 'Silver. One row per lead that signed up as a seller. flag_no_orders_in_data marks the 462 sellers we cannot follow into orders.'
AS
SELECT
  d.mql_id,
  d.seller_id,
  d.sdr_id,
  d.sr_id,
  try_to_timestamp(d.won_date)                              AS won_ts,
  COALESCE(d.business_segment, 'unknown')                   AS business_segment,
  COALESCE(d.lead_type, 'unknown')                          AS lead_type,
  d.lead_behaviour_profile,
  d.business_type,
  -- rule 30: 797 of 842 declare 0, which means the field was left blank
  NULLIF(TRY_CAST(d.declared_monthly_revenue AS DOUBLE), 0) AS declared_monthly_revenue,
  -- rule 29: kept in the funnel, but no performance can be measured
  s.seller_id IS NULL                                       AS flag_no_orders_in_data
FROM olist.raw.closed_deals AS d
LEFT JOIN (SELECT DISTINCT seller_id FROM olist.raw.order_items) AS s
  ON s.seller_id = d.seller_id;

-- ------------------------------------------------------------
-- 11. Quarantine: every row set aside, from every table, with its
--     reason and the raw row as JSON so a person can look at it.
--     No key: a table can set aside several rows with the same key.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.analytics.quarantine
COMMENT 'Raw rows set aside by a Silver rule, from every table, with the reason and the raw row as JSON.'
AS
SELECT 'orders' AS source_table, order_id AS record_key, quarantine_reason AS reason, raw_row,
       current_timestamp() AS quarantined_at
FROM olist.analytics.stg_orders WHERE quarantine_reason IS NOT NULL
UNION ALL
SELECT 'order_items', concat(order_id, ' / ', CAST(order_item_id AS STRING)), quarantine_reason, raw_row,
       current_timestamp()
FROM olist.analytics.stg_order_items WHERE quarantine_reason IS NOT NULL
UNION ALL
SELECT 'order_payments', concat(order_id, ' / ', CAST(payment_sequential AS STRING)), quarantine_reason, raw_row,
       current_timestamp()
FROM olist.analytics.stg_order_payments WHERE quarantine_reason IS NOT NULL
UNION ALL
SELECT 'order_reviews', concat(review_id, ' / ', order_id), quarantine_reason, raw_row,
       current_timestamp()
FROM olist.analytics.stg_order_reviews WHERE quarantine_reason IS NOT NULL
UNION ALL
-- rule 25: distinct points outside Brazil. Exact copies are not
-- quarantined: they are the same point again, not a bad row.
SELECT 'geolocation', zip_prefix, 'location outside Brazil',
       to_json(struct(zip_prefix, lat, lng, city, state)), current_timestamp()
FROM olist.analytics.stg_geolocation
WHERE NOT (lat BETWEEN -33.8 AND 5.3 AND lng BETWEEN -73.99 AND -34.7)
   OR lat IS NULL OR lng IS NULL;

-- ------------------------------------------------------------
-- 12. Quarantine summary. Expected today: 3 payments with type
--     not_defined and 33 geolocation points outside Brazil. The
--     profile counted 42 raw rows outside Brazil; 9 of them were
--     exact copies, removed before the quarantine. Removing those
--     points leaves one zip prefix with no location, so 279
--     customers (not the 278 of the profile) get flag_zip_not_in_geolocation.
-- ------------------------------------------------------------
SELECT source_table, reason, COUNT(*) AS row_count
FROM olist.analytics.quarantine
GROUP BY source_table, reason
ORDER BY source_table, row_count DESC;
