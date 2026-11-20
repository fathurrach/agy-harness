#!/usr/bin/env bash
# agy_verify.sh — deterministic PASS/FAIL for one agy task. Zero LLM tokens.
#
#   agy_verify.sh --task <slug> [--json]
#
# Checks: task dir, brief, RESULT.json payload (status SUCCESS + non-empty response),
# META.json (exit 0), produced artifacts non-empty, ledger line with exit 0.
# Exit: 0 pass · 1 fail · 2 usage
set -uo pipefail

ROOT="${AGY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agy}"
LEDGER="$ROOT/ledger.jsonl"
task=""; json=0; expect_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task) task="${2:?}"; shift 2 ;;
    --json) json=1; shift ;;
    --expect-file) expect_file="${2:?}"; shift 2 ;;
    *) echo "usage: $0 --task <slug> [--json] [--expect-file <relpath>]" >&2; exit 2 ;;
  esac
done
[ -n "$task" ] || { echo "usage: $0 --task <slug> [--json] [--expect-file <relpath>]" >&2; exit 2; }

d="$ROOT/$task"; out="$d/out"
checks=(); ok=1
add() { checks+=("$1|$2"); case "$2" in FAIL*) ok=0 ;; esac; }

if [ -d "$d" ]; then add task-dir PASS; else add task-dir "FAIL|$d tidak ada"; fi

if [ -d "$d" ]; then
  # brief
  if [ -s "$d/brief.md" ]; then add "brief" PASS; else add brief "FAIL|kosong/tidak ada"; fi

  # agy payload
  verdict=$(python3 - "$out/RESULT.json" <<'PY' 2>/dev/null || echo "FAIL|RESULT.json tidak terbaca"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"FAIL|RESULT.json tidak valid: {e}"); raise SystemExit
st = d.get("status"); resp = (d.get("response") or "").strip()
if st != "SUCCESS": print(f"FAIL|status={st} err={d.get('error')}")
elif not resp:      print("FAIL|response kosong (tool di-denied?)")
else:               print("PASS")
PY
)
  add "payload" "$verdict"

  # wrapper metadata
  mverdict=$(python3 - "$out/META.json" <<'PY' 2>/dev/null || echo "FAIL|META.json tidak terbaca"
import json, sys
try:
    m = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"FAIL|META.json tidak valid: {e}"); raise SystemExit
print("PASS" if m.get("exit") == 0 else f"FAIL|exit={m.get('exit')}")
PY
)
  add "meta" "$mverdict"

  # produced artifacts must be non-empty
  files=0; empty=0
  if [ -d "$out/workdir" ]; then
    files=$(find "$out/workdir" -type f | wc -l)
    empty=$(find "$out/workdir" -type f -size 0 | wc -l)
  fi
  if [ "$files" -gt 0 ] && [ "$empty" -eq 0 ]; then add artifacts "PASS|$files file"
  elif [ "$files" -gt 0 ]; then add artifacts "FAIL|$empty dari $files file kosong"
  else add artifacts "PASS|tanpa file (read-only, RESULT.json jadi handle)"; fi

  # eksplisit: pemanggil bisa mewajibkan satu file hasil
  if [ -n "$expect_file" ]; then
    if [ -s "$out/workdir/$expect_file" ]; then add "file:$expect_file" PASS
    else add "file:$expect_file" "FAIL|tidak ada atau kosong"; fi
  fi

  # ledger
  if [ -f "$LEDGER" ] && python3 - "$LEDGER" "$task" <<'PY'
import json, sys
ok = False
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try: r = json.loads(line)
    except Exception: continue
    if r.get("task") == sys.argv[2]: ok = (r.get("exit") == 0)
sys.exit(0 if ok else 1)
PY
  then add "ledger" PASS
  else add "ledger|FAIL|tidak ada baris exit=0 untuk task ini"; fi
fi

if [ "$json" = 1 ]; then
  python3 - "$ok" "${checks[@]}" <<'PY'
import json, sys
ok = sys.argv[1] == "1"
out = []
for c in sys.argv[2:]:
    parts = c.split("|")
    out.append({"check": parts[0], "result": parts[1], "detail": parts[2] if len(parts) > 2 else ""})
print(json.dumps({"verdict": "PASS" if ok else "FAIL", "checks": out}, indent=2))
PY
else
  for c in "${checks[@]}"; do
    IFS='|' read -r name res detail <<< "$c"
    printf '  %-4s %-10s %s\n' "$res" "$name" "$detail"
  done
  echo "VERDICT|$([ "$ok" = 1 ] && echo PASS || echo FAIL)|$task"
fi

[ "$ok" = 1 ] || exit 1
