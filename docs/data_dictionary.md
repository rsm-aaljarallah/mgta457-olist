# Data dictionary

Every table and view in `olist.analytics`, built from the live catalog on the day of the last build. Column names and types are exact. Measures of the metric view are queried with `MEASURE()`.

## Gold: the star schema

### fact_orders

Table. Gold fact. One row per order: promise, delivery, broken-promise outcome, latest review, route (single-seller orders) and the flags that keep a measure honest.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `customer_id` | string | Customer record on one order. The person is `customer_unique_id`. |
| `customer_unique_id` | string | The person who bought (one person can have several `customer_id`). |
| `customer_state` | string | Customer state. |
| `order_status` | string | Status as recorded: delivered, shipped, canceled, unavailable, invoiced, processing, created, approved. |
| `purchase_ts` | timestamp | When the order was bought. |
| `purchase_date` | date | Day the order was bought. |
| `approved_ts` | timestamp | When payment was approved. |
| `carrier_ts` | timestamp | When the seller handed the order to the carrier. |
| `delivered_ts` | timestamp | When the customer received the order. |
| `delivered_date` | date | Day the customer received the order. |
| `promised_date` | date | Delivery day promised at checkout. It has no time of day. |
| `item_count` | bigint | Item lines in the order. |
| `item_value` | decimal(20,2) | Sum of item prices, BRL. |
| `freight_value` | decimal(20,2) | Freight charged, BRL. |
| `payment_value` | decimal(20,2) | Amount paid, BRL. On `fact_orders`, all payments of the order summed (rule 15). |
| `seller_count` | bigint | Distinct sellers in the order. |
| `seller_id` | string | Seller id. On `fact_orders`, empty when several sellers shipped the order. |
| `seller_state` | string | Seller state. On `fact_orders`, empty when several sellers shipped the order. |
| `seller_deadline_ts` | timestamp | Latest item deadline, single-seller orders only; deadlines in 2019 or later left out. |
| `category` | string | Product category in English (Portuguese when no translation, `unknown` when blank). On `fact_orders`, the first item's category. |
| `review_id` | string | Review id. One review can cover several orders bought together. |
| `review_score` | int | Stars, 1 to 5. On `fact_orders`, the order's latest review. |
| `review_creation_date` | date | Day the review survey was sent. |
| `review_answer_ts` | timestamp | When the customer answered the review. |
| `flag_several_sellers` | boolean | Rule 13: items from two or more sellers, so the one carrier date cannot be credited to a seller. |
| `flag_delivered_without_date` | boolean | Rule 4: status delivered but no delivery date. |
| `flag_canceled_with_delivery` | boolean | Rule 5: canceled but has a delivery date. |
| `flag_carrier_before_purchase` | boolean | Rule 6: carrier date before the purchase. |
| `flag_carrier_before_approval` | boolean | Rule 7: carrier date before the approval. |
| `flag_delivered_before_carrier` | boolean | Rule 8: delivered before the carrier date. |
| `flag_outside_full_months` | boolean | Rule 9: bought before 2017 or after August 2018. |
| `is_in_window` | boolean | Bought from 2017-01-01 and promised by 2018-08-31. |
| `is_judged` | boolean | In window, not canceled or unavailable, and not one of the 8 orders marked delivered with no delivery date. An order that never arrived is judged. Every broken-promise rate counts these. |
| `is_broken` | int | 1 when a judged order was not delivered by the end of the promised day, else 0. |
| `is_broken_if_3_days_later` | int | 1 when it would still be broken with a promise 3 days later. |
| `days_vs_promise` | int | Delivery day minus promised day: negative early, positive late. |
| `delivery_days` | int | Days from purchase to delivery. |
| `days_to_carrier` | int | Days from purchase to the carrier; empty when the carrier date is before the purchase. |
| `days_carrier_to_customer` | int | Days from the carrier to the customer; empty when delivery is before the carrier date. |
| `promised_days` | int | Days from purchase to the promised day. |
| `promise_bucket` | string | Days early or late, grouped (Dashboard 1). |
| `promise_bucket_order` | int | Sort order of `promise_bucket`, early to late. |
| `delivery_time_band` | string | Delivery time by week (Dashboard 1). |
| `route` | string | Seller state > customer state, single-seller orders only. |
| `is_local_seller` | boolean | Seller in the customer's state; single-seller orders only. |
| `is_low_review` | int | 1 when the latest review gives 1 or 2 stars. |
| `reviewed_before_arrival` | boolean | The review was answered before delivery; delivered orders only. |
| `handed_over_by_deadline` | boolean | The carrier date is on or before the seller's deadline. |

