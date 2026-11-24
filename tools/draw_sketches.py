"""Draw the design document's figures from the dashboard plan: a layout sketch
of every dashboard page, and the intended user flow.

Run from the repo root, after `pip install Pillow`:

    python3 tools/draw_sketches.py docs/dashboard_plan.json

The plan is a JSON file with two parts:
- "pages": one entry per dashboard page, with "dashboard" (its number),
  "heading", "file" (the picture to write in docs/img) and "layout", a list
  of boxes. Each box has "kind" (text, filter, card, bar, line, scatter or
  table), "title", and its place on the 6-column dashboard grid: "x", "y",
  "w" (columns) and "h" (rows).
- "flow": the user-flow picture, with "title" and "rows". Each row has a
  "reader", one or two "boxes" (each with "title" and "question") and the
  "arrows" between them.

Boxes keep their place and width; heights are capped so a sketch fits on a
page. Each card, chart and table gets a number, counted from the top left
and continued across the pages of the same dashboard. The design document
uses the same numbers.

Adapted from the Chord project's sketch script, which read the built
dashboard files. Here the dashboards are not built yet, so the plan is the
source. Once they are built, the sketches can be drawn from those files.

AI use: drafted with Claude (Anthropic), 2026-11-17 (see docs/ai_usage.md).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(REPO, "docs", "img")

COL = 210        # pixels per grid column; every dashboard is 6 columns wide
ROW = 36         # pixels per grid row
MARGIN = 28
GAP = 6          # space between neighbouring boxes
INK = "#26343B"
FAINT = "#7D8D95"
LINE = "#B7C3C9"
FILL = "#F3F6F8"
ACCENT = "#1F6F8B"

# How tall each kind of box is drawn, in grid rows, at most.
MAX_ROWS = {"text": 1.6, "filter": 1, "card": 2.6, "bar": 3, "line": 3, "scatter": 3, "table": 3}


def load_font(size, bold=False):
    """Arial if the computer has it, otherwise Pillow's own font."""
    if bold:
        candidates = ["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "C:/Windows/Fonts/arialbd.ttf"]
    else:
        candidates = ["/System/Library/Fonts/Supplemental/Arial.ttf", "C:/Windows/Fonts/arial.ttf"]
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def fit(draw, text, font, width):
    """Cut text to fit a width, ending with an ellipsis if anything was cut."""
    if draw.textlength(text, font=font) <= width:
        return text
    while text and draw.textlength(text + "...", font=font) > width:
        text = text[:-1]
    return text.rstrip() + "..."


def wrap(draw, text, font, width, max_lines):
    """Break text into lines that fit a width. The last line is cut if needed."""
    lines, current = [], ""
    for word in text.split():
        trial = (current + " " + word).strip()
        if draw.textlength(trial, font=font) <= width:
            current = trial
        else:
            lines.append(current)
            current = word
    lines.append(current)
    if len(lines) > max_lines:
        lines = lines[:max_lines - 1] + [fit(draw, " ".join(lines[max_lines - 1:]), font, width)]
    return lines


def draw_marks(draw, kind, left, top, right, bottom):
    """Draw a small picture of the visual inside its box, below the title."""
    if kind == "card":
        draw.rectangle([left, bottom - 10, left + (right - left) * 0.45, bottom], fill=ACCENT)
    elif kind == "bar":
        count, span = 8, right - left
        for i in range(count):
            height = (bottom - top) * (0.35 + 0.6 * ((i * 37) % 11) / 10)
            x = left + span * (i + 0.2) / count
            draw.rectangle([x, bottom - height, x + span * 0.6 / count, bottom], fill=ACCENT)
    elif kind == "line":
        for shift, color in ((0, ACCENT), (0.25, FAINT)):
            points = [(left + (right - left) * i / 9,
                       top + (bottom - top) * (0.3 + shift + 0.25 * ((i * 53) % 7) / 6)) for i in range(10)]
            draw.line(points, fill=color, width=4)
    elif kind == "scatter":
        for i in range(30):
            x = left + (right - left) * ((i * 41) % 97) / 97
            y = top + (bottom - top) * ((i * 29) % 89) / 89
            draw.ellipse([x - 4, y - 4, x + 4, y + 4], fill=ACCENT)
    elif kind == "table":
        draw.rectangle([left, top, right, top + 12], fill=LINE)
        step = (bottom - top - 12) / 4
        for i in range(1, 5):
            y = top + 12 + step * i
            draw.line([(left, y), (right, y)], fill=LINE, width=2)


def band_heights(layout):
    """Rows of the dashboard grid, each drawn as tall as its boxes need.

    Cards always get their full drawn height, so a two-line title fits.
    Everything else is drawn at its planned height, up to its limit.
    """
    heights = {}
    for box in layout:
        drawn = MAX_ROWS["card"] if box["kind"] == "card" else min(box["h"], MAX_ROWS.get(box["kind"], 2))
        heights[box["y"]] = max(heights.get(box["y"], 0), drawn)
    return heights


def draw_page(page, first_number):
    """Draw one dashboard page. Returns the next free visual number."""
    layout = page["layout"]
    bands = band_heights(layout)
    top_of, y = {}, MARGIN + 56
    for start in sorted(bands):
        top_of[start] = y
        y += bands[start] * ROW
    image = Image.new("RGB", (6 * COL + 2 * MARGIN, int(y + MARGIN)), "white")
    draw = ImageDraw.Draw(image)
    heading_font, label_font, small_font = load_font(30, bold=True), load_font(22), load_font(20, bold=True)
    draw.text((MARGIN, MARGIN), page["heading"] + " (layout sketch)", font=heading_font, fill=INK)

    number = first_number
    for box in sorted(layout, key=lambda b: (b["y"], b["x"])):
        kind, label = box["kind"], box["title"]
        left = MARGIN + box["x"] * COL + GAP / 2
        right = MARGIN + (box["x"] + box["w"]) * COL - GAP / 2
        top = top_of[box["y"]] + GAP / 2
        bottom = top + bands[box["y"]] * ROW - GAP
        if kind == "text":
            draw.rounded_rectangle([left, top, right, bottom], radius=8, outline=LINE, width=2)
            bold = not label.startswith("Note: ")
            font = load_font(22, bold=bold)
            draw.text((left + 12, top + 10), fit(draw, label, font, right - left - 24), font=font, fill=INK if bold else FAINT)
            continue
        if kind == "filter":
            draw.rounded_rectangle([left, top, right, bottom], radius=6, outline=FAINT, width=2)
            draw.text((left + 10, top + 6), fit(draw, "Filter: " + label, label_font, right - left - 40), font=label_font, fill=INK)
            middle = (top + bottom) / 2
            draw.line([(right - 26, middle - 4), (right - 18, middle + 4), (right - 10, middle - 4)], fill=INK, width=3)
            continue
        draw.rounded_rectangle([left, top, right, bottom], radius=8, fill=FILL, outline=LINE, width=2)
        draw.ellipse([left + 8, top + 8, left + 38, top + 38], fill=INK)
        text = str(number)
        draw.text((left + 23 - draw.textlength(text, font=small_font) / 2, top + 12), text, font=small_font, fill="white")
        lines = wrap(draw, label, label_font, right - left - 60, 2 if kind == "card" else 1)
        for i, line in enumerate(lines):
            draw.text((left + 46, top + 10 + i * 26), line, font=label_font, fill=INK)
        marks_top = top + 14 + len(lines) * 26
        if bottom - marks_top > 16:
            draw_marks(draw, kind, left + 16, marks_top, right - 16, bottom - 10)
        number += 1

    image.save(os.path.join(IMG, page["file"]))
    print("wrote", page["file"], image.size)
    return number


def draw_flow(flow):
    """One row per reader: where they start, what they ask, where they go next."""
    rows = flow["rows"]
    name_w, box_w, box_h, arrow_w, row_h = 240, 520, 124, 200, 158
    width = MARGIN * 2 + name_w + 2 * box_w + arrow_w
    height = MARGIN * 2 + 62 + len(rows) * row_h
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    heading_font, name_font = load_font(34, bold=True), load_font(30, bold=True)
    title_font, question_font, arrow_font = load_font(28, bold=True), load_font(26), load_font(24)
    draw.text((MARGIN, MARGIN), flow["title"], font=heading_font, fill=INK)
    for r, row in enumerate(rows):
        top = MARGIN + 62 + r * row_h + (row_h - box_h) / 2
        if r % 2 == 0:
            draw.rectangle([MARGIN - 10, top - 18, width - MARGIN + 10, top + box_h + 18], fill="#F7FAFB")
        name_lines = wrap(draw, row["reader"], name_font, name_w - 20, 2)
        for i, line in enumerate(name_lines):
            draw.text((MARGIN, top + box_h / 2 - 18 * len(name_lines) + i * 36), line, font=name_font, fill=ACCENT)
        for b, box in enumerate(row["boxes"]):
            left = MARGIN + name_w + b * (box_w + arrow_w)
            fill = "#E8F1F4" if b == 0 else FILL
            draw.rounded_rectangle([left, top, left + box_w, top + box_h], radius=12, fill=fill, outline=LINE, width=2)
            draw.text((left + 16, top + 12), fit(draw, box["title"], title_font, box_w - 32), font=title_font, fill=INK)
            for i, line in enumerate(wrap(draw, box["question"], question_font, box_w - 32, 2)):
                draw.text((left + 16, top + 54 + i * 31), line, font=question_font, fill=FAINT)
            if b < len(row.get("arrows", [])):
                start, end, middle = left + box_w + 10, left + box_w + arrow_w - 10, top + box_h / 2
                draw.line([(start, middle), (end - 12, middle)], fill=INK, width=3)
                draw.polygon([(end, middle), (end - 16, middle - 9), (end - 16, middle + 9)], fill=INK)
                label_lines = wrap(draw, row["arrows"][b], arrow_font, arrow_w - 16, 2)
                for i, line in enumerate(label_lines):
                    draw.text((start + 2, middle - 10 - 24 * (len(label_lines) - i)), line, font=arrow_font, fill=INK)
    image.save(os.path.join(IMG, flow.get("file", "user_flow.png")))
    print("wrote", flow.get("file", "user_flow.png"), image.size)


def main():
    plan = json.load(open(sys.argv[1], encoding="utf-8"))
    os.makedirs(IMG, exist_ok=True)
    next_number = {}
    for page in plan["pages"]:
        dashboard = page["dashboard"]
        next_number[dashboard] = draw_page(page, next_number.get(dashboard, 1))
    if "flow" in plan:
        draw_flow(plan["flow"])


if __name__ == "__main__":
    main()
