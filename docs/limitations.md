# ModelFit limitations

ModelFit is a practical decision tool, not a formal scientific benchmark.

- LLM judges can be wrong. Blind labels hide the candidate name, but style can still leak identity.
- Candidate answers are untrusted data. ModelFit isolates them in the judge prompt and validates JSON, but prompt injection remains a residual risk.
- Judge-only probes do not compile or execute code. Use executable gates for tasks where runtime behavior is the source of truth.
- Provider compatibility varies even when an endpoint is OpenAI- or Anthropic-shaped.
- Token usage and prices may be missing or stale. Missing cost is shown as `NA`, never zero.
- One sample is not enough to prove a stable ranking. Use repeated samples when decisions are close.
- Generated probes may contain proprietary code or sensitive data. Review before sending to providers.
- Visual judging (`scoring: screenshot`) is subjective and single-viewport: the judge grades one rendered screenshot at one resolution. Screenshots do not test interactivity, hover/focus states, animation, or any JS behavior beyond the initial render.