### fact_order_items

Table. Gold fact. One row per item line (order_id + order_item_id): product, seller, price, freight and the seller's deadline to hand the item to the carrier.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `order_item_id` | int | Item line number within the order (1, 2, ...). |
| `product_id` | string | Product id. |
| `seller_id` | string | Seller id. On `fact_orders`, empty when several sellers shipped the order. |
| `seller_state` | string | Seller state. On `fact_orders`, empty when several sellers shipped the order. |
| `customer_state` | string | Customer state. |
| `purchase_date` | date | Day the order was bought. |
| `shipping_limit_ts` | timestamp | The seller's deadline to hand the item to the carrier. |
| `price` | decimal(10,2) | Item price, BRL. |
| `freight_value` | decimal(10,2) | Freight charged, BRL. |
| `flag_deadline_after_2018` | boolean | Rule 12: seller deadline in 2019 or later. |
| `flag_several_sellers` | boolean | Rule 13: items from two or more sellers, so the one carrier date cannot be credited to a seller. |

### dim_date

Table. Gold dimension. One row per day, September 2016 to December 2018, with month, year and the busy-month flag from gold_months.

| Column | Type | Meaning |
| --- | --- | --- |
| `date_key` | date | Calendar day. |
| `month_start` | date | First day of the month. |
| `year` | int | Year. |
| `month` | int | Month number. |
| `month_label` | string | Month as text, e.g. Nov 2017. |
| `is_full_month` | boolean | Day between January 2017 and August 2018 (rule 9). |
| `is_busy_month` | boolean | Month's national broken-promise rate is at least twice the median month. |

### dim_state

Table. Gold dimension. One row per Brazilian state: name, region, area (Southeast split into Rio and the rest) and 2018 IBGE population.

| Column | Type | Meaning |
| --- | --- | --- |
| `state` | string | State, two letters (SP, RJ, ...). |
| `state_name` | string | State name (IBGE spelling). |
| `state_code` | int | IBGE numeric state code (35 = Sao Paulo). |
| `region` | string | IBGE region in English: North, Northeast, Southeast, South, Center-West. |
| `area` | string | Region with the Southeast split into Rio de Janeiro and the rest. |
| `population_2018` | bigint | IBGE 2018 estimated resident population. |

### dim_seller

Table. Gold dimension. One row per seller: state, city, and the funnel channel and segment for sellers who came through the marketing funnel.

| Column | Type | Meaning |
| --- | --- | --- |
| `seller_id` | string | Seller id. On `fact_orders`, empty when several sellers shipped the order. |
| `seller_state` | string | Seller state. On `fact_orders`, empty when several sellers shipped the order. |
| `seller_city` | string | Seller city. |
| `came_through_funnel` | boolean | The seller signed through the marketing funnel. |
| `funnel_origin` | string | Marketing channel, for funnel sellers. |
| `funnel_segment` | string | Business segment, for funnel sellers. |
| `funnel_lead_type` | string | Lead type, for funnel sellers. |
| `funnel_won_date` | date | Day the deal was signed, for funnel sellers. |

### dim_product

Table. Gold dimension. One row per product, with its category in English (Portuguese when no translation exists, unknown when blank).

| Column | Type | Meaning |
| --- | --- | --- |
| `product_id` | string | Product id. |
| `category` | string | Product category in English (Portuguese when no translation, `unknown` when blank). On `fact_orders`, the first item's category. |
| `category_pt` | string | Product category in Portuguese. |
| `product_weight_g` | int | Weight, grams. |

## Gold: business rules

### gold_months

Table. Gold. One row per purchase month, Jan 2017 to Aug 2018: judged orders, broken promises, rate, the median month and the busy-month flag.

