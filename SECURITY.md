# Security

ModelFit runs entirely on your machine. There is no server, no telemetry, and no
dependencies beyond `bash`, `jq`, and `curl`.

## Your keys and data
- API keys live only in `.env` (gitignored) and your shell. They are never written to a
  tracked file, and are sent only to the provider endpoints you set in `config/models.json`.
- Probe prompts go to each candidate provider; the task, rubric, and candidate answer go to
  the judge provider. Nothing is sent anywhere else.
- Generated probes may contain proprietary code from a target repo. Review probes before
  running or sharing them. Run `./bin/scan-secrets.sh` before publishing; it checks tracked
  files for key-shaped strings.

## Reporting a vulnerability
Please report security issues privately via GitHub's
[Report a vulnerability](https://github.com/kwadwoadu/modelfit/security/advisories/new) on
the Security tab. Do not open a public issue for sensitive reports.
