#!/usr/bin/env bash
# modelfit -- selftest.sh
# Prove the plumbing with ZERO API spend: scripts parse, example config is valid
# JSON, every probe has both sections, and report.sh renders from sample data.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok(){ echo "  ok   $1"; }
no(){ echo "  FAIL $1"; fail=1; }

echo "== modelfit selftest =="
if command -v jq >/dev/null; then ok "jq present"; else no "jq missing"; fi
if command -v curl >/dev/null; then ok "curl present"; else no "curl missing"; fi

for s in bin/run.sh bin/judge.sh bin/report.sh bin/render.sh bin/selftest.sh bin/scan-secrets.sh; do
  if bash -n "$ROOT/$s"; then ok "syntax $s"; else no "syntax $s"; fi
done
for s in bin/lib/common.sh bin/doctor.sh bin/modelfit; do
  if bash -n "$ROOT/$s"; then ok "syntax $s"; else no "syntax $s"; fi
done

if jq -e . "$ROOT/config/models.example.json" >/dev/null 2>&1; then ok "example config is valid JSON"; else no "example config invalid JSON"; fi
if jq -e '.judge and (.models|type=="array")' "$ROOT/config/models.example.json" >/dev/null 2>&1; then
  ok "example config has .judge and .models[]"
else
  no "example config missing .judge/.models"
fi

shopt -s nullglob
for p in "$ROOT"/probes/*.md; do
  name="$(basename "$p")"
  has_p="$(awk '/^# *PROMPT[[:space:]]*$/{print "y";exit}' "$p")"
  has_r="$(awk '/^# *RUBRIC[[:space:]]*$/{print "y";exit}' "$p")"
  if [ "$has_p" = y ] && [ "$has_r" = y ]; then ok "probe $name has PROMPT+RUBRIC"; else no "probe $name missing a section"; fi
done

# Design/screenshot probe wiring.
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"
if [ -f "$ROOT/probes/example-design.md" ]; then
  if [ "$(scoring_for_probe "$ROOT/probes/example-design.md")" = "screenshot" ]; then
    ok "example-design.md is scoring: screenshot"
  else
    no "example-design.md is not scoring: screenshot"
  fi
else
  no "probes/example-design.md missing"
fi
# render_html must fail clearly with no MODELFIT_RENDER_CMD and no browser on PATH.
# Build a minimal PATH holding only the coreutils render_html needs (no npx, no browser).
render_probe="$(mktemp)"; printf '<html></html>' > "$render_probe"
render_bin="$(mktemp -d)"
for t in bash dirname mkdir base64; do
  p="$(command -v "$t")" && ln -s "$p" "$render_bin/$t"
done
render_msg="$(env -i PATH="$render_bin" MODELFIT_RENDER_CMD= bash -c ". '$ROOT/bin/lib/common.sh'; render_html '$render_probe' '$render_probe.png'" 2>&1)"
render_rc=$?
rm -rf "$render_bin"
rm -f "$render_probe" "$render_probe.png"
if [ "$render_rc" -ne 0 ] && printf '%s' "$render_msg" | grep -q "no renderer"; then
  ok "render_html reports 'no renderer' when none available"
else
  no "render_html did not fail with 'no renderer' message"
fi

if [ -f "$ROOT/results.example.csv" ]; then
  out="$(bash "$ROOT/bin/report.sh" "$ROOT/results.example.csv" 2>/dev/null)"
  if printf '%s' "$out" | grep -q "modelfit leaderboard"; then ok "report.sh renders sample data"; else no "report.sh did not render"; fi
else
  no "results.example.csv missing"
fi

for t in "$ROOT"/tests/*.test.sh; do
  [ -f "$t" ] || continue
  if bash "$t"; then ok "test $(basename "$t")"; else no "test $(basename "$t")"; fi
done

echo "== $([ $fail -eq 0 ] && echo PASS || echo FAILURES) =="
exit $fail
