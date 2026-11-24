# Metric dictionary

Every rate is a measure in the metric view `olist.analytics.delivery_metrics`, so a dashboard filter recalculates it instead of reading a stored value. Every rule is a column in Gold. This chapter gives each definition, where it lives, and its value on the current data.

## The orders a metric counts

| Set | Definition | Orders |
| --- | --- | ---: |
| All orders | Every order in `fact_orders` | 99,441 |
| In window | Bought from 2017-01-01 and promised by 2018-08-31. Deliveries stop being recorded after August 2018, so a promise is judged only once its day has passed inside the data | 97,048 |
| Judged | In window, not canceled or unavailable, delivery date known | 95,901 |
| Single-seller | Judged, all items from one seller: the only orders with a route | 94,684 |

## Delivery metrics

| Metric | Definition | Where | Value |
| --- | --- | --- | ---: |
| Broken promise | A judged order not delivered by the end of the promised day: delivered on a later calendar day, or not delivered | `fact_orders.is_broken` | 8,227 orders |
| Broken-promise rate | Broken promises / judged orders | measure `broken_rate` | 8.6% |
| Margin of error | 95% interval of a rate: 1.96 x sqrt(p(1-p)/n), shown as plus or minus points | measure `broken_rate_margin`; `gold_routes.margin` | |
| Rate with a promise 3 days later | Judged orders still late with 3 more days | measure `broken_rate_if_3_days_later` | 6.6% |
| Missed by 1 to 3 days | Share of broken promises delivered 1 to 3 days late | measure `share_broken_missed_by_1_to_3_days` | 22.7% |
| Median days late | Median days late of delivered broken promises | measure `median_days_late` | 8 in the Northeast |
| Handed over by the deadline | Of delivered broken promises, the share whose carrier date is on or before the seller's deadline | measure `share_late_handed_over_by_deadline` | 72.2% |
| Days to carrier, carrier to customer | Average days purchase to carrier, and carrier to customer; empty when the two dates are in an impossible order | measures `avg_days_to_carrier`, `avg_days_carrier_to_customer` | |
| Median delivery days | Median days purchase to delivery | measure `median_delivery_days` | |

## Review metrics

| Metric | Definition | Where | Value |
| --- | --- | --- | ---: |
| Low review | The order's latest review gives 1 or 2 stars (one score per order, rule 18) | `fact_orders.is_low_review` | 14,205 in window |
| Low reviews after a broken promise | Share of in-window low reviews whose order broke its promise. Counts canceled orders too: their bad reviews are part of the pile | measure `share_low_reviews_after_broken_promise` | 36.7% |
| Reviewed before arrival | Of delivered late orders with a review, the share answered before the parcel arrived | measure `share_late_reviewed_before_arrival` | 70.1% |
| Score before and after arrival | Average score of late orders reviewed before / after arrival | measures `avg_score_late_before_arrival`, `avg_score_late_after_arrival` | 1.65 / 3.72 |
| Score, kept and broken | Average score of judged orders that kept / broke their promise | measures `avg_score_kept`, `avg_score_broken` | |

## Route and month rules

| Rule | Definition | Where | Value |
| --- | --- | --- | --- |
| Route | Seller state > customer state, single-seller orders | `fact_orders.route` | 409 routes |
| Excess broken promises | A route's broken promises minus its orders x the national single-seller rate (8.7%) | `gold_routes.excess_broken` | SP > RJ: 678 |
| Busy month | National rate at least twice the median month (6.89%) | `gold_months.is_busy_month` | Nov 2017, Feb 2018, Mar 2018 |
| Lasting fix | The route's rate outside busy months, minus its margin, is above the national rate there (6.4%) | `gold_routes.needs_lasting_fix` | SP > BA, PE, PI ... |
| Busy-season plan | The route's excess in busy months (against the national busy-month rate) is larger than in the other months | `gold_routes.needs_busy_season_plan` | PR > RJ, SP > SC ... |
| Fix type | Both, Lasting fix, Busy-season plan, Watch (excess but neither test), No fix needed (no excess) | `gold_routes.fix_type` | SP > RJ: Both |

## State and funnel measures (Dashboard 3)

| Metric | Definition | Where | Value |
| --- | --- | --- | --- |
| Orders per 100,000 residents | Every order bought September 2017 to August 2018, any status, / IBGE 2018 population x 100,000 | `gold_states.orders_per_100k_12m` | RJ 56.4, SP 71.7 |
| Active sellers per million | Sellers with an order in those 12 months / population x 1,000,000 | `gold_states.active_sellers_per_million_12m` | RJ 8.5, SP 35.2 |
| Orders from another state | Share of the state's single-seller orders shipped from another state | `gold_states.share_from_other_state_12m` | RJ 91.5% |
| Local seller | Seller in the customer's state | `fact_orders.is_local_seller`; dimension `seller_location` | RJ: 7.7% broken, 5 days |
| Funnel recruits who sold | Funnel sellers with at least one order; share by state | `gold_states.share_of_funnel_sellers` | SP 61.1%, RJ 6.8% |

## Design choices

- **Calendar days, not timestamps.** The promised date has no time of day. Comparing timestamps would call 1,292 on-time deliveries late.
- **One score per order.** The latest review counts, so an order with two reviews is not averaged twice.
- **Rates in the metric view, rules in Gold.** A filter recalculates a rate; a rule that compares busy months with the rest of the year (fix type) must not change with a month filter, so it is stored.
- **Routes only for single-seller orders.** 1,278 orders have several sellers but one carrier date, so we cannot tell whose parcel the date records. They stay in every total.
- **The category of an order is its first item's category**, so an order counts once in the category filter.

## Fairness

Region and state say where the problem is; they never rank a seller. Northeast customers get worse service, 15.6% (plus or minus 0.8) against 7.8% (plus or minus 0.2) in the Southeast, and the trust page shows the gap with its margins instead of hiding it. The fixes aim at routes and carriers, not at customers. If Olist later scores sellers, it should use only the handover to the carrier, which the seller controls.

## Known weaknesses

- Every link between promises and reviews is a correlation.
- We found the busy-month rule by looking at the same data, so it must be judged again on new months.
- The data has no carrier name or tracking event, so why Sao Paulo to Rio breaks stays a question for Olist and its carriers.
- The data ends in August 2018: we deliver rules a monthly refresh would rerun, not a list for today.
- Only 380 of the 842 signed sellers appear in the orders, and the leads carry no location.
