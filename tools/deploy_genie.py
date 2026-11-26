"""Create or update the Olist Genie space from genie/ask_olist.json, and optionally test it.

    python3 tools/deploy_genie.py [--eval] [--profile chord]

A Genie space lets a reader ask a question in plain English: Genie writes the
SQL, runs it on the warehouse and shows the answer with the SQL it ran. Genie
only sees what the spec gives it:
  tables            the metric view, the route list view and two small Gold
                    tables, so every rate comes from the metric view or from a
                    rate stored in Gold and checked against it
  instructions      our definitions (judged, broken, route, busy month...)
  examples          questions with the SQL we trust, which Genie reuses
  sample_questions  the questions shown on the space's start page
  benchmarks        test questions with the SQL whose answer Genie must match
The space id is kept in genie/space_id.json, so a second run updates the same
space. --eval asks Genie every benchmark question, compares its answers with
the benchmark SQL, and prints the result of each.

AI use: drafted with Claude (Anthropic), 2026-11-26 (see docs/ai_usage.md).
"""
import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "genie", "ask_olist.json")
IDS = os.path.join(ROOT, "genie", "space_id.json")
WAREHOUSE = "667de8a20d9687ca"

args = sys.argv[1:]
profile = "chord"
if "--profile" in args:
    i = args.index("--profile"); profile = args[i + 1]; del args[i:i + 2]
run_eval = "--eval" in args


def cli(*cmd, body=None):
    """Run the Databricks CLI and return its JSON output. body: a request body, sent as a file."""
    extra = []
    if body is not None:
        f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump(body, f); f.close()
        extra = ["--json", "@" + f.name]
    r = subprocess.run(["databricks", *cmd, *extra, "--profile", profile, "-o", "json"],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit("databricks " + " ".join(cmd[:3]) + " failed: " + (r.stderr or r.stdout)[:1500])
    return json.loads(r.stdout) if r.stdout.strip() else {}


def lines(text):
    """Genie stores text as a list of lines, each but the last ending with its line break."""
    parts = text.split("\n")
    return [p + "\n" for p in parts[:-1]] + [parts[-1]]


def serialized_space(spec):
    """The space in Genie's export format (version 2). Every item needs a 32-character hex id; these
    are numbered in order, so they are sorted and a redeploy gives the same ids."""
    counter = iter(range(1, 1000))
    new_id = lambda: "01f1ea00" + format(next(counter), "024x")
    return {
        "version": 2,
        "config": {"sample_questions": [{"id": new_id(), "question": [q]} for q in spec["sample_questions"]]},
        "data_sources": {"tables": [{"identifier": t} for t in sorted(spec["tables"])]},
        "instructions": {
            "text_instructions": [{"id": new_id(),
                                   "content": lines("\n".join("* " + i for i in spec["instructions"]))}],
            "example_question_sqls": [{"id": new_id(), "question": [e["question"]], "sql": lines(e["sql"])}
                                      for e in spec["examples"]],
        },
        "benchmarks": {"questions": [{"id": new_id(), "question": [b["question"]],
                                      "answer": [{"format": "SQL", "content": lines(b["sql"])}]}
                                     for b in spec["benchmarks"]]},
    }


spec = json.load(open(SPEC))
space = json.dumps(serialized_space(spec))
home = "/Users/" + cli("current-user", "me")["userName"]
ids = json.load(open(IDS)) if os.path.exists(IDS) else {}
if "ask_olist" in ids:
    cli("genie", "update-space", ids["ask_olist"],
        body={"serialized_space": space, "title": spec["title"], "description": spec["description"],
              "warehouse_id": WAREHOUSE})
    print("updated Genie space", ids["ask_olist"])
else:
    created = cli("genie", "create-space",
                  body={"warehouse_id": WAREHOUSE, "serialized_space": space, "title": spec["title"],
                        "description": spec["description"], "parent_path": home + "/mgta457-olist"})
    ids["ask_olist"] = created["space_id"]
    json.dump(ids, open(IDS, "w"), indent=2)
    print("created Genie space", ids["ask_olist"])

if run_eval:
    # Databricks asks Genie each benchmark question, runs both Genie's SQL and the benchmark SQL,
    # and marks the answer GOOD when the results agree, BAD with its reasons when they do not.
    space_id = ids["ask_olist"]
    run_id = cli("genie", "genie-create-eval-run", space_id)["eval_run_id"]
    print("started benchmark run", run_id)
    while True:
        state = cli("genie", "genie-get-eval-run", space_id, run_id)
        if state.get("eval_run_status") != "RUNNING":
            break
        time.sleep(15)
    for r in cli("genie", "genie-list-eval-results", space_id, run_id).get("eval_results", []):
        d = cli("genie", "genie-get-eval-result-details", space_id, run_id, r["result_id"])
        genie_sql = " ".join(a.get("response", "") for a in d.get("actual_response", []) or []).replace("\n", " ")
        print(f"  {d.get('assessment', '?'):4} {r['question']}")
        if d.get("assessment") != "GOOD":
            print("       reasons:", ", ".join(d.get("assessment_reasons") or []), "| Genie ran:", genie_sql[:300])
    print(f"benchmark run {run_id}: {state.get('num_correct')} of {state.get('num_questions')} correct")