| Column | Type | Meaning |
| --- | --- | --- |
| `month_start` | date | First day of the month. |
| `judged_orders` | bigint | Judged orders. |
| `broken_orders` | bigint | Broken promises. |
| `broken_rate` | double | Broken promises / judged orders. |
| `median_rate` | double | Median of the 20 monthly rates (6.89%). |
| `is_busy_month` | boolean | Month's national broken-promise rate is at least twice the median month. |

### gold_routes

Table. Gold. One row per route (seller state > customer state, single-seller orders): orders, broken rate, margin, excess broken promises, rank and fix type.

| Column | Type | Meaning |
| --- | --- | --- |
| `route` | string | Seller state > customer state, single-seller orders only. |
| `seller_state` | string | Seller state. On `fact_orders`, empty when several sellers shipped the order. |
| `customer_state` | string | Customer state. |
| `orders` | bigint | Judged single-seller orders on the route. |
| `broken_orders` | bigint | Broken promises on the route. |
| `orders_busy` | bigint | Of those, bought in busy months. |
| `broken_busy` | bigint | Broken promises in busy months. |
| `orders_other` | bigint | Of those, bought in other months. |
| `broken_other` | bigint | Broken promises in other months. |
| `national_rate` | double | National broken rate, single-seller orders (8.7%). |
| `national_rate_busy` | double | National rate in busy months, single-seller orders. |
| `national_rate_other` | double | National rate in other months, single-seller orders (6.4%). |
| `broken_rate` | double | The route's broken rate. |
| `margin` | double | 95% margin of error of `broken_rate`: 1.96 x sqrt(p(1-p)/n). |
| `excess_broken` | double | Broken promises minus orders x national rate. |
| `rate_other` | double | The route's rate outside busy months. |
| `margin_other` | double | 95% margin of `rate_other`. |
| `excess_busy` | double | Excess in busy months, against the national busy-month rate. |
| `excess_other` | double | Excess in other months, against the national rate there. |
| `needs_lasting_fix` | boolean | The lasting-fix test alone: `rate_other` minus `margin_other` is above `national_rate_other`. `fix_type` also needs 100 orders. |
| `needs_busy_season_plan` | boolean | The busy-season test alone: `excess_busy` is larger than `excess_other`. `fix_type` also needs 100 orders. |
| `excess_rank` | int | Rank by `excess_broken`, largest first. |
| `fix_type` | string | No fix needed (no excess); Watch (excess but fewer than 100 orders, or neither test met); otherwise Both, Lasting fix or Busy-season plan. |
| `first_step` | string | Suggested first step for the fix type; empty when no fix is needed. |
| `customer_region` | string | Customer region. |

### gold_states

Table. Gold. One row per state: 12-month orders per 100,000 residents, active sellers per million, share of single-seller orders from another state, broken rate, and shares of orders, sellers and funnel recruits.

| Column | Type | Meaning |
| --- | --- | --- |
| `state` | string | State, two letters (SP, RJ, ...). |
| `state_name` | string | State name (IBGE spelling). |
| `region` | string | IBGE region in English: North, Northeast, Southeast, South, Center-West. |
| `area` | string | Region with the Southeast split into Rio de Janeiro and the rest. |
| `population_2018` | bigint | IBGE 2018 estimated resident population. |
| `orders_12m` | bigint | Orders bought Sep 2017 to Aug 2018, any status. |
| `orders_per_100k_12m` | double | `orders_12m` per 100,000 residents. |
| `active_sellers_12m` | bigint | Sellers in the state with an order in those 12 months. |
| `active_sellers_per_million_12m` | double | `active_sellers_12m` per million residents. |
| `share_from_other_state_12m` | double | Share of the state's single-seller orders shipped from another state. |
| `judged_orders` | bigint | Judged orders of the state's customers. |
| `broken_orders` | bigint | Broken promises of the state's customers. |
| `broken_rate` | double | Broken rate of the state's customers. |
| `share_of_orders_12m` | double | The state's share of all orders in those 12 months. |
| `share_of_sellers` | double | The state's share of all sellers. |
| `share_of_funnel_sellers` | double | The state's share of funnel sellers who sold. |

## Metric view

### delivery_metrics

Metric view. Olist delivery-promise metrics. Grain of the source: one row per order (fact_orders).

