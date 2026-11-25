-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     02_profile_bronze.sql
-- Owner:    TODO name
-- Purpose:  Measure every data problem in olist.raw before we
--           clean anything, following the steps from the class
--           tutorials: inspect the tables, check each table's
--           grain and key, see how duplicates inflate a join,
--           then find missing, invalid and mismatched values.
--           Results go in docs/data_quality_log.md.
-- Run:      Read-only. Changes nothing. Run after 01_load_raw.sql.
--           Every "Expected" value below was first computed on the
--           same files with DuckDB, reading every column as text,
--           and matched the Databricks run of 2026-11-17.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-17
--           (see docs/ai_usage.md).
--           Revised with Claude, 2026-11-24, after an audit: one
--           comment corrected (query 8), and the repeated-reviews
--           query also counts the orders whose scores differ (202).
--           Reviewed and understood by: TODO name
-- ============================================================

-- ------------------------------------------------------------
-- 1. What is there?
--    Expected: 13 tables. Every column from a CSV file is text
--    (STRING). Each table also has three columns added at load:
--    _rescued_data, _source_file and _loaded_at.
-- ------------------------------------------------------------
SHOW TABLES IN olist.raw;

SELECT table_name,
       COUNT(*) AS column_count,
       array_join(transform(sort_array(collect_list(struct(ordinal_position, column_name))), c -> c.column_name), ', ') AS columns
FROM olist.information_schema.columns
WHERE table_schema = 'raw'
GROUP BY table_name
ORDER BY table_name;

-- ------------------------------------------------------------
-- 2. Size of each table
--    Expected: orders 99,441; order_items 112,650; order_payments
--    103,886; order_reviews 99,224; customers 99,441; sellers 3,095;
--    products 32,951; geolocation 1,000,163; category_translation 71;
--    leads 8,000; closed_deals 842; ibge_states 27;
--    ibge_population_2018 1 row, with 27 states nested inside it
--    (section 7 unnests them).
-- ------------------------------------------------------------
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM olist.raw.orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM olist.raw.order_items
UNION ALL SELECT 'order_payments',       COUNT(*) FROM olist.raw.order_payments
UNION ALL SELECT 'order_reviews',        COUNT(*) FROM olist.raw.order_reviews
UNION ALL SELECT 'customers',            COUNT(*) FROM olist.raw.customers
UNION ALL SELECT 'sellers',              COUNT(*) FROM olist.raw.sellers
UNION ALL SELECT 'products',             COUNT(*) FROM olist.raw.products
UNION ALL SELECT 'geolocation',          COUNT(*) FROM olist.raw.geolocation
UNION ALL SELECT 'category_translation', COUNT(*) FROM olist.raw.category_translation
UNION ALL SELECT 'leads',                COUNT(*) FROM olist.raw.leads
UNION ALL SELECT 'closed_deals',         COUNT(*) FROM olist.raw.closed_deals
UNION ALL SELECT 'ibge_population_2018', COUNT(*) FROM olist.raw.ibge_population_2018
UNION ALL SELECT 'ibge_states',          COUNT(*) FROM olist.raw.ibge_states;

