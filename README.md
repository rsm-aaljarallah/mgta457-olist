# MGTA 457 team project: Olist marketplace

**Status, 2026-11-26: ready to submit.** The 13 source files were checked against Kaggle and IBGE (every SHA-256 hash matches) and are loaded in `olist.raw`. Silver, Gold, the metric view and the checks are built in `olist.analytics`: all 24 pipeline checks pass, and all 56 results printed in the design document come back exactly from Gold. The three dashboards are published, and the design document, final documentation and presentation are in `deliverables/`. An audit on 2026-11-24 rechecked everything; see "Audit of 2026-11-24" below. Three extras followed on 2026-11-26: what the bad reviews say, a Genie space, and a weekly schedule with an alert; see "Extras, 2026-11-26".

## What we submit

| Deliverable (syllabus) | File or place |
| --- | --- |
| Dashboard design document, 2 to 5 pages with sketches and user flow | `deliverables/olist_design_document.docx` (5 pages), source `docs/design_doc.md` |
| Databricks lakehouse: curated Unity Catalog tables | catalog `olist` (schemas `raw` and `analytics`), see "In Databricks" below |
| SQL workflow, the transformation layer | `sql/00_setup.sql` to `sql/07_dashboard_views.sql`; files 03 to 07 also run in order as the Databricks job "Olist rebuild: Silver to dashboards". `sql/08_robustness.sql` and `sql/09_alert_sp_rj.sql` (the alert's query) are read-only |
| Final project documentation | `deliverables/olist_final_documentation.docx`: overview, lineage, metric dictionary, data dictionary, data quality log, AI usage log |
| Dashboard files: 3 dashboards, 4 pages, 26 visuals | `dashboards/*.lvdash.json`, published in Databricks AI/BI (accepted by the professor in place of Power BI) |
| Final presentation, 10 to 15 minutes | `deliverables/olist_presentation.pptx` (13 slides, speaker notes), outline in `docs/presentation_outline.md` |

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
| Job "Olist rebuild: Silver to dashboards" | Runs files 03 to 07 in order, stops if a check fails, then refreshes the three dashboards. Every Monday at 6:00 Pacific time; emails the owner when a task fails. Settings in `jobs/olist_rebuild.json`, id in `jobs/job_id.json` |
| Alert "Olist: Sao Paulo > Rio de Janeiro breaks twice the national rate" | Every Monday at 7:00, compares the route's broken-promise rate in the latest month with the national rate, and emails the owner at twice or more. Query `sql/09_alert_sp_rj.sql`, settings `jobs/alert_sp_rj.json` |
| Genie space "Ask Olist: delivery promises" | Answers questions in plain English from `delivery_metrics`, `route_list`, `gold_states` and `gold_months`, and shows the SQL it ran. Spec `genie/ask_olist.json`, id `genie/space_id.json` |

What `olist.analytics` holds:

| Layer | Objects |
| --- | --- |
| Silver (`03_silver.sql`) | `silver_orders`, `silver_order_items`, `silver_order_payments`, `silver_order_reviews`, `silver_customers`, `silver_sellers`, `silver_products`, `silver_geolocation`, `silver_leads`, `silver_closed_deals`, `silver_states`; `quarantine` (every row set aside, with its reason); the `stg_` views that type the rows and apply the quarantine rules |
| Gold (`04_gold.sql`) | `fact_orders` (one row per order, with a flag for reviews whose text says the parcel was late or missing), `fact_order_items` (one row per item line), `dim_date`, `dim_state`, `dim_seller`, `dim_product`; `gold_months` (busy-month rule), `gold_routes` (ranked routes and fix type), `gold_states` (population measures); 9 primary and 15 foreign keys declared in Unity Catalog |
| Metric view (`05_metric_view.sql`) | `delivery_metrics`: every rate a dashboard filter recalculates |
| Dashboard views (`07_dashboard_views.sql`) | `route_list`, `state_view`, `region_fairness`, `deliveries_per_month`, `quarantine_summary` |
| Checks (`06_checks.sql`) | `pipeline_checks` (24 checks; every row should say PASS, and the file's last statement fails the run if one does not), `silver_rule_counts` (rows each rule touched, for the trust page), `design_doc_numbers` (the design document's results recomputed from Gold) |

## Documents and how they are built

The Word and PowerPoint files are built from the markdown and scripts in this repository. Edit the source, then rebuild; never edit the Office files by hand.

| Output | Source | Command (from the repo root) |
| --- | --- | --- |
| `deliverables/olist_design_document.docx` | `docs/design_doc.md`, sketches from `docs/dashboard_plan.json` | `python3 tools/draw_sketches.py docs/dashboard_plan.json`, then the first command at the top of `tools/export_word.py` |
| `deliverables/olist_final_documentation.docx` | `docs/project_overview.md`, `lineage.md`, `metric_dictionary.md`, `data_dictionary.md`, `data_quality_log.md`, `ai_usage.md` | `python3 tools/build_data_dictionary.py` and `python3 tools/draw_lineage.py`, then `python3 tools/export_word.py deliverables/olist_final_documentation.docx "Olist Delivery Promise: Final Project Documentation" "MGTA 457 Business Intelligence Systems, Fall 2026. Team: AJ, Ruby, Merna." docs/project_overview.md docs/lineage.md docs/metric_dictionary.md docs/data_dictionary.md docs/data_quality_log.md docs/ai_usage.md` |
| `deliverables/olist_presentation.pptx` | `tools/deck/build_deck.js`, notes in `tools/deck/script.json` | `NODE_PATH=<folder with pptxgenjs> OLIST_THEME_SCRIPT=<theme helper> node tools/deck/build_deck.js` |
| `docs/presentation_outline.md` | `tools/deck/script.json` | `python3 tools/deck/build_outline.py` |
| `../olist_submission/` and `../olist_submission.zip` | the three Office files, the dashboard files, the SQL, the Genie spec, the job and alert settings | `python3 tools/make_submission.py` |

The screenshots in `docs/img` were taken in Databricks on 2026-11-24, except `dash_1_words.png`, `genie_answer.png` and `star_schema.png`, taken on 2026-11-26.

Two paths depend on the machine: `NODE_PATH` must point at a folder where `pptxgenjs` is installed, and the deck's colour theme comes from a helper outside this repository (set `OLIST_THEME_SCRIPT` to it; without it the deck is written without the theme step).

## Before you submit

1. Each of us writes our name in the files we own: the `Owner` and `Reviewed and understood by` lines at the top of the 10 SQL files, the `Who reviewed it` and `What we changed` columns of `docs/ai_usage.md`, and the Reviewer column of the team-decisions doc.
2. Re-export `deliverables/olist_final_documentation.docx` (command above), because it contains the AI usage log.
3. Run `python3 tools/make_submission.py` and upload the files in `../olist_submission/`, or the zip.
4. If a PDF is required, open each Office file in Word or PowerPoint and save it as PDF there, so the fonts stay exact.

## How to run it

Run each SQL file in the Databricks SQL editor, in order, or from this folder with `python3 tools/run_dbx.py sql/<file>.sql` (Databricks CLI profile `chord`).

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
11. `sql/08_robustness.sql`: read-only. Asks whether Sao Paulo to Rio's excess survives an adjustment for what it sells and when, whether customers whose promise broke come back less, and how good the review word list is (two samples to read by hand); each query lists the value we expect.
12. `python3 tools/deploy_genie.py --eval`: creates or updates the Genie space from `genie/ask_olist.json`, then asks it every benchmark question and prints whether each answer matched the benchmark SQL.

Steps 5 to 9 and the dashboard refresh also run as one Databricks job: `python3 tools/deploy_job.py --run` copies files 03 to 07 to the workspace folder `mgta457-olist/sql`, creates or updates the job and the alert, and runs the job, printing each task's result. The job stops before the dashboard views if any check fails. It runs every Monday at 6:00 Pacific time, so new data would reach the dashboards without anyone starting it, and emails the owner when a task fails. The alert runs its query, `sql/09_alert_sp_rj.sql`, every Monday at 7:00.

## Dashboards

Published in the Databricks workspace on 2026-11-24 and checked page by page in the browser (Dashboard 1 republished on 2026-11-26 with two new cards):

| Dashboard | Reader | Pages |
| --- | --- | --- |
| Olist 1 - What broken promises cost | Head of Customer Experience | 1 |
| Olist 2 - Where promises break | Head of Logistics | 2: the routes, and "Can we trust it" |
| Olist 3 - Where local sellers would help | Head of Seller Acquisition | 1 |

They read only the metric view `delivery_metrics`, the views of `07_dashboard_views.sql` and two check views, so they do no calculation. Colour works the same way on every page: gray is context, red sets broken promises against kept or later ones, and blue marks what a chart's note talks about; the tables colour only the fix type and the check results. Every headline card sits next to its comparison. Published dashboards show cached results until someone clicks refresh. AJ, Ruby and Merna can open and edit them; anyone else must first be added to the workspace and then shared from the dashboard's Share button, or can import the `.lvdash.json` files into another workspace.

## Design document numbers

`design_doc_numbers` recomputes from Gold every result the design document prints, 56 numbers; all 56 match. The facts about the raw data come from `sql/02_profile_bronze.sql`, whose expected values are written in its comments. Three numbers were corrected on 2026-11-24, when the Gold build replaced the planning queries: the excess of the next nine routes (629 to 637), the median month's rate (6.85% to 6.89%) and the busy months' share of orders (22.2% to 22.1%). No conclusion changed.

## Audit of 2026-11-24

Every number was checked a second way before submission:

- The 13 files on disk were compared with `olist.raw`, and every order of `fact_orders` was rebuilt from the CSV files with pandas, without the SQL: all 99,441 orders agree on all 18 fields compared. The months, routes and states tables also reproduce from the files.
- The metric view was compared with SQL written out by hand under seven filter combinations, and the deployed views, metric view and dashboards with the files in this repository.
- Every cleaning rule was run on made-up bad rows to see it fire.

What changed: routes with fewer than 100 orders no longer get a fix type (they are "Watch"); the two "where the days go" averages now use the same orders; a missing order status is set aside; the Fernando de Noronha islands, which are Brazilian, are no longer set aside as points outside Brazil; city matching also removes an accent typed as a separate mark; six checks were made stricter and three added (stored rates agree with the metric view, typing lost nothing, days are the days written in the files); 17 more design-document numbers are recomputed by `design_doc_numbers`; and wording that did not match the build was corrected. No headline number changed. The audit also found that, for Rio customers, most of the local sellers' edge in broken promises comes from the busy months; the design document now says so. `docs/metric_dictionary.md` shows how the answer holds up under other definitions.

## After the audit, 2026-11-24

Four changes followed the audit. None moves a number: all 24 checks pass and all 56 design-document numbers match.

- **Keys.** The Gold tables declare 9 primary and 15 foreign keys in Unity Catalog, so Catalog Explorer draws the star schema. Unity Catalog does not enforce declared keys, so checks 10, 12 and 14 test them on every build, and check 14 also confirms that all 24 are declared.
- **A gate and a job.** `06_checks.sql` ends with a statement that fails the run when any check is not PASS, and the Databricks job runs files 03 to 07 and refreshes the dashboards only after it passes.
- **Dashboards.** Colour used the same way on every page, and a comparison next to every headline card: the average review of kept and broken promises (4.29 and 2.18), the scores of late orders reviewed before and after arrival (1.65 and 3.72), and the share of on-time deliveries handed over on time (92.3%, next to 72.2% for late ones). One new measure (`share_kept_handed_over_by_deadline`) and one label column (`state_view.highlight`) serve them; the dashboards then held 24 visuals.
- **Robustness.** `sql/08_robustness.sql` answers two likely questions. Adjusting for what a route sells and when it sells moves Sao Paulo to Rio's excess only from 678 to 660, so it stays first (a new row in the metric dictionary's sensitivity table). Customers whose first promise broke came back within 180 days at 1.3% against 1.7%, but the whole gap sits in the Southeast, so the dashboards do not claim a cost in repeat business.

