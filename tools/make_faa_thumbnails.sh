#!/usr/bin/env bash
# Renders page 1 of every PDF inside the handbook and ACS bundles of data/faa_docs.py
# (FAA_HANDBOOKS, FAA_HANDBOOKS_SPECIALTY, FAA_ACS) to a small PNG in assets/pdf_thumbnails/. The Documents screen shows these
# instead of the generic PDF icon. A thumbnail is named after its PDF, so
# "Handbooks/Airplane_Flying_Handbook.pdf" becomes "Airplane_Flying_Handbook.png".
#
# Needs: pdftoppm (poppler, `brew install poppler`) and unzip.
#
# Usage: tools/make_faa_thumbnails.sh [folder holding the zips] [width in px]
#   defaults: ../data, 360
set -euo pipefail

ZIP_DIR="${1:-$(cd "$(dirname "$0")/../../data" && pwd)}"
WIDTH="${2:-360}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/pdf_thumbnails"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v pdftoppm >/dev/null || { echo "pdftoppm not found (brew install poppler)"; exit 1; }

mkdir -p "$OUT"
rm -f "$OUT"/*.png

count=0
for bundle in FAA_HANDBOOKS FAA_HANDBOOKS_SPECIALTY FAA_ACS; do
  zip="$ZIP_DIR/$bundle.zip"
  echo "== $(basename "$zip")"
  rm -rf "$TMP/x" && mkdir "$TMP/x"
  unzip -q -o "$zip" '*.pdf' -d "$TMP/x"
  while IFS= read -r -d '' pdf; do
    name="$(basename "${pdf%.*}")"
    if [ -e "$OUT/$name.png" ]; then
      echo "duplicate name, skipped: $name" >&2
      continue
    fi
    # first page only, scaled to WIDTH px wide, 8-bit palette-free PNG
    pdftoppm -f 1 -l 1 -png -singlefile -scale-to-x "$WIDTH" -scale-to-y -1 "$pdf" "$OUT/$name"
    count=$((count + 1))
  done < <(find "$TMP/x" -iname '*.pdf' -print0)
done

echo "wrote $count thumbnails to $OUT"
du -sh "$OUT"
