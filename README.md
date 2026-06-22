# modelfit

**Stop guessing which LLM can back up your main coding model. Test it on YOUR actual work.**

Public benchmarks rank *average* code. They don't tell you whether a cheap model can
write *your* SwiftUI, *your* Drizzle migrations, *your* Cloudflare Worker, the way your
codebase actually does it. modelfit is a tiny, bring-your-own-workflow harness: you turn
how you work into a handful of sharp **probes**, fire them at any set of models, and an
automated **judge** ranks them, blind, on correctness first and cost second.

It started as a private suite one engineer used to pick a backup for Claude Code Opus.
This is the shareable, any-model version.

```
your repo ──▶ probes (PROMPT + RUBRIC) ──▶ run.sh ──▶ each model answers
                                                          │
                          results.csv ◀── judge.sh ◀──────┘  (blind LLM-judge vs the rubric)
                               │
                          report.sh ──▶ ranked leaderboard
```

## Why it's different
- **Your workflow, not a generic suite.** Probes are generated from *your* repo (or written by hand).
- **Any model.** OpenAI-compatible (`/chat/completions`: OpenAI, Gemini, Llama, Mistral, all of OpenRouter) and Anthropic-compatible (`/v1/messages`: Claude, DeepSeek, Kimi, GLM).
- **Automated, blind grading.** An LLM-judge scores each answer against a rubric and never sees which model wrote it.
- **Correctness over vibes.** Non-compiling code fails no matter how cheap or fast. Cost/latency never override a correctness loss.

## Security (read this)
This repo is meant to be shared publicly. It is built so you can't leak a key by accident:
- **No keys in the repo, ever.** `config/models.json` stores only the *name* of the env var that holds each key (`key_env`). The actual keys live in `.env`, which is gitignored.
- `.env`, `config/models.json`, and `runs/` (model outputs) are all gitignored.
- `bin/scan-secrets.sh` refuses to bless a repo where anything secret-shaped is tracked. Run it before every push.

## Quickstart
```bash
git clone <this-repo> && cd modelfit
brew install jq          # the only dependency besides curl + bash

./bin/selftest.sh        # proves the plumbing with ZERO API spend

cp config/models.example.json config/models.json   # edit: your models + a judge
cp .env.example .env                                # paste your API keys here (gitignored)

# run the two example probes across your models, judge them, rank:
for p in probes/*.md; do n=$(basename "$p" .md); ./bin/run.sh "$n" all && ./bin/judge.sh "$n" all; done
./bin/report.sh
```

## Add YOUR workflow (two ways)
1. **Let your Claude Code build them.** Open this repo in Claude Code (or paste
   `prompts/generate-probes.md`) and say *"generate modelfit probes from this repo."* It
   reads your codebase and writes 6-10 probes tuned to your stack and conventions. With
   the bundled slash-command, just run `/modelfit`.
2. **Write them by hand.** Copy the shape of `probes/example-*.md`: a `# PROMPT` (sent
   verbatim to each model) and a `# RUBRIC` (PASS criteria the judge grades against). The
   rule of thumb: each probe should encode one *decisive discriminator* -- the subtle
   thing a weaker model gets wrong.

## How scoring works
- `run.sh` POSTs each probe to every model, strips markdown fences, and on an empty or
  truncated reply **auto-escalates the token cap** (`MODELFIT_MAX_TOKENS` -> ceiling) so a
  reasoning-heavy model can't silently return nothing.
- `judge.sh` sends the task + rubric + the answer (author hidden) to the judge model and
  parses a strict JSON verdict: `correctness_pass`, `instruction_following` (0-5),
  `quality` (0-5), per-criterion checks, notes. Rows append to `results.csv`.
- `report.sh` ranks by **pass% desc, then quality desc, then cost asc.** Cost and latency
  never rescue a correctness failure.
- Cost is `tokens x price` from `config/models.json`. **Verify those prices** against each
  provider -- the examples shipped are placeholders, not confirmed.

## Layout
```
modelfit/
├─ bin/    run.sh  judge.sh  report.sh  selftest.sh  scan-secrets.sh
├─ config/ models.example.json        # copy to models.json (gitignored)
├─ probes/ example-honesty.md  example-chunk.md
├─ prompts/ generate-probes.md  judge-system.md
├─ .claude/commands/modelfit.md       # the /modelfit slash-command
├─ examples/                          # a real, shareable run write-up
├─ results.example.csv  .env.example  .gitignore  LICENSE
```

## Good probes, briefly
A probe is useful only if a strong model and a weak model would score *differently* on
it. Cover a spread: a surgical one-function edit, a field wired through every layer, an
idiomatic ORM/SDK call (with the trap a naive version hits), a debug-from-stack-trace
where the discriminator is the *root cause*, a multi-constraint task, and an honesty /
false-premise check. Keep it to ~6-10 so you'll actually re-run it when a new model drops.

MIT licensed. Built by Kwadwo Adu.
