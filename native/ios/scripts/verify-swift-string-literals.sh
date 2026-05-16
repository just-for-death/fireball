#!/usr/bin/env bash
# Fail if app/widget Swift sources contain invalid escape sequences in normal string literals.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
valid_after_bs = set('"\'(\\nrt0uU')
scan_roots = [root / "FireballNative", root / "FireballWidgets"]

def scan(text):
    issues = []
    i = 0
    while i < len(text):
        if text[i] == "#" and i + 1 < len(text) and text[i + 1] in '"\'':
            q = text[i + 1]
            end = text.find(q + "#", i + 2)
            if end != -1:
                i = end + 2
                continue
        if text[i] == '"':
            j = i + 1
            while j < len(text):
                c = text[j]
                if c == "\\":
                    nxt = text[j + 1] if j + 1 < len(text) else ""
                    if nxt == "(":
                        j += 2
                        depth = 1
                        while j < len(text) and depth:
                            if text[j] == "(":
                                depth += 1
                            elif text[j] == ")":
                                depth -= 1
                            j += 1
                        continue
                    if nxt not in valid_after_bs:
                        issues.append(text.count("\n", 0, j) + 1)
                    j += 2
                    continue
                if c == '"':
                    break
                j += 1
            i = j + 1
            continue
        i += 1
    return issues

failed = False
for base in scan_roots:
    for path in base.rglob("*.swift"):
        bad = scan(path.read_text(encoding="utf-8"))
        if bad:
            failed = True
            lines = ", ".join(map(str, bad))
            print(f"error: {path}: invalid escape sequence at line(s) {lines}", file=sys.stderr)

if failed:
    sys.exit(1)
print("OK: Swift string literals (app + widgets)")
PY
