"""Draws docs/img/lineage.png: the map of docs/lineage.md as one picture, for the Word files and the slides.

Run from the repo root:  python3 tools/draw_lineage.py
Row counts are those of the build of 2026-11-24; update them here if the data changes.

AI use: drafted with Claude (Anthropic), 2026-11-24, from the Chord project's script (see docs/ai_usage.md).
Revised with Claude, 2026-11-26: the Genie space and the alert.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "img", "lineage.png")
W, H = 2600, 1600
img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)


def font(size, bold=False):
    paths = (["/System/Library/Fonts/Supplemental/Arial Bold.ttf"] if bold else []) + \
            ["/System/Library/Fonts/Supplemental/Arial.ttf"]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


F, FB, FS = font(21), font(30, True), font(18)
COLS = [
    ("Sources", "#5B7C8A", [("Olist marketplace", "9 CSV, Kaggle"), ("Olist funnel", "2 CSV, Kaggle"),
                            ("IBGE", "2 JSON, public API")]),
    ("Bronze: olist.raw (01)", "#3F6E80", [("orders, order_items", "99,441 / 112,650"),
                                           ("order_payments, order_reviews", "103,886 / 99,224"),
                                           ("customers, sellers", "99,441 / 3,095"),
                                           ("products, category_translation", "32,951 / 71"),
                                           ("geolocation", "1,000,163 rows"),
                                           ("leads, closed_deals", "8,000 / 842"),
                                           ("ibge_population_2018, ibge_states", "27 states")]),
    ("Silver (03)", "#0E5E78", [("stg_ views", "typing, quarantine rules"),
                                ("silver_orders", "99,441"),
                                ("silver_order_items", "112,650"),
                                ("silver_order_payments", "103,883"),
                                ("silver_order_reviews", "99,224"),
                                ("silver_customers, silver_sellers", "99,441 / 3,095"),
                                ("silver_products", "32,951"),
                                ("silver_geolocation", "19,011 zip prefixes"),
                                ("silver_leads, silver_closed_deals", "8,000 / 842"),
                                ("silver_states", "27 states"),
                                ("quarantine", "30 rows set aside")]),
    ("Gold (04)", "#B8860B", [("fact_orders", "1 row per order"), ("fact_order_items", "1 row per item line"),
                              ("dim_date, dim_state", "852 days / 27 states"),
                              ("dim_seller, dim_product", "3,095 / 32,951"),
                              ("gold_months", "busy-month rule"), ("gold_routes", "409 routes, fix type"),
                              ("gold_states", "per-resident measures")]),
    ("Metrics and checks (05-07)", "#0B84A5", [("delivery_metrics", "metric view (05): the rates"),
                                               ("pipeline_checks", "24 checks, all PASS (06)"),
                                               ("silver_rule_counts", "rows per rule (06)"),
                                               ("design_doc_numbers", "56 of 56 match (06)"),
                                               ("route_list, state_view", "dashboard views (07)"),
                                               ("region_fairness", "dashboard view (07)"),
                                               ("deliveries_per_month", "dashboard view (07)"),
                                               ("quarantine_summary", "dashboard view (07)")]),
    ("Dashboards, Genie, alert", "#0B1F2A", [("1 What broken promises cost", "Customer Experience"),
                                             ("2 Where promises break", "Logistics, + trust page"),
                                             ("3 Where local sellers help", "Seller Acquisition"),
                                             ("Ask Olist (Genie)", "questions in plain English"),
                                             ("Alert: SP > RJ", "Mondays, at 2x the national rate")]),
]
BW, BH, TOP, GAPX = 380, 84, 120, 432
pos = {}
for ci, (title, color, boxes) in enumerate(COLS):
    x = 30 + ci * GAPX
    d.text((x, 40), title, font=FB, fill=color)
    gap = (H - TOP - 40 - len(boxes) * BH) / max(len(boxes), 1)
    for bi, (name, sub) in enumerate(boxes):
        y = TOP + gap / 2 + bi * (BH + gap)
        d.rounded_rectangle([x, y, x + BW, y + BH], radius=14, fill=color)
        d.text((x + 14, y + 13), name, font=F, fill="white")
        d.text((x + 14, y + 47), sub, font=FS, fill="#E8F1F5")
        pos[(ci, bi)] = (x, y)

# One arrow between each pair of neighbouring columns, from the middle of one to the middle of the next.
for ci in range(len(COLS) - 1):
    x1 = 30 + ci * GAPX + BW + 6
    x2 = 30 + (ci + 1) * GAPX - 6
    y = H / 2 + 20
    d.line([x1, y, x2, y], fill="#333333", width=5)
    d.polygon([(x2, y), (x2 - 18, y - 11), (x2 - 18, y + 11)], fill="#333333")

img.save(OUT)
print("wrote", OUT)
