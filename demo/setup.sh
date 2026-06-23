# Sourced by demo/demo.tape (and usable by hand) to drive ModelFit's built-in mock
# provider: no API keys, no network, fully deterministic output. Run from the repo root.
_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export PATH="$_root/tests:$PATH"            # tests/curl shadows real curl with canned responses
export DEMO_KEY=demo
export MODELFIT_CONFIG="$_root/demo/models.demo.json"
export MODELFIT_RUN_ID=demo
# Relative paths keep the demo output clean (no absolute machine path on screen).
# Run the tape from the repo root; .demo-runs / .demo-results.csv are gitignored.
export MODELFIT_RUNS_DIR=".demo-runs"
export MODELFIT_RESULTS_CSV=".demo-results.csv"
