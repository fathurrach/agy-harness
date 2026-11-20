#!/usr/bin/env bash
# agy_run.sh — single entry point to the Antigravity CLI (agy) harness.
#
# Two transports, one contract:
#   AGY_MODE=local  (default) run agy inside this container from /opt/data/bin/agy
#   AGY_MODE=ssh              run agy on host fm as user atnx over ssh (has --sandbox)
#
# Local mode uses an isolated HOME (/opt/data/.agy-home) whose credentials are a COPY of
# atnx's. Never run both modes against the same account for long: two refresh-token
# holders can invalidate each other.
#
# Usage:
#   agy_run.sh --brief <file> --out <dir> [--workdir <dir>] [--model <id>]
#              [--mode plan|auto|accept-edits] [--schema <file>] [--timeout <sec>]
#              [--allow-writes]
#
# Contract:
#   <out>/RESULT.json  agy payload   <out>/META.json  exit/wall/model/tokens
#   <out>/stderr.log   agy stderr    stdout           OK|... or FAIL|...
#   exit code          mirrors agy (0 ok, 124 timeout, 65 empty response, 2 bad args)
set -uo pipefail

# --- portable defaults (override via env) -------------------------------------
# AGY_BIN: agy executable. AGY_HOME: isolated HOME holding its OAuth token.
# AGY_STATE_DIR lives in agy_task/verify/usage; here we only need bin + home.
_resolve_agy() {
  if [ -n "${AGY_BIN:-}" ]; then echo "$AGY_BIN"; return; fi
  if command -v agy >/dev/null 2>&1; then command -v agy; return; fi
  for c in "$HOME/.local/bin/agy" /usr/local/bin/agy; do [ -x "$c" ] && { echo "$c"; return; }; done
  echo "$HOME/.local/bin/agy"
}
AGY_MODE="${AGY_MODE:-local}"     # local = run agy here; ssh = run it on a remote host
AGY_HOME="${AGY_HOME:-$HOME/.agy-home}"
LOCAL_BIN="$(_resolve_agy)"
HOST="${AGY_HOST:-}"
KEY="${AGY_KEY:-$HOME/.ssh/id_ed25519}"

brief=""; out=""; workdir=""; model="gemini-3.8-flash-high"; mode="auto"; schema=""; tmo=900; writes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --brief) brief="${2:?}"; shift 2 ;;
    --out) out="${2:?}"; shift 2 ;;
    --workdir) workdir="${2:?}"; shift 2 ;;
    --model) model="${2:?}"; shift 2 ;;
    --mode) mode="${2:?}"; shift 2 ;;
    --schema) schema="${2:?}"; shift 2 ;;
    --timeout) tmo="${2:?}"; shift 2 ;;
    --allow-writes) writes=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -r "$brief" ] || { echo "FAIL|brief not readable: $brief" >&2; exit 2; }   # -r, not -f: allows <(echo ...)
[ -n "$out" ] || { echo "FAIL|--out required" >&2; exit 2; }
# absolutise before any cd (local mode chdirs into the workdir -> relative paths would break)
brief="$(realpath "$brief")"
out="$(realpath -m "$out")"
[ -n "$workdir" ] && workdir="$(realpath -m "$workdir")"
[ -n "$schema" ] && schema="$(realpath "$schema")"
mkdir -p "$out"

flags="--output-format json --mode $mode --model $model --print-timeout 0"

