# Data quality log

**Status, 2026-11-24: the 31 rules are built in `sql/03_silver.sql`.** The numbers come from `sql/02_profile_bronze.sql`. They were first computed with DuckDB on the same files, reading every column as text the way `olist.raw` holds them, then run in Databricks through the CLI on 2026-11-17 and again on 2026-11-24: all 23 queries returned the expected values both times. Every raw table parsed cleanly (no row in `_rescued_data`), including the 3,852 reviews whose comment contains a line break. The view `olist.analytics.silver_rule_counts` shows the rows each rule touches in the current build; two counts moved from the profile:

- Rule 25 sets aside 33 geolocation points, not 42: 9 of the 42 raw rows outside Brazil were exact copies, removed first.
- Rule 26 flags 279 customers, not 278: removing those points leaves one more zip prefix without a location.
- Rule 21 changes no customer or seller city: the accents are all in geolocation, whose city Silver does not keep.

This follows the steps the professor described for the Silver layer: define the grain and key of each table, find duplicates and invalid or missing values, decide what to keep or quarantine, give the reason for each rule, and state our assumptions.

## Grain and key of every table

| Table | One row is | Key | Does the key hold? |
| --- | --- | --- | --- |
| `orders` | one order | `order_id` | Yes, 99,441 of 99,441. An order has one carrier date even when its items come from several sellers (1,278 orders) |
| `order_items` | one item line of an order | `order_id` + `order_item_id` | Yes, 112,650 of 112,650 |
| `order_payments` | one payment of an order (an order can be paid in parts) | `order_id` + `payment_sequential` | Yes, 103,886 of 103,886 |
| `order_reviews` | one review attached to one order | `review_id` + `order_id` | Yes, 99,224 of 99,224. `review_id` alone does not hold (98,410 distinct), nor does `order_id` (98,673 distinct) |
| `customers` | one customer account on one order | `customer_id` | Yes, 99,441. The person is `customer_unique_id`: 96,096 people |
| `sellers` | one seller | `seller_id` | Yes, 3,095 |
| `products` | one product | `product_id` | Yes, 32,951 |
| `geolocation` | one location point of a zip code prefix | none | No: 1,000,163 rows for 19,015 prefixes, and only 738,332 distinct rows |
| `category_translation` | one product category | `product_category_name` | Yes, 71 |
| `leads` | one seller who asked to join (marketing-qualified lead) | `mql_id` | Yes, 8,000 |
| `closed_deals` | one lead that signed up as a seller | `mql_id` (and `seller_id`) | Yes, 842 |
| `ibge_population_2018` | one IBGE variable, with the 27 states nested inside | none at this level; one row per state once unnested | 1 row, 27 states inside |
| `ibge_states` | one state | `id` (IBGE numeric code) | Yes, 27 |

## What the profile found

**Duplicates.** 261,831 geolocation rows (26.2%) are exact copies of another row. 789 review ids are attached to two or more orders. Each time it is the same person giving the same score, so one review covers several orders bought together. 547 orders have two or more reviews, and in 202 of them the scores differ.

**Joins on the wrong grain.** Joining items straight to payments turns 112,650 item rows into 117,601 and item value from 15,843,553.24 into 16,566,543.85 (+4.6%), because an order paid in several parts repeats its items once per payment. Joining customers straight to geolocation turns 99,441 customers into 15,083,455 rows, because a zip prefix has 52.6 location rows on average and up to 1,146. And 1,278 orders hold items from two or more sellers but have a single carrier date, so that date cannot be credited to one seller.

**Missing values.** Of the 96,478 delivered orders, 14 have no approval date, 2 no carrier date and 8 no delivery date. 610 products have no category and 2 no weight. 58,247 reviews have no comment and 87,656 no title. 60 leads have no origin and 1,099 more say "unknown". In the closed deals, 1 has no segment, 6 no lead type and 779 no `has_company`, and 797 of 842 declare a monthly revenue of 0.

**Invalid values and impossible dates.** No purchase date, price or review score is unreadable. 383 items have zero freight. 3 payments have the type `not_defined`; all three are 0.00 and on canceled orders. Another 6 payment rows are vouchers of 0.00, and 2 credit-card payments have 0 installments. 166 orders reached the carrier before they were even bought, and 1,359 before they were approved. 23 reached the customer before the carrier had them. 6 canceled orders have a delivery date. 4 seller shipping deadlines fall in 2019 or 2020, more than a year after the last order. No order was approved, delivered or promised before it was bought.

