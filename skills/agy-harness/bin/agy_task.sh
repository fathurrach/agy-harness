#!/usr/bin/env bash
# agy_task.sh — opinionated one-shot task runner on top of agy_run.sh.
# Handles dirs, brief rendering, validation, artifact listing, and cost ledger.
#
# Usage:
#   agy_task.sh --task <name> (--brief <file> | --text "<brief>" | --template <name> [--set k=v ...])
#              [--allow-writes] [--workdir <dir>] [--timeout <sec>] [--model <id>]
#              [--expect-json] [--print-response]
#
# Exit: 0 ok · 65 empty response · 124 timeout · 2 usage · others from agy
# Ledger: /opt/data/tmp/agy/ledger.jsonl (one JSON per run)
set -uo pipefail

# --- optional user config (KEY=VALUE lines, sourced before defaults) ----------
CFG="${AGY_CONFIG_FILE:-$HOME/.config/agy-harness/env}"
if [ -r "$CFG" ]; then set -a; . "$CFG"; set +a; fi

# --- portable layout (env-overridable) ----------------------------------------
# AGY_BIN_DIR: where agy_run.sh / agy_verify.sh / agy_to_outline.py live
# AGY_STATE_DIR: task dirs + ledger (default XDG state)
# AGY_SKILL_DIR: installed skill dir (for templates)
BIN_DIR="${AGY_BIN_DIR:-$(cd "$(dirname "$0")" && pwd)}"
S="$BIN_DIR/agy_run.sh"
ROOT="${AGY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agy}"
_resolve_tpl() {
  if [ -n "${AGY_SKILL_DIR:-}" ] && [ -d "$AGY_SKILL_DIR/templates" ]; then echo "$AGY_SKILL_DIR/templates"; return; fi
  for c in "$HOME/.hermes/skills/devops/agy-harness/templates" \
           "$HOME/.local/share/agy-harness/templates" \
           "$BIN_DIR/../skills/agy-harness/templates"; do
    [ -d "$c" ] && { echo "$c"; return; }
  done
  echo "$BIN_DIR/../skills/agy-harness/templates"
}
TPL_DIR="$(_resolve_tpl)"
task=""; brief=""; text=""; template=""; allow_writes=0; wd=""; tmo=300
model="gemini-3.8-flash-high"; expect_json=0; show_resp=0; sets=()
outline_title=""; outline_parent=""; dry_run=0; auto_remediate=1
agent=""; activity=0

while [ $# -gt 0 ]; do
  case "$1" in
    --task) task="${2:?}"; shift 2 ;;
    --brief) brief="${2:?}"; shift 2 ;;
    --text) text="${2:?}"; shift 2 ;;
    --template) template="${2:?}"; shift 2 ;;
    --set) sets+=("${2:?}"); shift 2 ;;
    --allow-writes) allow_writes=1; shift ;;
    --workdir) wd="${2:?}"; shift 2 ;;
    --timeout) tmo="${2:?}"; shift 2 ;;
    --model) model="${2:?}"; shift 2 ;;
    --expect-json) expect_json=1; shift ;;
    --print-response) show_resp=1; shift ;;
    --outline) outline_title="${2:?}"; shift 2 ;;
    --outline-parent) outline_parent="${2:?}"; shift 2 ;;
    --agent) agent="${2:?}"; shift 2 ;;
    --activity) activity=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --no-auto-retry) auto_remediate=0; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$task" ] || { echo "FAIL|--task required" >&2; exit 2; }
