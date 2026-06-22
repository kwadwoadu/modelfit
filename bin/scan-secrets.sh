#!/usr/bin/env bash
# modelfit -- scan-secrets.sh
# Refuse to publish if anything secret-shaped is tracked by git. Run before every
# push. Checks: (1) .env / real config are gitignored, (2) no key-shaped strings
# in tracked files, (3) runs/ outputs are not tracked.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bad=0
flag(){ echo "  LEAK $1"; bad=1; }
ok(){ echo "  ok   $1"; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "scan-secrets: not a git repo yet (nothing tracked) -- safe to init"; exit 0
fi

tracked="$(git ls-files)"

# 1. sensitive files must NOT be tracked
for f in .env config/models.json; do
  if printf '%s\n' "$tracked" | grep -qx "$f"; then flag "$f is tracked (should be gitignored)"; else ok "$f not tracked"; fi
done
if printf '%s\n' "$tracked" | grep -q '^runs/'; then flag "runs/ outputs are tracked"; else ok "runs/ not tracked"; fi

# 2. key-shaped strings in tracked files (skip docs that legitimately show placeholders)
#    Patterns: OpenAI sk-..., Anthropic sk-ant-..., generic 32+ hex/base64 after KEY=
pat='sk-[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|(API_KEY|SECRET|TOKEN)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_\-]{24,}'
hits=""
while IFS= read -r f; do
  case "$f" in
    *.example.*|.env.example|*.md) continue ;;  # placeholders allowed in examples/docs
  esac
  if grep -nEq "$pat" "$f" 2>/dev/null; then hits="$hits$f\n"; fi
done <<< "$tracked"
if [ -n "$hits" ]; then printf "%b" "$hits" | sed '/^$/d' | while read -r f; do flag "key-shaped string in $f"; done; bad=1; else ok "no key-shaped strings in tracked code"; fi

echo "== $([ $bad -eq 0 ] && echo CLEAN || echo LEAKS-FOUND) =="
exit $bad
