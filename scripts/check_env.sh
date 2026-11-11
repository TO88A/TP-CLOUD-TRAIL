#!/usr/bin/env bash
# scripts/check_env.sh — Étape 0 : vérifie les outils et LocalStack.
set -euo pipefail
source "$(dirname "$0")/tools.sh"
cd "$TP_ROOT"

ok=1
line() { printf "  %-12s %s\n" "$1" "$2"; }

echo "== Outils"
line docker    "$(docker --version 2>/dev/null || { ok=0; echo ABSENT; })"
line terraform "$(tf version 2>/dev/null | head -1 || { ok=0; echo ABSENT; })"
line checkov   "$(checkov --version 2>/dev/null | tail -1 || { ok=0; echo ABSENT; })"
line trivy     "$(trivy --version 2>/dev/null | head -1 || { ok=0; echo ABSENT; })"
line conftest  "$(conftest --version 2>/dev/null | tr '\n' ' ' || { ok=0; echo ABSENT; })"
line gitleaks  "$(gitleaks version 2>/dev/null || { ok=0; echo ABSENT; })"
line aws-cli   "$(aws --version 2>/dev/null || { ok=0; echo ABSENT; })"
line python    "$(python --version 2>/dev/null || python3 --version 2>/dev/null || { ok=0; echo ABSENT; })"
line git       "$(git --version 2>/dev/null || { ok=0; echo ABSENT; })"

echo "== LocalStack ($LOCALSTACK_IMAGE)"
if localstack_up; then
  curl -fs "$LOCALSTACK_ENDPOINT/_localstack/health" | python -c "
import sys,json; d=json.load(sys.stdin)
print('  version', d['version'], '-', ', '.join(f'{k}={v}' for k,v in d['services'].items() if v!='disabled'))"
else
  ok=0
fi

[ "$ok" = 1 ] && echo "Point de contrôle étape 0 : OK" || { echo "Point de contrôle étape 0 : ÉCHEC"; exit 1; }