| Column | Type | Meaning |
| --- | --- | --- |
| `purchase_month` | date | First day of the month the order was bought |
| `purchase_year` | int | Year the order was bought |
| `is_busy_month` | boolean | Bought in a busy month (gold_months): Nov 2017, Feb 2018, Mar 2018 |
| `customer_state` | string | Customer state, two letters |
| `customer_region` | string | Customer region (IBGE): North, Northeast, Southeast, South, Center-West |
| `customer_area` | string | Customer region with the Southeast split into Rio de Janeiro and the rest |
| `seller_state` | string | Seller state; empty for orders shipped by several sellers |
| `seller_region` | string | Seller region; empty for orders shipped by several sellers |
| `route` | string | Seller state > customer state; single-seller orders only |
| `seller_location` | string | Where the seller is, seen from the customer. 'Several sellers or no item' holds the orders without a single seller: several sellers, or no item line |
| `category` | string | Product category of the order's first item, in English where a translation exists |
| `order_status` | string | Order status as recorded |
| `promise_outcome` | string | Broken or kept, for judged orders |
| `promise_bucket` | string | Days before or after the promised day, grouped |
| `promise_bucket_order` | int | Sort order of promise_bucket, early to late |
| `promise_bucket_label` | string | promise_bucket with its sort number in front, so a chart axis runs from early to late; orders never delivered come last |
| `delivery_time_band` | string | Days from purchase to delivery, by week |
| `orders` | bigint | All orders |
| `judged_orders` | bigint | Orders whose promise can be judged |
| `broken_orders` | bigint | Judged orders not delivered by the end of the promised day |
| `broken_rate` | double | Broken promises divided by judged orders |
| `broken_rate_margin` | double | 95% margin of error of broken_rate, as a fraction (0.008 = plus or minus 0.8 points). It is 0 when no order or every order broke, so read it only on a few hundred orders or more |
| `broken_rate_if_3_days_later` | double | The broken rate if every promise had been 3 days later |
| `share_broken_missed_by_1_to_3_days` | double | Share of broken promises that arrived 1 to 3 days late |
| `median_days_late` | double | Median days late of broken promises that were delivered |
| `low_reviews` | bigint | Orders in the window whose latest review gives 1 or 2 stars |
| `low_reviews_after_broken_promise` | bigint | Of those, orders whose promise was broken |
| `share_low_reviews_after_broken_promise` | double | Of in-window orders whose latest review gives 1 or 2 stars, canceled ones included, the share that followed a broken promise |
| `avg_review_score` | double | Average latest review score of judged orders |
| `avg_score_kept` | double | Average latest review score of judged orders that kept their promise |
| `avg_score_broken` | double | Average latest review score of broken promises |
| `share_late_reviewed_before_arrival` | double | Of delivered broken promises with a review, the share answered before the parcel arrived (answer time before delivery time) |
| `avg_score_late_before_arrival` | double | Average score of late orders reviewed before arrival |
| `avg_score_late_after_arrival` | double | Average score of late orders reviewed after arrival |
| `share_late_handed_over_by_deadline` | double | Of delivered broken promises from one seller, the share handed to the carrier by the seller's deadline (carrier time at or before the deadline time) |
| `avg_days_to_carrier` | double | Average days from purchase to the carrier, judged orders that arrived and whose two gaps are both measured, so it stacks with avg_days_carrier_to_customer |
| `avg_days_carrier_to_customer` | double | Average days from the carrier to the customer, on the same orders as avg_days_to_carrier |
| `median_delivery_days` | double | Median days from purchase to delivery, judged orders |
| `median_promised_days` | double | Median days promised at checkout, judged orders |

## Views the dashboards read

### route_list

View. Dashboard 2. Routes with excess broken promises, ranked, with rate, margin, fix type and first step.

