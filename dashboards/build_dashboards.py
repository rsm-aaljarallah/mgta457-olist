"""Builds the three Olist dashboard files (.lvdash.json) in this folder.

Why a script: the dashboard files are long JSON. Generating them from one
short description keeps the three dashboards consistent, and lets each
teammate import the same dashboards into their own Databricks account
(Dashboards > arrow next to Create dashboard > Import dashboard from file).
The layout started from docs/dashboard_plan.json, the plan in the design
document; the build adds one card, splits two charts and shows the fairness
check as a table, five more cards put a comparison next to each headline
number, and two cards say what the 1-2 star reviews complain about (26
visuals, against 16 sketched).

The dashboards contain no business logic. Every widget either shows a column
of a Gold table or view as it is, or asks the metric view
olist.analytics.delivery_metrics for a measure with MEASURE().
Run:  python3 dashboards/build_dashboards.py   then   python3 tools/deploy_dashboards.py

AI use: drafted with Claude (Anthropic), 2026-11-24, adapted from the
dashboard script of the Chord project (see docs/ai_usage.md). Revised with
Claude, 2026-11-24: one colour rule on every page and the comparison cards.
Revised with Claude, 2026-11-26: the two cards on what the reviews say.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
A = "olist.analytics"

PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}
TWO = {"type": "number-plain", "decimalPlaces": {"type": "max", "places": 2}}
ONE = {"type": "number-plain", "decimalPlaces": {"type": "max", "places": 1}}

# Colour is used the same way on every page, and only where it carries meaning (Few:
# colour what needs attention). In charts: gray is context; red marks broken promises
# where a chart sets them against kept ones, or against a later promise; blue marks the
# series the chart's note talks about (amber a second one, on the one chart that has
# two). Tables have their own colour keys: the fix type and the check results.
RED, AMBER, GREEN, GRAY, BLUE, TEAL = "#FF3621", "#FFAB00", "#00A972", "#919191", "#3A7DC9", "#7BC4C4"
GRAY_DARK = "#5F6368"     # a second context series, next to GRAY
RESULT_COLORS = {"PASS": GREEN, "MATCH": GREEN, "WARN": AMBER, "ESCALATE": AMBER, "PAGE": RED, "FAIL": RED,
                 "DIFFERS": AMBER}
FIX_COLORS = {"Both": RED, "Lasting fix": AMBER, "Busy-season plan": BLUE, "Watch": GRAY}
# Dashboard 3 is about local sellers, so their bar is the blue one.
SELLER_COLORS = {"Same state as customer": BLUE, "Sao Paulo": GRAY, "Other state": GRAY,
                 "Several sellers or no item": GRAY}


# ---------------------------------------------------------------- datasets
def sql_dataset(name, sql):
    return {"name": name, "displayName": name, "queryLines": [sql]}


DATASETS = {
    # The metric view is attached as an asset, not as SQL, so its measures
    # are recalculated for every filter and grouping.
    "metrics": {"name": "metrics", "displayName": "delivery_metrics", "asset_name": f"{A}.delivery_metrics"},
    "routes": sql_dataset("routes", f"SELECT * FROM {A}.route_list ORDER BY excess_rank"),
    "checks": sql_dataset("checks", f"SELECT * FROM {A}.pipeline_checks ORDER BY check_no"),
    "rules": sql_dataset("rules", f"SELECT * FROM {A}.silver_rule_counts ORDER BY rule_no"),
    "quarantine": sql_dataset("quarantine", f"SELECT * FROM {A}.quarantine_summary"),
    "deliveries": sql_dataset("deliveries", f"SELECT * FROM {A}.deliveries_per_month ORDER BY delivery_month"),
    "fairness": sql_dataset("fairness", f"SELECT * FROM {A}.region_fairness ORDER BY broken_pct DESC"),
    "states": sql_dataset("states", f"SELECT * FROM {A}.state_view"),
}


# ---------------------------------------------------------------- widgets
def col(name):            # a plain column, shown as it is
    return {"name": name, "expression": f"`{name}`"}


def measure(name):        # a measure defined in the metric view
    return {"name": f"measure({name})", "expression": f"MEASURE(`{name}`)"}


def query(dataset, fields, disaggregated=False):
    return [{"name": "main_query",
             "query": {"datasetName": dataset, "fields": fields, "disaggregated": disaggregated}}]


def text(name, markdown):
    # Databricks stores a text box as a list of lines. Every line but the last keeps its line break.
    return {"name": name, "multilineTextboxSpec": {"lines": markdown.splitlines(keepends=True)}}


def frame(title, description=None):
    f = {"showTitle": True, "title": title}
    if description:
        f.update({"showDescription": True, "description": description})
    return f


def counter(name, title, field, fmt, description=None):
    f = measure(field)
    return {"name": name,
            "queries": query("metrics", [f]),
            "spec": {"version": 2, "widgetType": "counter",
                     "encodings": {"value": {"fieldName": f["name"], "displayName": title, "format": fmt}},
                     "frame": frame(title, description)}}


def chart(name, kind, title, dataset, x, x_title, x_type, ys, y_title, fmt=None, is_measure=True,
          description=None, sort_desc=False, color=None, color_title=None, colors=None, stack=False,
          series_colors=None, hide_legend=False):
    """ys: list of (field, label). color: a column that splits the series (one line per area, say),
    with colors mapping its values to colours. series_colors: one colour per field of ys, in order.
    hide_legend: when the axis already names what the colours mean."""
    fy = [(measure(n) if is_measure else col(n), label) for n, label in ys]
    scale = {"type": x_type}
    if sort_desc:
        scale["sort"] = {"by": "y-reversed"}
    x_enc = {"fieldName": x, "scale": scale, "displayName": x_title, "axis": {"title": x_title}}
    y_enc = {"scale": {"type": "quantitative"}, "axis": {"title": y_title}}
    if fmt:
        y_enc["format"] = fmt
    if len(fy) == 1:
        y_enc.update({"fieldName": fy[0][0]["name"], "displayName": fy[0][1]})
    else:
        y_enc["fields"] = [{"fieldName": f["name"], "displayName": label} for f, label in fy]
    enc = {"x": x_enc, "y": y_enc}
    fields = [col(x)] + [f for f, _ in fy]
    if color:
        c = {"fieldName": color, "displayName": color_title or color, "scale": {"type": "categorical"}}
        if colors:
            c["scale"]["mappings"] = [{"value": v, "color": k} for v, k in colors.items()]
        enc["color"] = c
        if color != x:
            fields.append(col(color))
    if hide_legend:
        enc.setdefault("color", {})["legend"] = {"hide": True}
    spec = {"version": 3, "widgetType": kind, "encodings": enc, "frame": frame(title, description)}
    if kind == "bar" and (len(fy) > 1 or color):
        spec["mark"] = {"layout": "stack" if stack else "group"}
    if series_colors:
        spec.setdefault("mark", {})["colors"] = series_colors
    return {"name": name, "queries": query(dataset, fields, disaggregated=not is_measure), "spec": spec}


def scatter(name, title, dataset, x, x_title, y, y_title, color, color_title, extra, description=None,
            colors=None):
    scale = {"type": "categorical"}
    if colors:
        scale["mappings"] = [{"value": v, "color": k} for v, k in colors.items()]
    return {"name": name,
            "queries": query(dataset, [col(x), col(y), col(color)] + [col(e) for e, _ in extra], disaggregated=True),
            "spec": {"version": 3, "widgetType": "scatter",
                     "encodings": {
                         "x": {"fieldName": x, "scale": {"type": "quantitative"}, "displayName": x_title,
                               "axis": {"title": x_title}},
                         "y": {"fieldName": y, "scale": {"type": "quantitative"}, "displayName": y_title,
                               "axis": {"title": y_title}},
                         "color": {"fieldName": color, "displayName": color_title, "scale": scale},
                         "extra": [{"fieldName": e, "displayName": label} for e, label in extra]},
                     "frame": frame(title, description)}}


def color_by_value(colors):
    """Rules that color the text of a column by its value, for example FAIL in red."""
    return {"type": "basic",
            "rules": [{"condition": {"operand": {"type": "data-value", "value": value}, "operator": "="},
                       "foregroundColor": color}
                      for value, color in colors.items()]}


def table(name, title, dataset, columns, description=None, colors=None, rows=30):
    """columns: list of (field, label, kind). kind is "text", "int" or "one_decimal".

    The dashboard only formats the value. It never changes it. Percentages in tables arrive
    from SQL already on a 0 to 100 scale.
    """
    number_formats = {"int": "0,0", "one_decimal": "0.0"}
    cols = []
    for field, label, kind in columns:
        c = {"fieldName": field, "displayName": label, "useForSearch": False,
             "actions": {"hover": {"type": "tooltip", "tooltipTemplate": "{{ @ }}"}}}
        if kind in number_formats:
            c["format"] = {"type": "numeral.js", "format": number_formats[kind]}
        if colors and field in colors:
            c["style"] = colors[field]
        cols.append(c)
    return {"name": name,
            "queries": query(dataset, [col(f) for f, _, _ in columns], disaggregated=True),
            "spec": {"version": 2, "widgetType": "table", "rowsPerPage": rows, "displayRowNumbers": False,
                     "data": {"queryName": "main_query"}, "encodings": {"columns": cols},
                     "frame": frame(title, description)}}


def filter_widget(name, title, kind, targets):
    """targets: list of (dataset, field). One filter can drive several datasets."""
    queries, fields = [], []
    # Every filter query has two fields: the column itself, and a COUNT_IF field that Databricks uses to let
    # one filter narrow the choices of the others. Both are copied from a dashboard exported from Databricks.
    for dataset, field in targets:
        qname = f"filter_{name}_{dataset}_{field}"
        queries.append({"name": qname, "query": {"datasetName": dataset, "disaggregated": False, "fields": [
            {"name": field, "expression": f"`{field}`"},
            {"name": f"{field}_associativity", "expression": "COUNT_IF(`associative_filter_predicate_group`)"}]}})
        fields.append({"fieldName": field, "displayName": field, "queryName": qname})
    return {"name": name, "queries": queries,
            "spec": {"version": 2, "widgetType": kind, "encodings": {"fields": fields},
                     "frame": {"showTitle": True, "title": title}}}


def place(widget, x, y, w, h):
    return {"widget": widget, "position": {"x": x, "y": y, "width": w, "height": h}}


def dashboard(dataset_names, pages):
    return {"datasets": [DATASETS[n] for n in dataset_names],
            "pages": [{"name": f"page{i}", "displayName": title, "pageType": "PAGE_TYPE_CANVAS",
                       "layout": taller_title(layout)}
                      for i, (title, layout) in enumerate(pages, 1)]}


def taller_title(layout):
    """The first widget on each page is its title. Give it two rows and move the rest down one."""
    for i, item in enumerate(layout):
        if i == 0:
            item["position"]["height"] = 2
        else:
            item["position"]["y"] += 1
    return layout


def month_filter(prefix):
    return filter_widget(f"{prefix}_f_month", "Purchase month", "filter-date-range-picker",
                         [("metrics", "purchase_month")])


# ---------------------------------------------------------------- dashboard 1
cost = dashboard(["metrics"], [("What broken promises cost", [
    place(text("c_title", "# What broken promises cost\nFor the Head of Customer Experience: how much of the "
               "bad-review pile follows a broken promise, and when those reviews are written. A promise is broken "
               "when the order was not delivered by the end of the promised day."), 0, 0, 6, 1),
    place(month_filter("c"), 0, 1, 2, 1),
    place(filter_widget("c_f_region", "Customer region", "filter-multi-select",
                        [("metrics", "customer_region")]), 2, 1, 2, 1),
    place(filter_widget("c_f_cat", "Product category", "filter-multi-select",
                        [("metrics", "category")]), 4, 1, 2, 1),
    # Each headline card sits next to its comparison, the question Few asks of every number:
    # compared to what?
    place(counter("c_rate", "Orders with a broken promise", "broken_rate", PCT,
                  "Of judged orders"), 0, 2, 2, 2),
    place(counter("c_low", "1-2 star reviews that follow a broken promise", "share_low_reviews_after_broken_promise",
                  PCT, "Of in-window orders with a 1-2 star review. Compare with the share of orders, on the "
                       "left."), 2, 2, 2, 4),
    place(counter("c_before", "Late orders reviewed before they arrived", "share_late_reviewed_before_arrival", PCT,
                  "Of delivered late orders with a review. Their scores are below."), 4, 2, 2, 2),
    place(counter("c_kept", "Average review, promise kept", "avg_score_kept", TWO), 0, 4, 1, 2),
    place(counter("c_broken", "Average review, promise broken", "avg_score_broken", TWO), 1, 4, 1, 2),
    place(counter("c_score_before", "Score if reviewed before arrival", "avg_score_late_before_arrival", TWO),
          4, 4, 1, 2),
    place(counter("c_score_after", "Score if reviewed after arrival", "avg_score_late_after_arrival", TWO),
          5, 4, 1, 2),
    # Every bucket holds only kept or only broken promises, so the two measures stack into one
    # bar per bucket, gray before the promised day and red after it.
    place(chart("c_bucket", "bar", "Review score by days before or after the promised day", "metrics",
                "promise_bucket_label", "Delivered, compared with the promised day", "categorical",
                [("avg_score_kept", "Promise kept"), ("avg_score_broken", "Promise broken")],
                "Average review score", TWO, stack=True, series_colors=[GRAY, RED],
                description="The score holds while orders arrive early, then falls right after the promised day."),
          0, 6, 3, 7),
    place(chart("c_band", "bar", "On time vs late, same delivery time", "metrics",
                "delivery_time_band", "Days from purchase to delivery", "categorical",
                [("avg_score_kept", "Promise kept"), ("avg_score_broken", "Promise broken")],
                "Average review score", TWO, series_colors=[GRAY, RED],
                description="With no filter, late orders score lower in every band of the same delivery time, "
                            "so the score follows the promise, not only the speed."), 3, 6, 3, 7),
    # What the customers write: the same 1-2 star reviews, read for words that say the parcel was
    # late, slow or missing. The word list is in 04_gold.sql, its hand check in 08_robustness.sql.
    place(text("c_words", "**What the 1-2 star reviews say.** A review counts when its title or comment, in "
               "Portuguese, says the parcel was late, slow or missing: *atraso*, *demora*, *não recebi*, "
               "*não chegou*, *não foi entregue*, *nunca chegou*, *extraviado*, *fora do prazo*. We read 100 "
               "reviews the list flags, drawn at random: 95 were real delivery complaints. The list also misses "
               "complaints worded otherwise (18 of 30 unflagged broken promises we read), so the share for broken "
               "promises is a floor. Base: judged orders whose latest review gives 1 or 2 stars and has text."),
          0, 13, 4, 2),
    place(counter("c_words_kept", "Promise kept", "share_low_reviews_late_or_missing_kept", PCT,
                  "Say late or missing"), 4, 13, 1, 2),
    place(counter("c_words_broken", "Promise broken", "share_low_reviews_late_or_missing_broken", PCT,
                  "Say late or missing"), 5, 13, 1, 2),
    place(text("c_note", "**Read with care.** Every link between promises and reviews is a correlation. "
               "The cheap test it points to: a delay notice with a new date, sent before the review survey to "
               "customers whose parcel will miss. Judged orders: bought from January 2017 and promised by "
               "August 31, 2018, not canceled or unavailable, and not one of 8 marked delivered with no delivery date; an order that never arrived counts as broken. Each "
               "order counts its latest review once. Source: `olist.analytics.delivery_metrics`."), 0, 15, 6, 2),
])])

# ---------------------------------------------------------------- dashboard 2
where = dashboard(["metrics", "routes", "checks", "rules", "quarantine", "deliveries", "fairness"], [
    ("Where promises break", [
        place(text("w_title", "# Where promises break\nFor the Head of Logistics: which routes to fix first, "
                   "and whether each needs a lasting fix, a busy-season plan, or both. A route is seller state > "
                   "customer state, for orders shipped by one seller."), 0, 0, 6, 1),
        place(month_filter("w"), 0, 1, 2, 1),
        place(filter_widget("w_f_seller", "Seller state", "filter-multi-select",
                            [("metrics", "seller_state"), ("routes", "seller_state")]), 2, 1, 2, 1),
        place(filter_widget("w_f_region", "Customer region", "filter-multi-select",
                            [("metrics", "customer_region"), ("routes", "customer_region")]), 4, 1, 2, 1),
        place(table("w_routes", "Routes to fix first", "routes", [
            ("excess_rank", "Rank", "int"),
            ("route", "Route", "text"),
            ("orders", "Orders", "int"),
            ("broken_pct", "Broken %", "one_decimal"),
            ("margin_pts", "+/- points", "text"),
            ("excess_broken", "Excess broken", "int"),
            ("fix_type", "Fix type", "text"),
            ("first_step", "First step", "text"),
        ], colors={"fix_type": color_by_value(FIX_COLORS)}, rows=10,
            description="Ranked by excess broken promises: broken minus what the national rate (8.7%) predicts "
                        "for the route's orders. A route with fewer than 100 orders gets no fix type (Watch) and "
                        "no margin (shown as –). The "
                        "fix type compares busy months with the rest of the year, so this table ignores the month "
                        "filter."), 0, 2, 6, 8),
        place(chart("w_line", "line", "Broken-promise rate by month and area", "metrics", "purchase_month",
                    "Purchase month", "temporal", [("broken_rate", "Broken-promise rate")], "Broken-promise rate",
                    PCT, color="customer_area", color_title="Customer area",
                    colors={"Rio de Janeiro": BLUE, "Northeast": AMBER, "Southeast without Rio": GRAY,
                            "South": GRAY, "Center-West": GRAY, "North": GRAY},
                    description="Busy months: Nov 2017, Feb 2018 and Mar 2018, when the national rate was at least "
                                "twice the median month. On average Rio (blue) jumps the most in those months; the "
                                "Northeast (amber) has the highest rate in ordinary months too. August 2018 is a "
                                "partial month: about 30% of its orders were promised for September and are not "
                                "judged."),
              0, 10, 3, 7),
        place(chart("w_later", "bar", "Now vs a promise 3 days later, by region", "metrics", "customer_region",
                    "Customer region", "categorical",
                    [("broken_rate", "Now"), ("broken_rate_if_3_days_later", "Promise 3 days later")],
                    "Broken-promise rate", PCT, sort_desc=True, series_colors=[RED, GRAY],
                    description="With no filter: promising later fixes less than a quarter of the problem, and "
                                "less in the Northeast, where a late order typically arrives 8 days late."),
              3, 10, 3, 7),
        place(chart("w_days", "bar", "Where the days go: purchase to carrier, carrier to customer", "metrics",
                    "promise_outcome", "Promise", "categorical",
                    [("avg_days_to_carrier", "Purchase to carrier"),
                     ("avg_days_carrier_to_customer", "Carrier to customer")],
                    "Average days", ONE, stack=True, series_colors=[GRAY, BLUE],
                    description="Judged orders that arrived, both parts measured on the same orders, so each bar "
                                "adds up to the delivery time. Most of a broken promise's delay comes after the "
                                "handover (blue)."), 0, 17, 4, 6),
        # Handed over on time = handed to the carrier by the seller's deadline.
        place(counter("w_handed", "Late deliveries handed over on time", "share_late_handed_over_by_deadline", PCT,
                      "Broken promises from one seller, by the seller's deadline"),
              4, 17, 2, 3),
        place(counter("w_handed_kept", "On-time deliveries handed over on time", "share_kept_handed_over_by_deadline",
                      PCT, "The same share for kept promises"),
              4, 20, 2, 3),
    ]),
    ("Can we trust it", [
        place(text("t_title", "# Can we trust it\nThe checks the pipeline ran, what each cleaning rule did, the "
                   "rows set aside, why the analysis stops in August 2018, and whether one region is served "
                   "worse."), 0, 0, 6, 1),
        place(table("t_checks", "Pipeline checks", "checks", [
            ("check_no", "#", "int"),
            ("check_name", "Check", "text"),
            ("result", "Result", "text"),
            ("detail", "Detail", "text"),
        ], colors={"result": color_by_value(RESULT_COLORS)},
            description="Recalculated whenever the dashboard is refreshed. Every row should say PASS."),
              0, 1, 6, 10),
        place(table("t_rules", "Silver rules: rows fixed, kept, flagged or set aside", "rules", [
            ("rule_no", "Rule", "int"),
            ("action", "Action", "text"),
            ("row_count", "Rows", "int"),
            ("table_name", "Table", "text"),
            ("rule", "What it does", "text"),
        ], description="The rules and their reasons are in docs/data_quality_log.md."), 0, 11, 4, 10),
        place(chart("t_quarantine", "bar", "Rows set aside, by reason", "quarantine", "table_and_reason",
                    "Table: reason", "categorical", [("row_count", "Rows")], "Rows", is_measure=False,
                    sort_desc=True, series_colors=[GRAY],
                    description="Quarantine rate is check 5: class thresholds warn 1%, "
                                "escalate 3%, page 10%."), 4, 11, 2, 10),
        place(chart("t_deliveries", "bar", "Deliveries recorded per month", "deliveries", "delivery_month",
                    "Month delivered", "temporal", [("deliveries", "Deliveries")], "Deliveries", is_measure=False,
                    series_colors=[GRAY], description="8,314 deliveries in August 2018, then 56 in September and 3 in October, so a "
                                "promise is judged only if its day passed by August 31, 2018. Even so, the last "
                                "days of August hold mostly orders that had already arrived."), 0, 21, 3, 6),
        place(table("t_fair", "Fairness: broken-promise rate by region, with margins", "fairness", [
            ("region", "Customer region", "text"),
            ("judged_orders", "Orders", "int"),
            ("broken_pct", "Broken %", "one_decimal"),
            ("margin_pts", "+/- points", "one_decimal"),
        ], description="Northeast customers get worse service. We show the gap with its margin; the fixes aim at "
                       "routes and carriers, never at customers or sellers."), 3, 21, 3, 6),
    ]),
])

# ---------------------------------------------------------------- dashboard 3
local = dashboard(["metrics", "states"], [("Where local sellers would help", [
    place(text("l_title", "# Where local sellers would help\nFor the Head of Seller Acquisition: which states "
               "buy a lot but have few nearby sellers, how much faster local sellers deliver, and whether the "
               "funnel recruits there."), 0, 0, 6, 1),
    place(filter_widget("l_f_region", "Customer region", "filter-multi-select",
                        [("metrics", "customer_region"), ("states", "region")]), 0, 1, 2, 1),
    place(filter_widget("l_f_state", "Customer state", "filter-multi-select",
                        [("metrics", "customer_state")]), 2, 1, 2, 1),
    place(filter_widget("l_f_cat", "Product category", "filter-multi-select",
                        [("metrics", "category")]), 4, 1, 2, 1),
    place(scatter("l_scatter", "States: orders per 100,000 residents vs broken-promise rate", "states",
                  "orders_per_100k", "Orders per 100,000 residents (12 months to Aug 2018)",
                  "broken_pct", "Broken %", "highlight", "State",
                  [("state_name", "State"), ("region", "Region"),
                   ("active_sellers_per_million", "Active sellers per million"),
                   ("pct_orders_from_other_state", "% of single-seller orders from another state")],
                  colors={"Rio de Janeiro": BLUE, "Other states": GRAY},
                  description="Each dot is a state: orders per 100,000 residents (IBGE 2018 population) in the 12 "
                              "months to August 2018, against the broken-promise rate over the whole window. Rio "
                              "(blue) buys 56.4 against 71.7 in Sao Paulo, the dot furthest right, with a quarter "
                              "of Sao Paulo's sellers per resident. Only the region filter applies here."), 0, 2, 3, 9),
    place(chart("l_rate", "bar", "Local vs Sao Paulo sellers: broken-promise rate", "metrics", "seller_location",
                "Seller", "categorical", [("broken_rate", "Broken-promise rate")], "Broken-promise rate", PCT,
                color="seller_location", colors=SELLER_COLORS, stack=True, hide_legend=True,
                description="Pick one customer state above. Example, Rio de Janeiro with no other filter: local "
                            "sellers (blue) 7.7% (+/- 1.7), Sao Paulo sellers 17.1%. Most of that gap is in the busy "
                            "months (4.1% against 39.8%); in the other months it is 8.7% against 10.0%. 'Several "
                            "sellers or no item' holds the orders with no single seller."), 3, 2, 3, 9),
    place(chart("l_days", "bar", "Local vs Sao Paulo sellers: median days to deliver", "metrics",
                "seller_location", "Seller", "categorical", [("median_delivery_days", "Median days")],
                "Median days from purchase to delivery", ONE,
                color="seller_location", colors=SELLER_COLORS, stack=True, hide_legend=True,
                description="Local sellers may sell different products, so this is a correlation: a recruiting "
                            "pilot has to prove the speed."), 0, 11, 6, 6),
    place(chart("l_shares", "bar", "Share of orders, sellers and funnel recruits, by state", "states", "state",
                "Customer or seller state", "categorical",
                [("pct_of_orders", "% of orders (12 months)"), ("pct_of_sellers", "% of all sellers"),
                 ("pct_of_funnel_recruits", "% of funnel recruits who sold")],
                "Percent", ONE, is_measure=False, sort_desc=True, series_colors=[GRAY, GRAY_DARK, BLUE],
                description="The funnel recruits (blue) where sellers already are: Sao Paulo holds 59.7% of sellers and "
                            "61.1% of funnel recruits who sold, while Rio, with 12.7% of orders, got 6.8%. The "
                            "region filter narrows the states shown; the state and category filters do not apply "
                            "here."),
          0, 17, 6, 7),
])])

FILES = {
    "olist_1_what_broken_promises_cost.lvdash.json": cost,
    "olist_2_where_promises_break.lvdash.json": where,
    "olist_3_where_local_sellers_would_help.lvdash.json": local,
}

if __name__ == "__main__":
    for filename, content in FILES.items():
        with open(os.path.join(HERE, filename), "w") as f:
            json.dump(content, f, indent=2)
        print("wrote", filename)
