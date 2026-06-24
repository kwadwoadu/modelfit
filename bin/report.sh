#!/usr/bin/env bash
# modelfit -- report.sh [--run-id ID] [--by-task] [--strict] [legacy-results.csv]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"

STRICT=0
RUN_ID=""
LEGACY=""
BYTASK=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-id) shift; RUN_ID="${1:-}" ;;
    --by-task) BYTASK=1 ;;
    --strict) STRICT=1 ;;
    *.csv) LEGACY="$1" ;;
    *) LEGACY="$1" ;;
  esac
  shift
done

legacy_report() {
  local csv="$1"
  [ -f "$csv" ] || die "no results.csv at $csv"
  awk -F, '
  NR==1 { next }
  $2!="" {
    m=$2; gsub(/^"|"$/, "", m); runs[m]++; models[m]=1
    p=$5; gsub(/^"|"$/, "", p)
    if (p=="true") { pass[m]++; obj[m]++ } else if (p=="false") { obj[m]++ }
    qv=$7; gsub(/^"|"$/, "", qv); if (qv!="" && qv!="NA") { q[m]+=qv; qn[m]++ }
    cv=$8; gsub(/^"|"$/, "", cv); if (cv!="" && cv!="NA") { c[m]+=cv }
    lv=$9; gsub(/^"|"$/, "", lv); if (lv!="" && lv!="NA") { l[m]+=lv; ln[m]++ }
  }
  END {
    print "# modelfit leaderboard"; print ""
    print "| Rank | Model | Pass % | Quality (0-5) | Candidate cost $ | Avg latency s | Runs |"
    print "|------|-------|--------|---------------|------------------|---------------|------|"
    for (m in models) {
      pr=(obj[m]>0)?pass[m]/obj[m]*100:0; aq=(qn[m]>0)?q[m]/qn[m]:0; al=(ln[m]>0)?l[m]/ln[m]:0
      printf "%s\t%.0f\t%.2f\t%.4f\t%.1f\t%d\n", m, pr, aq, c[m]+0, al, runs[m]
    }
  }' "$csv" | sort -t"$(printf '\t')" -k2,2nr -k3,3nr -k4,4n |
  awk -F"$(printf '\t')" 'NR<=4{print;next}{printf "| %d | %s | %s%% | %s | %s | %s | %s |\n", NR-4, $1,$2,$3,$4,$5,$6}'
}

bytask_report() {
  # Per-task candidate cost (USD), pivoted: rows = probes, columns = models.
  # Reads verdicts.csv (model = col 3, probe = col 4, cost_usd = col 9).
  local verdicts="$1" m p v agg
  local models=()
  agg="$(mktemp)"
  trap 'rm -f "$agg"' RETURN
  # Columns = unique models, read into an array so keys with spaces or glob chars survive.
  while IFS= read -r m; do [ -n "$m" ] && models+=("$m"); done \
    < <(awk -F, 'NR>1{x=$3; gsub(/^"|"$/,"",x); if(x!="")print x}' "$verdicts" | sort -u)
  [ "${#models[@]}" -gt 0 ] || return 0
  # Aggregate candidate cost per probe|model into a TAB-delimited lookup (tab survives spaces).
  awk -F, 'function c(x){gsub(/^"|"$/,"",x); gsub(/""/,"\"",x); return x}
           NR>1{ k=c($4)"|"c($3); val=c($9); if(val=="NA"||val=="")val=0; cost[k]+=val }
           END{ for(k in cost) printf "%s\t%.6f\n", k, cost[k] }' "$verdicts" > "$agg"
  echo "Cost per task (USD, candidate cost; summed across samples)"
  echo ""
  printf '| Probe |'; for m in "${models[@]}"; do printf ' %s |' "$m"; done; echo
  printf '%s' '|---|'; for m in "${models[@]}"; do printf '%s' '---|'; done; echo
  awk -F, 'NR>1{x=$4; gsub(/^"|"$/,"",x); if(x!="")print x}' "$verdicts" | sort -u | while IFS= read -r p; do
    printf '| %s |' "$p"
    for m in "${models[@]}"; do
      v="$(awk -F'\t' -v k="$p|$m" '$1==k{print $2; f=1} END{if(!f)print "-"}' "$agg")"
      printf ' %s |' "$v"
    done
    echo
  done
}

if [ -n "$LEGACY" ]; then
  legacy_report "$LEGACY"
  [ "$BYTASK" -eq 1 ] && echo "(--by-task needs a run directory; ignored for a legacy CSV)" >&2
  exit 0
fi

