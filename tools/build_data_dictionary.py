"""Builds docs/data_dictionary.md from the live Databricks catalog plus the meanings below.

Column names, order and types come from olist.information_schema.columns, and each table's purpose
is its Unity Catalog comment, so the document cannot list a column that does not exist or miss one
that does. A column with no meaning below is listed as "(no description)", and the script prints
it, so a new column cannot slip through undocumented.

Run from the repo root:  python3 tools/build_data_dictionary.py
(needs tools/run_dbx.py, in this folder, and the Databricks CLI profile "chord")

AI use: drafted with Claude (Anthropic), 2026-11-24, from the Chord project's script
(see docs/ai_usage.md). Revised with Claude, 2026-11-24: the declared keys are marked.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_dbx  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# One meaning per column name. Where a name means something different in one table, MEANING_BY_TABLE wins.
MEANING = {
    # keys and ids
    "order_id": "Order id.",
    "order_item_id": "Item line number within the order (1, 2, ...).",
    "customer_id": "Customer record on one order. The person is `customer_unique_id`.",
    "customer_unique_id": "The person who bought (one person can have several `customer_id`).",
    "seller_id": "Seller id. On `fact_orders`, empty when several sellers shipped the order.",
    "product_id": "Product id.",
    "review_id": "Review id. One review can cover several orders bought together.",
    "mql_id": "Marketing-qualified lead id: a seller who asked to join Olist.",
    "sdr_id": "Sales development representative who worked the lead.",
    "sr_id": "Sales representative who closed the deal.",
    "landing_page_id": "Landing page the lead arrived on.",
    "zip_prefix": "First 5 digits of the zip code, kept as text so a leading 0 is not lost.",
    "state": "State, two letters (SP, RJ, ...).",
    "state_code": "IBGE numeric state code (35 = Sao Paulo).",
    "state_name": "State name (IBGE spelling).",
    "region": "IBGE region in English: North, Northeast, Southeast, South, Center-West.",
    "region_code": "IBGE region abbreviation (N, NE, SE, S, CO).",
    "region_name_pt": "IBGE region name in Portuguese.",
    "area": "Region with the Southeast split into Rio de Janeiro and the rest.",
    "population_2018": "IBGE 2018 estimated resident population.",
    "city": "City as written in the source.",
    "city_match": "City in lower case without accents, with ´ or ` read as an apostrophe, for matching.",
    "lat": "Average latitude of the prefix's distinct points.",
    "lng": "Average longitude of the prefix's distinct points.",
    "distinct_points": "Distinct location points averaged for the prefix.",
    # order dates
    "order_status": "Status as recorded: delivered, shipped, canceled, unavailable, invoiced, processing, created, approved.",
    "purchase_ts": "When the order was bought.",
    "purchase_date": "Day the order was bought.",
    "approved_ts": "When payment was approved.",
    "carrier_ts": "When the seller handed the order to the carrier.",
    "delivered_ts": "When the customer received the order.",
    "delivered_date": "Day the customer received the order.",
    "promised_date": "Delivery day promised at checkout. It has no time of day.",
    "shipping_limit_ts": "The seller's deadline to hand the item to the carrier.",
    "seller_deadline_ts": "Latest item deadline, single-seller orders only; deadlines in 2019 or later left out.",
    # flags
    "flag_several_sellers": "Rule 13: items from two or more sellers, so the one carrier date cannot be credited to a seller.",
    "flag_delivered_without_date": "Rule 4: status delivered but no delivery date.",
    "flag_canceled_with_delivery": "Rule 5: canceled but has a delivery date.",
    "flag_carrier_before_purchase": "Rule 6: carrier date before the purchase.",
    "flag_carrier_before_approval": "Rule 7: carrier date before the approval.",
    "flag_delivered_before_carrier": "Rule 8: delivered before the carrier date.",
    "flag_outside_full_months": "Rule 9: bought before 2017 or after August 2018.",
    "flag_deadline_after_2018": "Rule 12: seller deadline in 2019 or later.",
    "flag_zip_not_in_geolocation": "Rule 26: the zip prefix has no location.",
    "flag_no_orders_in_data": "Rule 29: the signed seller never appears in the orders.",
    "quarantine_reason": "Why the row is set aside; empty for a row that passes.",
    "raw_row": "The raw row as JSON, so a person can look at it.",
    # money
    "price": "Item price, BRL.",
    "freight_value": "Freight charged, BRL.",
    "item_value": "Sum of item prices, BRL.",
    "payment_value": "Amount paid, BRL. On `fact_orders`, all payments of the order summed (rule 15).",
    "payment_sequential": "Payment number within the order.",
    "payment_type": "credit_card, boleto, voucher or debit_card.",
    "payment_installments": "Installments chosen. Not used in any measure (rule 16).",
    # reviews
    "review_score": "Stars, 1 to 5. On `fact_orders`, the order's latest review.",
    "review_comment_title": "Review title, often blank.",
    "review_comment_message": "Review text in Portuguese, often blank.",
    "review_creation_date": "Day the review survey was sent.",
    "review_answer_ts": "When the customer answered the review.",
    "is_latest_for_order": "Rule 18: the one review per order that score measures use.",
    # products
    "category": "Product category in English (Portuguese when no translation, `unknown` when blank). On `fact_orders`, the first item's category.",
    "category_pt": "Product category in Portuguese.",
    "product_name_length": "Characters in the product name (renamed from `lenght`, rule 22).",
    "product_description_length": "Characters in the description (renamed from `lenght`, rule 22).",
    "product_photos_qty": "Photos on the listing.",
    "product_weight_g": "Weight, grams.",
    "product_length_cm": "Length, cm.",
    "product_height_cm": "Height, cm.",
    "product_width_cm": "Width, cm.",
    # funnel
    "first_contact_date": "Day the lead first contacted Olist.",
    "origin": "Marketing channel of the lead; blank became `unknown` (rule 28).",
    "won_ts": "When the deal was signed.",
    "business_segment": "Segment the seller declared.",
    "lead_type": "Lead type from the sales team.",
    "lead_behaviour_profile": "Behaviour profile from the sales team.",
    "business_type": "Reseller, manufacturer or other.",
    "declared_monthly_revenue": "Monthly revenue the seller declared; 0 became empty (rule 30).",
    "came_through_funnel": "The seller signed through the marketing funnel.",
    "funnel_origin": "Marketing channel, for funnel sellers.",
    "funnel_segment": "Business segment, for funnel sellers.",
    "funnel_lead_type": "Lead type, for funnel sellers.",
    "funnel_won_date": "Day the deal was signed, for funnel sellers.",
    "seller_state": "Seller state. On `fact_orders`, empty when several sellers shipped the order.",
    "seller_city": "Seller city.",
    "customer_state": "Customer state.",
    # fact_orders measures
    "item_count": "Item lines in the order.",
    "seller_count": "Distinct sellers in the order.",
    "is_in_window": "Bought from 2017-01-01 and promised by 2018-08-31.",
    "is_judged": "In window, not canceled or unavailable, and not one of the 8 orders marked delivered with no delivery date. An order that never arrived is judged. Every broken-promise rate counts these.",
    "is_broken": "1 when a judged order was not delivered by the end of the promised day, else 0.",
    "is_broken_if_3_days_later": "1 when it would still be broken with a promise 3 days later.",
    "days_vs_promise": "Delivery day minus promised day: negative early, positive late.",
    "delivery_days": "Days from purchase to delivery.",
    "days_to_carrier": "Days from purchase to the carrier; empty when the carrier date is before the purchase.",
    "days_carrier_to_customer": "Days from the carrier to the customer; empty when delivery is before the carrier date.",
    "promised_days": "Days from purchase to the promised day.",
    "promise_bucket": "Days early or late, grouped (Dashboard 1).",
    "promise_bucket_order": "Sort order of `promise_bucket`, early to late.",
    "delivery_time_band": "Delivery time by week (Dashboard 1).",
    "route": "Seller state > customer state, single-seller orders only.",
    "is_local_seller": "Seller in the customer's state; single-seller orders only.",
    "is_low_review": "1 when the latest review gives 1 or 2 stars.",
    "reviewed_before_arrival": "The review was answered before delivery; delivered orders only.",
    "handed_over_by_deadline": "The carrier date is on or before the seller's deadline.",
    # dim_date
    "date_key": "Calendar day.",
    "month_start": "First day of the month.",
    "year": "Year.",
    "month": "Month number.",
    "month_label": "Month as text, e.g. Nov 2017.",
    "is_full_month": "Day between January 2017 and August 2018 (rule 9).",
    "is_busy_month": "Month's national broken-promise rate is at least twice the median month.",
    # gold_months
    "judged_orders": "Judged orders.",
    "broken_orders": "Broken promises.",
    "broken_rate": "Broken promises / judged orders.",
    "median_rate": "Median of the 20 monthly rates (6.89%).",
    # gold_routes
    "orders": "Judged single-seller orders on the route.",
    "orders_busy": "Of those, bought in busy months.",
    "orders_other": "Of those, bought in other months.",
    "broken_busy": "Broken promises in busy months.",
    "broken_other": "Broken promises in other months.",
    "national_rate": "National broken rate, single-seller orders (8.7%).",
    "national_rate_busy": "National rate in busy months, single-seller orders.",
    "national_rate_other": "National rate in other months, single-seller orders (6.4%).",
    "margin": "95% margin of error of `broken_rate`: 1.96 x sqrt(p(1-p)/n).",
    "excess_broken": "Broken promises minus orders x national rate.",
    "rate_other": "The route's rate outside busy months.",
    "margin_other": "95% margin of `rate_other`.",
    "excess_busy": "Excess in busy months, against the national busy-month rate.",
    "excess_other": "Excess in other months, against the national rate there.",
    "needs_lasting_fix": "The lasting-fix test alone: `rate_other` minus `margin_other` is above `national_rate_other`. `fix_type` also needs 100 orders.",
    "needs_busy_season_plan": "The busy-season test alone: `excess_busy` is larger than `excess_other`. `fix_type` also needs 100 orders.",
    "excess_rank": "Rank by `excess_broken`, largest first.",
    "fix_type": "No fix needed (no excess); Watch (excess but fewer than 100 orders, or neither test met); otherwise Both, Lasting fix or Busy-season plan.",
    "first_step": "Suggested first step for the fix type; empty when no fix is needed.",
    "customer_region": "Customer region.",
    # gold_states
    "orders_12m": "Orders bought Sep 2017 to Aug 2018, any status.",
    "orders_per_100k_12m": "`orders_12m` per 100,000 residents.",
    "active_sellers_12m": "Sellers in the state with an order in those 12 months.",
    "active_sellers_per_million_12m": "`active_sellers_12m` per million residents.",
    "share_from_other_state_12m": "Share of the state's single-seller orders shipped from another state.",
    "share_of_orders_12m": "The state's share of all orders in those 12 months.",
    "share_of_sellers": "The state's share of all sellers.",
    "share_of_funnel_sellers": "The state's share of funnel sellers who sold.",
    # dashboard views
    "broken_pct": "Broken rate, percent (0 to 100).",
    "margin_pts": "95% margin, percentage points.",
    "broken_pct_outside_busy_months": "Broken rate outside busy months, percent.",
    "orders_per_100k": "Orders per 100,000 residents, 12 months to Aug 2018.",
    "active_sellers_per_million": "Active sellers per million residents.",
    "pct_orders_from_other_state": "Percent of the state's single-seller orders in the 12 months shipped from another state.",
    "pct_of_orders": "Percent of all orders, 12 months.",
    "pct_of_sellers": "Percent of all sellers.",
    "pct_of_funnel_recruits": "Percent of funnel sellers who sold.",
    "delivery_month": "Month the orders were delivered.",
    "deliveries": "Orders delivered that month.",
    "table_and_reason": "Source table and quarantine reason.",
    "row_count": "Rows.",
    # checks
    "check_no": "Check number.",
    "check_name": "What the check tests.",
    "result": "PASS, FAIL, WARN, ESCALATE or PAGE (MATCH or DIFFERS in `design_doc_numbers`).",
    "detail": "The counts behind the result.",
    "rule_no": "Rule number in docs/data_quality_log.md.",
    "table_name": "Table the rule applies to.",
    "rule": "What the rule does.",
    "action": "FIX, KEEP, FLAG or QUARANTINE.",
    "number": "The number as named in the design document.",
    "doc_value": "The number as printed in the design document.",
    "gold_value": "The same number recomputed from Gold today.",
    # quarantine
    "source_table": "Raw table the row came from.",
    "record_key": "The row's key, as far as it can be read.",
    "reason": "Why the row was set aside.",
    "quarantined_at": "When the build set it aside.",
}
MEANING_BY_TABLE = {
    ("gold_states", "judged_orders"): "Judged orders of the state's customers.",
    ("gold_states", "broken_orders"): "Broken promises of the state's customers.",
    ("gold_states", "broken_rate"): "Broken rate of the state's customers.",
    ("gold_routes", "broken_orders"): "Broken promises on the route.",
    ("gold_routes", "broken_rate"): "The route's broken rate.",
    ("route_list", "orders"): "Judged single-seller orders on the route.",
    ("route_list", "excess_broken"): "Excess broken promises, rounded.",
    ("route_list", "margin_pts"): "95% margin in percentage points, as text; a dash under 100 orders, where the formula is not reliable.",
    ("region_fairness", "judged_orders"): "Judged orders of the region's customers.",
    ("state_view", "highlight"): "Rio de Janeiro or Other states: the label Dashboard 3's scatter colors by.",
    ("silver_states", "region"): "IBGE region in English.",
    ("stg_geolocation", "state"): "State as written in geolocation (not used; rule 27).",
    ("stg_geolocation", "city"): "City as written in geolocation.",
    ("stg_geolocation", "lat"): "Latitude.",
    ("stg_geolocation", "lng"): "Longitude.",
}

LAYERS = [
    ("Gold: the star schema", ["fact_orders", "fact_order_items", "dim_date", "dim_state", "dim_seller", "dim_product"]),
    ("Gold: business rules", ["gold_months", "gold_routes", "gold_states"]),
    ("Metric view", ["delivery_metrics"]),
    ("Views the dashboards read", ["route_list", "state_view", "region_fairness", "deliveries_per_month",
                                   "quarantine_summary"]),
    ("Checks", ["pipeline_checks", "silver_rule_counts", "design_doc_numbers"]),
    ("Silver and quarantine", ["silver_orders", "silver_order_items", "silver_order_payments", "silver_order_reviews",
                               "silver_customers", "silver_sellers", "silver_products", "silver_geolocation",
                               "silver_leads", "silver_closed_deals", "silver_states", "quarantine"]),
    ("Staging views (where the Silver rules live)", ["stg_orders", "stg_order_items", "stg_order_payments",
                                                      "stg_order_reviews", "stg_geolocation"]),
]

cols = run_dbx.run("SELECT table_name, column_name, full_data_type, comment FROM olist.information_schema.columns "
                   "WHERE table_schema = 'analytics' ORDER BY table_name, ordinal_position")["result"]["data_array"]
tabs = run_dbx.run("SELECT table_name, table_type, comment FROM olist.information_schema.tables "
                   "WHERE table_schema = 'analytics'")["result"]["data_array"]
catalog, info = {}, {t: (ty, c) for t, ty, c in tabs}
for t, c, typ, com in cols:
    catalog.setdefault(t, []).append((c, typ, com))

# The primary and foreign keys declared in 04_gold.sql (section 10), marked in the Meaning column.
keys = run_dbx.run(
    "SELECT k.table_name, k.column_name, t.constraint_type, p.table_name "
    "FROM olist.information_schema.key_column_usage k "
    "JOIN olist.information_schema.table_constraints t "
    "  ON t.constraint_name = k.constraint_name AND t.constraint_schema = k.constraint_schema "
    "LEFT JOIN olist.information_schema.referential_constraints r "
    "  ON r.constraint_name = k.constraint_name AND r.constraint_schema = k.constraint_schema "
    "LEFT JOIN olist.information_schema.table_constraints p "
    "  ON p.constraint_name = r.unique_constraint_name AND p.constraint_schema = r.unique_constraint_schema "
    "WHERE k.table_schema = 'analytics' ORDER BY 1, 3 DESC, 2")["result"]["data_array"]
pk_size = {}
for t, c, ctype, _ in keys:
    if ctype == "PRIMARY KEY":
        pk_size[t] = pk_size.get(t, 0) + 1
key_note = {}
for t, c, ctype, ref in keys:
    if ctype == "PRIMARY KEY":
        note = "Primary key" if pk_size[t] == 1 else "Part of the primary key"
    else:
        note = f"Foreign key to `{ref}`"
    key_note.setdefault((t, c), []).append(note)

listed = {t for _, ts in LAYERS for t in ts}
missing_tables = sorted(set(catalog) - listed)
if missing_tables:
    print("NOT LISTED IN LAYERS:", missing_tables)

KIND = {"MANAGED": "table", "VIEW": "view", "METRIC_VIEW": "metric view"}
out = ["# Data dictionary", "",
       "Every table and view in `olist.analytics`, built from the live catalog on the day of the last build. "
       "Column names and types are exact. Measures of the metric view are queried with `MEASURE()`. "
       "The primary and foreign keys declared in Unity Catalog (`04_gold.sql`, section 10) open the meaning "
       "of their column.", ""]
undocumented = []
for layer, tables in LAYERS:
    out += [f"## {layer}", ""]
    for t in tables:
        if t not in catalog:
            continue
        ty, comment = info.get(t, ("", ""))
        out += [f"### {t}", "", f"{KIND.get(ty, ty.lower()).capitalize()}. {comment or ''}".strip(), "",
                "| Column | Type | Meaning |", "| --- | --- | --- |"]
        for c, typ, com in catalog[t]:
            meaning = MEANING_BY_TABLE.get((t, c)) or (com if ty == "METRIC_VIEW" and com else None) or MEANING.get(c)
            if not meaning:
                meaning = "(no description)"
                undocumented.append(f"{t}.{c}")
            if (t, c) in key_note:
                notes = key_note[(t, c)]
                meaning = "; ".join([notes[0]] + [n[0].lower() + n[1:] for n in notes[1:]]) + ". " + meaning
            out.append(f"| `{c}` | {typ.lower()} | {meaning} |")
        out.append("")

open(os.path.join(ROOT, "docs", "data_dictionary.md"), "w").write("\n".join(out))
print("wrote docs/data_dictionary.md:", sum(len(v) for v in catalog.values()), "columns in", len(catalog), "objects")
if undocumented:
    print("UNDOCUMENTED:", ", ".join(undocumented))
