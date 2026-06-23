# Sourced by demo/demo.tape (and usable by hand) to drive ModelFit's built-in mock
# provider: no API keys, no network, fully deterministic output. Run from the repo root.
_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export PATH="$_root/tests:$PATH"            # tests/curl shadows real curl with canned responses
export DEMO_KEY=demo
export MODELFIT_CONFIG="$_root/demo/models.demo.json"
export MODELFIT_RUN_ID=demo
export MODELFIT_RUNS_DIR="$_root/.demo-runs"
export MODELFIT_RESULTS_CSV="$_root/.demo-results.csv"
