# AGENTS.md

Guidance for AI coding agents (Codex, Claude Code, Cursor, Aider, and similar) working in
this repository. ModelFit benchmarks LLMs on a *target* codebase to decide which model can
back up or replace a primary coding model. Public benchmarks rank average code; ModelFit
ranks correctness on the user's actual work.

## Your job in this repo
When a user opens ModelFit and asks to benchmark models on their codebase:

1. **Generate probes from their target repo.** Read `prompts/generate-probes.md` and follow
   it: inspect the target repository the user names, then write 6-10 sharp `probes/<name>.md`
   files. Each probe is a `# PROMPT` sent verbatim to every candidate model plus a `# RUBRIC`
   the judge grades against. Every probe must encode one decisive discriminator: the subtle
   thing a weaker model gets wrong. Show the user the probe list before running anything.
2. **Run the pipeline** (only after the user confirms; this spends API tokens):
   ```bash
   ./bin/modelfit doctor --repo ../their-app      # check config, keys, providers
   for p in probes/*.md; do
     n=$(basename "$p" .md)
     ./bin/modelfit run   "$n" all --samples 1     # candidates answer each probe
     ./bin/modelfit judge "$n" all                 # blind LLM-judge vs the rubric
   done
   ./bin/modelfit report                            # coverage-aware leaderboard
   ```
   Iterate on a single probe/model with `./bin/modelfit run <probe> <model-key> --samples 1`.
3. **Read the result back for the user**: who passed, the cost and latency trade-off, and the
   one or two probes that actually separated the models. Correctness beats cost: a cheap model
   that ships non-compiling code is not a usable backup.

Full CLI: `./bin/modelfit <doctor|run|judge|report|selftest|scan-secrets>`.

## Setup (once)
- `cp config/models.example.json config/models.json`, then edit the candidate models and the
  judge. `key_env` holds the NAME of the env var that stores each key, never a key itself.
  Verify every `model_id`, `base_url` and price against the provider's own docs; the shipped
  values are placeholders.
- `cp .env.example .env` and have the user paste their API keys there.

## Guardrails (do not violate)
- **Never write an API key into any tracked file.** Keys live only in `.env` (gitignored),
  referenced by `key_env` names in `config/models.json`.
- **Never commit** `.env`, `config/models.json`, `runs/`, or `results.csv` (all gitignored).
- **Confirm before spending tokens.** `run` and `judge` call paid model APIs.
- **Generated probes may contain proprietary code, customer data, or secrets** copied from the
  target repo. Surface this and let the user review the probes before they are run or committed.
- Run `./bin/scan-secrets.sh` before suggesting any `git push`.

## Where things live
- `prompts/generate-probes.md` - the probe generator you follow in step 1.
- `.claude/commands/modelfit.md` - the `/modelfit` slash command (Claude Code).
- `prompts/judge-system.md` - the blind judge's system prompt.
- `README.md` - full human-facing docs. `docs/limitations.md` - what ModelFit is not.

Validate the plumbing anytime with zero API spend: `./bin/modelfit selftest`.
