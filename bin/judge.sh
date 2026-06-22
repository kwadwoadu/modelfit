#!/usr/bin/env bash
# modelfit -- judge.sh <probe> [model-key|all] [run-date]
#
# Blind LLM-judge. For each model that answered <probe>, send the judge model
# the task + the probe's # RUBRIC + the candidate answer (author hidden), and
# parse back a strict JSON verdict. Append one row per (probe, model) to
# results.csv. The judge is configured under ".judge" in config/models.json.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${MODELFIT_CONFIG:-$ROOT/config/models.json}"
CSV="$ROOT/results.csv"
SYS="$ROOT/prompts/judge-system.md"
command -v jq >/dev/null || { echo "modelfit: needs jq" >&2; exit 1; }
[ -f "$ROOT/.env" ] && { set -a; . "$ROOT/.env"; set +a; }

PROBE="${1:?usage: judge.sh <probe> [model-key|all] [run-date]}"
WHICH="${2:-all}"
RUN_DATE="${3:-$(date +%Y-%m-%d)}"
PROBE_FILE="$ROOT/probes/$PROBE.md"
[ -f "$PROBE_FILE" ] || { echo "modelfit: no probe probes/$PROBE.md" >&2; exit 1; }
[ -f "$SYS" ]        || { echo "modelfit: missing prompts/judge-system.md" >&2; exit 1; }

CATEGORY="$(awk -F': *' '/^category:/{print $2; exit}' "$PROBE_FILE" | tr -d '\r')"
[ -n "$CATEGORY" ] || CATEGORY="uncategorized"

prompt_section() { awk '/^# *PROMPT[[:space:]]*$/{f=1;next} /^# *RUBRIC[[:space:]]*$/{f=0} f{print}' "$1"; }
rubric_section() { awk '/^# *RUBRIC[[:space:]]*$/{f=1;next} f{print}' "$1"; }

J_provider="$(jq -r '.judge.provider' "$CONFIG")"
J_base="$(jq -r '.judge.base_url'   "$CONFIG")"
J_model="$(jq -r '.judge.model_id'  "$CONFIG")"
J_keyenv="$(jq -r '.judge.key_env'  "$CONFIG")"
J_tparam="$(jq -r '.judge.token_param // "max_tokens"' "$CONFIG")"
J_kv="${!J_keyenv:-}"
[ -n "$J_kv" ] || { echo "modelfit: judge key \$$J_keyenv not set (add it to .env)" >&2; exit 1; }
# Reasoning-model judges can spend a small cap entirely on thinking and return no
# text. Start generous and escalate on empty/truncated, same as run.sh.
J_TOK_START="${MODELFIT_JUDGE_MAX_TOKENS:-2048}"
J_TOK_CEIL="${MODELFIT_JUDGE_MAX_TOKENS_CEIL:-8192}"

SYS_TXT="$(cat "$SYS")"
TASK_TXT="$(prompt_section "$PROBE_FILE")"
RUBRIC_TXT="$(rubric_section "$PROBE_FILE")"

[ -f "$CSV" ] || echo "run_date,model_key,probe,category,correctness_pass,instruction_following,quality,cost_usd,latency_s,input_tokens,output_tokens,truncated,judge_model,notes" > "$CSV"

JCALL_ERR=""   # set to the API error message if the call hard-fails
judge_call() {  # $1 = user content ; $2 = raw-json path to keep ; echoes the judge's text
  local user="$1" raw="$2" body maxtok="$J_TOK_START" text err trunc stripped
  JCALL_ERR=""
  while : ; do
    if [ "$J_provider" = "openai" ]; then
      body="$(jq -n --arg m "$J_model" --argjson mt "$maxtok" --arg tp "$J_tparam" --arg s "$SYS_TXT" --arg u "$user" \
              '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$u}]} + {($tp):$mt}')"
      curl -s -o "$raw" "$J_base/chat/completions" \
        -H "content-type: application/json" -H "Authorization: Bearer $J_kv" -d "$body" >/dev/null
    else
      body="$(jq -n --arg m "$J_model" --argjson mt "$maxtok" --arg s "$SYS_TXT" --arg u "$user" \
              '{model:$m, max_tokens:$mt, system:$s, messages:[{role:"user",content:$u}]}')"
      curl -s -o "$raw" "$J_base/v1/messages" \
        -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
        -H "x-api-key: $J_kv" -H "Authorization: Bearer $J_kv" -d "$body" >/dev/null
    fi
    err="$(jq -r '.error.message // empty' "$raw" 2>/dev/null)"
    if [ -n "$err" ]; then JCALL_ERR="$err"; printf ''; return 0; fi
    if [ "$J_provider" = "openai" ]; then
      text="$(jq -r '.choices[0].message.content // ""' "$raw")"
      [ "$(jq -r '.choices[0].finish_reason // ""' "$raw")" = "length" ] && trunc="yes" || trunc="no"
    else
      text="$(jq -r '[.content[]?|select(.type=="text")|.text]|join("")' "$raw")"
      [ "$(jq -r '.stop_reason // ""' "$raw")" = "max_tokens" ] && trunc="yes" || trunc="no"
    fi
    stripped="$(printf '%s' "$text" | tr -d '[:space:]')"
    if { [ -n "$stripped" ] && [ "$trunc" = "no" ]; } || [ "$maxtok" -ge "$J_TOK_CEIL" ]; then
      printf '%s' "$text"; return 0
    fi
    maxtok=$(( maxtok * 2 ))
    echo "  judge empty/truncated -> retry at max_tokens=$maxtok" >&2
  done
}

