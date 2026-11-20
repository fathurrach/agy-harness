#!/usr/bin/env bash
# Self-contained installer for when you only have the skill directory (tap / URL install):
# copies the sibling agy_*.sh + python helpers onto PATH.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${AGY_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"
cp -f "$HERE"/agy_run.sh "$HERE"/agy_task.sh "$HERE"/agy_verify.sh "$HERE"/agy_usage.sh "$BIN_DIR"/
cp -f "$HERE"/agy_to_outline.py "$HERE"/outline_keton.py "$BIN_DIR"/
chmod +x "$BIN_DIR"/agy_run.sh "$BIN_DIR"/agy_task.sh "$BIN_DIR"/agy_verify.sh "$BIN_DIR"/agy_usage.sh
echo "installed to $BIN_DIR:"
ls -1 "$BIN_DIR" | grep -E '^agy_|^outline_keton' | sed 's/^/  /'
echo
echo "pastikan PATH memuat $BIN_DIR, lalu:"
echo "  agy_task.sh --task smoke --text 'Reply with exactly: PONG' --timeout 120"
echo "prasyarat: agy sudah terpasang dan login (lihat SKILL.md bagian Login)."