| Column | Type | Meaning |
| --- | --- | --- |
| `excess_rank` | int | Rank by `excess_broken`, largest first. |
| `route` | string | Seller state > customer state, single-seller orders only. |
| `seller_state` | string | Seller state. On `fact_orders`, empty when several sellers shipped the order. |
| `customer_state` | string | Customer state. |
| `customer_region` | string | Customer region. |
| `orders` | bigint | Judged single-seller orders on the route. |
| `broken_orders` | bigint | Broken promises. |
| `broken_pct` | double | Broken rate, percent (0 to 100). |
| `margin_pts` | string | 95% margin in percentage points, as text; a dash under 100 orders, where the formula is not reliable. |
| `excess_broken` | double | Excess broken promises, rounded. |
| `broken_pct_outside_busy_months` | double | Broken rate outside busy months, percent. |
| `fix_type` | string | No fix needed (no excess); Watch (excess but fewer than 100 orders, or neither test met); otherwise Both, Lasting fix or Busy-season plan. |
| `first_step` | string | Suggested first step for the fix type; empty when no fix is needed. |

### state_view

View. Dashboard 3. One row per state: orders per 100,000 residents, broken rate, sellers per million, and shares of orders, sellers and funnel recruits.

| Column | Type | Meaning |
| --- | --- | --- |
| `state` | string | State, two letters (SP, RJ, ...). |
| `state_name` | string | State name (IBGE spelling). |
| `region` | string | IBGE region in English: North, Northeast, Southeast, South, Center-West. |
| `orders_per_100k` | double | Orders per 100,000 residents, 12 months to Aug 2018. |
| `broken_pct` | double | Broken rate, percent (0 to 100). |
| `active_sellers_per_million` | double | Active sellers per million residents. |
| `pct_orders_from_other_state` | double | Percent of the state's single-seller orders in the 12 months shipped from another state. |
| `pct_of_orders` | double | Percent of all orders, 12 months. |
| `pct_of_sellers` | double | Percent of all sellers. |
| `pct_of_funnel_recruits` | double | Percent of funnel sellers who sold. |

### region_fairness

View. Dashboard 2, trust page. Broken-promise rate by customer region with its 95% margin, in points.

| Column | Type | Meaning |
| --- | --- | --- |
| `region` | string | IBGE region in English: North, Northeast, Southeast, South, Center-West. |
| `judged_orders` | bigint | Judged orders of the region's customers. |
| `broken_orders` | bigint | Broken promises. |
| `broken_pct` | double | Broken rate, percent (0 to 100). |
| `margin_pts` | double | 95% margin, percentage points. |

### deliveries_per_month

View. Dashboard 2, trust page. Orders delivered per calendar month of delivery, all months in the data.

| Column | Type | Meaning |
| --- | --- | --- |
| `delivery_month` | date | Month the orders were delivered. |
| `deliveries` | bigint | Orders delivered that month. |

### quarantine_summary

View. Dashboard 2, trust page. Rows set aside in Silver, by table and reason.

| Column | Type | Meaning |
| --- | --- | --- |
| `table_and_reason` | string | Source table and quarantine reason. |
| `row_count` | bigint | Rows. |

## Checks

### pipeline_checks

View. One row per pipeline check with its result. Every row should say PASS.

| Column | Type | Meaning |
| --- | --- | --- |
| `check_no` | int | Check number. |
| `check_name` | string | What the check tests. |
| `result` | string | PASS, FAIL, WARN, ESCALATE or PAGE (MATCH or DIFFERS in `design_doc_numbers`). |
| `detail` | string | The counts behind the result. |

### silver_rule_counts

View. One row per Silver rule: table, rule, action (FIX, KEEP, FLAG, QUARANTINE) and the rows it touched in the current build.

| Column | Type | Meaning |
| --- | --- | --- |
| `rule_no` | int | Rule number in docs/data_quality_log.md. |
| `table_name` | string | Table the rule applies to. |
| `rule` | string | What the rule does. |
| `action` | string | FIX, KEEP, FLAG or QUARANTINE. |
| `row_count` | bigint | Rows. |

### design_doc_numbers

View. Every result printed in the design document, recomputed from Gold, next to the printed value.

| Column | Type | Meaning |
| --- | --- | --- |
| `number` | string | The number as named in the design document. |
| `doc_value` | string | The number as printed in the design document. |
| `gold_value` | string | The same number recomputed from Gold today. |
| `result` | string | PASS, FAIL, WARN, ESCALATE or PAGE (MATCH or DIFFERS in `design_doc_numbers`). |

## Silver and quarantine

### silver_orders

