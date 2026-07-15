#!/usr/bin/env bash
# modelfit -- render.sh <html_in> <png_out>
# Render a self-contained HTML file to a PNG screenshot.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"

usage() {
  echo "usage: render.sh <html_in> <png_out>" >&2
  exit 1
}

IN="${1:-}"; OUT="${2:-}"
{ [ -n "$IN" ] && [ -n "$OUT" ]; } || usage
[ -f "$IN" ] || die "no html at $IN"

if render_html "$IN" "$OUT"; then
  echo "rendered $IN -> $OUT"
else
  die "render failed for $IN"
fi
