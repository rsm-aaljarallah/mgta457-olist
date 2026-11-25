# References

Two guides we saved on 2026-11-19 and designed against. The pages are kept without their style and script folders, so they open as plain pages; the links go to the live versions.

| File | Source | Licence | What we took from it |
| --- | --- | --- | --- |
| `ons_choosing_a_chart_type.html` | Office for National Statistics, Service manual, [Choosing a chart type](https://service-manual.ons.gov.uk/data-visualisation/chart-types/choosing-a-chart-type) | Open Government Licence v3.0, which allows reuse with attribution | Choose the chart by the relationship it shows; keep charts simple; one relationship per chart; give compared parts a common baseline; start with the big picture; columns for flows, lines for stocks |
| `kimball_fact_and_dimension_tables.html` | Ralph Kimball, [Fact Tables and Dimension Tables](https://www.kimballgroup.com/2003/01/fact-tables-and-dimension-tables/), Kimball Group, 2003 | All rights reserved by the Kimball Group. This is a private course copy: if the repository is ever made public, delete it and keep the link | Facts and dimensions, one grain per fact table, keys with referential integrity, flat dimensions, additive facts, degenerate dimensions |

## Our charts, checked against the ONS guide

Each chart shows one relationship, in a familiar chart type.

| Dashboard | Chart | Relationship | Chart type |
| --- | --- | --- | --- |
| 1 | Broken promises, low reviews, reviewed before arrival | Magnitude, the big picture first | Cards |
| 1 | Review score by days before or after the promised day | Deviation from the promised day | Bar |
| 1 | On time vs late, same delivery week | Magnitude, side by side on one baseline | Clustered bar |
| 2 | Routes to fix first | Ranking | Table, because the reader needs names and reasons |
| 2 | Broken-promise rate by month and area | Time | Line: a rate, and six areas compared on one baseline |
| 2 | Now vs a promise 3 days later, by region | Magnitude | Clustered bar |
| 2 | Where the days go | Parts of a whole | Stacked bar |
| 2 | Deliveries recorded per month | Time, flow data | Column, as ONS advises for flows |
| 2 | Fairness by region | Deviation, with margins | Table |
| 3 | States: orders per 100,000 residents vs broken-promise rate | Correlation | Scatter |
| 3 | Local vs Sao Paulo sellers, rate and days | Magnitude | Bar |
| 3 | Shares of orders, sellers and funnel recruits by state | Magnitude and ranking | Clustered bar, sorted |

One chart takes the exception ONS allows. "Where the days go" stacks purchase-to-carrier under carrier-to-customer because the total delivery time matters. Its top segments do not share a baseline, so the 72.2% card next to it carries the comparison.

## Our Gold layer, checked against Kimball

The star schema follows the article:

- **Measurements and context.** `fact_orders` (one row per order) and `fact_order_items` (one row per item line) hold the measurements; date, state, seller and product hold the context.
- **One grain per fact table.** Order facts and item facts live in separate tables, and payments are summed to the order before any join (rule 15).
- **Additive facts.** Counts and money are stored, and the metric view computes every rate from sums, as Kimball computes a unit price from total sales and total units.
- **Flat dimensions.** Region and population sit in `dim_state`, and the funnel channel in `dim_seller`, with no snowflaking.
- **Degenerate dimension.** `order_id` on `fact_order_items` ties the items of one order together.
- **Referential integrity.** Every fact key finds its dimension row. On 2026-11-24, 0 item lines had an unknown seller, product or purchase day, and 0 orders had an unknown seller. Check 14 runs this test on every build for the customer state and the purchase day only.

It departs in two places, on purpose:

- **Natural keys, not surrogate keys.** We keep Olist's ids, the state codes and the dates as keys. The data is a fixed extract with no history to track, so surrogate integers would add joins without benefit. A monthly refresh in which sellers change would need surrogate keys and slowly changing dimensions.
- **An empty seller key instead of a "no single seller" row.** 2,053 orders have no single seller: 1,278 shipped by several sellers and 775 with no item. Kimball would point them at a special dimension row; we leave the key empty, and the metric view labels them "Several sellers or no item".
