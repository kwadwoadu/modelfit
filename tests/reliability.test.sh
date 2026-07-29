#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod +x "$ROOT/tests/curl"

config="$tmp/models.json"
junk_results="$tmp/results.csv"
cat > "$config" <<'JSON'
{
  "judge": {
    "provider": "openai",
    "base_url": "https://fake.test",
    "model_id": "fake-judge",
    "key_env": "TEST_API_KEY",
    "token_param": "max_tokens",
    "price_in": 10,
    "price_out": 20
  },
  "models": [
    {
      "key": "fake",
      "provider": "openai",
      "base_url": "https://fake.test",
      "model_id": "fake-model",
      "key_env": "TEST_API_KEY",
      "token_param": "max_tokens",
      "price_in": 1,
      "price_out": 2
    }
  ]
}
JSON

export PATH="$ROOT/tests:$PATH"
export TEST_API_KEY="test-key"
export MODELFIT_CONFIG="$config"
export MODELFIT_RUNS_DIR="$tmp/runs"
export MODELFIT_RESULTS_CSV="$junk_results"

MODELFIT_RUN_ID=run_success "$ROOT/bin/run.sh" example-chunk fake --samples 2 >/tmp/modelfit-test-run.out || { cat /tmp/modelfit-test-run.out; exit 1; }
[ -f "$tmp/runs/run_success/fake/example-chunk/sample-1/result.txt" ] || { echo "missing sample 1 result"; exit 1; }
[ -f "$tmp/runs/run_success/fake/example-chunk/sample-2/result.txt" ] || { echo "missing sample 2 result"; exit 1; }
[ "$(awk 'END{print NR}' "$tmp/runs/run_success/attempts.csv")" -eq 3 ] || { echo "expected two candidate attempts plus header"; exit 1; }

"$ROOT/bin/judge.sh" example-chunk fake run_success >/tmp/modelfit-test-judge.out || { cat /tmp/modelfit-test-judge.out; exit 1; }
[ "$(awk 'END{print NR}' "$tmp/runs/run_success/verdicts.csv")" -eq 3 ] || { echo "expected two verdicts plus header"; exit 1; }
# Judge cost must reflect .judge.price_in/.price_out. It was hardcoded to 0/0, which
# made judging look free in the report when it is usually the dominant cost.
awk -F, 'NR>1 {gsub(/"/,""); if ($3=="judge" && ($NF+0)>0) found=1} END{exit !found}' "$tmp/runs/run_success/attempts.csv" || {
  echo "judge attempts recorded zero cost despite judge pricing being configured"
  grep ',judge,' "$tmp/runs/run_success/attempts.csv"; exit 1; }
"$ROOT/bin/report.sh" --run-id run_success >/tmp/modelfit-test-report.out || { cat /tmp/modelfit-test-report.out; exit 1; }
grep -q 'Actual total' /tmp/modelfit-test-report.out || { cat /tmp/modelfit-test-report.out; exit 1; }

export MODELFIT_FAKE_SCENARIO=http_error
if MODELFIT_RUN_ID=run_fail "$ROOT/bin/run.sh" example-chunk fake >/tmp/modelfit-test-fail.out 2>&1; then
  cat /tmp/modelfit-test-fail.out
  echo "expected run failure"
  exit 1
fi
jq -e '.status=="partial"' "$tmp/runs/run_fail/manifest.json" >/dev/null || { cat "$tmp/runs/run_fail/manifest.json"; exit 1; }
# An HTTP failure must surface the provider's own message, not just the status code:
# curl runs with --fail-with-body, so the reason is already on disk. Regression guard.
grep -q 'rate limited' /tmp/modelfit-test-fail.out || {
  cat /tmp/modelfit-test-fail.out; echo "http_error did not surface the provider message"; exit 1; }
grep -q 'raw response:' /tmp/modelfit-test-fail.out || {
  cat /tmp/modelfit-test-fail.out; echo "http_error did not point at the raw response file"; exit 1; }

# Providers that hide reasoning tokens (Gemini's OpenAI-compatible endpoint) report
# completion_tokens EXCLUDING thinking while billing output INCLUDING it. Billed output
# must be total - prompt (120), not completion_tokens (20), or the cost column silently
# understates the most expensive models. price_out is 2, price_in 1, so 120 output
# tokens cost 0.000250 rather than 0.000050.
export MODELFIT_FAKE_SCENARIO=hidden_thinking
MODELFIT_RUN_ID=run_thinking "$ROOT/bin/run.sh" example-chunk fake --samples 1 >/tmp/modelfit-test-thinking.out 2>&1 ||
  { cat /tmp/modelfit-test-thinking.out; echo "hidden_thinking run failed"; exit 1; }
awk -F, 'NR>1 {gsub(/"/,""); if ($3=="candidate") { out=$13; cost=$NF } } END{
  if (out != 120) { print "billed output tokens was " out ", expected 120"; exit 1 }
  if (cost+0 < 0.00024 || cost+0 > 0.00026) { print "cost was " cost ", expected ~0.000250"; exit 1 }
}' "$tmp/runs/run_thinking/attempts.csv" || { cat "$tmp/runs/run_thinking/attempts.csv"; exit 1; }

unset MODELFIT_FAKE_SCENARIO
MODELFIT_RUN_ID=run_bad_judge "$ROOT/bin/run.sh" example-chunk fake >/tmp/modelfit-test-run2.out || { cat /tmp/modelfit-test-run2.out; exit 1; }
export MODELFIT_FAKE_SCENARIO=invalid_verdict
if "$ROOT/bin/judge.sh" example-chunk fake run_bad_judge >/tmp/modelfit-test-badjudge.out 2>&1; then
  cat /tmp/modelfit-test-badjudge.out
  echo "expected invalid verdict failure"
  exit 1
fi

echo "reliability tests passed"
