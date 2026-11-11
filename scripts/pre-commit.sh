#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/pre-commit.sh — hook pre-commit (bonus).
# Contrôles RAPIDES sur ce qui va être commité :
#   1. aucun fichier interdit indexé (*.tfstate, *.tfvars, .env, tfplan)
#   2. secrets dans les fichiers INDEXÉS (gitleaks --staged)
#   3. terraform fmt -check (si des .tf sont indexés)
#   4. Checkov (si des .tf sont indexés)
# La chaîne complète (Trivy, plan, Conftest) reste dans ci/ci.sh.
# Installation : bash scripts/install-hooks.sh
# Contournement d'urgence (tracé dans l'historique du shell) : git commit --no-verify
# ---------------------------------------------------------------------------
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=tools.sh
source "$ROOT/scripts/tools.sh"
cd "$ROOT"

fail() { echo "[pre-commit] ÉCHEC : $*" >&2; exit 1; }

staged="$(git diff --cached --name-only --diff-filter=ACMR)"
[ -z "$staged" ] && exit 0

echo "[pre-commit] 1/4 fichiers interdits"
if echo "$staged" | grep -E '(\.tfstate(\.backup)?$|\.tfvars$|(^|/)\.env$|(^|/)tfplan$)'; then
  fail "fichier(s) sensible(s) indexé(s) ci-dessus : retirez-les (git rm --cached)."
fi

echo "[pre-commit] 2/4 secrets dans les fichiers indexés (gitleaks)"
gitleaks git --pre-commit --staged --config .gitleaks.toml --no-banner \
  --redact=100 --no-color --exit-code 1 . || fail "secret détecté dans les fichiers indexés."

if echo "$staged" | grep -qE '\.tf$'; then
  echo "[pre-commit] 3/4 terraform fmt -check"
  tf -chdir=terraform fmt -check -recursive -no-color || fail "lancez : terraform fmt -recursive"
  echo "[pre-commit] 4/4 Checkov"
  checkov -d terraform --framework terraform --compact --quiet --skip-path .terraform \
    || fail "Checkov signale des constats (corrigez ou documentez une exception)."
else
  echo "[pre-commit] 3-4/4 aucun fichier .tf indexé : fmt/Checkov ignorés"
fi
echo "[pre-commit] OK"
