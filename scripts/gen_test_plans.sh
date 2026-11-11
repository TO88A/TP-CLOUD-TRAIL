#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/gen_test_plans.sh — produit les jeux de plans de test (Partie 4).
#
# Chaque plan est un VRAI plan Terraform (terraform show -json), généré dans
# une copie isolée SANS state : ce sont des plans de création, donc
# reproductibles quel que soit l'état de LocalStack. Les plans sont assainis
# (valeurs sensibles -> "REDACTED") avant d'être rangés dans tests/plans/.
#
#   plan_bad.json            branche naive         -> doit échouer (3 règles)
#   plan_good.json           branche secure        -> doit réussir
#   rule1_iam_fail.json      secure + Action "*"   -> échoue UNIQUEMENT règle 1
#   rule1_iam_unknown.json   secure + ARN inconnu  -> règle 1 (fail-closed)
#   rule2_tags_fail.json     secure sans owner     -> échoue UNIQUEMENT règle 2
#   rule3_s3_fail.json       secure, 1 verrou off  -> échoue UNIQUEMENT règle 3
#
# Prérequis : LocalStack démarré (le plan lit aws_caller_identity).
# ---------------------------------------------------------------------------
set -euo pipefail
source "$(dirname "$0")/tools.sh"
cd "$TP_ROOT"

OUT="tests/plans"; WORK="build/pg"
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
# Valeur factice, uniquement pour produire les plans de test (puis masquée).
export TF_VAR_db_password="CHANGE_ME_test_only_00000"

export_tree() { # export_tree <ref|WORKTREE> <dest>
  mkdir -p "$2"
  if [ "$1" = "WORKTREE" ]; then
    git ls-files -z --cached --others --exclude-standard -- terraform \
      | while IFS= read -r -d '' f; do
          [ -f "$f" ] || continue; mkdir -p "$2/$(dirname "$f")"; cp "$f" "$2/$f"
        done
  else
    git archive "$1" terraform | tar -x -C "$2"
  fi
}

make_plan() { # make_plan <nom> <ref|WORKTREE> [commande sed à appliquer]
  local name="$1" ref="$2" patch="${3:-}"
  local dir="$WORK/$name"
  export_tree "$ref" "$dir"
  if [ -n "$patch" ]; then eval "$patch"; fi
  ( cd "$dir/terraform"
    tf init -input=false -no-color >/dev/null
    tf plan -input=false -no-color -out=tfplan >/dev/null
    tf show -json tfplan > plan.raw.json )
  python scripts/sanitize_plan.py "$dir/terraform/plan.raw.json" "$OUT/$name.json"
  echo "  OK  $OUT/$name.json"
}

M="\$dir/terraform/main.tf"
MOD="\$dir/terraform/modules/secure-bucket/main.tf"

make_plan plan_bad  naive
make_plan plan_good WORKTREE
make_plan rule1_iam_fail WORKTREE \
  "sed -i 's/\"s3:AbortMultipartUpload\",/\"s3:AbortMultipartUpload\",\n          \"*\",/' $M"
make_plan rule1_iam_unknown WORKTREE \
  "sed -i 's|Resource = \"\${module.logs_bucket.bucket_arn}/app/\\*\"|Resource = \"\${module.logs_bucket.bucket_arn}/app/*\"\n        Condition = { StringEquals = { \"aws:PrincipalArn\" = aws_iam_user.app_writer.arn } }|' $M"
make_plan rule2_tags_fail WORKTREE \
  "sed -i '/name = \"app-writer\"/{n;s/  tags = local.common_tags/  tags = { env = var.environment }/}' $M"
make_plan rule3_s3_fail WORKTREE \
  "sed -i 's/  block_public_policy     = true/  block_public_policy     = false/' $MOD"

echo "Plans générés dans $OUT/"