## Extras, 2026-11-26

Three additions. All 24 checks still pass and all 56 design-document numbers match; the only change to an existing table is two new columns on `fact_orders`.

- **What the bad reviews say.** `fact_orders` flags each latest review whose title or comment says the parcel was late, slow or missing, by a Portuguese word list written out in `04_gold.sql`. Of the 1-2 star reviews that have text, 66.4% on broken promises say so, against 19.1% on kept ones: two new cards on Dashboard 1, from two of four new measures (the other two serve Genie and other groupings). We read 100 flagged reviews drawn at random and 95 were real delivery complaints; 18 of 30 unflagged broken-promise reviews were delivery complaints too, so the list undercounts (`sql/08_robustness.sql`, query 3).
- **Ask Olist, a Genie space.** Questions in plain English, answered from the metric view and three small tables, with our definitions as instructions and six trusted example queries. We test it with benchmark questions whose answers we know: the first run missed 1 of 10 (a rate written as a percentage), and after one fix to its instructions it got 10 of 10, then 11 of 11 with one more question (`python3 tools/deploy_genie.py --eval`).
- **A weekly schedule and an alert.** The job runs every Monday at 6:00 Pacific time and emails the owner when a task fails. At 7:00 an alert compares Sao Paulo to Rio's broken-promise rate in the latest month with the national rate, and fires at twice or more, the same yardstick as the busy-month rule. It would have fired for orders bought from November 2017 to March 2018, and reads 0.87 for August 2018. We made it evaluate on the real rule (OK), on a lowered one (triggered) and on a route with no orders (no row, OK) before setting it to weekly.

