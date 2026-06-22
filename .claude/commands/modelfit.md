---
description: Benchmark candidate LLMs on THIS repo's real workflow and rank them
---

# /modelfit

You are driving **modelfit** inside the user's repository. Goal: find which LLM can
back up or replace their main coding model, judged on *their* stack, not generic
benchmarks. Pipeline: generate probes -> run candidates -> blind LLM-judge -> rank.

## Guardrails (always)
- NEVER write API keys into any file. Keys live only in `.env` (gitignored), referenced
  by `key_env` names in `config/models.json`.
- NEVER commit `runs/`, `.env`, or `config/models.json`.
- Anything that calls a model spends tokens. Confirm with the user before a full run.
- Run `bin/scan-secrets.sh` before suggesting any `git push`.

## Step 0 -- setup (once)
- If `config/models.json` is missing: `cp config/models.example.json config/models.json`,
  then help the user list the candidate models + a judge model (edit `model_id`,
  `base_url`, `price_in/out`; verify each against provider docs -- the examples are not verified).
- If `.env` is missing: `cp .env.example .env` and tell the user to paste their keys there.

## Step 1 -- build probes (the user picked one)
- **Auto from this repo:** read `prompts/generate-probes.md` and follow it -- inspect the
  codebase, then write 6-10 sharp `probes/<name>.md` files (each a `# PROMPT` + a
  `# RUBRIC` with one decisive discriminator). Show the user the list before running.
- **Manual:** point them at `prompts/generate-probes.md` Step 3 for the file format and
  the two example probes (`probes/example-*.md`).

## Step 2 -- run + judge (after the user confirms)
```bash
for p in probes/*.md; do
  n=$(basename "$p" .md)
  bin/run.sh   "$n" all     # POST the probe to every model, auto-escalate token cap
  bin/judge.sh "$n" all     # blind LLM-judge each answer against the rubric -> results.csv
done
bin/report.sh               # ranked leaderboard
```
Run a single probe/model while iterating: `bin/run.sh <probe> <model-key>`.

## Step 3 -- read the result
- Summarize `bin/report.sh` for the user: who passed, the cost/latency trade-off, and
  the one or two probes that actually separated the models (those are the decisions).
- Remind them correctness beats cost/latency: a cheap model that ships non-compiling code
  is not a backup.
- Offer to write a shareable summary (see `examples/REPORT-*.md` for the shape).