# Pull the first balanced {...} JSON block out of arbitrary judge text.
first_json() {
  awk 'BEGIN{d=0;s=0}{for(i=1;i<=length($0);i++){c=substr($0,i,1);
       if(c=="{"){d++;s=1} if(s)printf "%s",c; if(c=="}"){d--; if(d==0){print "";exit}}}}'
}

judge_one() {
  local key="$1"
  local dir="$ROOT/runs/$RUN_DATE/$key/$PROBE"
  local rf="$dir/result.txt" mf="$dir/meta.txt"
  [ -f "$rf" ] || { echo "[$key/$PROBE] no result.txt for $RUN_DATE, skip"; return 0; }
  local cand user resp js pass IF q notes
  cand="$(cat "$rf")"
  user="TASK GIVEN TO THE CANDIDATE:
$TASK_TXT

RUBRIC (grade strictly against this, criterion by criterion):
$RUBRIC_TXT

CANDIDATE ANSWER (author hidden -- judge the text only):
$cand

Return ONLY the JSON verdict object, nothing else."
  resp="$(judge_call "$user" "$dir/judge.api.json")"
  if [ -n "$JCALL_ERR" ]; then echo "[$key/$PROBE] judge API error: $JCALL_ERR"; return 0; fi
  js="$(printf '%s' "$resp" | first_json)"
  pass="$(printf '%s' "$js"  | jq -r '.correctness_pass // empty'      2>/dev/null)"
  IF="$(printf '%s' "$js"    | jq -r '.instruction_following // empty' 2>/dev/null)"
  q="$(printf '%s' "$js"     | jq -r '.quality // empty'              2>/dev/null)"
  notes="$(printf '%s' "$js" | jq -r '.notes // empty' 2>/dev/null | tr ',\n' '; ')"
  if [ -z "$pass" ]; then
    echo "[$key/$PROBE] judge gave no parseable JSON (raw text -> judge.raw.txt, api -> judge.api.json)"
    printf '%s' "$resp" > "$dir/judge.raw.txt"; return 0
  fi
  local cost lat intok outtok trunc
  cost="$(awk -F= '/^cost_usd=/{print $2}'      "$mf" 2>/dev/null)"
  lat="$(awk -F= '/^latency_s=/{print $2}'      "$mf" 2>/dev/null)"
  intok="$(awk -F= '/^input_tokens=/{print $2}' "$mf" 2>/dev/null)"
  outtok="$(awk -F= '/^output_tokens=/{print $2}' "$mf" 2>/dev/null)"
  trunc="$(awk -F= '/^truncated=/{print $2}'    "$mf" 2>/dev/null)"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$RUN_DATE" "$key" "$PROBE" "$CATEGORY" "$pass" "$IF" "$q" \
    "${cost:-NA}" "${lat:-NA}" "${intok:-NA}" "${outtok:-NA}" "${trunc:-NA}" "$J_model" "$notes" >> "$CSV"
  echo "[$key/$PROBE] judged: pass=$pass IF=$IF quality=$q"
}

if [ "$WHICH" = "all" ]; then
  for d in "$ROOT/runs/$RUN_DATE"/*/ ; do [ -d "$d$PROBE" ] && judge_one "$(basename "$d")"; done
else
  judge_one "$WHICH"
fi
echo "Done. Render the ranking with: bin/report.sh"
