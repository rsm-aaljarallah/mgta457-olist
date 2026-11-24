"""Export one or more markdown files from docs/ to a single Word file.

Run from the repo root, after `pip install python-docx`:

    python3 tools/export_word.py deliverables/olist_design_document.docx \
        "Olist Delivery Promise: Dashboard Design Document" "" docs/design_doc.md

The arguments are: the Word file to write, the title, a byline, then the
markdown files. With several files the title and the byline open the
document. With one file the document keeps its own title, and the byline
is left empty ("").

The markdown files are the source. Edit them, then run this again. Do not
edit the Word files by hand, or the two will drift apart.

The script understands only what our docs use: headings, paragraphs, bullet
and numbered lists, tables, images, `code` and **bold**. Code blocks, such as
the mermaid diagram, are left out.

AI use: drafted with Claude (Anthropic) for the Chord project, 2026-11-14,
revised 2026-11-16; copied unchanged into this project on 2026-11-19
(see docs/ai_usage.md).
"""
import datetime
import os
import re
import sys

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches, Pt


def add_text(paragraph, text):
    """Add text to a paragraph. `code` and **bold** become Word formatting."""
    for part in re.split(r"(`[^`]+`|\*\*[^*]+\*\*)", text):
        if part.startswith("`"):
            run = paragraph.add_run(part[1:-1])
            run.font.name = "Consolas"
            run.font.size = Pt(9.5)
        elif part.startswith("**"):
            paragraph.add_run(part[2:-2]).bold = True
        elif part:
            paragraph.add_run(part)


def read_sources(paths, title, byline):
    """Return the lines of all source files as one list.

    With several files, every heading moves down one level, and the title
    and byline given on the command line open the document.
    """
    if len(paths) == 1:
        return open(paths[0]).read().splitlines()
    lines = ["# " + title, "", byline, ""]
    for path in paths:
        for line in open(path).read().splitlines():
            if line.startswith("#"):
                line = "#" + line          # "# " becomes "## ", "## " becomes "### ", and so on
            lines.append(line)
        lines.append("")
    return lines


def add_heading(doc, text, level):
    """Add a heading. The text goes through add_text so `code` in a heading looks like code."""
    heading = doc.add_heading("", level)
    add_text(heading, text)
    if level > 0:
        heading.paragraph_format.keep_with_next = True
    if level == 1:
        heading.paragraph_format.space_before = Pt(8)


TEXT_WIDTH = 6.7   # inches between the left and right margins


def column_widths(rows):
    """Share the text width between the columns by how much each one holds.

    Every column first gets room for its longest word, so no word is broken
    in two (capped, so one long file path cannot take the whole table). The
    rest of the width goes by the average length of each column's cells.
    """
    count = len(rows[0])
    minimum, average = [], []
    for c in range(count):
        cells = [row[c] if c < len(row) else "" for row in rows]
        words = [word for cell in cells for word in cell.replace("`", "").replace("*", "").split()]
        longest = max((len(word) for word in words), default=4)
        minimum.append(min(0.075 * longest + 0.15, 2.0))   # about 0.075 inches per character at 9.5 points
        average.append(max(sum(len(cell) for cell in cells) / len(cells), 1))
    spare = TEXT_WIDTH - sum(minimum)
    if spare <= 0:
        return [width * TEXT_WIDTH / sum(minimum) for width in minimum]
    return [width + spare * share / sum(average) for width, share in zip(minimum, average)]


def add_table(doc, rows):
    """Add a table. The first row is the header."""
    column_count = len(rows[0])
    table = doc.add_table(rows=len(rows), cols=column_count)
    table.style = "Light Grid Accent 1"
    table.autofit = False
    for c, width in enumerate(column_widths(rows)):
        table.columns[c].width = Inches(width)
        for cell in table.columns[c].cells:
            cell.width = Inches(width)
    for r, row in enumerate(rows):
        for c, cell_text in enumerate(row[:column_count]):
            paragraph = table.cell(r, c).paragraphs[0]
            paragraph.paragraph_format.space_after = Pt(0)
            add_text(paragraph, cell_text)
            for run in paragraph.runs:
                run.font.size = Pt(9.5)
                if r == 0:
                    run.bold = True
    doc.add_paragraph()


def add_image(doc, line, base_folder):
    """Add a picture from a markdown image line, with its caption below.

    A width in inches can follow the path as a title, as in
    ![caption](img/user_flow.png "width=6.4"). Without one, the lineage map
    gets the full text width and any other picture 4.7 inches.
    """
    match = re.match(r'!\[(.*?)\]\((\S+?)(?:\s+"width=([\d.]+)")?\)', line)
    caption, path, width_text = match.group(1), match.group(2), match.group(3)
    if width_text:
        width = Inches(float(width_text))
    else:
        width = Inches(6.4) if "lineage" in path else Inches(4.7)
    picture = doc.add_paragraph()
    picture.alignment = WD_ALIGN_PARAGRAPH.CENTER
    picture.add_run().add_picture(os.path.join(base_folder, path), width=width)
    label = doc.add_paragraph()
    label.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = label.add_run("Figure: " + caption)
    run.italic = True
    run.font.size = Pt(9)


def main():
    out_path, title, byline, sources = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    # Image links in the markdown are relative to the folder the files are in.
    base_folder = os.path.dirname(sources[0])

    doc = Document()
    doc.core_properties.author = "AJ"
    doc.core_properties.last_modified_by = "AJ"
    doc.core_properties.title = title
    doc.core_properties.comments = ""
    doc.core_properties.created = datetime.datetime.now()
    doc.core_properties.modified = datetime.datetime.now()
    for section in doc.sections:
        section.left_margin = section.right_margin = Inches(0.9)
        section.top_margin = section.bottom_margin = Inches(0.8)
    normal = doc.styles["Normal"]
    normal.font.name = "Calibri"
    normal.font.size = Pt(10.5)
    normal.paragraph_format.space_after = Pt(5)

    lines = read_sources(sources, title, byline)
    in_code_block = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            in_code_block = not in_code_block
        elif in_code_block or not line.strip():
            pass
        elif line.startswith("#"):
            # "# " is the title (level 0), "## " is level 1, and so on
            marks = len(line) - len(line.lstrip("#"))
            add_heading(doc, line[marks:].strip(), marks - 1)
        elif line.startswith("- "):
            add_text(doc.add_paragraph(style="List Bullet"), line[2:])
        elif re.match(r"\d+\. ", line):
            # Keep the number that is written in the markdown, so every list starts where it should.
            paragraph = doc.add_paragraph()
            paragraph.paragraph_format.left_indent = Inches(0.25)
            paragraph.paragraph_format.first_line_indent = Inches(-0.25)
            add_text(paragraph, line)
        elif line.startswith("!["):
            add_image(doc, line, base_folder)
        elif line.startswith("|"):
            # Collect every row of the table, skipping the |---|---| divider.
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [cell.strip() for cell in lines[i].strip().strip("|").split("|")]
                is_divider = all(set(cell) <= set("-: ") for cell in cells)
                if not is_divider:
                    rows.append(cells)
                i += 1
            add_table(doc, rows)
            continue
        else:
            add_text(doc.add_paragraph(), line)
        i += 1

    doc.save(out_path)
    print("saved", out_path)


if __name__ == "__main__":
    main()