Table. Silver. One row per order, dates typed, with flags for dates in an impossible order and for orders shared by several sellers.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `customer_id` | string | Customer record on one order. The person is `customer_unique_id`. |
| `order_status` | string | Status as recorded: delivered, shipped, canceled, unavailable, invoiced, processing, created, approved. |
| `purchase_ts` | timestamp | When the order was bought. |
| `approved_ts` | timestamp | When payment was approved. |
| `carrier_ts` | timestamp | When the seller handed the order to the carrier. |
| `delivered_ts` | timestamp | When the customer received the order. |
| `promised_date` | date | Delivery day promised at checkout. It has no time of day. |
| `flag_several_sellers` | boolean | Rule 13: items from two or more sellers, so the one carrier date cannot be credited to a seller. |
| `flag_delivered_without_date` | boolean | Rule 4: status delivered but no delivery date. |
| `flag_canceled_with_delivery` | boolean | Rule 5: canceled but has a delivery date. |
| `flag_carrier_before_purchase` | boolean | Rule 6: carrier date before the purchase. |
| `flag_carrier_before_approval` | boolean | Rule 7: carrier date before the approval. |
| `flag_delivered_before_carrier` | boolean | Rule 8: delivered before the carrier date. |
| `flag_outside_full_months` | boolean | Rule 9: bought before 2017 or after August 2018. |

### silver_order_items

Table. Silver. One row per item line of an order (order_id + order_item_id), price and freight as decimals.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `order_item_id` | int | Item line number within the order (1, 2, ...). |
| `product_id` | string | Product id. |
| `seller_id` | string | Seller id. On `fact_orders`, empty when several sellers shipped the order. |
| `shipping_limit_ts` | timestamp | The seller's deadline to hand the item to the carrier. |
| `price` | decimal(10,2) | Item price, BRL. |
| `freight_value` | decimal(10,2) | Freight charged, BRL. |
| `flag_deadline_after_2018` | boolean | Rule 12: seller deadline in 2019 or later. |

### silver_order_payments

Table. Silver. One row per payment of an order (order_id + payment_sequential). Sum to one row per order before joining to items.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `payment_sequential` | int | Payment number within the order. |
| `payment_type` | string | credit_card, boleto, voucher or debit_card. |
| `payment_installments` | int | Installments chosen. Not used in any measure (rule 16). |
| `payment_value` | decimal(10,2) | Amount paid, BRL. On `fact_orders`, all payments of the order summed (rule 15). |

### silver_order_reviews

Table. Silver. One row per review on one order (review_id + order_id). is_latest_for_order marks the one review per order that score measures use.

| Column | Type | Meaning |
| --- | --- | --- |
| `review_id` | string | Review id. One review can cover several orders bought together. |
| `order_id` | string | Order id. |
| `review_score` | int | Stars, 1 to 5. On `fact_orders`, the order's latest review. |
| `review_comment_title` | string | Review title, often blank. |
| `review_comment_message` | string | Review text in Portuguese, often blank. |
| `review_creation_date` | date | Day the review survey was sent. |
| `review_answer_ts` | timestamp | When the customer answered the review. |
| `is_latest_for_order` | boolean | Rule 18: the one review per order that score measures use. |

### silver_customers

Table. Silver. One row per customer_id (a customer record on one order); customer_unique_id is the person.

| Column | Type | Meaning |
| --- | --- | --- |
| `customer_id` | string | Customer record on one order. The person is `customer_unique_id`. |
| `customer_unique_id` | string | The person who bought (one person can have several `customer_id`). |
| `zip_prefix` | string | First 5 digits of the zip code, kept as text so a leading 0 is not lost. |
| `city` | string | City as written in the source. |
| `city_match` | string | City in lower case without accents, with ´ or ` read as an apostrophe, for matching. |
| `state` | string | State, two letters (SP, RJ, ...). |
| `flag_zip_not_in_geolocation` | boolean | Rule 26: the zip prefix has no location. |

### silver_sellers

Table. Silver. One row per seller.

| Column | Type | Meaning |
| --- | --- | --- |
| `seller_id` | string | Seller id. On `fact_orders`, empty when several sellers shipped the order. |
| `zip_prefix` | string | First 5 digits of the zip code, kept as text so a leading 0 is not lost. |
| `city` | string | City as written in the source. |
| `city_match` | string | City in lower case without accents, with ´ or ` read as an apostrophe, for matching. |
| `state` | string | State, two letters (SP, RJ, ...). |
| `flag_zip_not_in_geolocation` | boolean | Rule 26: the zip prefix has no location. |

