#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ci/ci.sh — chaîne de contrôle IaC NovaCorp (Partie 5).
#
# Enchaîne, dans l'ordre, et S'ARRÊTE AU PREMIER ÉCHEC (code de sortie != 0) :
#   1. terraform fmt -check     5. Trivy
#   2. terraform validate       6. terraform plan
#   3. détection de secrets     7. export du plan en JSON
#   4. Checkov                  8. Conftest (policies/)
#
# Usage : ci/ci.sh [dossier_terraform]   (défaut : terraform)
# Prérequis : Docker (outils épinglés, cf. scripts/tools.sh) ; LocalStack est
# démarré automatiquement pour l'étape plan.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/tools.sh
source "$ROOT/scripts/tools.sh"
cd "$ROOT"

TF_DIR="${1:-terraform}"
BUILD="build/ci"
mkdir -p "$BUILD"
PLAN_BIN="$BUILD/tfplan"      # hors de $TF_DIR : sinon Trivy analyserait un
PLAN_JSON="$BUILD/plan.json"  # ancien plan binaire (piège rencontré en Partie 3)

STEP=0; TOTAL=8
START=$(date +%s)
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"

echo "=================================================================="
echo " Chaîne de contrôle IaC — NovaCorp"
echo " branche : $branch ($commit)   dossier : $TF_DIR"
echo " $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=================================================================="

# step "<libellé>" <commande...> : exécute, affiche la sortie indentée,
# puis « OK » ou « ÉCHEC : … » et arrête la chaîne en cas d'échec.
step() {
  local label="$1"; shift
  STEP=$((STEP + 1))
  echo
  echo "[$STEP/$TOTAL] $label"
  local rc=0
  "$@" > "$BUILD/step.log" 2>&1 || rc=$?
  sed 's/^/      /' "$BUILD/step.log"
  if [ "$rc" -ne 0 ]; then
    echo "  => ÉCHEC : $label (code $rc). Chaîne interrompue à l'étape $STEP/$TOTAL."
    echo
    echo "RÉSULTAT : ÉCHEC ($(( $(date +%s) - START )) s)"
    exit "$rc"
  fi
  echo "  => OK"
}

# --- Étapes -----------------------------------------------------------------
do_fmt()      { tf -chdir="$TF_DIR" fmt -check -recursive -diff -no-color; }

do_validate() {
  tf -chdir="$TF_DIR" init -input=false -no-color -backend=false >/dev/null
  tf -chdir="$TF_DIR" validate -no-color
}

do_secrets()  { bash scripts/scan_secrets.sh "$TF_DIR"; }

do_checkov() {
  checkov -d "$TF_DIR" --framework terraform --compact --quiet \
    --skip-path .terraform -o cli
}

do_trivy() {
  trivy config --quiet --exit-code 1 --severity LOW,MEDIUM,HIGH,CRITICAL \
    --skip-dirs "$TF_DIR/.terraform" "$TF_DIR"
}

do_plan() {
  localstack_up
  tf -chdir="$TF_DIR" init -input=false -no-color >/dev/null
  tf -chdir="$TF_DIR" plan -input=false -no-color -lock-timeout=30s \
    -out="$(rel_from_tf "$PLAN_BIN")" | tail -n 25
}

do_export()   {
  tf -chdir="$TF_DIR" show -json "$(rel_from_tf "$PLAN_BIN")" > "$PLAN_JSON"
  python -c "import json,sys;d=json.load(open(sys.argv[1],encoding='utf-8'));print('plan JSON :',sys.argv[1],'-',len(d.get('resource_changes',[])),'resource_changes')" "$PLAN_JSON"
}

do_conftest() { conftest test "$PLAN_JSON" -p policies --no-color; }

# Chemin de $1 vu depuis $TF_DIR (pour -chdir)
rel_from_tf() {
  local depth; depth=$(echo "$TF_DIR" | awk -F/ '{print NF}')
  local up=""; for _ in $(seq 1 "$depth"); do up="../$up"; done
  echo "${up}$1"
}

step "Formatage (terraform fmt -check)"              do_fmt
step "Validation (terraform validate)"               do_validate
step "Détection de secrets (gitleaks + regex)"       do_secrets
step "Analyse statique Checkov"                      do_checkov
step "Analyse statique Trivy"                        do_trivy
step "Plan (terraform plan sur LocalStack)"          do_plan
step "Export du plan en JSON (terraform show -json)" do_export
step "Policy as code (Conftest)"                     do_conftest

echo
echo "RÉSULTAT : SUCCÈS — $TOTAL/$TOTAL étapes OK ($(( $(date +%s) - START )) s)"
