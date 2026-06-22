# Generate modelfit probes from THIS repository

You are running inside a user's codebase. Your job: turn how *they* actually work
into a small set of **probes** that will reveal which LLM can back up or replace
their main coding model. Generic benchmarks measure average code. modelfit measures
*their* stack, *their* conventions, *their* failure modes.

A probe is one self-contained `.md` file in `probes/` with two sections: a `# PROMPT`
sent verbatim to each candidate model, and a `# RUBRIC` an automated judge grades
against. The whole point is that the rubric encodes a **single decisive
discriminator** -- the thing a weaker model gets subtly wrong -- not a vague "is it
good".

## Step 1 -- Understand this repo (read, do not assume)
- Detect the languages, frameworks, and the 2-3 libraries that show up most
  (e.g. SwiftUI + Drizzle/Postgres, Next.js App Router, Cloudflare Workers, Rust + axum).
- Find the conventions a newcomer would get wrong: naming (camelCase vs snake_case
  mapping, file layout), error-handling style, how migrations/tests/imports are done,
  any house rules in CLAUDE.md / CONTRIBUTING / lint config.
- Note the recurring *task shapes* in git history and TODOs: "add a field across
  layers", "fix a crash from a stack trace", "write an ORM query", "a small surgical
  edit to one function". These become probes.

## Step 2 -- Choose 6 to 10 probes across these axes
Aim for coverage, not volume (small enough that they will actually re-run it):
1. **Surgical edit** -- change one function minimally, do not restructure the file.
2. **Cross-layer consistency** -- wire one field/feature through every layer (schema -> migration -> API -> UI) with the naming mapping kept identical.
3. **Idiomatic query / API call** -- the ORM/SDK call their codebase would actually write, including the trap a naive version falls into.
4. **Debug from a trace** -- give a real stack trace + the buggy function; the discriminator is the *root cause*, not a plausible-looking nearby bug.
5. **Constraint adherence** -- a task with 5-6 hard constraints; PASS requires all of them.
6. **Honesty / false premise** -- embed a confident but false claim about their stack; PASS = the model refuses to play along instead of fabricating.
7. (optional) **Taste / refactor**, **multi-file coherence**, **perf**, whatever dominates their work.

## Step 3 -- Write each probe file as `probes/<short-kebab-name>.md`
Use EXACTLY this shape:

```
---
id: cross-layer-pin
category: cross-layer-consistency
scoring: judge          # judge = LLM-graded against the rubric; gate = self-checks via a command
---

# PROMPT
<the exact text the candidate model receives. Be specific and closed-ended.
Demand an exact output shape so the judge can grade it. No "be helpful" filler.>

# RUBRIC
The discriminator (one line: the subtle thing a weaker model gets wrong).

PASS requires ALL of:
- M1 <objective, checkable criterion>
- M2 <...>
- M3 <...>

FAIL if: <the specific traps -- name them: wrong naming mapping, non-compiling code,
hard-set instead of toggle, accepts the false premise, etc.>

Quality pluses (do not gate, just rank): <nice-to-haves>
```

Rules for good rubrics:
- Every M-criterion must be checkable from the answer text alone (the judge sees only
  the answer, not your repo). Bake the needed context into the PROMPT.
- Name the failure modes explicitly. "Uses camelCase column name in SQL = FAIL" beats
  "should be consistent".
- Non-compiling / non-running code is always a FAIL -- say so when relevant.
- Keep one decisive discriminator per probe. If you can't name what a weaker model
  would get wrong, the probe is too soft -- sharpen or drop it.

## Step 4 -- Wire it up
- Make sure `config/models.json` exists (copy `config/models.example.json`) and lists
  the candidate models + a judge model, with `key_env` names only (never paste keys).
- Tell the user the run command:
  `for p in probes/*.md; do n=$(basename "$p" .md); bin/run.sh "$n" all && bin/judge.sh "$n" all; done && bin/report.sh`
- Do NOT run anything that spends API tokens without the user's go-ahead. Do NOT write
  keys anywhere. Do NOT commit `runs/`, `.env`, or `config/models.json`.

## Step 5 -- Sanity self-check before handing back
For each probe you wrote, ask: "Could a strong model and a weak model both PASS this?"
If yes, the discriminator is too weak -- rewrite it. The benchmark is only useful when
the probes actually separate models.
