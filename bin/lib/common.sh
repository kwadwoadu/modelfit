#!/usr/bin/env bash
# Shared helpers for modelfit scripts. Bash + jq only.

MODELFIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELFIT_ROOT="$(cd "$MODELFIT_LIB_DIR/../.." && pwd)"
MODELFIT_CONFIG="${MODELFIT_CONFIG:-$MODELFIT_ROOT/config/models.json}"
MODELFIT_RUNS_DIR="${MODELFIT_RUNS_DIR:-$MODELFIT_ROOT/runs}"

die() { echo "modelfit: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null || die "needs $1"
}

load_env() {
  # shellcheck disable=SC1091
  [ -f "$MODELFIT_ROOT/.env" ] && { set -a; . "$MODELFIT_ROOT/.env"; set +a; }
}

make_run_id() {
  if [ -n "${MODELFIT_RUN_ID:-}" ]; then
    printf '%s' "$MODELFIT_RUN_ID"
    return 0
  fi
  printf 'run_%s_%s_%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "${RANDOM:-0}"
}

latest_run_id() {
  [ -d "$MODELFIT_RUNS_DIR" ] || return 1
  find "$MODELFIT_RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    sort |
    tail -n 1 |
    xargs basename 2>/dev/null
}

ensure_parent() { mkdir -p "$(dirname "$1")"; }

csv_row() {
  jq -n -r '$ARGS.positional | @csv' --args "$@"
}

ensure_attempts_header() {
  local file="$1"
  if [ ! -f "$file" ]; then
    ensure_parent "$file"
    csv_row run_id sample stage model_key model_id probe attempt started_at http_status outcome max_tokens input_tokens output_tokens latency_s cost_usd > "$file"
  fi
}

append_attempt() {
  local file="$1"; shift
  ensure_attempts_header "$file"
  csv_row "$@" >> "$file"
}

ensure_verdicts_header() {
  local file="$1"
  if [ ! -f "$file" ]; then
    ensure_parent "$file"
    csv_row run_id sample model_key probe category correctness_pass instruction_following quality cost_usd latency_s input_tokens output_tokens truncated judge_model notes > "$file"
  fi
}

append_verdict() {
  local file="$1"; shift
  ensure_verdicts_header "$file"
  csv_row "$@" >> "$file"
}

prompt_section() {
  awk '/^# *PROMPT[[:space:]]*$/{f=1;next} /^# *RUBRIC[[:space:]]*$/{f=0} f{print}' "$1"
}

rubric_section() {
  awk '/^# *RUBRIC[[:space:]]*$/{f=1;next} f{print}' "$1"
}

strip_fences() {
  awk 'BEGIN{bt=sprintf("%c%c%c",96,96,96)}
       {l[NR]=$0}
       END{s=1;e=NR;
        while(s<=e && l[s]~/^[[:space:]]*$/)s++; if(index(l[s],bt)==1)s++;
        while(e>=s && l[e]~/^[[:space:]]*$/)e--; if(index(l[e],bt)==1)e--;
        for(i=s;i<=e;i++)print l[i]}'
}

category_for_probe() {
  awk -F': *' '/^category:/{print $2; exit}' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr ',' ';'
}

validate_config_file() {
  [ -f "$MODELFIT_CONFIG" ] || die "no config -- run: cp config/models.example.json config/models.json"
  jq -e '.judge and (.models|type=="array")' "$MODELFIT_CONFIG" >/dev/null ||
    die "config must contain .judge and .models[]"
}

validate_provider() {
  case "$1" in
    openai|anthropic) return 0 ;;
    *) return 1 ;;
  esac
}

calc_cost() {
  local intok="$1" outtok="$2" pin="$3" pout="$4"
  if [ "$intok" != "NA" ] && [ "$outtok" != "NA" ]; then
    awk -v i="$intok" -v o="$outtok" -v pi="$pin" -v po="$pout" 'BEGIN{printf "%.6f",(i*pi+o*po)/1000000}'
  else
    printf 'NA'
  fi
}

probe_file_for() {
  local probe="$1"
  local path="$MODELFIT_ROOT/probes/$probe.md"
  [ -f "$path" ] || die "no probe at probes/$probe.md"
  printf '%s' "$path"
}

require_nonempty_prompt() {
  local file="$1" probe="$2"
  [ -n "$(prompt_section "$file" | tr -d '[:space:]')" ] ||
    die "probe $probe has an empty or whitespace-only '# PROMPT' section"
}
