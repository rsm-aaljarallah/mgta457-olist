# Metric dictionary

Every rate that a dashboard filter must recalculate is a measure in the metric view `olist.analytics.delivery_metrics`, so a filter changes the inputs of the formula, not a stored answer. A few rates are stored in Gold because a rule needs them (the busy months, the route fix types, the state measures); on every build, check 22 of `pipeline_checks` compares the judged and broken orders behind each stored month, route and state rate, and each route's split between busy and other months, with the metric view. The per-resident measures have no counterpart there. This chapter gives each definition, where it lives, and its value on the current data.

## The orders a metric counts

| Set | Definition | Orders |
| --- | --- | ---: |
| All orders | Every order in `fact_orders` | 99,441 |
| In window | Bought from 2017-01-01 and promised by 2018-08-31. Deliveries stop being recorded after August 2018, so a promise is judged only once its day has passed inside the data | 97,048 |
| Judged | In window, not canceled or unavailable, and not one of the 8 orders marked delivered with no delivery date. An order that never arrived is judged, and counts as broken | 95,901 |
| Single-seller | Judged, all items from one seller: the only judged orders with a route | 94,684 |

## Delivery metrics

| Metric | Definition | Where | Value |
| --- | --- | --- | ---: |
| Broken promise | A judged order not delivered by the end of the promised day: delivered on a later calendar day (6,531), shipped but never delivered (1,094), or never handed to a carrier (602) | `fact_orders.is_broken` | 8,227 orders |
| Broken-promise rate | Broken promises / judged orders | measure `broken_rate` | 8.6% |
| Margin of error | 95% interval of a rate: 1.96 x sqrt(p(1-p)/n), shown as plus or minus points. It is 0 when no order or every order broke, so the routes table shows a dash instead under 100 orders | measure `broken_rate_margin`; `gold_routes.margin` | |
| Rate with a promise 3 days later | Judged orders still late with 3 more days | measure `broken_rate_if_3_days_later` | 6.6% |
| Missed by 1 to 3 days | Share of all broken promises delivered 1 to 3 days late | measure `share_broken_missed_by_1_to_3_days` | 22.7% |
| Median days late | Median days late of the broken promises that were delivered | measure `median_days_late` | 8 days in the Northeast |
| Handed over by the deadline | Of delivered broken promises from one seller, the share whose carrier time is at or before the seller's deadline time (both are timestamps) | measure `share_late_handed_over_by_deadline` | 72.2% |
| Days to carrier, carrier to customer | Average days from purchase to the carrier and from the carrier to the customer, both over the same judged orders: delivered, with both gaps measurable (dates in an impossible order are left out), so the two parts add up to the delivery time | measures `avg_days_to_carrier`, `avg_days_carrier_to_customer` | broken 6.0 + 27.9; kept 3.0 + 8.0 |
| Median delivery days | Median days from purchase to delivery, judged orders | measure `median_delivery_days` | |

## Review metrics

| Metric | Definition | Where | Value |
| --- | --- | --- | ---: |
| Low review | The order's latest review gives 1 or 2 stars (one score per order, rule 18) | `fact_orders.is_low_review` | 14,205 orders in the window |
| Low reviews after a broken promise | Of the in-window orders with a low review, the share whose promise was broken. Canceled and unavailable orders count in the pile: their bad reviews are real, though they can never follow a broken promise | measure `share_low_reviews_after_broken_promise` | 36.7% |
| Reviewed before arrival | Of delivered broken promises with a review, the share answered before the parcel arrived, comparing the two timestamps | measure `share_late_reviewed_before_arrival` | 70.1% |
| Score before and after arrival | Average score of late orders reviewed before / after arrival | measures `avg_score_late_before_arrival`, `avg_score_late_after_arrival` | 1.65 / 3.72 |
| Score, kept and broken | Average score of judged orders that kept / broke their promise | measures `avg_score_kept`, `avg_score_broken` | |

## Route and month rules

| Rule | Definition | Where | Value |
| --- | --- | --- | --- |
| Route | Seller state > customer state, single-seller orders | `fact_orders.route` | 409 routes among judged orders (`gold_routes`); 413 with unjudged orders |
| Excess broken promises | A route's broken promises minus its orders x the national single-seller rate (8.7%) | `gold_routes.excess_broken` | SP > RJ: 678 |
| Busy month | National rate at least twice the median month (6.89%). November 2017 clears it by 15 broken promises | `gold_months.is_busy_month` | Nov 2017, Feb 2018, Mar 2018 |
| Lasting-fix test | The route's rate outside busy months, minus that rate's own margin (`margin_other`), is above the national rate there (6.4%) | `gold_routes.needs_lasting_fix` | |
| Busy-season test | The route's excess in busy months (against the national busy-month rate) is larger than in the other months (against the national rate there) | `gold_routes.needs_busy_season_plan` | |
| Fix type | No fix needed when the route has no excess, even if a test passes on its own (RJ > RJ passes the lasting-fix test this way, and 172 routes the busy-season test, SP > MG among them). A route with excess but fewer than 100 orders is Watch, because one order moves its rate by a point or more. Otherwise: Both, Lasting fix or Busy-season plan by the two tests, or Watch when it meets neither | `gold_routes.fix_type` | 152 routes with excess: 5 Both, 10 Lasting fix, 12 Busy-season plan, 125 Watch. SP > RJ: Both |

