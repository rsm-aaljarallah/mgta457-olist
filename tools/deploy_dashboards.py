"""Create or update the three Olist dashboards in Databricks from dashboards/*.lvdash.json, then publish them.

    python3 tools/deploy_dashboards.py [name part] [--profile chord]

The dashboard ids are kept in dashboards/dash_ids.json, so a second run updates
the same dashboards instead of making new ones. Run dashboards/build_dashboards.py
first, and sql/06_checks.sql: do not publish unless every pipeline check says PASS.

AI use: drafted with Claude (Anthropic), 2026-11-24, from the Chord project's
deploy script (see docs/ai_usage.md).
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DASH = os.path.join(ROOT, "dashboards")
IDS = os.path.join(DASH, "dash_ids.json")
WAREHOUSE = "667de8a20d9687ca"
PARENT = "/Users/aaljarallah@ucsd.edu"
NAMES = {
    "olist_1_what_broken_promises_cost.lvdash.json": "Olist 1 - What broken promises cost",
    "olist_2_where_promises_break.lvdash.json": "Olist 2 - Where promises break",
    "olist_3_where_local_sellers_would_help.lvdash.json": "Olist 3 - Where local sellers would help",
}

args = sys.argv[1:]
profile = "chord"
if "--profile" in args:
    i = args.index("--profile"); profile = args[i + 1]; del args[i:i + 2]
only = args[0] if args else None

ids = json.load(open(IDS)) if os.path.exists(IDS) else {}
ok = True
for f, name in NAMES.items():
    if only and only not in f:
        continue
    body = {"display_name": name, "warehouse_id": WAREHOUSE,
            "serialized_dashboard": json.dumps(json.load(open(os.path.join(DASH, f))))}
    if f in ids:
        cmd = ["databricks", "lakeview", "update", ids[f]]
    else:
        cmd = ["databricks", "lakeview", "create"]
        body["parent_path"] = PARENT
    r = subprocess.run(cmd + ["--profile", profile, "--json", json.dumps(body), "-o", "json"],
                       capture_output=True, text=True)
    if r.returncode:
        print("ERROR", f, r.stderr[:800]); ok = False; continue
    ids[f] = json.loads(r.stdout)["dashboard_id"]
    p = subprocess.run(["databricks", "lakeview", "publish", ids[f], "--warehouse-id", WAREHOUSE,
                        "--embed-credentials", "--profile", profile], capture_output=True, text=True)
    print(name, ids[f], "published" if p.returncode == 0 else "PUBLISH ERROR " + p.stderr[:400])
    ok = ok and p.returncode == 0
    json.dump(ids, open(IDS, "w"), indent=2)
sys.exit(0 if ok else 1)
