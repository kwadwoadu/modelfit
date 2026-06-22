#!/usr/bin/env bash
# modelfit -- run.sh <probe> [model-key|all]
#
# POST a probe's PROMPT to every configured model over an OpenAI-compatible
# (/chat/completions) or Anthropic-compatible (/v1/messages) API, auto-escalate
# the token cap when a model truncates or returns nothing, then save the answer
# plus metrics (tokens, latency, cost, truncation flag).
#
# No API keys live in this repo. They are read at runtime from your shell env
# or a gitignored .env, via the key_env name in config/models.json.
#
# Output per run: runs/<date>/<model>/<probe>/{raw.json,result.txt,meta.txt}
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${MODELFIT_CONFIG:-$ROOT/config/models.json}"
command -v jq   >/dev/null || { echo "modelfit: needs jq (brew install jq)"   >&2; exit 1; }
command -v curl >/dev/null || { echo "modelfit: needs curl" >&2; exit 1; }

PROBE="${1:?usage: run.sh <probe> [model-key|all]}"
WHICH="${2:-all}"
PROBE_FILE="$ROOT/probes/$PROBE.md"
[ -f "$PROBE_FILE" ] || { echo "modelfit: no probe at probes/$PROBE.md" >&2; exit 1; }
[ -f "$CONFIG" ]     || { echo "modelfit: no config -- run: cp config/models.example.json config/models.json" >&2; exit 1; }

# Load .env (gitignored) so keys can live there instead of the shell.
if [ -f "$ROOT/.env" ]; then set -a; . "$ROOT/.env"; set +a; fi

RUN_DATE="$(date +%Y-%m-%d)"
TOK_START="${MODELFIT_MAX_TOKENS:-2048}"
TOK_CEIL="${MODELFIT_MAX_TOKENS_CEIL:-8192}"

prompt_section() { awk '/^# *PROMPT[[:space:]]*$/{f=1;next} /^# *RUBRIC[[:space:]]*$/{f=0} f{print}' "$1"; }
strip_fences() {
  awk '{l[NR]=$0} END{s=1;e=NR;
        while(s<=e && l[s]~/^[[:space:]]*$/)s++; if(l[s]~/^```/)s++;
        while(e>=s && l[e]~/^[[:space:]]*$/)e--; if(l[e]~/^```/)e--;
        for(i=s;i<=e;i++)print l[i]}'
}

PROMPT_TMP="$(mktemp)"; trap 'rm -f "$PROMPT_TMP"' EXIT
prompt_section "$PROBE_FILE" > "$PROMPT_TMP"
[ -n "$(tr -d '[:space:]' < "$PROMPT_TMP")" ] || { echo "modelfit: probe $PROBE has an empty or whitespace-only '# PROMPT' section" >&2; exit 1; }