case "$agent" in ""|pilot|coder|professor) ;; *) echo "FAIL|--agent harus pilot|coder|professor" >&2; exit 2 ;; esac
if [ "$activity" = 1 ] && [ -z "$agent" ]; then echo "FAIL|--activity butuh --agent" >&2; exit 2; fi
case "$task" in */*|*..*) echo "FAIL|task name must be a simple slug" >&2; exit 2 ;; esac

d="$ROOT/$task"
mkdir -p "$d" "$d/wd"
bf="$d/brief.md"

if [ -n "$text" ]; then
  printf '%s\n' "$text" > "$bf"
elif [ -n "$brief" ]; then
  [ -r "$brief" ] || { echo "FAIL|brief not readable: $brief" >&2; exit 2; }
  cp "$brief" "$bf"
elif [ -n "$template" ]; then
  src="$TPL_DIR/$template.md"
  [ -r "$src" ] || { echo "FAIL|template not found: $src" >&2; exit 2; }
  cp "$src" "$bf"
  for kv in "${sets[@]:-}"; do
    [ -n "$kv" ] || continue
    k="${kv%%=*}"; v="${kv#*=}"
    KEY="$k" VAL="$v" python3 - "$bf" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read().replace("{{" + os.environ["KEY"] + "}}", os.environ["VAL"])
open(p, "w").write(s)
PY
  done
else
  echo "FAIL|need --brief, --text, or --template" >&2; exit 2
fi

# refuse leftover template placeholders: they silently become part of the prompt
if grep -q '{{[a-zA-Z0-9_]*}}' "$bf"; then
  echo "FAIL|unfilled template placeholder: $(grep -o '{{[a-zA-Z0-9_]*}}' "$bf" | sort -u | tr '\n' ' ')" >&2
  exit 2
fi

out="$d/out"

# --dry-run: tampilkan brief final + kelas biaya, tanpa memanggil agy (0 token)
if [ "$dry_run" = 1 ]; then
  bytes=$(wc -c < "$bf")
  words=$(wc -w < "$bf")
  if [ "$bytes" -lt 300 ]; then tier="murah (~10k token)"; elif [ "$bytes" -lt 1500 ]; then tier="sedang (~12-20k)"; else tier="berat (~25k+ / banyak iterasi tool)"; fi
  echo "DRYRUN|task=$task|brief=$bf|${bytes}B/${words} kata|kelas=$tier|model=$model|writes=$allow_writes"
  echo "--- brief ---"
  cat "$bf"
  echo "--- end ---"
  exit 0
fi

rm -rf "$out"
run_once() {  # $1 = 1 kalau pakai writes
  local a=(--brief "$bf" --out "$out" --timeout "$tmo" --model "$model")
  if [ "$1" = 1 ]; then a+=(--allow-writes --workdir "${wd:-$d/wd}")
  elif [ -n "$wd" ]; then a+=(--workdir "$wd"); fi
  "$S" "${a[@]}"
}

line=$(run_once "$allow_writes")
rc=$?
retry=""

# auto-remediasi satu kali: exit 65 hampir selalu berarti tool butuh --allow-writes
if [ "$rc" = 65 ] && [ "$allow_writes" = 0 ] && [ "$auto_remediate" = 1 ]; then
  echo "RETRY|exit=65 (tool auto-denied) -> ulang sekali dengan --allow-writes"
  rm -rf "$out"
  line=$(run_once 1)
  rc=$?
  retry="writes"
fi
echo "$line"

# --- validate agy's own payload, not just the exit code ---
status=$(python3 - "$out/RESULT.json" <<'PY' 2>/dev/null || echo "noparse"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    r = (d.get("response") or "").strip()
    print("ok" if r else "empty")
except Exception:
    print("noparse")
PY
)

json_ok="na"
if [ "$expect_json" = 1 ] && [ "$rc" = 0 ]; then
  json_ok=$(python3 - "$out/RESULT.json" <<'PY' 2>/dev/null || echo "false"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    json.loads(d.get("response") or "")
    print("true")
except Exception:
    print("false")
PY
)
  [ "$json_ok" = "true" ] || rc=66
fi

arts=$(find "$out/workdir" -type f 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//')
# read-only runs produce no workdir files; the wrapper payload is still the verifiable handle
[ -n "$arts" ] || arts="$out/RESULT.json"
tokens=$(python3 -c "import json;print(json.load(open('$out/META.json'))['total_tokens'])" 2>/dev/null || echo 0)
wall=$(python3 -c "import json;print(json.load(open('$out/META.json'))['wall_seconds'])" 2>/dev/null || echo 0)

printf '{"ts":"%s","task":"%s","agent":"%s","exit":%s,"status":"%s","json":"%s","tokens":%s,"wall":%s,"model":"%s","out":"%s","retry":"%s","artifacts":"%s"}\n' \
  "$(date -Is)" "$task" "$agent" "$rc" "$status" "$json_ok" "$tokens" "$wall" "$model" "$out" "$retry" "$arts" \
  >> "$ROOT/ledger.jsonl"

# pemeriksa deterministik: exit 0 saja tidak cukup, artefak harus benar-benar ada
if [ "$rc" = 0 ]; then
  v=$(bash "$BIN_DIR/agy_verify.sh" --task "$task" 2>/dev/null | tail -1)
  echo "$v"
  case "$v" in VERDICT\|PASS*) ;; *) rc=70 ;; esac
fi

echo "EXIT|$rc|status=$status|json=$json_ok|tokens=$tokens|wall=${wall}s${retry:+|retry=$retry}"
[ -n "$arts" ] && echo "ARTIFACTS|$arts"

# publish to Outline only on a clean run, so garbage never lands in the wiki
if [ -n "$outline_title" ] && [ "$rc" = 0 ]; then
  oargs=(--task "$task" --title "$outline_title")
  [ -n "$outline_parent" ] && oargs+=(--parent "$outline_parent")
  python3 "$BIN_DIR/agy_to_outline.py" "${oargs[@]}" || echo "OUTLINE|FAIL"
fi

# Activity Logger: satu dokumen per run, di cabang agent masing-masing
if [ "$activity" = 1 ] && [ "$rc" = 0 ]; then
  python3 "$BIN_DIR/agy_activity.py" --agent "$agent" --publish --task "$task" || echo "ACTIVITY|FAIL"
fi
if [ "$show_resp" = 1 ]; then
  python3 -c "import json;print(json.load(open('$out/RESULT.json')).get('response','').strip())" 2>/dev/null
fi
exit "$rc"