-- ------------------------------------------------------------
-- 3. Grain and key: what one row means, and which columns make
--    it unique. A key holds when distinct_keys = row_count.
--    Expected:
--      orders          order_id                          99,441 of 99,441
--      order_items     order_id + order_item_id         112,650 of 112,650
--      order_payments  order_id + payment_sequential    103,886 of 103,886
--      order_reviews   review_id                         98,410 of 99,224  NOT a key
--      order_reviews   review_id + order_id              99,224 of 99,224
--      order_reviews   order_id                          98,673 of 99,224  NOT a key
--      customers       customer_id                       99,441 of 99,441
--      customers       customer_unique_id (a person)     96,096 of 99,441  NOT a key
--      sellers         seller_id                          3,095 of 3,095
--      products        product_id                        32,951 of 32,951
--      geolocation     zip code prefix                   19,015 of 1,000,163  NOT a key
--      geolocation     the whole row                    738,332 of 1,000,163  exact copies
--      category_translation  product_category_name           71 of 71
--      leads           mql_id                             8,000 of 8,000
--      closed_deals    mql_id                               842 of 842
--      closed_deals    seller_id                            842 of 842
--      ibge_states     id                                    27 of 27
-- ------------------------------------------------------------
SELECT 'orders: order_id' AS table_and_key, COUNT(*) AS row_count, COUNT(DISTINCT order_id) AS distinct_keys FROM olist.raw.orders
UNION ALL SELECT 'order_items: order_id + order_item_id', COUNT(*), COUNT(DISTINCT order_id, order_item_id) FROM olist.raw.order_items
UNION ALL SELECT 'order_payments: order_id + payment_sequential', COUNT(*), COUNT(DISTINCT order_id, payment_sequential) FROM olist.raw.order_payments
UNION ALL SELECT 'order_reviews: review_id', COUNT(*), COUNT(DISTINCT review_id) FROM olist.raw.order_reviews
UNION ALL SELECT 'order_reviews: review_id + order_id', COUNT(*), COUNT(DISTINCT review_id, order_id) FROM olist.raw.order_reviews
UNION ALL SELECT 'order_reviews: order_id', COUNT(*), COUNT(DISTINCT order_id) FROM olist.raw.order_reviews
UNION ALL SELECT 'customers: customer_id', COUNT(*), COUNT(DISTINCT customer_id) FROM olist.raw.customers
UNION ALL SELECT 'customers: customer_unique_id', COUNT(*), COUNT(DISTINCT customer_unique_id) FROM olist.raw.customers
UNION ALL SELECT 'sellers: seller_id', COUNT(*), COUNT(DISTINCT seller_id) FROM olist.raw.sellers
UNION ALL SELECT 'products: product_id', COUNT(*), COUNT(DISTINCT product_id) FROM olist.raw.products
UNION ALL SELECT 'geolocation: zip code prefix', COUNT(*), COUNT(DISTINCT geolocation_zip_code_prefix) FROM olist.raw.geolocation
UNION ALL SELECT 'geolocation: whole row', COUNT(*),
  (SELECT COUNT(*) FROM (SELECT DISTINCT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state FROM olist.raw.geolocation))
  FROM olist.raw.geolocation
UNION ALL SELECT 'category_translation: product_category_name', COUNT(*), COUNT(DISTINCT product_category_name) FROM olist.raw.category_translation
UNION ALL SELECT 'leads: mql_id', COUNT(*), COUNT(DISTINCT mql_id) FROM olist.raw.leads
UNION ALL SELECT 'closed_deals: mql_id', COUNT(*), COUNT(DISTINCT mql_id) FROM olist.raw.closed_deals
UNION ALL SELECT 'closed_deals: seller_id', COUNT(*), COUNT(DISTINCT seller_id) FROM olist.raw.closed_deals
UNION ALL SELECT 'ibge_states: id', COUNT(*), COUNT(DISTINCT id) FROM olist.raw.ibge_states;

-- Repeated reviews. Expected: 789 review ids appear more than once
-- (each time on a different order), 547 orders have two or more
-- reviews, 202 of them with different scores, and 768 orders have none.
SELECT
  (SELECT COUNT(*) FROM (SELECT review_id FROM olist.raw.order_reviews GROUP BY review_id HAVING COUNT(*) > 1)) AS review_ids_repeated,
  (SELECT COUNT(*) FROM (SELECT order_id FROM olist.raw.order_reviews GROUP BY order_id HAVING COUNT(*) > 1)) AS orders_with_2plus_reviews,
  (SELECT COUNT(*) FROM (SELECT order_id FROM olist.raw.order_reviews GROUP BY order_id HAVING COUNT(DISTINCT review_score) > 1)) AS orders_with_different_scores,
  (SELECT COUNT(*) FROM olist.raw.orders o
    WHERE NOT EXISTS (SELECT 1 FROM olist.raw.order_reviews r WHERE r.order_id = o.order_id)) AS orders_without_review;

-- ------------------------------------------------------------
-- 4. How a join on the wrong grain inflates the numbers
--    a) Items joined to payments: 112,650 item rows become 117,601,
--       and item value grows from 15,843,553.24 to 16,566,543.85
--       (+4.6%), because an order paid in several parts repeats
--       every item once per payment row.
--    b) Customers joined to geolocation on the zip prefix: 99,441
--       customers become 15,083,455 rows, because a zip prefix has
--       52.6 geolocation rows on average and up to 1,146.
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM olist.raw.order_items) AS item_rows,
  (SELECT COUNT(*) FROM olist.raw.order_items i JOIN olist.raw.order_payments p ON i.order_id = p.order_id) AS rows_after_join_to_payments,
  (SELECT ROUND(SUM(CAST(price AS DECIMAL(12,2)) + CAST(freight_value AS DECIMAL(12,2))), 2) FROM olist.raw.order_items) AS item_value,
  (SELECT ROUND(SUM(CAST(i.price AS DECIMAL(12,2)) + CAST(i.freight_value AS DECIMAL(12,2))), 2)
     FROM olist.raw.order_items i JOIN olist.raw.order_payments p ON i.order_id = p.order_id) AS item_value_after_join;

