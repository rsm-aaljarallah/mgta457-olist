# MGTA 457 team project: Olist marketplace

**Status, 2026-11-24: ready to submit.** The 13 source files were checked against Kaggle and IBGE (every SHA-256 hash matches) and are loaded in `olist.raw`. Silver, Gold, the metric view and the checks are built in `olist.analytics`: all 21 pipeline checks pass, and all 39 headline numbers of the design document come back exactly from Gold. The three dashboards are published, and the design document, final documentation and presentation are in `deliverables/`.

## What we submit

| Deliverable (syllabus) | File or place |
| --- | --- |
| Dashboard design document, 2 to 5 pages with sketches and user flow | `deliverables/olist_design_document.docx` (5 pages), source `docs/design_doc.md` |
| Databricks lakehouse: curated Unity Catalog tables | catalog `olist` (schemas `raw` and `analytics`), see "In Databricks" below |
| SQL workflow, the transformation layer | `sql/00_setup.sql` to `sql/07_dashboard_views.sql` |
| Final project documentation | `deliverables/olist_final_documentation.docx`: overview, lineage, metric dictionary, data dictionary, data quality log, AI usage log |
| Dashboard files: 3 dashboards, 4 pages, 19 visuals | `dashboards/*.lvdash.json`, published in Databricks AI/BI (accepted by the professor in place of Power BI) |
| Final presentation, 10 to 15 minutes | `deliverables/olist_presentation.pptx` (11 slides, speaker notes), outline in `docs/presentation_outline.md` |

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
| Dashboard views (`07_dashboard_views.sql`) | `route_list`, `state_view`, `region_fairness`, `deliveries_per_month`, `quarantine_summary` |
| Checks (`06_checks.sql`) | `pipeline_checks` (every row should say PASS), `silver_rule_counts` (rows each rule touched, for the trust page), `design_doc_numbers` (the design document's numbers recomputed from Gold) |

## Documents and how they are built

The Word and PowerPoint files are built from the markdown and scripts in this repository. Edit the source, then rebuild; never edit the Office files by hand.

| Output | Source | Command (from the repo root) |
| --- | --- | --- |
| `deliverables/olist_design_document.docx` | `docs/design_doc.md`, sketches from `docs/dashboard_plan.json` | `python3 tools/draw_sketches.py docs/dashboard_plan.json`, then the first command at the top of `tools/export_word.py` |
| `deliverables/olist_final_documentation.docx` | `docs/project_overview.md`, `lineage.md`, `metric_dictionary.md`, `data_dictionary.md`, `data_quality_log.md`, `ai_usage.md` | `python3 tools/build_data_dictionary.py` and `python3 tools/draw_lineage.py`, then `python3 tools/export_word.py deliverables/olist_final_documentation.docx "Olist Delivery Promise: Final Project Documentation" "MGTA 457 Business Intelligence Systems, Fall 2026. Team: AJ, Ruby, Merna." docs/project_overview.md docs/lineage.md docs/metric_dictionary.md docs/data_dictionary.md docs/data_quality_log.md docs/ai_usage.md` |
| `deliverables/olist_presentation.pptx` | `tools/deck/build_deck.js`, notes in `tools/deck/script.json` | `NODE_PATH=/Users/aj/Documents/BI/tools/deck/node_modules node tools/deck/build_deck.js` |

The dashboard screenshots in `docs/img/dash_*.png` were taken from the published dashboards on 2026-11-24.

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

## Design document numbers

`design_doc_numbers` recomputes the 39 headline numbers of the design document from Gold; all 39 match. Three were corrected on 2026-11-24, when the Gold build replaced the planning queries: the excess of the next nine routes (629 to 637), the median month's rate (6.85% to 6.89%) and the busy months' share of orders (22.2% to 22.1%). No conclusion changed.

## What the profile found

All written up in [docs/data_quality_log.md](docs/data_quality_log.md):

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
