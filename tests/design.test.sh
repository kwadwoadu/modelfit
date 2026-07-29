#!/usr/bin/env bash
# modelfit -- design.test.sh
# Prove scoring: screenshot probes render + judge with NO browser and NO network:
# a stub MODELFIT_RENDER_CMD writes a valid PNG, the mock provider returns the verdict.
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
    "token_param": "max_tokens"
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

# A design probe fixture with scoring: screenshot and M1..M5 (matches the mock verdict).
probe="$ROOT/probes/design-test-fixture.md"
cat > "$probe" <<'MD'
---
id: design-test-fixture
category: design
scoring: screenshot
---

# PROMPT
Output ONLY a self-contained HTML document with a single centered heading.

# RUBRIC
Discriminator: renders at all.

PASS requires ALL of:
- M1 renders
- M2 renders
- M3 renders
- M4 renders
- M5 renders

FAIL if: blank.
MD
trap 'rm -rf "$tmp"; rm -f "$probe"' EXIT

# Stub renderer: decode a minimal 1x1 PNG to {OUT}. No browser needed.
png_stub="$tmp/render-stub.sh"
cat > "$png_stub" <<'STUB'
#!/usr/bin/env bash
out="$1"
b64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
printf '%s' "$b64" | base64 -d > "$out"
STUB
chmod +x "$png_stub"

export PATH="$ROOT/tests:$PATH"
export TEST_API_KEY="test-key"
export MODELFIT_CONFIG="$config"
export MODELFIT_RUNS_DIR="$tmp/runs"
export MODELFIT_RESULTS_CSV="$junk_results"
export MODELFIT_RENDER_CMD="$png_stub {OUT}"

sd="$tmp/runs/run_design/fake/design-test-fixture/sample-1"

MODELFIT_RUN_ID=run_design "$ROOT/bin/run.sh" design-test-fixture fake >/tmp/modelfit-design-run.out 2>&1 || { cat /tmp/modelfit-design-run.out; echo "expected run success"; exit 1; }
[ -f "$sd/result.html" ] || { echo "missing result.html"; exit 1; }
[ -f "$sd/result.png" ] || { echo "missing result.png"; exit 1; }
[ -s "$sd/result.png" ] || { echo "empty result.png"; exit 1; }
jq -e '.rendered==true and .screenshot=="result.png"' "$sd/candidate.meta.json" >/dev/null || { cat "$sd/candidate.meta.json"; echo "meta not marked rendered"; exit 1; }

"$ROOT/bin/judge.sh" design-test-fixture fake run_design >/tmp/modelfit-design-judge.out 2>&1 || { cat /tmp/modelfit-design-judge.out; echo "expected judge success"; exit 1; }
[ "$(awk 'END{print NR}' "$tmp/runs/run_design/verdicts.csv")" -eq 2 ] || { cat "$tmp/runs/run_design/verdicts.csv"; echo "expected one verdict plus header"; exit 1; }

# Negative: renderer that produces nothing -> render_error and nonzero exit.
export MODELFIT_RENDER_CMD="/bin/false"
if MODELFIT_RUN_ID=run_design_fail "$ROOT/bin/run.sh" design-test-fixture fake >/tmp/modelfit-design-fail.out 2>&1; then
  cat /tmp/modelfit-design-fail.out
  echo "expected render failure"
  exit 1
fi
grep -q 'render_error' "$tmp/runs/run_design_fail/attempts.csv" || { cat "$tmp/runs/run_design_fail/attempts.csv"; echo "expected render_error outcome"; exit 1; }
[ -f "$tmp/runs/run_design_fail/fake/design-test-fixture/sample-1/result.html" ] || { echo "expected result.html kept on render failure"; exit 1; }

echo "design tests passed"
