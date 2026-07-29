---
description: Generate repo-specific ModelFit probes and run/judge them after approval
---

# /modelfit

Usage: `/modelfit --repo <path-to-target-repo>`

You are driving **ModelFit** to benchmark candidate LLMs on a user's actual codebase, not on ModelFit itself.

## Step 0a — locate the ModelFit checkout

This command may be invoked from anywhere, so never assume the working directory is the
ModelFit repo. Resolve `MODELFIT_HOME` in this order and `cd` there before running anything:

1. `$MODELFIT_HOME`, if set and it contains `bin/modelfit`.
2. The current repo, if the working directory is inside a ModelFit checkout.
3. Otherwise ask the user where ModelFit is checked out. Do not guess a path.

Every command below assumes you are in that directory. Use `"$MODELFIT_HOME/bin/modelfit"`
when you need to call it from elsewhere.

## Guardrails

- A target repo is required. Resolve `--repo`; if omitted, ask for it.
- If the target resolves to the ModelFit repository itself, stop unless the user explicitly confirms self-benchmarking.
- Never write API keys into tracked files. Keys live in shell env or `.env`, referenced by `key_env` in `config/models.json`.
- Never commit `runs/`, `.env`, `config/models.json` or `results.csv`.
- Generated probes may contain proprietary data and will be sent to model providers during a run. Tell the user to review probes before running.
- Anything that calls configured models spends tokens. Confirm before run/judge.
- Run `bin/scan-secrets.sh` before suggesting any push.

## Step 0b — setup

If needed:

```bash
cp config/models.example.json config/models.json
cp .env.example .env
./bin/modelfit doctor --repo <target>
```

`doctor` reads `.env`, so a key set there reports as `key env set`. If it reports
`key env not set`, the variable really is missing from both `.env` and the shell.

Verify every `model_id` is one the configured key can actually reach before a full run.
A model the account cannot access fails at request time, not at config time.

## Step 1 — build probes

Read `prompts/generate-probes.md` and follow it against the resolved target repo. Write 6-10 probes into the ModelFit `probes/` directory. Show the list before any model run.

## Step 2 — run + judge after approval

Smoke first:

```bash
./bin/modelfit run <probe> <model-key> --samples 1
./bin/modelfit judge <probe> <model-key>
./bin/modelfit report
```

Full run:

```bash
for p in probes/*.md; do
  n=$(basename "$p" .md)
  ./bin/modelfit run "$n" all --samples 1
  ./bin/modelfit judge "$n" all
done
./bin/modelfit report
```

On failure, `run`/`judge` print the provider's own error message plus the path to the raw
response. Read that message before changing anything: it distinguishes a billing problem
from a bad key from an unavailable model, which need different fixes.

## Step 3 — summarize

Report who passed, coverage gaps, incomplete attempts, candidate cost, judge cost and the probes that separated models. Remind the user that correctness beats cost/latency, and that any cost column is only as trustworthy as the unverified `price_in`/`price_out` values in `config/models.json`.