SELECT
  (SELECT COUNT(*) FROM olist.raw.customers) AS customer_rows,
  (SELECT COUNT(*) FROM olist.raw.customers c
     JOIN olist.raw.geolocation g ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix) AS rows_after_join_to_geolocation,
  (SELECT ROUND(AVG(n), 1) FROM (SELECT COUNT(*) AS n FROM olist.raw.geolocation GROUP BY geolocation_zip_code_prefix)) AS avg_rows_per_zip,
  (SELECT MAX(n) FROM (SELECT COUNT(*) AS n FROM olist.raw.geolocation GROUP BY geolocation_zip_code_prefix)) AS max_rows_per_zip;

-- ------------------------------------------------------------
-- 5. Missing values
--    Orders: which dates are blank, by status. Expected for
--    delivered (96,478 orders): 14 without an approval date, 2
--    without a carrier date, 8 without a delivery date. Canceled
--    (625): 6 of them have a delivery date.
-- ------------------------------------------------------------
SELECT order_status,
       COUNT(*) AS orders,
       SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END)             AS no_approval_date,
       SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END)  AS no_carrier_date,
       SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS no_delivery_date,
       SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS no_estimated_date
FROM olist.raw.orders
GROUP BY order_status
ORDER BY orders DESC;

-- Other blanks. Expected: 610 products without a category and 2
-- without a weight; 58,247 reviews without a comment and 87,656
-- without a title; 60 leads without an origin (and 1,099 more say
-- "unknown"); closed deals: 1 without a segment, 6 without a lead
-- type, 779 without has_company, 797 declare a monthly revenue of 0.
SELECT
  (SELECT COUNT(*) FROM olist.raw.products WHERE product_category_name IS NULL) AS products_no_category,
  (SELECT COUNT(*) FROM olist.raw.products WHERE product_weight_g IS NULL) AS products_no_weight,
  (SELECT COUNT(*) FROM olist.raw.order_reviews WHERE review_comment_message IS NULL) AS reviews_no_comment,
  (SELECT COUNT(*) FROM olist.raw.order_reviews WHERE review_comment_title IS NULL) AS reviews_no_title,
  (SELECT COUNT(*) FROM olist.raw.leads WHERE origin IS NULL) AS leads_no_origin,
  (SELECT COUNT(*) FROM olist.raw.leads WHERE origin = 'unknown') AS leads_origin_unknown,
  (SELECT COUNT(*) FROM olist.raw.closed_deals WHERE business_segment IS NULL) AS deals_no_segment,
  (SELECT COUNT(*) FROM olist.raw.closed_deals WHERE lead_type IS NULL) AS deals_no_lead_type,
  (SELECT COUNT(*) FROM olist.raw.closed_deals WHERE has_company IS NULL) AS deals_no_has_company,
  (SELECT COUNT(*) FROM olist.raw.closed_deals WHERE CAST(declared_monthly_revenue AS DOUBLE) = 0) AS deals_revenue_zero;

-- ------------------------------------------------------------
-- 6. Invalid values and dates in an impossible order
--    Expected: no unreadable purchase date, price or review score;
--    383 items with zero freight; 3 payments of type "not_defined";
--    9 payments of 0; 2 payments in 0 installments.
--    Dates: 166 orders handed to the carrier before they were even
--    bought, and 1,359 before they were approved; 23 delivered before
--    the carrier had them; none approved, delivered or promised before
--    the purchase. 4 seller shipping deadlines fall in 2019 or 2020,
--    more than a year after the last order.
--    "Late" must be counted by calendar day. The promised date has no
--    time of day (it is always midnight), so comparing timestamps calls
--    an order that arrived during the promised day late. Of the 96,470
--    delivered orders with a delivery date, 7,826 are late by timestamp
--    but only 6,534 by day: 1,292 arrived on the promised day.
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM olist.raw.orders WHERE order_purchase_timestamp IS NOT NULL AND try_to_timestamp(order_purchase_timestamp) IS NULL) AS unreadable_purchase_date,
  (SELECT COUNT(*) FROM olist.raw.order_items WHERE try_cast(price AS DOUBLE) IS NULL OR CAST(price AS DOUBLE) <= 0) AS unreadable_or_zero_price,
  (SELECT COUNT(*) FROM olist.raw.order_items WHERE CAST(freight_value AS DOUBLE) = 0) AS zero_freight,
  (SELECT COUNT(*) FROM olist.raw.order_payments WHERE payment_type = 'not_defined') AS payment_type_not_defined,
  (SELECT COUNT(*) FROM olist.raw.order_payments WHERE CAST(payment_value AS DOUBLE) = 0) AS payment_value_zero,
  (SELECT COUNT(*) FROM olist.raw.order_payments WHERE CAST(payment_installments AS INT) = 0) AS installments_zero,
  (SELECT COUNT(*) FROM olist.raw.order_reviews WHERE review_score NOT IN ('1', '2', '3', '4', '5')) AS invalid_review_score;

