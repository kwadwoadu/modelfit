#!/usr/bin/env bash
# modelfit -- doctor.sh [--repo PATH]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"

TARGET=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) shift; TARGET="${1:-}" ;;
    *) die "usage: doctor.sh [--repo PATH]" ;;
  esac
  shift
done
[ -n "$TARGET" ] || TARGET="${MODELFIT_TARGET_REPO:-}"

fail=0
ok(){ echo "  ok   $1"; }
bad(){ echo "  FAIL $1"; fail=1; }

echo "== modelfit doctor =="
if command -v jq >/dev/null; then ok "jq present"; else bad "jq missing"; fi
if command -v curl >/dev/null; then ok "curl present"; else bad "curl missing"; fi

if [ -f "$MODELFIT_CONFIG" ] && jq -e '.judge and (.models|type=="array")' "$MODELFIT_CONFIG" >/dev/null 2>&1; then
  ok "config has .judge and .models[]"
else
  bad "config missing or invalid: $MODELFIT_CONFIG"
fi

if [ -n "$TARGET" ]; then
  if [ ! -d "$TARGET" ]; then
    bad "target repo path is not a directory: $TARGET"
  else
    target_abs="$(cd "$TARGET" && pwd)"
    root_abs="$(cd "$ROOT" && pwd)"
    if [ "$target_abs" = "$root_abs" ] && [ "${MODELFIT_ALLOW_SELF_BENCHMARK:-0}" != "1" ]; then
      bad "target repo resolves to ModelFit itself; pass a real app repo or set MODELFIT_ALLOW_SELF_BENCHMARK=1"
    else
      ok "target repo: $(basename "$target_abs")"
      if git -C "$target_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ok "target is a git repo"
      else
        ok "target is readable but not a git repo"
      fi
    fi
  fi
else
  echo "  note no --repo supplied; use /modelfit --repo <path> when generating probes"
fi

if [ -f "$MODELFIT_CONFIG" ]; then
  while IFS= read -r envname; do
    [ -n "$envname" ] || continue
    if [ -n "${!envname:-}" ]; then ok "key env set: $envname"; else echo "  note key env not set: $envname"; fi
  done < <(jq -r '.judge.key_env, .models[].key_env' "$MODELFIT_CONFIG" 2>/dev/null | sort -u)
fi

echo "== $([ "$fail" -eq 0 ] && echo PASS || echo FAIL) =="
exit "$fail"
