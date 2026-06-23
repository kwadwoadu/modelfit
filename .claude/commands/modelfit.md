---
description: Generate repo-specific ModelFit probes and run/judge them after approval
---

# /modelfit

Usage: `/modelfit --repo <path-to-target-repo>`

You are driving **ModelFit** from this repository. Goal: benchmark candidate LLMs on a user’s actual codebase, not on ModelFit itself.

## Guardrails

- A target repo is required. Resolve `--repo`; if omitted, ask for it.
- If the target resolves to this ModelFit repository, stop unless the user explicitly confirms self-benchmarking.
- Never write API keys into tracked files. Keys live in shell env or `.env`, referenced by `key_env` in `config/models.json`.
- Never commit `runs/`, `.env`, `config/models.json` or `results.csv`.
- Generated probes may contain proprietary data and will be sent to model providers during a run. Tell the user to review probes before running.
- Anything that calls configured models spends tokens. Confirm before run/judge.
- Run `bin/scan-secrets.sh` before suggesting any push.

## Step 0 — setup

If needed:

```bash
cp config/models.example.json config/models.json
cp .env.example .env
./bin/modelfit doctor --repo <target>
```

## Step 1 — build probes

Read `prompts/generate-probes.md` and follow it against the resolved target repo. Write 6–10 probes into this repository’s `probes/` directory. Show the list before any model run.

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

## Step 3 — summarize

Report who passed, coverage gaps, incomplete attempts, candidate cost, judge cost and the probes that separated models. Remind the user that correctness beats cost/latency.
