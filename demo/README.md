# Demo

`demo.tape` records the ModelFit pipeline as a GIF using the **built-in mock provider**
(`tests/curl`), so it runs offline, spends no API budget, and is byte-for-byte
deterministic. Re-render it anytime a model or the CLI changes.

## Render
```bash
brew install vhs        # one-time; pulls ttyd + ffmpeg
vhs demo/demo.tape      # writes demo/demo.gif
```
Run from the repo root. ([VHS](https://github.com/charmbracelet/vhs) drives the terminal
from the `.tape` script.)

## What it shows
`selftest` (zero API spend) -> `run` one probe across two candidate models -> blind
`judge` against the rubric -> ranked `report`.

The two demo models (`model-a`, `model-b`) are mock entries in `demo/models.demo.json`,
and `demo/setup.sh` points ModelFit at the mock provider. A real run swaps in real
candidate + judge models via `config/models.json` and real API keys in `.env`; the
output format is identical.
