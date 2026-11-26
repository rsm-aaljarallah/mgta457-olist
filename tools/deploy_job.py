"""Create or update the Olist rebuild job and its alert in Databricks, and optionally run the job.

    python3 tools/deploy_job.py [--run] [--profile chord]

The job (settings in jobs/olist_rebuild.json) runs sql/03_silver.sql to
sql/07_dashboard_views.sql in order on the SQL warehouse, then refreshes the
three published dashboards. 06_checks.sql ends with a gate that fails when any
pipeline check is not PASS, so 07 and the refresh never run on a build that
failed a check. 00 to 02 are not in the job: olist.raw is loaded once. The job
runs every Monday at 6:00 Pacific time and emails its owner when a task fails.

The alert (settings in jobs/alert_sp_rj.json, query in sql/09_alert_sp_rj.sql)
checks every Monday at 7:00 whether Sao Paulo > Rio de Janeiro broke at least
twice the national rate in the latest month, and emails the owner when it did.
The owner's email is read from Databricks at deploy time, so it is not stored
in this repository.

Each deploy first copies the five SQL files into <home>/mgta457-olist/sql in the
workspace, so the job runs the files of this repository as they are on disk.
The job and alert ids are kept in jobs/job_id.json, so a second deploy updates
the same job and alert. --run starts the job, waits for it and prints the
result of every task.

AI use: drafted with Claude (Anthropic), 2026-11-24 (see docs/ai_usage.md).
Revised with Claude, 2026-11-26: the schedule, the failure email and the alert.
"""
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "jobs", "olist_rebuild.json")
ALERT = os.path.join(ROOT, "jobs", "alert_sp_rj.json")
IDS = os.path.join(ROOT, "jobs", "job_id.json")
DASH_IDS = os.path.join(ROOT, "dashboards", "dash_ids.json")
WAREHOUSE = "667de8a20d9687ca"
SQL_FILES = ["03_silver.sql", "04_gold.sql", "05_metric_view.sql", "06_checks.sql", "07_dashboard_views.sql"]
DASHBOARDS = ["olist_1_what_broken_promises_cost.lvdash.json",
              "olist_2_where_promises_break.lvdash.json",
              "olist_3_where_local_sellers_would_help.lvdash.json"]

args = sys.argv[1:]
profile = "chord"
if "--profile" in args:
    i = args.index("--profile"); profile = args[i + 1]; del args[i:i + 2]
run_it = "--run" in args


def cli(*cmd, parse=True):
    r = subprocess.run(["databricks", *cmd, "--profile", profile] + (["-o", "json"] if parse else []),
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit("databricks " + " ".join(cmd[:3]) + " failed: " + (r.stderr or r.stdout)[:800])
    return json.loads(r.stdout) if parse and r.stdout.strip() else None


def fill(text):
    """Put this workspace's values in place of the ${...} names in a settings file."""
    text = text.replace("${FOLDER}", folder).replace("${WAREHOUSE}", WAREHOUSE).replace("${OWNER_EMAIL}", owner)
    for n, f in enumerate(DASHBOARDS, 1):
        text = text.replace("${DASHBOARD_%d}" % n, dash[f])
    return text


owner = cli("current-user", "me")["userName"]
home = "/Users/" + owner
folder = home + "/mgta457-olist/sql"
cli("workspace", "mkdirs", folder, parse=False)
for f in SQL_FILES:
    cli("workspace", "import", f"{folder}/{f}", "--file", os.path.join(ROOT, "sql", f),
        "--format", "RAW", "--overwrite", parse=False)
print(f"copied {len(SQL_FILES)} SQL files to the workspace folder <home>/mgta457-olist/sql")

dash = json.load(open(DASH_IDS))
settings = json.loads(fill(open(SPEC).read()))
ids = json.load(open(IDS)) if os.path.exists(IDS) else {}
if "olist_rebuild" in ids:
    cli("jobs", "reset", "--json", json.dumps({"job_id": int(ids["olist_rebuild"]), "new_settings": settings}),
        parse=False)
    print("updated job", ids["olist_rebuild"])
else:
    ids["olist_rebuild"] = str(cli("jobs", "create", "--json", json.dumps(settings))["job_id"])
    json.dump(ids, open(IDS, "w"), indent=2)
    print("created job", ids["olist_rebuild"])

alert = json.loads(fill(open(ALERT).read()))
alert["query_text"] = open(os.path.join(ROOT, alert.pop("query_file"))).read()
if "alert_sp_rj" in ids:
    fields = "display_name,query_text,warehouse_id,evaluation,schedule,custom_summary,custom_description"
    cli("alerts-v2", "update-alert", ids["alert_sp_rj"], fields, "--json", json.dumps(alert))
    print("updated alert", ids["alert_sp_rj"])
else:
    alert["parent_path"] = home + "/mgta457-olist"
    ids["alert_sp_rj"] = cli("alerts-v2", "create-alert", "--json", json.dumps(alert))["id"]
    json.dump(ids, open(IDS, "w"), indent=2)
    print("created alert", ids["alert_sp_rj"])

if run_it:
    run_id = cli("jobs", "run-now", ids["olist_rebuild"], "--no-wait")["run_id"]
    print("started run", run_id)
    while True:
        run = cli("jobs", "get-run", str(run_id))
        if run["state"]["life_cycle_state"] in ("TERMINATED", "SKIPPED", "INTERNAL_ERROR"):
            break
        time.sleep(20)
    for t in sorted(run.get("tasks", []), key=lambda t: (t.get("start_time") or 0, t["task_key"])):
        st = t.get("state", {})
        print(f"  {t['task_key']:22} {st.get('result_state') or st.get('life_cycle_state')}"
              f"  {(st.get('state_message') or '')[:200]}")
    final = run["state"].get("result_state")
    print("run", run_id, final, run.get("run_page_url", ""))
    sys.exit(0 if final == "SUCCESS" else 1)
