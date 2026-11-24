# Lineage map

Every number on the dashboards comes from 13 source files through the SQL scripts 00 to 07, and every step is a table or view you can open in Catalog Explorer. Read the map from left to right.

![Lineage: sources, Bronze, Silver, Gold, metrics and checks, dashboards](img/lineage.png "width=6.5")

## Table by table

| Step | Script | Reads | Writes | Grain |
| --- | --- | --- | --- | --- |
| Setup | `00_setup.sql` | nothing | catalog `olist`, schemas `raw` and `analytics`, volume `landing_zone` | |
| Bronze | `01_load_raw.sql` | the 13 files in the volume | 13 tables in `olist.raw`, every CSV column as text | as delivered |
| Profile | `02_profile_bronze.sql` | `olist.raw` | nothing (read-only, 23 queries with expected values) | |
| Silver | `03_silver.sql` | `olist.raw` | `stg_` views (the rules), 11 `silver_` tables, `quarantine` | one row per source key |
| Gold | `04_gold.sql` | Silver | `fact_orders`, `fact_order_items`, `dim_date`, `dim_state`, `dim_seller`, `dim_product`, `gold_months`, `gold_routes`, `gold_states` | order; item line; day; state; seller; product; month; route; state |
| Metrics | `05_metric_view.sql` | `fact_orders` and three dimensions | `delivery_metrics` | formulas, not rows |
| Checks | `06_checks.sql` | raw, Silver, Gold, metric view | `pipeline_checks`, `silver_rule_counts`, `design_doc_numbers` | one row per check, rule or number |
| Dashboard views | `07_dashboard_views.sql` | Gold and quarantine | `route_list`, `state_view`, `region_fairness`, `deliveries_per_month`, `quarantine_summary` | route; state; region; month; reason |
| Dashboards | `dashboards/build_dashboards.py` | the metric view and the views above | three published AI/BI dashboards | |

The dashboards read only the metric view and the views of `07_dashboard_views.sql`. They do no calculation: every rate is a measure in `delivery_metrics`, and every rule (busy months, fix type, per-resident measures) is a column in Gold.

## Tracing one number back

The headline "8.6% of orders broke their promise" on Dashboard 1:

1. The card asks the metric view for `MEASURE(broken_rate)`, defined as `SUM(is_broken) / SUM(is_judged)` over `fact_orders`.
2. In `fact_orders`, `is_judged` is true for 95,901 orders: bought from January 2017, promised by August 31, 2018, not canceled or unavailable, and not one of the 8 delivered orders without a delivery date. `is_broken` is 1 for 8,227 of them: delivered on a later calendar day than promised, or not delivered.
3. `fact_orders` takes the order, its dates and its status from `silver_orders`, where `stg_orders` read the five dates as timestamps and the promised date as a day (rule 3), and flagged the 8 orders (rule 4).
4. `silver_orders` comes from `olist.raw.orders`, the file `olist_orders_dataset.csv` exactly as downloaded from Kaggle (SHA-256 in `docs/sources.md`).

Check 19 of `pipeline_checks` confirms the metric view and `fact_orders` agree (95,901 judged, 8,227 broken), and `design_doc_numbers` confirms the 8.6% printed in the design document.