Ruby and Merna can edit the dashboards, the Genie space and the alert, run the job, and read the `olist` data.

## What the profile found

All written up in [docs/data_quality_log.md](docs/data_quality_log.md):

- **Repeated rows.** 261,831 exact duplicate location rows.
- **Repeated reviews.** One review attached to several orders, and 547 orders with more than one review.
- **Joins that multiply rows.** Joining items to payments adds 4.6% to item value. Joining customers to locations turns 99,441 customers into 15 million rows.
- **Zip codes.** 23,995 customers have a zip prefix starting with 0, which a number type would drop.
- **Dates in an impossible order.** For example, 1,359 orders reached the carrier before they were approved.
- **A data window that ends early.** The orders stop in August 2018, two months before the last date.
- **Codes that differ by source.** IBGE names states by number, Olist by letters.

## References

[docs/references/](docs/references/README.md) keeps the two guides we designed against: the ONS guide to choosing a chart type, and Kimball's article on fact and dimension tables. Its notes check every dashboard chart and the Gold layer against them, and name the two places where we depart on purpose. They also cite Stephen Few's "Why Most Dashboards Fail", behind the comparison next to each headline card.

## Rules carried over from the Chord project

- `olist.raw` is read-only after loading. Everything we build goes in `olist.analytics`.
- Every SQL file keeps its header, including the AI use line, and [docs/ai_usage.md](docs/ai_usage.md) gets a row for every AI-assisted change.
- No tokens, passwords or data files in the repository.
