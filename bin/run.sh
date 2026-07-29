#!/usr/bin/env bash
# modelfit -- run.sh <probe> [model-key|all] [--samples N] [--run-id ID]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"

usage() {
  echo "usage: run.sh <probe> [model-key|all] [--samples N] [--run-id ID]" >&2
  exit 1
}

need_cmd jq
need_cmd curl

PROBE="${1:-}"; [ -n "$PROBE" ] || usage; shift
WHICH="all"
if [ "${1:-}" != "" ] && [ "${1#--}" = "$1" ]; then WHICH="$1"; shift; fi

SAMPLES="${MODELFIT_SAMPLES:-1}"
RUN_ID=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --samples) shift; SAMPLES="${1:-}"; [ -n "$SAMPLES" ] || usage ;;
    --run-id) shift; RUN_ID="${1:-}"; [ -n "$RUN_ID" ] || usage ;;
    *) usage ;;
  esac
  shift
done

case "$SAMPLES" in ''|*[!0-9]*) die "--samples must be a positive integer" ;; esac
[ "$SAMPLES" -gt 0 ] || die "--samples must be a positive integer"

validate_config_file
load_env

PROBE_FILE="$(probe_file_for "$PROBE")"
require_nonempty_prompt "$PROBE_FILE" "$PROBE"
SCORING="$(scoring_for_probe "$PROBE_FILE")"

RUN_ID="${RUN_ID:-$(make_run_id)}"
RUN_DIR="$MODELFIT_RUNS_DIR/$RUN_ID"
ATTEMPTS="$RUN_DIR/attempts.csv"
mkdir -p "$RUN_DIR"

TOK_START="${MODELFIT_MAX_TOKENS:-2048}"
TOK_CEIL="${MODELFIT_MAX_TOKENS_CEIL:-8192}"
CURL_CONNECT_TIMEOUT="${MODELFIT_CURL_CONNECT_TIMEOUT:-10}"
CURL_MAX_TIME="${MODELFIT_CURL_MAX_TIME:-300}"

PROMPT_TMP="$(mktemp)"
trap 'rm -f "$PROMPT_TMP"' EXIT
prompt_section "$PROBE_FILE" > "$PROMPT_TMP"

write_manifest() {
  local status="$1" success="$2" failed="$3" skipped="$4"
  jq -n \
    --arg run_id "$RUN_ID" \
    --arg status "$status" \
    --arg probe "$PROBE" \
    --arg which "$WHICH" \
    --argjson samples "$SAMPLES" \
    --argjson success "$success" \
    --argjson failed "$failed" \
    --argjson skipped "$skipped" \
    '{schema_version:2, run_id:$run_id, status:$status,
      requested:{probe:$probe, model:$which, samples:$samples},
      counts:{candidate_success:$success, candidate_failed:$failed, skipped:$skipped}}' > "$RUN_DIR/manifest.json"
}
write_manifest running 0 0 0

model_stream() {
  if [ "$WHICH" = "all" ]; then
    jq -c '.models[]' "$MODELFIT_CONFIG"
  else
    jq -c --arg k "$WHICH" '.models[] | select(.key==$k)' "$MODELFIT_CONFIG"
  fi
}

status_json() {
  local path="$1" status="$2" detail="$3"
  jq -n --arg status "$status" --arg detail "$detail" '{status:$status, detail:$detail}' > "$path"
}

curl_json() {
  local raw="$1" url="$2" body="$3"; shift 3
  curl -sS --fail-with-body --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
    -o "$raw" -w '%{http_code}\t%{time_total}' "$url" "$@" -d "$body"
}

