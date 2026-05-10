#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKLIST_FILE="$ROOT_DIR/SMOKE_TEST_CHECKLIST.md"

if [[ ! -f "$CHECKLIST_FILE" ]]; then
  echo "Smoke checklist not found: $CHECKLIST_FILE" >&2
  exit 1
fi

echo "========================================"
echo " Fireball Native Smoke Test (10-Minute) "
echo "========================================"
echo

# Print markdown as plain terminal text.
# Keep checkbox lines and headings, drop markdown separators.
awk '
  /^---$/ { next }
  /^# /   { print; print ""; next }
  /^## /  { print; next }
  /^\- \[ \]/ { print; next }
  /^\- / { print; next }
  /^[[:space:]]*$/ { print; next }
  { print }
' "$CHECKLIST_FILE"

echo
echo "Tip: run this before/after major changes."