## State and funnel measures (Dashboard 3)

| Metric | Definition | Where | Value |
| --- | --- | --- | --- |
| Orders per 100,000 residents | Every order bought September 2017 to August 2018, any status, / IBGE 2018 population x 100,000 | `gold_states.orders_per_100k_12m` | RJ 56.4, SP 71.7 |
| Active sellers per million | Sellers with an order in those 12 months / population x 1,000,000 | `gold_states.active_sellers_per_million_12m` | RJ 8.5, SP 35.2 |
| Orders from another state | Share of the state's single-seller orders in those 12 months shipped from another state | `gold_states.share_from_other_state_12m` | RJ 91.5% |
| Local seller | Seller in the customer's state. On the dashboard, orders with no single seller show as "Several sellers or no item" | `fact_orders.is_local_seller`; dimension `seller_location` | RJ: 7.7% broken, 5 days |
| Funnel recruits who sold | Funnel sellers with at least one order; share by state | `gold_states.share_of_funnel_sellers` | SP 61.1%, RJ 6.8% |

## Design choices

- **Calendar days, not timestamps.** The promised date has no time of day. Comparing timestamps would call 1,292 on-time deliveries late.
- **One score per order.** The latest review counts, so an order with two reviews is not averaged twice.
- **Rates in the metric view, rules in Gold.** A filter recalculates a rate; a rule that compares busy months with the rest of the year (fix type) must not change with a month filter, so it is stored, and check 22 keeps the orders behind the stored rates equal to the metric view's.
- **Routes only for single-seller orders.** 1,278 orders have several sellers but one carrier date, so we cannot tell whose parcel the date records. They stay in every total.
- **The category of an order is its first item's category**, so an order counts once in the category filter.

## Sensitivity: does the answer change with another definition?

| Change | Broken-promise rate | Sao Paulo to Rio excess | Next nine routes together |
| --- | ---: | ---: | ---: |
| As built | 8.6% | 678 | 637 |
| Window ends a week earlier (promised by August 24, 2018) | 8.7% | 677 | 638 |
| Window ends two weeks earlier (August 17) | 8.7% | 680 | 639 |
| Window ends a month earlier (July 31) | 8.7% | 689 | 647 |
| Only parcels that arrived late count as broken | 6.8% | 591 | 579 |
| Orders with dates in an impossible order left out | 8.7% | 675 | 632 |

Sao Paulo to Rio stays first, above the next nine routes together, in every row. With the window a week shorter the same ten routes stay on top; only the 8th and 9th swap. The review choice barely matters either: averaging an order's reviews instead of keeping the latest gives 14,160 low reviews instead of 14,205, 36.7% after a broken promise either way, and moves the average score by 0.0004 stars.

## Fairness

Region and state say where the problem is; they never rank a seller. Northeast customers get worse service, 15.6% (plus or minus 0.8) against 7.8% (plus or minus 0.2) in the Southeast, and the trust page shows the gap with its margins instead of hiding it. The fixes aim at routes and carriers, not at customers. If Olist later scores sellers, it should use only the handover to the carrier, which the seller controls.

## Known weaknesses

- Every link between promises and reviews is a correlation.
- We found the busy-month rule by looking at the same data, so it must be judged again on new months; November 2017 passes it by only 15 broken promises.
- The busy-season test has no margin of error, and 152 routes are tested at once, so some labels on smaller routes may be chance. The 100-order floor limits this.
- The last days of August hold mostly orders that had already arrived, so the end of the window looks better than it was (see the sensitivity table).
- One broken promise in five (1,696) is an order that never arrived. The data does not say why.
- For Rio customers, most of the local sellers' edge in broken promises comes from the busy months: 4.1% against 39.8% for Sao Paulo sellers. In the other months it is 8.7% against 10.0%, within the margin, though local sellers stay faster (a median of 5 days against 12).
- The data has no carrier name or tracking event, so why Sao Paulo to Rio breaks stays a question for Olist and its carriers.
- Deliveries stop being recorded after August 2018: we deliver rules a monthly refresh would rerun, not a list for today.
- Only 380 of the 842 signed sellers appear in the orders, and the leads carry no location.
