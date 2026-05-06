#!/usr/bin/env bash
# Regenerate assets/docs/USER_MANUAL.pdf from USER_MANUAL.md.
#
# Requirements (macOS):
#   brew install pandoc poppler
#   /Applications/Google Chrome.app    (used in headless mode)
#
# Usage (from project root):
#   ./.cursor/scripts/regenerate_user_manual_pdf.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

if ! command -v pandoc >/dev/null 2>&1; then
  echo "pandoc not found. Install with: brew install pandoc" >&2
  exit 1
fi

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "Google Chrome not found at $CHROME" >&2
  exit 1
fi

CSS_FILE=$(mktemp -t avarex-manual-css.XXXXXX)
HTML_FILE=$(mktemp -t avarex-manual.XXXXXX)
trap 'rm -f "$CSS_FILE" "$HTML_FILE" "${HTML_FILE}.html"' EXIT

cat > "$CSS_FILE" <<'EOF'
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  max-width: 900px;
  margin: 1.5em auto;
  padding: 0 1.5em;
  line-height: 1.55;
  color: #222;
}
h1, h2, h3, h4 { color: #1a237e; }
h1 { border-bottom: 2px solid #1a237e; padding-bottom: 0.3em; }
h2 { border-bottom: 1px solid #c5cae9; padding-bottom: 0.2em; margin-top: 2em; }
code { background: #f6f8fa; padding: 0.1em 0.4em; border-radius: 3px; font-size: 0.92em; }
pre code { display: block; padding: 0.7em; }
table { border-collapse: collapse; margin: 1em 0; }
th, td { border: 1px solid #d1d5da; padding: 0.45em 0.8em; }
th { background: #f6f8fa; }
img {
  max-width: 90%;
  display: block;
  margin: 0.8em auto;
  border: 1px solid #d1d5da;
  border-radius: 6px;
  box-shadow: 0 2px 6px rgba(0,0,0,0.08);
  page-break-inside: avoid;
}
blockquote {
  border-left: 4px solid #c5cae9;
  margin: 1em 0;
  padding: 0.4em 1em;
  color: #444;
  background: #f5f7ff;
}
hr { border: none; border-top: 1px solid #d1d5da; margin: 2em 0; }
EOF

mv "$HTML_FILE" "${HTML_FILE}.html"
HTML_FILE="${HTML_FILE}.html"

echo "[1/2] Pandoc: USER_MANUAL.md -> HTML"
pandoc USER_MANUAL.md \
  -f gfm \
  -t html5 \
  --embed-resources --standalone \
  --css="$CSS_FILE" \
  -o "$HTML_FILE"

echo "[2/2] Chrome headless: HTML -> assets/docs/USER_MANUAL.pdf"
"$CHROME" \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --no-pdf-header-footer \
  --print-to-pdf=assets/docs/USER_MANUAL.pdf \
  --print-to-pdf-no-header \
  "file://$HTML_FILE" 2>/dev/null

echo "Done. assets/docs/USER_MANUAL.pdf:"
ls -la assets/docs/USER_MANUAL.pdf