run_one() {
  local cfg="$1" key provider base model keyenv pin pout tparam kv
  key="$(jq -r '.key'        <<<"$cfg")"
  provider="$(jq -r '.provider' <<<"$cfg")"
  base="$(jq -r '.base_url'   <<<"$cfg")"
  model="$(jq -r '.model_id'  <<<"$cfg")"
  keyenv="$(jq -r '.key_env'  <<<"$cfg")"
  pin="$(jq -r '.price_in  // 0' <<<"$cfg")"
  pout="$(jq -r '.price_out // 0' <<<"$cfg")"
  tparam="$(jq -r '.token_param // "max_tokens"' <<<"$cfg")"
  local _f _v
  for _f in key provider base model keyenv; do
    _v="${!_f}"
    [ -n "$_v" ] && [ "$_v" != "null" ] || { echo "modelfit: config error: a model entry is missing required field .$_f" >&2; return 1; }
  done
  case "$provider" in
    openai|anthropic) ;;
    *) echo "modelfit: model '$key' has invalid provider '$provider' (must be 'openai' or 'anthropic')" >&2; return 1 ;;
  esac
  kv="${!keyenv:-}"
  local out="$ROOT/runs/$RUN_DATE/$key/$PROBE"; mkdir -p "$out"
  if [ -z "$kv" ]; then echo "[$key/$PROBE] SKIP: \$$keyenv not set (add it to .env)"; return 0; fi

  local maxtok="$TOK_START" raw="$out/raw.json" text intok outtok trunc lat body err stripped
  while : ; do
    if [ "$provider" = "openai" ]; then
      body="$(jq -n --arg m "$model" --argjson mt "$maxtok" --arg tp "$tparam" --rawfile p "$PROMPT_TMP" \
              '{model:$m, messages:[{role:"user", content:$p}]} + {($tp): $mt}')"
      lat="$(curl -s -o "$raw" -w '%{time_total}' "$base/chat/completions" \
              -H "content-type: application/json" -H "Authorization: Bearer $kv" -d "$body")" \
        || { echo "[$key/$PROBE] curl failed" >&2; return 1; }
    else
      body="$(jq -n --arg m "$model" --argjson mt "$maxtok" --rawfile p "$PROMPT_TMP" \
              '{model:$m, max_tokens:$mt, messages:[{role:"user", content:$p}]}')"
      lat="$(curl -s -o "$raw" -w '%{time_total}' "$base/v1/messages" \
              -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
              -H "x-api-key: $kv" -H "Authorization: Bearer $kv" -d "$body")" \
        || { echo "[$key/$PROBE] curl failed" >&2; return 1; }
    fi

    if [ ! -s "$raw" ] || ! jq -e 'type=="object"' "$raw" >/dev/null 2>&1; then
      echo "[$key/$PROBE] non-JSON or unexpected response from $base (HTTP error page, empty body, or proxy?); first bytes:" >&2
      head -c 200 "$raw" >&2; echo >&2
      return 1
    fi
    err="$(jq -r '.error.message // empty' "$raw" 2>/dev/null)"
    if [ -n "$err" ]; then echo "[$key/$PROBE] API error: $err" >&2; return 1; fi

    if [ "$provider" = "openai" ]; then
      text="$(jq -r '.choices[0].message.content // ""' "$raw")"
      intok="$(jq -r '.usage.prompt_tokens // "NA"' "$raw")"
      outtok="$(jq -r '.usage.completion_tokens // "NA"' "$raw")"
      [ "$(jq -r '.choices[0].finish_reason // ""' "$raw")" = "length" ] && trunc="yes" || trunc="no"
    else
      text="$(jq -r '[.content[]?|select(.type=="text")|.text]|join("")' "$raw")"
      intok="$(jq -r '.usage.input_tokens // "NA"' "$raw")"
      outtok="$(jq -r '.usage.output_tokens // "NA"' "$raw")"
      [ "$(jq -r '.stop_reason // ""' "$raw")" = "max_tokens" ] && trunc="yes" || trunc="no"
    fi

    stripped="$(printf '%s' "$text" | tr -d '[:space:]')"
    # Stop when we have real content that wasn't cut off, or we hit the ceiling.
    if { [ -n "$stripped" ] && [ "$trunc" = "no" ]; } || [ "$maxtok" -ge "$TOK_CEIL" ]; then break; fi
    maxtok=$(( maxtok * 2 ))
    echo "[$key/$PROBE] empty or truncated output -> retry at max_tokens=$maxtok"
  done

  printf '%s' "$text" | strip_fences > "$out/result.txt"
  local cost="NA"
  if [ "$intok" != "NA" ] && [ "$outtok" != "NA" ]; then
    cost="$(awk -v i="$intok" -v o="$outtok" -v pi="$pin" -v po="$pout" 'BEGIN{printf "%.6f",(i*pi+o*po)/1000000}')"
  fi
  { echo "model_key=$key"; echo "model_id=$model"; echo "provider=$provider"; echo "probe=$PROBE";
    echo "run_date=$RUN_DATE"; echo "latency_s=$lat"; echo "input_tokens=$intok";
    echo "output_tokens=$outtok"; echo "truncated=$trunc"; echo "max_tokens=$maxtok"; echo "cost_usd=$cost"; } > "$out/meta.txt"
  echo "[$key/$PROBE] ok ${lat}s in=$intok out=$outtok trunc=$trunc cost=\$$cost -> $out/result.txt"
}

if [ "$WHICH" = "all" ]; then
  jq -c '.models[]' "$CONFIG" | while IFS= read -r m; do run_one "$m"; done
else
  m="$(jq -c --arg k "$WHICH" '.models[] | select(.key==$k)' "$CONFIG")"
  [ -n "$m" ] || { echo "modelfit: no model '$WHICH' in $CONFIG" >&2; exit 1; }
  run_one "$m"
fi
