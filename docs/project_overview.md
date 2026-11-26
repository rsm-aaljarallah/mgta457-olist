# Project overview


## The question and the answer

Olist lets small Brazilian shops sell on the big marketplaces, and its carriers deliver the orders. Every customer sees a promised delivery date at checkout. We asked where Olist breaks that promise, what a broken promise costs, and what Olist should fix first.

- **What it costs.** 8.6% of the orders we judge broke their promise, but they make up 36.7% of the orders in the window with a 1 or 2 star review, canceled ones included. Of the late parcels with a review, 70.1% were reviewed before they arrived, at 1.65 stars against 3.72 after. In their own words, 66.4% of the 1-2 star reviews with text on broken promises say the parcel was late or missing, against 19.1% on kept ones.
- **Where it happens.** One route, Sao Paulo to Rio de Janeiro, has 678 more broken promises than the national rate predicts, more than the next nine routes together (637). The Northeast breaks promises in ordinary months too; three busy months hold 22.1% of orders but 42.9% of broken promises.
- **What to fix first.** Promising three days later only brings the rate from 8.6% to 6.6%, and 72.2% of the late parcels from one seller reached the carrier on time (92.3% of the on-time ones did), so most of the fix is on the routes and the carriers. Rio buys 56.4 orders per 100,000 residents against 71.7 in Sao Paulo, but has a quarter of its sellers per resident; its local sellers broke 7.7% of promises against 17.1% for Sao Paulo sellers, which supports a measured recruiting pilot in Rio.

## What we deliver

| Deliverable | Where |
| --- | --- |
| Dashboard design document (5 pages, sketches, user flow) | `deliverables/olist_design_document.docx`, source `docs/design_doc.md` |
| Databricks lakehouse: curated Unity Catalog tables | catalog `olist`: `raw` (Bronze), `analytics` (Silver, Gold, metric view, checks) |
| SQL workflow (the transformation layer) | `sql/00_setup.sql` to `sql/07_dashboard_views.sql`; files 03 to 07 also run as one Databricks job that stops if a check fails |
| Three dashboards, 4 pages, 26 visuals | Databricks AI/BI (accepted by the professor in place of Power BI); files in `dashboards/` |
| Ask Olist, a Genie space for questions in plain English | Databricks; spec in `genie/ask_olist.json`, 11 of 11 benchmark questions answered correctly |
| A weekly rebuild and an alert on Sao Paulo to Rio | Databricks job and SQL alert; settings in `jobs/`, the alert's query in `sql/09_alert_sp_rj.sql` |
| Final documentation (this document) | `deliverables/olist_final_documentation.docx` |
| Presentation | `deliverables/olist_presentation.pptx` |
| Code | GitHub `rsm-aaljarallah/mgta457-olist` (private) |

## The three dashboards

Each dashboard has one reader, in the order of the story: what it costs, where it happens, what to change.

**Dashboard 1, What broken promises cost**, for the Head of Customer Experience: three headline cards, each next to its comparison, then the review score by days early or late, and on-time against late orders delivered in the same week. On every page gray is context, red sets broken promises against kept or later ones, and blue marks what a chart's note talks about.

![Dashboard 1: What broken promises cost](img/dash_1_cost.png "width=6.3")

Below the charts, two cards say what the 1-2 star reviews complain about, with the Portuguese words the count looks for and how often they are right.

![Dashboard 1: what the 1-2 star reviews say](img/dash_1_words.png "width=6.3")

**Dashboard 2, Where promises break**, for the Head of Logistics: the routes to fix first with their fix type, the monthly rate by area, the "promise later" test, and where the days go.

![Dashboard 2: routes to fix first](img/dash_2_routes.png "width=6.3")

![Dashboard 2: why there are two kinds of fix](img/dash_2_charts.png "width=6.3")

Its second page, **Can we trust it**, shows every pipeline check, what each Silver rule did, the rows set aside, why the analysis stops in August 2018, and the fairness check by region.

![Dashboard 2, page 2: Can we trust it](img/dash_2_trust_checks.png "width=6.3")

![Dashboard 2, page 2: the data window and fairness by region](img/dash_2_trust_window.png "width=6.3")

**Dashboard 3, Where local sellers would help**, for the Head of Seller Acquisition, here filtered to Rio de Janeiro customers.

![Dashboard 3: states, and local against Sao Paulo sellers for Rio](img/dash_3_local_rio.png "width=6.3")

![Dashboard 3: where the funnel recruits](img/dash_3_shares.png "width=6.3")

**Ask Olist**, a Genie space, takes the questions the dashboards do not chart. Genie writes the SQL against the metric view and three small Gold tables, runs it, and shows the SQL with the answer. Its instructions hold our definitions (judged, broken, route, busy month), and six example questions carry SQL we trust. We tested it with 11 benchmark questions whose answers we know: after one fix to how it states percentages, it answered all 11 correctly. Below, it compares Rio with Sao Paulo.

![Ask Olist: Genie compares Rio de Janeiro with Sao Paulo](img/genie_answer.png "width=6.3")

## How to run it

1. In Databricks, run `sql/00_setup.sql`, upload the files (`tools/fetch_ibge.sh`, then `tools/upload_raw.sh`), and run `sql/01_load_raw.sql`.
2. Run `sql/02_profile_bronze.sql` (read-only; every query lists the value it should return).
3. Run `sql/03_silver.sql` to `sql/07_dashboard_views.sql` in order, or run them as the Databricks job with `python3 tools/deploy_job.py --run`. The same command sets the job to run every Monday and creates the alert on Sao Paulo to Rio.
4. Check `olist.analytics.pipeline_checks`: every row must say PASS before a dashboard is refreshed. The last statement of `06_checks.sql` fails when one does not, so the job stops before the dashboard views and the refresh, and emails its owner.
5. Build and publish the dashboards: `python3 dashboards/build_dashboards.py`, then `python3 tools/deploy_dashboards.py`. A teammate can instead import the three `.lvdash.json` files.
6. Create the Genie space and test it: `python3 tools/deploy_genie.py --eval` asks it every benchmark question and prints whether each answer matched.

## Result of the last build

All 24 pipeline checks pass. 3 of 415,201 order, item, payment and review rows were set aside (0.001%), plus 27 location points outside Brazil. All 56 results printed in the design document are recomputed from Gold by `design_doc_numbers` and match. The Gold tables declare 9 primary and 15 foreign keys, and every foreign key finds its row (check 14). An audit on 2026-11-24 rebuilt every order from the source files independently and found the same numbers; the metric dictionary shows how the answer holds up under other definitions. On 2026-11-26 the Genie space answered all 11 of its benchmark questions correctly, and the alert, made to evaluate on the spot, read OK on its real rule and triggered on a lowered one.

## The rest of this document

The lineage map traces every table from the source files to the dashboards, the Genie space and the alert, and shows the declared star schema and the rebuild job. The metric dictionary defines every number. The data dictionary lists every column. The data quality log gives the grain of each table, what the profile found and the 31 rules with their reasons. The AI usage log records every AI-assisted change and who reviewed it.