[ -n "$RUN_ID" ] || RUN_ID="$(latest_run_id)" || die "no runs found"
RUN_DIR="$MODELFIT_RUNS_DIR/$RUN_ID"
[ -d "$RUN_DIR" ] || die "no run at runs/$RUN_ID"
VERDICTS="$RUN_DIR/verdicts.csv"
ATTEMPTS="$RUN_DIR/attempts.csv"
[ -f "$VERDICTS" ] || die "no verdicts.csv for $RUN_ID"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

awk -F, '
function clean(x){gsub(/^"|"$/, "", x); gsub(/""/, "\"", x); return x}
NR==1{next}
{
  m=clean($3); models[m]=1; judged[m]++
  passv=clean($6); if(passv=="true") pass[m]++
  qv=clean($8); if(qv!="NA" && qv!=""){quality[m]+=qv; qn[m]++}
  cv=clean($9); if(cv!="NA" && cv!=""){candidate_cost[m]+=cv}
  lv=clean($10); if(lv!="NA" && lv!=""){lat[m]+=lv; ln[m]++}
}
END {
  for(m in models){
    pr=(judged[m]>0)?pass[m]/judged[m]*100:0
    q=(qn[m]>0)?quality[m]/qn[m]:0
    l=(ln[m]>0)?lat[m]/ln[m]:0
    printf "%s\t%d\t%.0f\t%.2f\t%.6f\t%.2f\n", m, judged[m], pr, q, candidate_cost[m]+0, l
  }
}' "$VERDICTS" > "$tmp"

attempts_tmp="$(mktemp)"
trap 'rm -f "$tmp" "$attempts_tmp"' EXIT
if [ -f "$ATTEMPTS" ]; then
  awk -F, '
  function clean(x){gsub(/^"|"$/, "", x); return x}
  NR==1{next}
  {
    m=clean($4); st=clean($3); out=clean($10); cost=clean($15)
    if(cost=="NA" || cost=="") cost=0
    total[m]+=cost; attempts[m]++
    if(st=="judge") judge[m]+=cost
    if(out!="success") incomplete[m]++
    models[m]=1
  }
  END{for(m in models) printf "%s\t%.6f\t%.6f\t%d\t%d\n", m, judge[m]+0, total[m]+0, attempts[m]+0, incomplete[m]+0}
  ' "$ATTEMPTS" > "$attempts_tmp"
fi

echo "# modelfit leaderboard"
echo ""
echo "Run: $RUN_ID"
echo ""
echo "| Rank | Model | Judged | Pass % | Quality (0-5) | Candidate $ | Judge $ | Actual total $ | Avg latency s | Attempts | Incomplete attempts |"
echo "|------|-------|--------|--------|---------------|-------------|---------|----------------|---------------|----------|---------------------|"
sort -t"$(printf '\t')" -k3,3nr -k4,4nr -k5,5n "$tmp" |
awk -F"$(printf '\t')" -v OFS="$(printf '\t')" '{print NR,$0}' |
while IFS="$(printf '\t')" read -r rank model judged passpct q cand latavg; do
  line="$(awk -F'\t' -v m="$model" '$1==m{print; exit}' "$attempts_tmp")"
  jc="$(printf '%s' "$line" | awk -F'\t' '{print $2}')"; [ -n "$jc" ] || jc="0.000000"
  tc="$(printf '%s' "$line" | awk -F'\t' '{print $3}')"; [ -n "$tc" ] || tc="$cand"
  at="$(printf '%s' "$line" | awk -F'\t' '{print $4}')"; [ -n "$at" ] || at="0"
  inc="$(printf '%s' "$line" | awk -F'\t' '{print $5}')"; [ -n "$inc" ] || inc="0"
  printf '| %s | %s | %s | %s%% | %s | %.6f | %s | %s | %s | %s | %s |\n' "$rank" "$model" "$judged" "$passpct" "$q" "$cand" "$jc" "$tc" "$latavg" "$at" "$inc"
done
echo ""
echo "Rank: pass% desc, then quality desc, then candidate cost asc. Actual total includes recorded candidate and judge attempts when provider usage is available."

if [ "$BYTASK" -eq 1 ]; then
  echo ""
  bytask_report "$VERDICTS"
fi

# --strict: exit non-zero if any result in this run is not "success"
# (status.json is {status, detail}; statuses other than success: skipped,
# candidate_error, truncated_at_ceiling).
if [ "$STRICT" -eq 1 ]; then
  strict_bad=0
  while IFS= read -r _sj; do
    jq -e '.status=="success"' "$_sj" >/dev/null 2>&1 || strict_bad=1
  done < <(find "$RUN_DIR" -name status.json)
  if [ "$strict_bad" -eq 1 ]; then
    echo "modelfit: --strict: at least one result is not 'success' in runs/$RUN_ID" >&2
    exit 1
  fi
fi
