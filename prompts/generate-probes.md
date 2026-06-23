# Generate ModelFit probes from a TARGET repository

You are running inside the ModelFit repository. Your job is to turn a separate target codebase into 6–10 sharp probes.

Target selection is mandatory:
- Prefer the slash command form: `/modelfit --repo <path-to-target-repo>`.
- If this prompt is pasted manually, read `MODELFIT_TARGET_REPO` or ask for the target path.
- Resolve the target path before reading. If it resolves to the ModelFit repository itself, stop unless the user explicitly says they want to benchmark ModelFit.

A probe is one self-contained `.md` file in ModelFit’s `probes/` directory with two sections: `# PROMPT` and `# RUBRIC`. The prompt is sent verbatim to candidate models; the rubric is used by the judge.

Before writing probes, warn the user: generated probes may contain proprietary code or customer/personal data and will be sent to configured providers during a run. They must review probes before spending API tokens.

## Step 1 — Understand the target repo

- Detect languages, frameworks and the 2–3 most important libraries.
- Find conventions a newcomer would get wrong: naming, file layout, error handling, tests, migrations and agent instructions.
- Look at recurring task shapes in git history and TODOs: surgical edit, cross-layer field, ORM/API call, stack-trace debug, constraint task, false-premise honesty check.

## Step 2 — Choose 6 to 10 probes

Cover:
1. Surgical edit.
2. Cross-layer consistency.
3. Idiomatic query/API call.
4. Debug from a trace.
5. Constraint adherence.
6. Honesty/false premise.
7. Optional repo-specific discriminator.

## Step 3 — Write probes

Use exactly this shape:

```
---
id: short-kebab-name
category: surgical-correctness
scoring: judge
target_repo: <basename only>
target_commit: <git sha or unknown>
generated_at: <UTC timestamp>
---

# PROMPT
<closed-ended task text with all context needed to grade from the answer alone>

# RUBRIC
Discriminator: <one sentence>

PASS requires ALL of:
- M1 <objective criterion>
- M2 <objective criterion>

FAIL if: <specific traps>

Quality pluses: <nice-to-haves>
```

Rules:
- Every M criterion must be checkable from the answer text alone.
- Name failure modes explicitly.
- Do not include secrets, full customer records or unnecessary large source dumps.
- Keep one decisive discriminator per probe.

## Step 4 — Hand back

Show the probe list and tell the user to review sensitive content before running:

```bash
./bin/modelfit run <probe> <model-key> --samples 1
./bin/modelfit judge <probe> <model-key>
./bin/modelfit report
```

Do not run anything that spends provider API tokens without explicit approval.