SELECT
  SUM(CASE WHEN try_to_timestamp(order_delivered_carrier_date) < try_to_timestamp(order_purchase_timestamp) THEN 1 ELSE 0 END)    AS carrier_before_purchase,
  SUM(CASE WHEN try_to_timestamp(order_delivered_carrier_date) < try_to_timestamp(order_approved_at) THEN 1 ELSE 0 END)           AS carrier_before_approval,
  SUM(CASE WHEN try_to_timestamp(order_delivered_customer_date) < try_to_timestamp(order_delivered_carrier_date) THEN 1 ELSE 0 END) AS delivered_before_carrier,
  SUM(CASE WHEN try_to_timestamp(order_approved_at) < try_to_timestamp(order_purchase_timestamp) THEN 1 ELSE 0 END)                 AS approved_before_purchase,
  SUM(CASE WHEN try_to_timestamp(order_delivered_customer_date) < try_to_timestamp(order_purchase_timestamp) THEN 1 ELSE 0 END)     AS delivered_before_purchase,
  SUM(CASE WHEN try_to_timestamp(order_estimated_delivery_date) < try_to_timestamp(order_purchase_timestamp) THEN 1 ELSE 0 END)     AS promised_before_purchase,
  SUM(CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END)                         AS delivered_with_date,
  SUM(CASE WHEN order_status = 'delivered'
            AND try_to_timestamp(order_delivered_customer_date) > try_to_timestamp(order_estimated_delivery_date) THEN 1 ELSE 0 END) AS late_by_timestamp,
  SUM(CASE WHEN order_status = 'delivered'
            AND to_date(try_to_timestamp(order_delivered_customer_date)) > to_date(try_to_timestamp(order_estimated_delivery_date)) THEN 1 ELSE 0 END) AS late_by_day,
  SUM(CASE WHEN order_status = 'delivered'
            AND to_date(try_to_timestamp(order_delivered_customer_date)) = to_date(try_to_timestamp(order_estimated_delivery_date)) THEN 1 ELSE 0 END) AS arrived_on_promised_day,
  SUM(CASE WHEN date_format(try_to_timestamp(order_estimated_delivery_date), 'HH:mm:ss') <> '00:00:00' THEN 1 ELSE 0 END)           AS promised_dates_with_a_time
FROM olist.raw.orders;

-- Seller deadlines far in the future. Expected: 4, the latest on
-- 2020-04-09, against a last order in October 2018.
SELECT COUNT(*) AS deadlines_2019_or_later, MAX(try_to_timestamp(shipping_limit_date)) AS latest_deadline
FROM olist.raw.order_items
WHERE try_to_timestamp(shipping_limit_date) >= TIMESTAMP '2019-01-01';

-- Orders shared by several sellers. The order has one carrier date,
-- but its items can come from different sellers with different
-- deadlines. Expected: 1,278 orders with items from two or more
-- sellers, and 336 orders with two or more different deadlines.
SELECT
  (SELECT COUNT(*) FROM (SELECT order_id FROM olist.raw.order_items GROUP BY order_id HAVING COUNT(DISTINCT seller_id) > 1)) AS orders_with_2plus_sellers,
  (SELECT COUNT(*) FROM (SELECT order_id FROM olist.raw.order_items GROUP BY order_id HAVING COUNT(DISTINCT shipping_limit_date) > 1)) AS orders_with_2plus_deadlines;