run_one_sample() {
  local cfg="$1" sample="$2"
  local key provider base model keyenv pin pout tparam kv
  key="$(jq -r '.key' <<<"$cfg")"
  provider="$(jq -r '.provider' <<<"$cfg")"
  base="$(jq -r '.base_url' <<<"$cfg")"
  model="$(jq -r '.model_id' <<<"$cfg")"
  keyenv="$(jq -r '.key_env' <<<"$cfg")"
  pin="$(jq -r '.price_in // 0' <<<"$cfg")"
  pout="$(jq -r '.price_out // 0' <<<"$cfg")"
  tparam="$(jq -r '.token_param // "max_tokens"' <<<"$cfg")"

  local f v
  for f in key provider base model keyenv; do
    v="${!f}"
    if [ -z "$v" ] || [ "$v" = "null" ]; then
      echo "[$key/$PROBE/sample-$sample] config error: missing .$f" >&2
      return 1
    fi
  done
  validate_provider "$provider" || { echo "[$key/$PROBE/sample-$sample] invalid provider '$provider'" >&2; return 1; }

  kv="${!keyenv:-}"
  local out="$RUN_DIR/$key/$PROBE/sample-$sample"
  mkdir -p "$out"
  if [ -z "$kv" ]; then
    status_json "$out/status.json" skipped "\$$keyenv not set"
    echo "[$key/$PROBE/sample-$sample] SKIP: \$$keyenv not set"
    return 2
  fi

  local maxtok="$TOK_START" attempt=0
  local raw="$out/candidate.raw.json" text intok outtok trunc stripped body curl_out curl_rc http lat err outcome cost started detail
  while : ; do
    attempt=$((attempt + 1))
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ "$provider" = "openai" ]; then
      body="$(jq -n --arg m "$model" --argjson mt "$maxtok" --arg tp "$tparam" --rawfile p "$PROMPT_TMP" \
              '{model:$m, messages:[{role:"user", content:$p}]} + {($tp): $mt}')"
      curl_out="$(curl_json "$raw" "$base/chat/completions" "$body" \
              -H "content-type: application/json" -H "Authorization: Bearer $kv")"; curl_rc=$?
    else
      body="$(jq -n --arg m "$model" --argjson mt "$maxtok" --rawfile p "$PROMPT_TMP" \
              '{model:$m, max_tokens:$mt, messages:[{role:"user", content:$p}]}')"
      curl_out="$(curl_json "$raw" "$base/v1/messages" "$body" \
              -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
              -H "x-api-key: $kv" -H "Authorization: Bearer $kv")"; curl_rc=$?
    fi
    http="$(printf '%s' "$curl_out" | awk '{print $1}')"
    lat="$(printf '%s' "$curl_out" | awk '{print $2}')"
    [ -n "$http" ] || http="000"
    [ -n "$lat" ] || lat="NA"

    intok="NA"; outtok="NA"; cost="NA"
    if [ "$curl_rc" -ne 0 ]; then
      outcome="curl_error"
      case "$http" in 4*|5*) outcome="http_error" ;; esac
      detail="$(http_error_detail "$raw")"
      append_attempt "$ATTEMPTS" "$RUN_ID" "$sample" candidate "$key" "$model" "$PROBE" "$attempt" "$started" "$http" "$outcome" "$maxtok" "$intok" "$outtok" "$lat" "$cost"
      status_json "$out/status.json" candidate_error "$outcome http=$http$detail"
      echo "[$key/$PROBE/sample-$sample] $outcome http=$http$detail"
      echo "[$key/$PROBE/sample-$sample] raw response: $raw"
      return 1
    fi
    if [ ! -s "$raw" ] || ! jq -e 'type=="object"' "$raw" >/dev/null 2>&1; then
      append_attempt "$ATTEMPTS" "$RUN_ID" "$sample" candidate "$key" "$model" "$PROBE" "$attempt" "$started" "$http" invalid_response "$maxtok" "$intok" "$outtok" "$lat" "$cost"
      status_json "$out/status.json" candidate_error "invalid_response"
      echo "[$key/$PROBE/sample-$sample] invalid_response"
      return 1
    fi
    err="$(jq -r '.error.message // empty' "$raw")"
    if [ -n "$err" ]; then
      append_attempt "$ATTEMPTS" "$RUN_ID" "$sample" candidate "$key" "$model" "$PROBE" "$attempt" "$started" "$http" provider_error "$maxtok" "$intok" "$outtok" "$lat" "$cost"
      status_json "$out/status.json" candidate_error "$err"
      echo "[$key/$PROBE/sample-$sample] provider_error: $err"
      return 1
    fi

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
    cost="$(calc_cost "$intok" "$outtok" "$pin" "$pout")"
    stripped="$(printf '%s' "$text" | tr -d '[:space:]')"
    if [ -n "$stripped" ] && [ "$trunc" = "no" ]; then
      append_attempt "$ATTEMPTS" "$RUN_ID" "$sample" candidate "$key" "$model" "$PROBE" "$attempt" "$started" "$http" success "$maxtok" "$intok" "$outtok" "$lat" "$cost"
      printf '%s' "$text" | strip_fences > "$out/result.txt"
      local rendered=false shot=""
      if [ "$SCORING" = "screenshot" ]; then
        cp "$out/result.txt" "$out/result.html"
        if render_html "$out/result.html" "$out/result.png"; then
          rendered=true; shot="result.png"
          echo "[$key/$PROBE/sample-$sample] RENDERED -> $out/result.png"
        else
          append_attempt "$ATTEMPTS" "$RUN_ID" "$sample" candidate "$key" "$model" "$PROBE" "$attempt" "$started" "$http" render_error "$maxtok" "$intok" "$outtok" "$lat" "$cost"
          status_json "$out/status.json" render_error "render failed for $out/result.html"
          echo "[$key/$PROBE/sample-$sample] RENDER_ERROR: could not render $out/result.html"
          return 1
        fi
      fi
      jq -n --arg model_key "$key" --arg model_id "$model" --arg provider "$provider" --arg probe "$PROBE" --arg run_id "$RUN_ID" --arg sample "$sample" \
        --arg latency_s "$lat" --arg input_tokens "$intok" --arg output_tokens "$outtok" --arg truncated "$trunc" --arg max_tokens "$maxtok" --arg cost_usd "$cost" \
        --argjson rendered "$rendered" --arg screenshot "$shot" \
        '{model_key:$model_key, model_id:$model_id, provider:$provider, probe:$probe, run_id:$run_id, sample:($sample|tonumber),
          latency_s:$latency_s, input_tokens:$input_tokens, output_tokens:$output_tokens, truncated:$truncated,
          max_tokens:($max_tokens|tonumber), cost_usd:$cost_usd}
         + (if $rendered then {rendered:true, screenshot:$screenshot} else {} end)' > "$out/candidate.meta.json"
      status_json "$out/status.json" success "candidate complete"
      echo "[$key/$PROBE/sample-$sample] SUCCESS ${lat}s in=$intok out=$outtok cost=\$$cost -> $out/result.txt"
      return 0
    fi

    outcome="empty"
    [ "$trunc" = "yes" ] && outcome="truncated"
    append_attempt "$ATTEMPTS" "$RUN_ID" "$sample" candidate "$key" "$model" "$PROBE" "$attempt" "$started" "$http" "$outcome" "$maxtok" "$intok" "$outtok" "$lat" "$cost"
    if [ "$maxtok" -ge "$TOK_CEIL" ]; then
      printf '%s' "$text" | strip_fences > "$out/result.txt"
      status_json "$out/status.json" truncated_at_ceiling "$outcome at max_tokens=$maxtok"
      echo "[$key/$PROBE/sample-$sample] TRUNCATED_AT_CEILING max_tokens=$maxtok"
      return 1
    fi
    local next=$((maxtok * 2))
    [ "$next" -gt "$TOK_CEIL" ] && next="$TOK_CEIL"
    maxtok="$next"
    echo "[$key/$PROBE/sample-$sample] $outcome output -> retry at max_tokens=$maxtok"
  done
}

models_seen=0; success=0; failed=0; skipped=0
while IFS= read -r m; do
  [ -n "$m" ] || continue
  models_seen=$((models_seen + 1))
  s=1
  while [ "$s" -le "$SAMPLES" ]; do
    run_one_sample "$m" "$s"
    rc=$?
    case "$rc" in
      0) success=$((success + 1)) ;;
      2) skipped=$((skipped + 1)) ;;
      *) failed=$((failed + 1)) ;;
    esac
    s=$((s + 1))
  done
done < <(model_stream)

[ "$models_seen" -gt 0 ] || die "no model '$WHICH' in $MODELFIT_CONFIG"
if [ "$failed" -gt 0 ] || [ "$skipped" -gt 0 ]; then
  write_manifest partial "$success" "$failed" "$skipped"
  echo "Summary: $success succeeded, $failed failed, $skipped skipped. run_id=$RUN_ID"
  exit 1
fi
write_manifest complete "$success" "$failed" "$skipped"
echo "Summary: $success succeeded, 0 failed, 0 skipped. run_id=$RUN_ID"
