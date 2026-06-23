# Contributing

Thanks for helping make ModelFit better.

## Ground rules
- `./bin/modelfit selftest` must pass before and after your change (zero API spend).
- Keep it dependency-light: `bash` + `jq` + `curl` only, no frameworks.
- One focused change per PR; explain the *why* in the description.
- Run `./bin/scan-secrets.sh` before you push, so no keys are staged.

## Adding a probe
A probe is a `probes/<name>.md` file with a `# PROMPT` (sent verbatim to each candidate
model) and a `# RUBRIC` (what the judge grades against). A good probe encodes one decisive
discriminator: the subtle thing a weaker model gets wrong. See `probes/example-*.md` and
`prompts/generate-probes.md`.

## Questions
Open a [Discussion](https://github.com/kwadwoadu/modelfit/discussions) for questions or
ideas; use Issues for bugs.