**"Late" depends on how you count it.** The promised delivery date never has a time of day: it is always midnight. Comparing timestamps therefore calls an order late when it arrived during the promised day. Of the 96,470 delivered orders with a delivery date, 7,826 are late by timestamp, but only 6,534 by calendar day; 1,292 arrived on the promised day. We count by day.

**Codes that do not match.** Every item points to a known order, product and seller. 775 orders have no item; they are mostly canceled or unavailable. 1 order has no payment. 2 Portuguese categories have no English name: `pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos`, 13 products in all. Every closed deal points to a known lead. But 462 of the 842 deal sellers never appear in the order data, so 380 can be followed into orders. All 27 customer states and 23 seller states match an IBGE abbreviation. 278 customers and 7 sellers have a zip prefix that is not in the geolocation table.

**Text that looks alike but is not.** Zip prefixes are 5 characters, and 23,995 customers' prefixes start with 0. A number type would drop that zero and break the join to geolocation. 73,442 geolocation rows spell the city with accents, so "sao paulo" and "são paulo" both appear. 8,556 zip prefixes carry two or more city spellings, 8 prefixes sit in two states, and 42 location points fall outside Brazil.

**Time coverage.** Orders run from September 2016 to October 2018, but they are not spread evenly:

- 2016 has 329 orders (4 in September, 324 in October, 0 in November, 1 in December).
- From January 2017 to August 2018 every month has between 800 and 7,544 orders: 800 in January 2017, a peak of 7,544 in November 2017, and 6,000 to 7,300 a month through 2018.
- September and October 2018 have 16 and 4 orders.

The deals run from December 2017 to November 2018. None of the 50 sellers who signed after August 2018 appears in the order data.

## Proposed Silver rules

Actions, as in the class tutorials: **FIX** corrects a format or fixes a definition, **KEEP** chooses one version of a record, **QUARANTINE** sets a row aside in a quarantine table with its reason, **FLAG** keeps the row and marks it so a measure can leave it out. Rows are today's counts.

