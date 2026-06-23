# ModelFit demo  ->  offline, deterministic GIF via the built-in mock provider.
# Render from the repo root:  brew install vhs && vhs demo/demo.tape   (writes demo/demo.gif)
# No API keys, no network: tests/curl returns canned responses (see demo/setup.sh).

Output demo/demo.gif

Set Shell "bash"
Set FontSize 18
Set Width 1120
Set Height 760
Set Padding 20
Set TypingSpeed 40ms
Set Theme "Dracula"

Type "# ModelFit: benchmark any LLM on YOUR codebase, ranking correctness before cost."
Enter
Sleep 1200ms
Type "# (this demo uses a built-in mock provider -- no keys, no network)"
Enter
Sleep 1200ms
Enter

Type "./bin/modelfit selftest"
Enter
Sleep 2500ms

# Point ModelFit at the mock provider, off-screen, so the commands below stay clean.
Hide
Type "source demo/setup.sh && rm -rf .demo-runs .demo-results.csv && clear"
Enter
Show

Type "# 1. run one probe across the candidate models"
Enter
Type "./bin/modelfit run example-chunk all --samples 1"
Enter
Sleep 2500ms

Type "# 2. blind-judge each answer against the probe's rubric"
Enter
Type "./bin/modelfit judge example-chunk all demo"
Enter
Sleep 2500ms

Type "# 3. rank: correctness first, then quality, then cost"
Enter
Type "./bin/modelfit report --run-id demo"
Enter
Sleep 5000ms

Hide
Type "rm -rf .demo-runs .demo-results.csv"
Enter
Show
Sleep 800ms
