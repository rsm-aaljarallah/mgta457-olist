"""Run a .sql file on the Databricks warehouse, one statement at a time, and print results.

    python3 tools/run_dbx.py sql/03_silver.sql sql/04_gold.sql ...

It sends each statement through the Databricks CLI (`databricks api`, profile "chord")
to the SQL warehouse below, and prints the rows of every SELECT. It stops at the
first statement that fails. A statement ends at a line whose code ends in ";", so
no SQL string in this project may end a line with ";".

Copied unchanged from the Chord project's helper on 2026-11-24, so the scripts in
this repository run from a fresh clone (see docs/ai_usage.md). The warehouse id and
the CLI profile name are specific to our workspace.
"""
import sys, json, subprocess, time, re
WH = "667de8a20d9687ca"; PROFILE = "chord"

def api(method, path, body=None):
    cmd = ["databricks", "api", method, path, "--profile", PROFILE]
    if body is not None: cmd += ["--json", json.dumps(body)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0: raise RuntimeError(r.stderr.strip() or r.stdout.strip())
    return json.loads(r.stdout)

def split(sql):
    out, cur, in_yaml = [], [], False
    for line in sql.splitlines():
        cur.append(line)
        if line.count("$$") % 2 == 1: in_yaml = not in_yaml
        code = line.split("--")[0].rstrip() if not in_yaml else line.rstrip()
        if code.endswith(";") and not in_yaml:
            out.append("\n".join(cur)); cur = []
    if any(l.strip() and not l.strip().startswith("--") for l in cur): out.append("\n".join(cur))
    return out

def first_code_line(st):
    for l in st.splitlines():
        if l.strip() and not l.strip().startswith("--"): return l.strip()[:90]
    return ""

def run(st):
    r = api("post", "/api/2.0/sql/statements", {"warehouse_id": WH, "statement": st.rstrip().rstrip(";"), "wait_timeout": "50s"})
    while r["status"]["state"] in ("PENDING", "RUNNING"):
        time.sleep(3); r = api("get", f"/api/2.0/sql/statements/{r['statement_id']}")
    return r

def show(r, limit=60):
    cols = [c["name"] for c in r.get("manifest", {}).get("schema", {}).get("columns", [])]
    rows = r.get("result", {}).get("data_array", []) or []
    if not cols: return
    w = [min(60, max(len(str(c)), *(len(str(x[i])) for x in rows[:limit]))) if rows else len(c) for i, c in enumerate(cols)]
    print("   " + " | ".join(str(c)[:60].ljust(w[i]) for i, c in enumerate(cols)))
    for x in rows[:limit]: print("   " + " | ".join(str(v)[:60].ljust(w[i]) for i, v in enumerate(x)))
    if len(rows) > limit: print(f"   ... {len(rows)} rows")

if __name__ == "__main__":
    ok = True
    for path in sys.argv[1:]:
        print(f"=== {path.split('/')[-1]}")
        for i, st in enumerate(split(open(path).read()), 1):
            r = run(st); state = r["status"]["state"]
            print(f"[{i}] {state}: {first_code_line(st)}")
            if state != "SUCCEEDED":
                print("   ERROR:", r["status"].get("error", {}).get("message", "")[:1500]); ok = False; break
            if re.match(r"\s*(SELECT|SHOW|DESCRIBE|WITH)", first_code_line(st), re.I): show(r)
        if not ok: break
    sys.exit(0 if ok else 1)
