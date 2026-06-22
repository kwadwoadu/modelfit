# I benchmarked 3 cheap LLMs on my real coding work. Here is what happened.

*A worked example of [modelfit](../README.md). June 2026.*

## The question
Claude Opus is my main coding model. The cheap Chinese models (DeepSeek, Kimi, GLM)
cost a fraction of the price. **Could one of them quietly back up Opus for everyday
coding without me noticing the drop?**

Public benchmarks could not answer that, because they test *average* code, not *my*
SwiftUI, my Drizzle migrations, my Cloudflare Workers. So I built a tiny harness that
tests models on tasks shaped like my actual work, and grades them blind.

## The setup
- **8 tasks** pulled from how I really work: a surgical one-function edit, wiring a
  field through every layer of an app, an idiomatic database query, debugging from a
  stack trace, a multi-constraint task, an honesty trap, a translation, a Cloudflare
  Worker.
- Each task has a **rubric** with one decisive thing a weaker model gets subtly wrong.
- Every model gets the same prompt. The answers are graded against the rubric.
- **Opus 4.8 is the baseline** (the bar to clear). The three challengers: **DeepSeek,
  Kimi, GLM**.

## The scoreboard

| Task | DeepSeek | Kimi | GLM | Opus (bar) |
|------|:--------:|:----:|:---:|:----------:|
| Surgical edit | PASS | PASS | PASS | PASS |
| Constraint adherence | PASS | PASS | PASS | PASS |
| Honesty (false premise) | PASS | PASS | PASS | PASS |
| Database query (ORM) | PASS | PASS | PASS | PASS |
| Translations | PASS | FAIL | FAIL | PASS |
| Debug from stack trace | FAIL | FAIL | FAIL | PASS |
| Cloudflare Worker | PASS | PASS | **FAIL** | PASS |
| Multi-file consistency | PASS | PASS | **FAIL** | PASS |
| **Correct out of 8** | **7** | **6** | **4** | **8** |

```
Correctness (8 tasks)
Opus      ████████  8/8   the bar
DeepSeek  ███████░  7/8
Kimi      ██████░░  6/8
GLM       ████░░░░  4/8
```

## The three things that surprised me

**1. Cheap and fast does not mean correct.** GLM was the fastest and cheapest on every
single task. It was also the only one that shipped code that *does not compile* on the
two hardest problems. On the Worker it called a function it never wired in; on the
multi-file task it used a helper it forgot to import. Same mistake twice: it
pattern-matches the right idea, then fails to connect the wiring. Fast and wrong is not
a backup.

**2. The best code can still let you down.** DeepSeek wrote the highest-quality code of
the three. But it "thinks" so much that on one task it spent its entire output budget
reasoning and returned a completely **empty answer** at a normal setting. Brilliant, but
it can silently hand you nothing if you do not give it room.

**3. The quiet one won.** Kimi was never the flashiest, never the cheapest, never the
fastest. It was also never broken. Its only miss was a single translation typo. For a
tool I would leave running unattended, "boringly reliable" beats "brilliant but
temperamental."

## My verdict

> **For a cheap backup to Claude on routine coding: Kimi.** Reliable, sane cost and
> speed, never shipped broken code.
> Reach for **DeepSeek** when you want the single most thorough answer and can give it
> room and patience. Use **GLM** only for trivial edits you will eyeball yourself.
> None of them replaces Opus on the hard reasoning tasks. That gap is still real.

The whole run cost a few cents and about an hour. The point is not my answer. It is that
**you can get your own answer, for your own stack, in an afternoon, and re-run it the day
a new model drops.**

## Want to run this on YOUR workflow?
I packaged the harness as **modelfit** (open source, MIT). You bring your own models
(any OpenAI- or Anthropic-compatible model: GPT, Gemini, Llama, DeepSeek, Kimi, GLM,
anything on OpenRouter) and your own work. The fastest path:

1. Clone the repo and open it in Claude Code.
2. Say *"generate modelfit probes from this repo."* It reads your codebase and writes
   the tasks for you.
3. Paste your API keys into `.env`, run one command, read the leaderboard.

No keys ever touch the repo. Correctness always beats cost. See the
[README](../README.md) to get going.
