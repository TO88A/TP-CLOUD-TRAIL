#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/test_policies.sh — vérifie que chaque règle Rego se comporte comme
# attendu sur les plans de tests/plans/ (Partie 4, point de contrôle).
#   1. conftest verify   : tests unitaires (policies/policies_test.rego)
#   2. matrice de plans  : chaque plan doit produire EXACTEMENT les refus
#                          attendus (codes de règle IAM-001 / TAG-001 / S3-001)
# ---------------------------------------------------------------------------
set -euo pipefail
source "$(dirname "$0")/tools.sh"
cd "$TP_ROOT"

echo "== 1. Tests unitaires Rego (conftest verify)"
conftest verify -p policies --no-color

echo
echo "== 2. Matrice règle x plan"
# plan : refus attendus (codes:nombre), "-" = aucun refus
declare -A EXPECTED=(
  [plan_bad]="IAM-001:1 S3-001:2 TAG-001:4"
  [plan_good]="-"
  [rule1_iam_fail]="IAM-001:1"
  [rule1_iam_unknown]="IAM-001:1"
  [rule2_tags_fail]="TAG-001:1"
  [rule3_s3_fail]="S3-001:2"
)
rc=0
printf "%-20s %-30s %-30s %s\n" "PLAN" "ATTENDU" "OBTENU" "RÉSULTAT"
for plan in plan_bad plan_good rule1_iam_fail rule1_iam_unknown rule2_tags_fail rule3_s3_fail; do
  got=$(conftest test "tests/plans/$plan.json" -p policies --no-color 2>/dev/null \
        | sed -nE 's/^FAIL .*\[([A-Z0-9]+-[0-9]+)\].*/\1/p' | sort | uniq -c \
        | awk '{printf "%s:%s ", $2, $1}' | sed 's/ $//') || true
  [ -z "$got" ] && got="-"
  if [ "$got" = "${EXPECTED[$plan]}" ]; then res="OK"; else res="ÉCHEC"; rc=1; fi
  printf "%-20s %-30s %-30s %s\n" "$plan" "${EXPECTED[$plan]}" "$got" "$res"
done
exit "$rc"
