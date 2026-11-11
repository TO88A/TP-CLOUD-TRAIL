#!/usr/bin/env bash
# scripts/step_check.sh [dossier] — contrôle rapide après chaque correction
# (Partie 3) : fmt, validate, puis nombre d'échecs Checkov et Trivy.
set -euo pipefail
source "$(dirname "$0")/tools.sh"
DIR="${1:-terraform}"; cd "$TP_ROOT"
tf -chdir="$DIR" fmt -recursive -check >/dev/null && echo "fmt      : OK"
tf -chdir="$DIR" init -input=false -no-color >/dev/null
tf -chdir="$DIR" validate -no-color >/dev/null && echo "validate : OK"
c=$(checkov -d "$DIR" --framework terraform --soft-fail -o json 2>/dev/null | python -c "import sys,json;d=json.load(sys.stdin);d=d[0] if isinstance(d,list) else d;s=d['summary'];print(f\"{s['failed']} échecs / {s['passed']} succès / {s['skipped']} exceptions\")")
echo "checkov  : $c"
t=$(trivy config --quiet --format json "$DIR" | python -c "import sys,json;d=json.load(sys.stdin);print(sum(len(r.get('Misconfigurations') or []) for r in d.get('Results',[])))")
echo "trivy    : $t constats"
