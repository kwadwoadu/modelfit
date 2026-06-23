# ModelFit

**Find the best LLM for your codebase—not someone else’s benchmark.**

![ModelFit running a probe across two models, blind-judging the answers, and ranking them](demo/demo.gif)

> Demo above runs offline against a built-in mock provider (no keys, no network). Reproduce it with `vhs demo/demo.tape` — see [`demo/`](demo/).

ModelFit runs repo-specific coding probes across candidate models, grades their answers blindly against explicit rubrics, and ranks correctness before cost and latency. Public benchmarks measure average code; ModelFit asks whether a cheaper or secondary model can handle *your* SwiftUI, *your* Drizzle migrations, *your* Cloudflare Worker, and *your* failure modes.

```
target repo ──▶ probes (PROMPT + RUBRIC) ──▶ run.sh ──▶ candidate answers
                                                              │
        attempts.csv + verdicts.csv ◀── judge.sh ◀────────────┘
                    │
                report.sh ──▶ coverage-aware leaderboard
```

## Why it is different

- **Your workflow, not a generic suite.** Probes are generated from a target repo you name explicitly.
- **Any compatible model.** OpenAI-compatible `/chat/completions` and Anthropic-compatible `/v1/messages` endpoints.
- **Blind rubric grading.** The judge sees the task, rubric and answer, not the candidate model name.
- **Correctness first.** Cost and latency never rescue a correctness loss.
- **Auditable runs.** Every run gets an immutable run ID, per-sample outputs, attempt ledger and verdict ledger.

## Security and data boundary

ModelFit is designed so secrets and run outputs are excluded from Git by default, but no local tool can guarantee you will never leak sensitive data.

- `config/models.json` stores only the environment variable names that hold keys. The real keys live in your shell or `.env`, which is gitignored.
- `.env`, `config/models.json`, `runs/` and `results.csv` are ignored.
- `bin/scan-secrets.sh` checks tracked files for common secret-shaped strings before publishing.
- Generated probes may contain proprietary code, customer data, credentials or personal data. Review probes before running them.
- Probe prompts are sent to each configured candidate provider. Task, rubric and candidate answer are sent to the judge provider.

## Quickstart

```bash
git clone https://github.com/kwadwoadu/modelfit.git
cd modelfit
brew install jq shellcheck   # shellcheck optional, used by CI/self-review

./bin/selftest.sh            # zero API spend; includes mock-provider tests

cp config/models.example.json config/models.json   # edit models + judge
cp .env.example .env                                # paste keys; never commit
./bin/modelfit doctor --repo ../your-app
```

Generate probes with Claude Code from the ModelFit repo:

```text
/modelfit --repo ../your-app
```

Then smoke-test one probe/model before the full suite:

```bash
./bin/modelfit run example-chunk fake-model-key --samples 1
./bin/modelfit judge example-chunk fake-model-key
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

If one model fails, the batch continues where possible but exits non-zero and the report shows incomplete coverage.

## Add your workflow

1. **Agent-generated probes.** Run `/modelfit --repo ../your-app`. The command inspects the target repository, writes 6–10 probes into `probes/`, and records non-sensitive provenance.
2. **Manual probes.** Copy `probes/example-*.md`: a `# PROMPT` sent to each model and a `# RUBRIC` the judge grades against.

A good probe has one decisive discriminator: the subtle thing a weaker model gets wrong.

## How scoring works

- `run.sh` sends each probe to candidates, strips markdown fences, retries empty/truncated replies up to the token ceiling, and records every attempt in `runs/<run-id>/attempts.csv`.
- `judge.sh` sends task + rubric + untrusted candidate answer to the judge, validates strict JSON verdicts, and writes `runs/<run-id>/verdicts.csv`.
- `report.sh` ranks by pass percentage, quality and candidate cost, while showing judged count, attempts, incomplete attempts and actual recorded total cost.
- Candidate cost, judge cost and retry cost are tracked from provider token usage when available. Missing usage is `NA`, not zero.

## Limitations

- LLM judges are useful but not objective. Blind labels reduce model-identity bias; they do not remove style bias or prompt-injection risk.
- Judge-only probes do not execute candidate code. If compilation is decisive, add an executable gate in a future probe.
- Prices in `config/models.example.json` are placeholders. Verify provider pricing before trusting cost comparisons.
- One sample is not statistical confidence. Use `--samples N` when run-to-run variance matters.
- Provider “compatibility” varies. Use `./bin/modelfit doctor` and a smoke probe before a large run.

## Layout

```
modelfit/
├─ bin/    modelfit run.sh judge.sh report.sh doctor.sh selftest.sh scan-secrets.sh
├─ bin/lib/common.sh
├─ config/ models.example.json
├─ probes/ example-honesty.md example-chunk.md
├─ prompts/ generate-probes.md judge-system.md
├─ tests/ mock-provider reliability tests
├─ .claude/commands/modelfit.md
├─ examples/ results.example.csv .env.example .gitignore LICENSE
```

MIT licensed. Built by Kwadwo Adu.
