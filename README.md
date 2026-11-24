# MGTA 457 team project: Olist marketplace

**Status, 2026-11-24: the data layer is built.** The 13 source files were checked against Kaggle and IBGE (every SHA-256 hash matches) and are loaded in `olist.raw`. Silver, Gold, the metric view and the checks are built in `olist.analytics`: all 21 pipeline checks pass, and 36 of the 39 headline numbers of the design document come back exactly from Gold (the other three are in "Numbers that moved" below). The three dashboards are published. Nothing here is committed or pushed yet.

## The data

Three datasets from two publishers, 13 files, 13 tables in `olist.raw`:

1. **Olist e-commerce marketplace** (Kaggle): orders, items, payments, reviews, customers, sellers, products, zip-code locations, category names in English.
2. **Olist marketing funnel** (Kaggle): sellers who asked to join, and those who signed up.
3. **IBGE**, Brazil's statistics office: 2018 population by state, and the list of states with their codes and regions.

Where each file came from, its license and its SHA-256 hash are in [docs/sources.md](docs/sources.md). The data files never go in this repository.

## In Databricks

| Object | What it holds |
| --- | --- |
| `olist` | The catalog for this project, apart from the class tutorial catalogs |
| `olist.raw` | Bronze: the 13 files as delivered, every CSV column as text. Loaded once, never edited |
| `olist.raw.landing_zone` | The volume with the downloaded files, one folder per source |
| `olist.analytics` | Everything we build, listed below |

What `olist.analytics` holds:

| Layer | Objects |
| --- | --- |
| Silver (`03_silver.sql`) | `silver_orders`, `silver_order_items`, `silver_order_payments`, `silver_order_reviews`, `silver_customers`, `silver_sellers`, `silver_products`, `silver_geolocation`, `silver_leads`, `silver_closed_deals`, `silver_states`; `quarantine` (every row set aside, with its reason); the `stg_` views that hold the rules |
| Gold (`04_gold.sql`) | `fact_orders` (one row per order), `fact_order_items` (one row per item line), `dim_date`, `dim_state`, `dim_seller`, `dim_product`; `gold_months` (busy-month rule), `gold_routes` (ranked routes and fix type), `gold_states` (population measures) |
| Metric view (`05_metric_view.sql`) | `delivery_metrics`: every rate the dashboards show, recalculated for any filter |
| Checks (`06_checks.sql`) | `pipeline_checks` (every row should say PASS), `silver_rule_counts` (rows each rule touched, for the trust page), `design_doc_numbers` (the design document's numbers recomputed from Gold) |

## Design document

`docs/design_doc.md` is the source; `deliverables/olist_design_document.docx` is its Word export (5 pages). The sketches come from `docs/dashboard_plan.json`: run `python3 tools/draw_sketches.py docs/dashboard_plan.json`, then `tools/export_word.py` (command at the top of that file).

## How to run it

Run each SQL file in the Databricks SQL editor, in order, or with the CLI.

1. `sql/00_setup.sql`: creates the catalog, the schemas and the volume.
2. Upload the files: `sh tools/fetch_ibge.sh <ibge folder>`, then `sh tools/upload_raw.sh <csv folder> <ibge folder>`.
3. `sql/01_load_raw.sql`: loads the 13 tables.
4. `sql/02_profile_bronze.sql`: read-only. Measures every data problem; each query lists the value we expect.
5. `sql/03_silver.sql`: Silver and the quarantine.
6. `sql/04_gold.sql`: the star schema and the three rule tables.
7. `sql/05_metric_view.sql`: the metric view.
8. `sql/06_checks.sql`: the audit. Do not build or refresh a dashboard unless every row of `pipeline_checks` says PASS.
9. `sql/07_dashboard_views.sql`: the small views the dashboards read besides the metric view.
10. `python3 dashboards/build_dashboards.py`, then `python3 tools/deploy_dashboards.py`: writes the three `.lvdash.json` files, then creates or updates and publishes the dashboards (ids in `dashboards/dash_ids.json`). A teammate can instead import the `.lvdash.json` files into their own workspace.

## Dashboards

Published in the Databricks workspace on 2026-11-24 and checked page by page in the browser:

| Dashboard | Reader | Pages |
| --- | --- | --- |
| Olist 1 - What broken promises cost | Head of Customer Experience | 1 |
| Olist 2 - Where promises break | Head of Logistics | 2: the routes, and "Can we trust it" |
| Olist 3 - Where local sellers would help | Head of Seller Acquisition | 1 |

They read only the metric view `delivery_metrics` and the views of `07_dashboard_views.sql`, so they do no calculation. Published dashboards show cached results until someone clicks refresh.

## Numbers that moved since the design document

`design_doc_numbers` compares the 39 numbers printed in the design document of 2026-11-19 with Gold. Three differ slightly, and none changes a conclusion:

| Number | Design document | Gold |
| --- | --- | --- |
| Excess broken promises of the next nine routes, together | 629 | 637 (Sao Paulo to Rio, 678, is still larger) |
| Median month's broken-promise rate | 6.85% | 6.89% (the same three busy months) |
| Busy months' share of orders | 22.2% | 22.1% |

## What we found so far

The profile shows real work for Silver, all written up in [docs/data_quality_log.md](docs/data_quality_log.md):

- **Repeated rows.** 261,831 exact duplicate location rows.
- **Repeated reviews.** One review attached to several orders, and 547 orders with more than one review.
- **Joins that multiply rows.** Joining items to payments adds 4.6% to item value. Joining customers to locations turns 99,441 customers into 15 million rows.
- **Zip codes.** 23,995 zip codes lose their leading zero if read as numbers.
- **Dates in an impossible order.** For example, 1,359 orders reached the carrier before they were approved.
- **A data window that ends early.** The orders stop in August 2018, two months before the last date.
- **Codes that differ by source.** IBGE names states by number, Olist by letters.

## Rules carried over from the Chord project

- `olist.raw` is read-only after loading. Everything we build goes in `olist.analytics`.
- Every SQL file keeps its header, including the AI use line, and [docs/ai_usage.md](docs/ai_usage.md) gets a row for every AI-assisted change.
- No tokens, passwords or data files in the repository.
