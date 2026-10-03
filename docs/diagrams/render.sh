#!/usr/bin/env bash
# Renders every docs/diagrams/*.d2 to an SVG next to it. Each source sets its own
# style (sketch, light + dark theme in one file, layout engine) in `vars.d2-config`.
# Usage: docs/diagrams/render.sh          render all
#        docs/diagrams/render.sh --check  fail if an SVG is out of date (for CI)
set -euo pipefail
cd "$(dirname "$0")"

status=0
for src in *.d2; do
  [[ "$src" == palette.d2 ]] && continue # shared classes, imported by the others
  svg="${src%.d2}.svg"
  if [[ "${1:-}" == "--check" ]]; then
    tmp="$(mktemp -d)/$svg"
    d2 "$src" "$tmp" 2>/dev/null
    cmp -s "$tmp" "$svg" || { echo "out of date: docs/diagrams/$svg (run docs/diagrams/render.sh)"; status=1; }
  else
    d2 "$src" "$svg" 2>/dev/null
    echo "rendered docs/diagrams/$svg"
  fi
done
exit $status
