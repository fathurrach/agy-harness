#!/usr/bin/env bash
# agy_usage.sh — cost/latency summary from the agy ledger.
#   agy_usage.sh            # total + per task
#   agy_usage.sh --days 7   # only last N days
#   agy_usage.sh --tail 5   # last N runs
set -uo pipefail
STATE="${AGY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agy}"
LEDGER="$STATE/ledger.jsonl"
[ -f "$LEDGER" ] || { echo "belum ada ledger ($LEDGER)"; exit 0; }

days=9999; tailn=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="${2:?}"; shift 2 ;;
    --tail) tailn="${2:?}"; shift 2 ;;
    *) echo "usage: $0 [--days N] [--tail N]" >&2; exit 2 ;;
  esac
done

python3 - "$LEDGER" "$days" "$tailn" <<'PY'
import json, sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

path, days, tailn = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
cutoff = datetime.now(timezone.utc) - timedelta(days=days)
rows = []
for line in open(path):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
        ts = datetime.fromisoformat(r["ts"])
    except Exception:
        continue
    if ts >= cutoff:
        rows.append(r)
rows.sort(key=lambda r: r["ts"])

if tailn:
    for r in rows[-tailn:]:
        print(f"{r['ts'][:19]}  {r['task']:<22} exit={r['exit']:<3} {r['tokens']:>7} tok {r['wall']:>4}s")
    sys.exit(0)

if not rows:
    print("belum ada run dalam rentang itu")
    sys.exit(0)

tot_tok = sum(r["tokens"] for r in rows)
tot_wall = sum(r["wall"] for r in rows)
ok = sum(1 for r in rows if r["exit"] == 0)
print(f"RUNS {len(rows)}  OK {ok}  FAIL {len(rows)-ok}")
print(f"TOTAL {tot_tok} token  {tot_wall}s ({tot_wall/60:.1f} menit)  rata2 {tot_tok//len(rows)} token/run")

agg = defaultdict(lambda: [0, 0, 0])
for r in rows:
    a = agg[r["task"]]
    a[0] += 1; a[1] += r["tokens"]; a[2] = max(a[2], r["wall"])
print("\nPER TASK")
for task, (n, tok, wall) in sorted(agg.items(), key=lambda kv: -kv[1][1]):
    print(f"  {task:<24} {n:>3}x  {tok:>8} tok  max {wall}s")
PY
