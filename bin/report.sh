#!/usr/bin/env bash
# modelfit -- report.sh [results.csv]
# Render results.csv into a ranked markdown leaderboard.
# Rank: objective pass% desc, then mean quality desc, then total cost asc.
# Cost/latency never override a correctness loss.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSV="${1:-$ROOT/results.csv}"
[ -f "$CSV" ] || { echo "modelfit: no results.csv at $CSV" >&2; exit 1; }

# cols: 1 date 2 model 3 probe 4 cat 5 pass 6 instr 7 quality
#       8 cost 9 lat 10 in 11 out 12 trunc 13 judge 14 notes
awk -F, '
NR==1 { next }
$2!="" {
  m=$2; runs[m]++; models[m]=1
  if ($5=="true")  { pass[m]++; obj[m]++ }
  else if ($5=="false") { obj[m]++ }
  if ($6!="" && $6!="NA") { fi[m]+=$6; fin[m]++ }
  if ($7!="" && $7!="NA") { q[m]+=$7; qn[m]++ }
  if ($8!="" && $8!="NA") { c[m]+=$8 }
  if ($9!="" && $9!="NA") { l[m]+=$9; ln[m]++ }
}
END {
  for (m in models) {
    pr  = (obj[m]>0) ? pass[m]/obj[m]*100 : 0
    afi = (fin[m]>0) ? fi[m]/fin[m] : 0
    aq  = (qn[m]>0)  ? q[m]/qn[m]   : 0
    al  = (ln[m]>0)  ? l[m]/ln[m]   : 0
    printf "%s\t%.0f\t%.2f\t%.2f\t%.4f\t%.1f\t%d\n", m, pr, afi, aq, c[m]+0, al, runs[m]
  }
}' "$CSV" \
| sort -t"$(printf '\t')" -k2,2nr -k4,4nr -k5,5n \
| awk -F"$(printf '\t')" '
BEGIN {
  print "# modelfit leaderboard"; print ""
  print "| Rank | Model | Pass % | Instr (0-5) | Quality (0-5) | Total cost $ | Avg latency s | Runs |"
  print "|------|-------|--------|-------------|---------------|--------------|---------------|------|"
}
{ printf "| %d | %s | %s%% | %s | %s | %s | %s | %s |\n", NR, $1, $2, $3, $4, $5, $6, $7 }
END {
  print ""
  print "Rank: pass% desc, then quality desc, then cost asc. Cost/latency never override a correctness loss."
  print "Treat gaps inside run-to-run variance as ties -- raise MODELFIT_SAMPLES and re-run to be sure."
}'
