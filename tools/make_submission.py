"""Assemble the submission folder and zip next to this repository, from the files in it.

    python3 tools/make_submission.py

Writes ../olist_submission/ (the three Office files, the three dashboard files, the SQL,
the Genie spec and the job and alert settings, and a short README.txt) and
../olist_submission.zip, then checks that every copy is byte-identical to the
repository's file. Rebuild the Office files first (see README.md); the folder is
replaced on every run.

AI use: drafted with Claude (Anthropic), 2026-11-26 (see docs/ai_usage.md).
"""
import hashlib
import os
import shutil
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(os.path.dirname(REPO), "olist_submission")
ZIP = os.path.join(os.path.dirname(REPO), "olist_submission.zip")

files = {
    "olist_design_document.docx": "deliverables/olist_design_document.docx",
    "olist_final_documentation.docx": "deliverables/olist_final_documentation.docx",
    "olist_presentation.pptx": "deliverables/olist_presentation.pptx",
}
for f in sorted(os.listdir(os.path.join(REPO, "dashboards"))):
    if f.endswith(".lvdash.json"):
        files["dashboards/" + f] = "dashboards/" + f
for f in sorted(os.listdir(os.path.join(REPO, "sql"))):
    if f.endswith(".sql"):
        files["sql/" + f] = "sql/" + f
files["genie_and_jobs/ask_olist.json"] = "genie/ask_olist.json"
files["genie_and_jobs/olist_rebuild.json"] = "jobs/olist_rebuild.json"
files["genie_and_jobs/alert_sp_rj.json"] = "jobs/alert_sp_rj.json"

readme = """Olist delivery promise - MGTA 457 team project (AJ, Ruby, Merna)

What is here
  olist_design_document.docx      Dashboard design document (5 pages, sketches, user flow)
  olist_final_documentation.docx  Final documentation: overview, lineage, metric and data
                                  dictionaries, data quality log, AI usage log
  olist_presentation.pptx         The talk: 13 slides, about 14.75 minutes, speaker notes on every slide
  dashboards/                     The three Databricks AI/BI dashboards (.lvdash.json); import them
                                  under Dashboards > Import dashboard from file
  sql/                            The SQL workflow, run in order 00 to 07 (08 and 09 are read-only)
  genie_and_jobs/                 The Genie space spec, the weekly rebuild job and the alert

Everything is built in Databricks (catalog olist). The full repository, with the scripts that
build these files, is on GitHub: rsm-aaljarallah/mgta457-olist (private; access on request).
"""

if os.path.exists(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)
for dst, src in files.items():
    os.makedirs(os.path.dirname(os.path.join(OUT, dst)) or OUT, exist_ok=True)
    shutil.copy2(os.path.join(REPO, src), os.path.join(OUT, dst))
open(os.path.join(OUT, "README.txt"), "w").write(readme)

if os.path.exists(ZIP):
    os.remove(ZIP)
with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, names in os.walk(OUT):
        for n in sorted(names):
            p = os.path.join(root, n)
            z.write(p, os.path.join("olist_submission", os.path.relpath(p, OUT)))

# every copied file must be byte-identical to the repository's
bad = [d for d, s in files.items()
       if hashlib.sha256(open(os.path.join(OUT, d), "rb").read()).digest()
       != hashlib.sha256(open(os.path.join(REPO, s), "rb").read()).digest()]
print(f"{len(files)} files copied, {len(bad)} differ; zip {os.path.getsize(ZIP) // 1024} KB at {ZIP}")