-- ------------------------------------------------------------
-- 7. Codes that do not match across tables and sources
--    Expected inside the marketplace: every item points to a known
--    order, product and seller; 775 orders have no item and 1 order
--    has no payment; 2 Portuguese categories (pc_gamer and
--    portateis_cozinha_e_preparadores_de_alimentos, 13 products)
--    have no English name.
--    Funnel to marketplace: every deal points to a known lead, but
--    462 of the 842 deal sellers are not in the marketplace data, so
--    380 can be followed into orders.
--    Marketplace to IBGE: all 27 customer states and all 23 seller
--    states match an IBGE abbreviation; 278 customers and 7 sellers
--    have a zip prefix that is not in the geolocation table.
-- ------------------------------------------------------------
-- A LEFT ANTI JOIN keeps the rows on the left that have no match on
-- the right, so each count below is "rows whose code points nowhere".
SELECT 'items with an unknown order' AS check_name, COUNT(*) AS row_count
  FROM olist.raw.order_items i LEFT ANTI JOIN olist.raw.orders o ON o.order_id = i.order_id
UNION ALL SELECT 'items with an unknown product', COUNT(*)
  FROM olist.raw.order_items i LEFT ANTI JOIN olist.raw.products p ON p.product_id = i.product_id
UNION ALL SELECT 'items with an unknown seller', COUNT(*)
  FROM olist.raw.order_items i LEFT ANTI JOIN olist.raw.sellers s ON s.seller_id = i.seller_id
UNION ALL SELECT 'orders without any item', COUNT(*)
  FROM olist.raw.orders o LEFT ANTI JOIN olist.raw.order_items i ON i.order_id = o.order_id
UNION ALL SELECT 'orders without any payment', COUNT(*)
  FROM olist.raw.orders o LEFT ANTI JOIN olist.raw.order_payments p ON p.order_id = o.order_id
UNION ALL SELECT 'orders with an unknown customer', COUNT(*)
  FROM olist.raw.orders o LEFT ANTI JOIN olist.raw.customers c ON c.customer_id = o.customer_id
UNION ALL SELECT 'reviews with an unknown order', COUNT(*)
  FROM olist.raw.order_reviews r LEFT ANTI JOIN olist.raw.orders o ON o.order_id = r.order_id;

SELECT p.product_category_name AS category_without_english_name, COUNT(*) AS products
FROM olist.raw.products p
LEFT ANTI JOIN olist.raw.category_translation t ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY products DESC;

-- Across sources. A LEFT SEMI JOIN keeps the rows that do have a match.
SELECT 'deals with an unknown lead' AS check_name, COUNT(*) AS row_count
  FROM olist.raw.closed_deals d LEFT ANTI JOIN olist.raw.leads l ON l.mql_id = d.mql_id
UNION ALL SELECT 'deal sellers not in the marketplace data', COUNT(*)
  FROM olist.raw.closed_deals d LEFT ANTI JOIN olist.raw.sellers s ON s.seller_id = d.seller_id
UNION ALL SELECT 'deal sellers in the marketplace data', COUNT(*)
  FROM olist.raw.closed_deals d LEFT SEMI JOIN olist.raw.sellers s ON s.seller_id = d.seller_id
UNION ALL SELECT 'customer states not in the IBGE list', COUNT(DISTINCT c.customer_state)
  FROM olist.raw.customers c LEFT ANTI JOIN olist.raw.ibge_states s ON s.sigla = c.customer_state
UNION ALL SELECT 'seller states not in the IBGE list', COUNT(DISTINCT x.seller_state)
  FROM olist.raw.sellers x LEFT ANTI JOIN olist.raw.ibge_states s ON s.sigla = x.seller_state
UNION ALL SELECT 'customers whose zip prefix is not in geolocation', COUNT(*)
  FROM olist.raw.customers c LEFT ANTI JOIN olist.raw.geolocation g ON g.geolocation_zip_code_prefix = c.customer_zip_code_prefix
UNION ALL SELECT 'sellers whose zip prefix is not in geolocation', COUNT(*)
  FROM olist.raw.sellers x LEFT ANTI JOIN olist.raw.geolocation g ON g.geolocation_zip_code_prefix = x.seller_zip_code_prefix;

-- The IBGE population answer, unnested: one row per state.
-- Expected: 27 states and 208,494,900 people in 2018. IBGE names
-- states by number (35 is Sao Paulo); Olist uses letters (SP).
-- ibge_states holds both, so it is the bridge between the two.
SELECT COUNT(*) AS states, SUM(CAST(s.serie.`2018` AS BIGINT)) AS population_2018
FROM (SELECT explode(r.series) AS s
      FROM (SELECT explode(resultados) AS r FROM olist.raw.ibge_population_2018));

