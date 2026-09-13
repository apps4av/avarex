#!/usr/bin/env bash
# Write store/whatsnew/whatsnew-en-US from the latest AvareX Releases entry
# in USER_MANUAL.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANUAL="$ROOT/USER_MANUAL.md"
OUT_DIR="$ROOT/store/whatsnew"
OUT="$OUT_DIR/whatsnew-en-US"

python3 - "$MANUAL" "$OUT" <<'PY'
import pathlib, re, sys

manual_path, out_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = manual_path.read_text(encoding="utf-8")
match = re.search(
    r'^## AvareX Releases\s+'
    r'\*\*([^*]+)\*\*\s+'
    r'((?:- .+\n)+)',
    text,
    re.M,
)
if not match:
    sys.exit("Could not find the latest AvareX Releases entry in USER_MANUAL.md")

items = []
for raw in re.findall(r'^- (.+)$', match.group(2), re.M):
    line = ' '.join(raw.split()).strip()
    if line:
        items.append(line)

footer = "Thank you for flying with AvareX. Send feedback at the Apps4Av forum."
lines = items if items else ["Bug fixes."]
body = "\n".join(lines)
note = f"{body}\n{footer}" if len(body) + 1 + len(footer) <= 500 else body
if len(note) > 500:
    kept, used = [], 0
    for line in lines:
        extra = len(line) if not kept else len(line) + 1
        if used + extra > 500:
            break
        kept.append(line)
        used += extra
    note = "\n".join(kept) if kept else body[:500].rstrip()

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(note.rstrip() + "\n", encoding="utf-8")
print(f"Wrote {out_path} ({len(note)} chars) from AvareX {match.group(1).strip()}")
PY
