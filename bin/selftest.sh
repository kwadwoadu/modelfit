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
command -v jq   >/dev/null && ok "jq present"   || no "jq missing"
command -v curl >/dev/null && ok "curl present" || no "curl missing"

for s in bin/run.sh bin/judge.sh bin/report.sh bin/selftest.sh bin/scan-secrets.sh; do
  bash -n "$ROOT/$s" && ok "syntax $s" || no "syntax $s"
done

if jq -e . "$ROOT/config/models.example.json" >/dev/null 2>&1; then ok "example config is valid JSON"; else no "example config invalid JSON"; fi
jq -e '.judge and (.models|type=="array")' "$ROOT/config/models.example.json" >/dev/null 2>&1 \
  && ok "example config has .judge and .models[]" || no "example config missing .judge/.models"

shopt -s nullglob
for p in "$ROOT"/probes/*.md; do
  name="$(basename "$p")"
  has_p="$(awk '/^# *PROMPT[[:space:]]*$/{print "y";exit}' "$p")"
  has_r="$(awk '/^# *RUBRIC[[:space:]]*$/{print "y";exit}' "$p")"
  [ "$has_p" = y ] && [ "$has_r" = y ] && ok "probe $name has PROMPT+RUBRIC" || no "probe $name missing a section"
done

if [ -f "$ROOT/results.example.csv" ]; then
  out="$(bash "$ROOT/bin/report.sh" "$ROOT/results.example.csv" 2>/dev/null)"
  printf '%s' "$out" | grep -q "modelfit leaderboard" && ok "report.sh renders sample data" || no "report.sh did not render"
else
  no "results.example.csv missing"
fi

echo "== $([ $fail -eq 0 ] && echo PASS || echo FAILURES) =="
exit $fail