-- ------------------------------------------------------------
-- 8. Text that looks alike but is not
--    Expected: every customer zip prefix has 5 characters and 23,995
--    start with a zero (a number type would drop it); 73,442
--    geolocation rows spell the city with accents (so "sao paulo"
--    and "são paulo" both appear); 8,556 zip prefixes carry two or
--    more city spellings; 8 zip prefixes sit in two states; 42
--    geolocation rows fall outside a rough box around Brazil (11 of
--    them are the Fernando de Noronha islands, which are Brazilian;
--    Silver keeps those).
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM olist.raw.customers WHERE length(customer_zip_code_prefix) <> 5) AS customer_zip_not_5_characters,
  (SELECT COUNT(*) FROM olist.raw.customers WHERE customer_zip_code_prefix LIKE '0%') AS customer_zip_starts_with_zero,
  (SELECT COUNT(*) FROM olist.raw.geolocation WHERE geolocation_city RLIKE '[^ -~]') AS geolocation_rows_with_accents,
  (SELECT COUNT(*) FROM (SELECT geolocation_zip_code_prefix FROM olist.raw.geolocation
                         GROUP BY geolocation_zip_code_prefix HAVING COUNT(DISTINCT geolocation_city) > 1)) AS zips_with_2plus_city_spellings,
  (SELECT COUNT(*) FROM (SELECT geolocation_zip_code_prefix FROM olist.raw.geolocation
                         GROUP BY geolocation_zip_code_prefix HAVING COUNT(DISTINCT geolocation_state) > 1)) AS zips_in_2plus_states,
  (SELECT COUNT(*) FROM olist.raw.geolocation
    WHERE CAST(geolocation_lat AS DOUBLE) > 5.3 OR CAST(geolocation_lat AS DOUBLE) < -33.8
       OR CAST(geolocation_lng AS DOUBLE) > -34.7 OR CAST(geolocation_lng AS DOUBLE) < -73.99) AS geolocation_outside_brazil;

-- ------------------------------------------------------------
-- 9. The values a slicer would show
--    Expected order statuses: delivered 96,478; shipped 1,107;
--    canceled 625; unavailable 609; invoiced 314; processing 301;
--    created 5; approved 2. Payment types: credit_card 76,795;
--    boleto 19,784; voucher 5,775; debit_card 1,529; not_defined 3.
--    Lead origins: 10 named channels, "unknown" 1,099, blank 60.
-- ------------------------------------------------------------
SELECT order_status, COUNT(*) AS orders FROM olist.raw.orders GROUP BY order_status ORDER BY orders DESC;
SELECT payment_type, COUNT(*) AS payment_rows FROM olist.raw.order_payments GROUP BY payment_type ORDER BY payment_rows DESC;
SELECT origin, COUNT(*) AS leads FROM olist.raw.leads GROUP BY origin ORDER BY leads DESC;

-- ------------------------------------------------------------
-- 10. Did every row parse?
--     read_files puts anything it cannot fit into a table's columns in
--     the extra column _rescued_data. Expected: 0 rows with rescued data
--     in every table. 3,852 review comments contain a line break, which
--     is why 01_load_raw.sql reads the files with multiLine; without it
--     each of those reviews would be cut into pieces.
-- ------------------------------------------------------------
SELECT 'orders' AS table_name, COUNT(*) AS rows_with_rescued_data FROM olist.raw.orders WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'order_items',          COUNT(*) FROM olist.raw.order_items          WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'order_payments',       COUNT(*) FROM olist.raw.order_payments       WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'order_reviews',        COUNT(*) FROM olist.raw.order_reviews        WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'customers',            COUNT(*) FROM olist.raw.customers            WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'sellers',              COUNT(*) FROM olist.raw.sellers              WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'products',             COUNT(*) FROM olist.raw.products             WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'geolocation',          COUNT(*) FROM olist.raw.geolocation          WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'category_translation', COUNT(*) FROM olist.raw.category_translation WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'leads',                COUNT(*) FROM olist.raw.leads                WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'closed_deals',         COUNT(*) FROM olist.raw.closed_deals         WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'ibge_population_2018', COUNT(*) FROM olist.raw.ibge_population_2018 WHERE _rescued_data IS NOT NULL
UNION ALL SELECT 'ibge_states',          COUNT(*) FROM olist.raw.ibge_states          WHERE _rescued_data IS NOT NULL;

SELECT COUNT(*) AS reviews_with_line_break
FROM olist.raw.order_reviews
WHERE instr(review_comment_message, chr(10)) > 0 OR instr(review_comment_message, chr(13)) > 0;