### silver_products

Table. Silver. One row per product, with its category in Portuguese and English.

| Column | Type | Meaning |
| --- | --- | --- |
| `product_id` | string | Product id. |
| `category_pt` | string | Product category in Portuguese. |
| `category` | string | Product category in English (Portuguese when no translation, `unknown` when blank). On `fact_orders`, the first item's category. |
| `product_name_length` | int | Characters in the product name (renamed from `lenght`, rule 22). |
| `product_description_length` | int | Characters in the description (renamed from `lenght`, rule 22). |
| `product_photos_qty` | int | Photos on the listing. |
| `product_weight_g` | int | Weight, grams. |
| `product_length_cm` | int | Length, cm. |
| `product_height_cm` | int | Height, cm. |
| `product_width_cm` | int | Width, cm. |

### silver_geolocation

Table. Silver. One row per zip code prefix: average latitude and longitude of its distinct points inside Brazil.

| Column | Type | Meaning |
| --- | --- | --- |
| `zip_prefix` | string | First 5 digits of the zip code, kept as text so a leading 0 is not lost. |
| `lat` | double | Average latitude of the prefix's distinct points. |
| `lng` | double | Average longitude of the prefix's distinct points. |
| `distinct_points` | bigint | Distinct location points averaged for the prefix. |

### silver_leads

Table. Silver. One row per seller who asked to join Olist (marketing-qualified lead), with the channel they came from.

| Column | Type | Meaning |
| --- | --- | --- |
| `mql_id` | string | Marketing-qualified lead id: a seller who asked to join Olist. |
| `first_contact_date` | date | Day the lead first contacted Olist. |
| `landing_page_id` | string | Landing page the lead arrived on. |
| `origin` | string | Marketing channel of the lead; blank became `unknown` (rule 28). |

### silver_closed_deals

Table. Silver. One row per lead that signed up as a seller. flag_no_orders_in_data marks the 462 sellers we cannot follow into orders.

| Column | Type | Meaning |
| --- | --- | --- |
| `mql_id` | string | Marketing-qualified lead id: a seller who asked to join Olist. |
| `seller_id` | string | Seller id. On `fact_orders`, empty when several sellers shipped the order. |
| `sdr_id` | string | Sales development representative who worked the lead. |
| `sr_id` | string | Sales representative who closed the deal. |
| `won_ts` | timestamp | When the deal was signed. |
| `business_segment` | string | Segment the seller declared. |
| `lead_type` | string | Lead type from the sales team. |
| `lead_behaviour_profile` | string | Behaviour profile from the sales team. |
| `business_type` | string | Reseller, manufacturer or other. |
| `declared_monthly_revenue` | double | Monthly revenue the seller declared; 0 became empty (rule 30). |
| `flag_no_orders_in_data` | boolean | Rule 29: the signed seller never appears in the orders. |

### silver_states

Table. Silver. One row per Brazilian state: IBGE code, two-letter abbreviation, name, region and 2018 population.

| Column | Type | Meaning |
| --- | --- | --- |
| `state_code` | int | IBGE numeric state code (35 = Sao Paulo). |
| `state` | string | State, two letters (SP, RJ, ...). |
| `state_name` | string | State name (IBGE spelling). |
| `region_code` | string | IBGE region abbreviation (N, NE, SE, S, CO). |
| `region_name_pt` | string | IBGE region name in Portuguese. |
| `region` | string | IBGE region in English. |
| `population_2018` | bigint | IBGE 2018 estimated resident population. |

### quarantine

Table. Raw rows set aside by a Silver rule, from every table, with the reason and the raw row as JSON.

| Column | Type | Meaning |
| --- | --- | --- |
| `source_table` | string | Raw table the row came from. |
| `record_key` | string | The row's key, as far as it can be read. |
| `reason` | string | Why the row was set aside. |
| `raw_row` | string | The raw row as JSON, so a person can look at it. |
| `quarantined_at` | timestamp | When the build set it aside. |