| # | Table | Rule | Action | Rows today | Why |
| --- | --- | --- | --- | ---: | --- |
| 1 | orders | Read the five dates as timestamps; an unreadable purchase date is set aside | FIX / QUARANTINE | 0 | An order without a readable purchase date cannot be placed in a month |
| 2 | orders | A status outside the 8 known values is set aside | QUARANTINE | 0 | A new status must be looked at before it is counted as a sale or a cancellation |
| 3 | orders | Late means delivered on a later calendar day than promised | FIX | 6,534 late (7,826 by timestamp) | The promised date has no time of day, so a delivery during the promised day is on time |
| 4 | orders | Delivered but no delivery date: counted as a sale, left out of delivery-time measures | FLAG | 8 | The sale happened; only its delivery time is unknown |
| 5 | orders | Canceled but has a delivery date: stays canceled | FLAG | 6 | The status is the latest word on the order; we cannot tell what the date means |
| 6 | orders | Carrier date before the purchase: kept, but no time is measured from purchase or approval to the carrier | FLAG | 166 | A parcel cannot leave before it is bought, so one of the two dates is wrong, and we cannot tell which |
| 7 | orders | Carrier date before approval date: kept, but the approval-to-carrier time is not measured | FLAG | 1,359 | 1.4% of orders, too many to drop, and we cannot tell which of the two dates is wrong |
| 8 | orders | Customer delivery before the carrier date: kept, but the carrier-to-customer time is not measured | FLAG | 23 | Same reason as rule 7 |
| 9 | orders | Monthly views cover January 2017 to August 2018 only; every order stays in Silver | FLAG | 349 outside | 2016 and September-October 2018 hold a few hundred orders against thousands a month in between; a chart that includes them shows a collapse that is a gap in the data, not in the business |
| 10 | order_items | A repeated `order_id` + `order_item_id` keeps one copy | KEEP | 0 | The key must hold before items are summed |
| 11 | order_items | Price and freight as DECIMAL(10,2); an unreadable price or a price of 0 or less is set aside; zero freight is kept | FIX / QUARANTINE | 0 set aside, 383 zero freight kept | Free shipping is a real price; a free item is not |
| 12 | order_items | A shipping deadline in 2019 or later is kept but not used in any deadline measure | FLAG | 4 | A deadline more than a year after the last order is almost certainly a typing error |
| 13 | orders, order_items | An order with items from two or more sellers counts in sales, but not in any measure that credits the carrier date to a seller | FLAG | 1,278 | The order has one carrier date, so we cannot tell whose parcel it records |
| 14 | order_payments | Type `not_defined` is set aside | QUARANTINE | 3 | No money moved (0.00) and the method is unknown; all three orders were canceled |
| 15 | order_payments | Payments are summed to one row per order before any join to items | KEEP | all | Joining raw items to raw payments repeats items: +4.6% value |
| 16 | order_payments | Vouchers of 0.00 and 0 installments are kept as they are; installments are not used in any measure | KEEP | 6 and 2 | They change no amount, and we do not know what 0 installments means |
| 17 | order_reviews | Key is `review_id` + `order_id`; a review covering several orders stays on each of them; review counts use distinct `review_id` | KEEP | 789 review ids | Each order did get that review, but it is one opinion |
| 18 | order_reviews | One score per order: the latest review (latest answer time, then creation date, then `review_id`) | KEEP | 547 orders, 202 with different scores | The latest is the customer's final word, and one score per order stops an average from counting an order twice |
| 19 | order_reviews | A score outside 1 to 5 is set aside; a blank comment or title stays blank | QUARANTINE / KEEP | 0; 58,247 and 87,656 blanks | A score without words is still a score |
| 20 | customers, sellers | Zip prefix stays 5-character text | FIX | 23,995 customers start with 0 | A number type drops the leading zero and breaks the join |
| 21 | customers, sellers, geolocation | City matched in lower case without accents; the original kept for display | FIX | 73,442 geolocation rows with accents | "são paulo" and "sao paulo" are the same city |
| 22 | products | Rename `product_name_lenght` and `product_description_lenght` to `..._length` | FIX | 2 columns | Spelling in the source file |
| 23 | products | Blank category becomes `unknown` | FIX | 610 | These products sold; dropping them would remove real sales from category totals |
| 24 | products | A category without an English name keeps its Portuguese name | FIX | 2 categories, 13 products | We do not invent translations |
| 25 | geolocation | Remove exact copies, drop points outside Brazil, then one row per zip prefix (average latitude and longitude) | KEEP / QUARANTINE | 261,831 copies; 42 outside | One row per prefix makes the join safe: no more 15 million rows |
| 26 | customers, sellers | A zip prefix missing from geolocation gives an empty location | FLAG | 278 customers, 7 sellers | Their orders are real; only the distance is unknown |
| 27 | geolocation | The state comes from the customer or seller table, not from geolocation | KEEP | 8 prefixes in two states | One source of truth for the state |
| 28 | leads | Blank origin becomes `unknown` | FIX | 60 | Both mean the channel was not recorded |
| 29 | closed_deals | A deal seller with no orders in the data is kept in the funnel and has no performance measures | FLAG | 462 | 50 signed after the order data ends; for the other 412 the data does not say why |
| 30 | closed_deals | Declared monthly revenue of 0 becomes empty | FIX | 797 of 842 | 95% zeros means the field was mostly left blank, not that sellers earn nothing |
| 31 | ibge | Unnest the population answer to one row per state, then join the state list on the numeric code to get the abbreviation and region | FIX | 27 states | IBGE names states by number, Olist by letters; the state list is the bridge |

## Assumptions

| # | Assumption | What changes if it is wrong |
| --- | --- | --- |
| A1 | `customer_unique_id` is one person; `customer_id` is that person's record on one order | Repeat-buyer counts |
| A2 | `order_estimated_delivery_date` is the day promised to the customer at purchase, so a delivery at any time on that day is on time | Every "late" measure |
| A3 | `shipping_limit_date` is the seller's deadline to hand the item to the carrier. The data do not say who sets it | Any split of lateness between seller and carrier |
| A4 | All timestamps are Brazil local time, so we do not convert them | Day and hour of day; not months |
| A5 | The 2018 population is a fair base for 2017 and 2018 orders | Orders per 100,000 people by state, by a percent or so |
| A6 | A deal seller with no orders in the data has no measured performance; we do not read it as a seller who sold nothing | Any funnel-to-sales comparison |
| A7 | January 2017 to August 2018 is the period the data covers fully | Every monthly trend |

## Open questions for the team, and the answers we built

The design document of 2026-11-19 committed to the first answer of each, so `sql/03_silver.sql` applies them. Change the SQL if the team decides otherwise.

1. Rule 18: an order with several reviews takes the latest score, not the average.
2. Rules 6 to 8: orders with dates in an impossible order stay in every measure except the gap that cannot be measured.
3. Rule 25: geolocation is cleaned to one row per zip prefix, but no measure uses distance. Routes use states.
