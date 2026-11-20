#!/usr/bin/env bash
# agy-harness installer — puts the scripts on PATH and the skill where Hermes finds it.
# Nothing is downloaded; requires the Antigravity CLI (agy) to already exist.
#
#   ./install.sh              # install for current user
#   AGY_BIN_DIR=~/.local/bin  # where scripts go
#   AGY_SKILL_DIR=...         # where SKILL.md + templates go
#   AGY_STATE_DIR=...         # task dirs + ledger (default: ~/.local/state/agy)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$SRC/skills/agy-harness"
BIN_DIR="${AGY_BIN_DIR:-$HOME/.local/bin}"
SKILL_DIR="${AGY_SKILL_DIR:-$HOME/.hermes/skills/devops/agy-harness}"
STATE_DIR="${AGY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agy}"

say() { printf '%s\n' "$*"; }

say "== agy-harness installer =="
say "  scripts -> $BIN_DIR"
say "  skill   -> $SKILL_DIR"
say "  state   -> $STATE_DIR"

mkdir -p "$BIN_DIR" "$SKILL_DIR/templates" "$STATE_DIR"
cp -f "$SKILL_SRC"/bin/agy_run.sh "$SKILL_SRC"/bin/agy_task.sh \
      "$SKILL_SRC"/bin/agy_verify.sh "$SKILL_SRC"/bin/agy_usage.sh "$BIN_DIR"/
cp -f "$SKILL_SRC"/bin/agy_to_outline.py "$SKILL_SRC"/bin/outline_keton.py "$BIN_DIR"/
chmod +x "$BIN_DIR"/agy_run.sh "$BIN_DIR"/agy_task.sh "$BIN_DIR"/agy_verify.sh "$BIN_DIR"/agy_usage.sh
cp -f "$SKILL_SRC/SKILL.md" "$SKILL_DIR/SKILL.md"
cp -f "$SKILL_SRC"/templates/*.md "$SKILL_DIR/templates/"
say "  files copied."

# --- locate agy ---------------------------------------------------------------
AGY_FOUND=""
if [ -n "${AGY_BIN:-}" ] && [ -x "${AGY_BIN}" ]; then AGY_FOUND="$AGY_BIN"
elif command -v agy >/dev/null 2>&1; then AGY_FOUND="$(command -v agy)"
elif [ -x "$HOME/.local/bin/agy" ]; then AGY_FOUND="$HOME/.local/bin/agy"
fi

if [ -z "$AGY_FOUND" ]; then
  say ""
  say "!! 'agy' (Antigravity CLI) tidak ditemukan."
  say "   Skill ini TIDAK mem-bundle agy. Pasang dulu dari akun Antigravity kamu, misal:"
  say "     ~/.local/bin/agy --version"
  say "   Lalu ulangi ./install.sh, atau set AGY_BIN=/path/to/agy."
else
  say "  agy ditemukan: $AGY_FOUND ($("$AGY_FOUND" --version 2>/dev/null | head -1))"
fi

# --- PATH sanity --------------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) say ""
     say "!! $BIN_DIR belum ada di PATH. Tambahkan ke shell profile:"
     say "     export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

# --- smoke test ---------------------------------------------------------------
if [ -n "$AGY_FOUND" ]; then
  say ""
  say "== smoke test (butuh login agy) =="
  if AGY_BIN="$AGY_FOUND" "$BIN_DIR/agy_task.sh" --task install-smoke \
       --text "Reply with exactly: PONG" --timeout 120 2>&1 | tail -3; then
    say ""
    say "OK. Pemakaian:"
    say "  agy_task.sh --task <slug> --template analysis --set 'target=<path>' \\"
    say "    --set 'questions=<pertanyaan>' --allow-writes --timeout 420 --print-response"
  else
    say ""
    say "Smoke test gagal — biasanya belum login. Jalankan (di terminal, bukan lewat chat):"
    say "  agy -p 'Reply with exactly: PONG' --output-format json"
    say "Ikuti URL + tempel kode OAuth (jendela 60 detik), lalu ulangi installer ini."
  fi
fi

say ""
say "Selesai. Dokumentasi kontrak: $SRC/docs/CONTRACT.md"