## Staging views (where the Silver rules live)

### stg_orders

View. Staging. Every raw order, typed, with flags and a quarantine_reason if it fails a rule.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `customer_id` | string | Customer record on one order. The person is `customer_unique_id`. |
| `order_status` | string | Status as recorded: delivered, shipped, canceled, unavailable, invoiced, processing, created, approved. |
| `purchase_ts` | timestamp | When the order was bought. |
| `approved_ts` | timestamp | When payment was approved. |
| `carrier_ts` | timestamp | When the seller handed the order to the carrier. |
| `delivered_ts` | timestamp | When the customer received the order. |
| `promised_date` | date | Delivery day promised at checkout. It has no time of day. |
| `raw_row` | string | The raw row as JSON, so a person can look at it. |
| `flag_several_sellers` | boolean | Rule 13: items from two or more sellers, so the one carrier date cannot be credited to a seller. |
| `flag_delivered_without_date` | boolean | Rule 4: status delivered but no delivery date. |
| `flag_canceled_with_delivery` | boolean | Rule 5: canceled but has a delivery date. |
| `flag_carrier_before_purchase` | boolean | Rule 6: carrier date before the purchase. |
| `flag_carrier_before_approval` | boolean | Rule 7: carrier date before the approval. |
| `flag_delivered_before_carrier` | boolean | Rule 8: delivered before the carrier date. |
| `flag_outside_full_months` | boolean | Rule 9: bought before 2017 or after August 2018. |
| `quarantine_reason` | string | Why the row is set aside; empty for a row that passes. |

### stg_order_items

View. Staging. Every raw item line, typed, with a quarantine_reason if it fails a rule.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `order_item_id` | int | Item line number within the order (1, 2, ...). |
| `product_id` | string | Product id. |
| `seller_id` | string | Seller id. On `fact_orders`, empty when several sellers shipped the order. |
| `shipping_limit_ts` | timestamp | The seller's deadline to hand the item to the carrier. |
| `price` | decimal(10,2) | Item price, BRL. |
| `freight_value` | decimal(10,2) | Freight charged, BRL. |
| `raw_row` | string | The raw row as JSON, so a person can look at it. |
| `flag_deadline_after_2018` | boolean | Rule 12: seller deadline in 2019 or later. |
| `quarantine_reason` | string | Why the row is set aside; empty for a row that passes. |

### stg_order_payments

View. Staging. Every raw payment, typed, with a quarantine_reason if it fails a rule.

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | string | Order id. |
| `payment_sequential` | int | Payment number within the order. |
| `payment_type` | string | credit_card, boleto, voucher or debit_card. |
| `payment_installments` | int | Installments chosen. Not used in any measure (rule 16). |
| `payment_value` | decimal(10,2) | Amount paid, BRL. On `fact_orders`, all payments of the order summed (rule 15). |
| `raw_row` | string | The raw row as JSON, so a person can look at it. |
| `quarantine_reason` | string | Why the row is set aside; empty for a row that passes. |

### stg_order_reviews

View. Staging. Every raw review, typed, with a quarantine_reason if it fails a rule.

| Column | Type | Meaning |
| --- | --- | --- |
| `review_id` | string | Review id. One review can cover several orders bought together. |
| `order_id` | string | Order id. |
| `review_score` | int | Stars, 1 to 5. On `fact_orders`, the order's latest review. |
| `review_comment_title` | string | Review title, often blank. |
| `review_comment_message` | string | Review text in Portuguese, often blank. |
| `review_creation_date` | date | Day the review survey was sent. |
| `review_answer_ts` | timestamp | When the customer answered the review. |
| `raw_row` | string | The raw row as JSON, so a person can look at it. |
| `quarantine_reason` | string | Why the row is set aside; empty for a row that passes. |

### stg_geolocation

View. Staging. Distinct raw geolocation points, typed. Feeds silver_geolocation and the quarantine.

| Column | Type | Meaning |
| --- | --- | --- |
| `zip_prefix` | string | First 5 digits of the zip code, kept as text so a leading 0 is not lost. |
| `lat` | double | Latitude. |
| `lng` | double | Longitude. |
| `city` | string | City as written in geolocation. |
| `state` | string | State as written in geolocation (not used; rule 27). |