if [ "$AGY_MODE" = local ]; then
  # container is the sandbox already (unshare is blocked here, so --sandbox cannot run);
  # the flag would only fail loudly, so it is dropped rather than faked.
  [ -x "$LOCAL_BIN" ] || { echo "FAIL|agy not found at $LOCAL_BIN (AGY_MODE=local)" >&2; exit 2; }
  [ -n "$workdir" ] && mkdir -p "$workdir"
  FLAGS=($flags)   # no word-splitting on the JSON schema: use an array locally
  [ -n "$schema" ] && FLAGS+=(--json-schema "$(cat "$schema")")

  # --- agy-auto permission gate (default ON) ---------------------------------
  # PreToolUse hook: read-only + workspace-scoped work is allowed, destructive /
  # credential / system writes are denied. Replaces --dangerously-skip-permissions.
  if [ "${AGY_AUTO:-1}" = 1 ] && [ -x "$AGY_HOME/.gemini/config/plugins/agy-auto/hook.sh" ]; then
    for _ov in agy-1.5.13.toml local-1.5.13.toml; do
      _p="$AGY_HOME/.gemini/config/plugins/agy-auto/policy/$_ov"
      [ -f "$_p" ] && { export AGY_AUTO_POLICY="${AGY_AUTO_POLICY:-$_p}"; break; }
    done
    if [ -z "${AGY_CLASSIFIER_KEY:-}" ]; then
      AGY_CLASSIFIER_KEY=$(grep -m1 -E "^  api_key:" "${AGY_MAIN_CONFIG:-/opt/data/config.yaml}" 2>/dev/null | sed -E 's/.*api_key: *//')
    fi
    export AGY_CLASSIFIER_KEY
  else
    # fallback: no gate installed -> old blunt behaviour
    [ "$writes" = 1 ] && FLAGS+=(--dangerously-skip-permissions)
  fi
  run() { HOME="$AGY_HOME" timeout "$tmo" "$LOCAL_BIN" -p "$(cat "$brief")" "${FLAGS[@]}"; }
  cd "${workdir:-/tmp}" || exit 2
else
  # sandbox only matters once agy can run tools; text-only headless runs auto-deny tools
  if [ "$writes" = 1 ]; then flags="$flags --sandbox --dangerously-skip-permissions"; fi
  [ -n "$workdir" ] && flags="$flags --add-dir $workdir"
  if [ -n "$schema" ]; then
    [ -f "$schema" ] || { echo "FAIL|schema not found: $schema" >&2; exit 2; }
    flags="$flags --json-schema \"\$(echo $(base64 -w0 "$schema") | base64 -d)\""
  fi
  if [ -n "$workdir" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$KEY" "$HOST" "mkdir -p '$workdir'" </dev/null \
      || { echo "FAIL|cannot create remote workdir $workdir" >&2; exit 2; }
  fi
  remote="export PATH=\$HOME/.local/bin:\$PATH; cd ${workdir:-/tmp}; timeout $tmo agy -p \"\$(cat)\" $flags"
  run() { timeout $((tmo + 30)) ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$KEY" "$HOST" "$remote" < "$brief"; }
fi

start=$(date +%s)
run > "$out/RESULT.json" 2> "$out/stderr.log"
rc=$?
wall=$(( $(date +%s) - start ))

# agy reports status SUCCESS with an empty response when a tool was auto-denied headless
if [ "$rc" = 0 ] && grep -q '"response":"",' "$out/RESULT.json"; then rc=65; fi

# mirror artefacts produced in the workdir back to <out>/workdir/
if [ -n "$workdir" ] && [ "$writes" = 1 ]; then
  mkdir -p "$out/workdir"
  if [ "$AGY_MODE" = local ]; then
    tar -C "$workdir" --exclude=.git --exclude=node_modules -cf - . 2>/dev/null | tar -C "$out/workdir" -xf - 2>/dev/null
  else
    ssh -o BatchMode=yes -i "$KEY" "$HOST" "tar -C '$workdir' --exclude=.git --exclude=node_modules -cf - . 2>/dev/null" \
      | tar -C "$out/workdir" -xf - 2>/dev/null
  fi
fi

tokens=$(grep -o '"total_tokens":[0-9]*' "$out/RESULT.json" | head -1 | cut -d: -f2)
printf '{"exit":%s,"wall_seconds":%s,"transport":"%s","model":"%s","mode":"%s","timeout":%s,"total_tokens":%s,"brief_sha256":"%s"}\n' \
  "$rc" "$wall" "$AGY_MODE" "$model" "$mode" "$tmo" "${tokens:-0}" \
  "$(sha256sum "$brief" | cut -d' ' -f1)" > "$out/META.json"

if [ "$rc" = 0 ]; then
  echo "OK|$AGY_MODE|$out/RESULT.json|${tokens:-?} tokens|${wall}s"
else
  echo "FAIL|$AGY_MODE|exit=$rc|$out"
fi
exit "$rc"
