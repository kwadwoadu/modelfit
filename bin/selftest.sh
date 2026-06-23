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

for s in bin/run.sh bin/judge.sh bin/report.sh bin/selftest.sh bin/scan-secrets.sh; do
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
