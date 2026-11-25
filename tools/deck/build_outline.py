"""Writes docs/presentation_outline.md from tools/deck/script.json, the same text as the slides' speaker notes.

    python3 tools/deck/build_outline.py

Run it after editing script.json, together with build_deck.js, so the outline and
the notes in the deck never drift apart.

AI use: drafted with Claude (Anthropic), 2026-11-24 (see docs/ai_usage.md).
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
script = json.load(open(os.path.join(ROOT, "tools", "deck", "script.json")))
total = sum(s["minutes"] for s in script)
by_speaker = {}
for s in script:
    by_speaker[s["speaker"]] = by_speaker.get(s["speaker"], 0) + s["minutes"]

out = ["# Presentation outline", "",
       f"The talk for `deliverables/olist_presentation.pptx`: {len(script)} slides, about {total} minutes, within the "
       "10 to 15 the syllabus asks. The same text is in each slide's speaker notes; both come from "
       "`tools/deck/script.json`. The speaker split is a suggestion.", "",
       "| Slide | Title | Speaker | Minutes |", "| ---: | --- | --- | ---: |"]
out += [f"| {s['slide']} | {s['title']} | {s['speaker']} | {s['minutes']} |" for s in script]
out += ["", f"Total: {total} minutes. " + ", ".join(f"{k} {v}" for k, v in by_speaker.items()) + ".", ""]
for s in script:
    out += [f"## {s['slide']}. {s['title']}", "", f"**{s['speaker']}, {s['minutes']} min.** {s['say']}", ""]
open(os.path.join(ROOT, "docs", "presentation_outline.md"), "w").write("\n".join(out))
print("wrote docs/presentation_outline.md:", len(script), "slides,", total, "minutes")
