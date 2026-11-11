#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/scan_secrets.sh <dossier> — détection de secrets.
#   1. gitleaks (règles par défaut + .gitleaks.toml du dépôt)
#   2. filet de sécurité : recherche de motifs par expressions régulières
#      (clés AKIA..., password = "...", access_key/secret_key littéraux)
# Code de sortie non nul si un secret est trouvé.
# ---------------------------------------------------------------------------
set -euo pipefail
source "$(dirname "$0")/tools.sh"
TARGET="${1:-terraform}"
cd "$TP_ROOT"

# On analyse ce qui PEUT être versionné : fichiers suivis + nouveaux fichiers
# non ignorés. Le state (*.tfstate), .env, .terraform/ sont exclus ici car
# ignorés par Git — le state contient pourtant des secrets en clair : risque
# résiduel documenté dans SYNTHESE.md.
SCAN_DIR="build/secret-scan"
rm -rf "$SCAN_DIR"; mkdir -p "$SCAN_DIR"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -z --cached --others --exclude-standard -- "$TARGET"     | while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        mkdir -p "$SCAN_DIR/$(dirname "$f")"; cp "$f" "$SCAN_DIR/$f"
      done
else
  cp -r "$TARGET" "$SCAN_DIR/"
fi
nfiles=$(find "$SCAN_DIR" -type f | wc -l | tr -d ' ')

rc=0
echo "  [gitleaks] analyse de '$TARGET' ($nfiles fichiers versionnables, config .gitleaks.toml)"
if ! gitleaks dir "$SCAN_DIR" --config .gitleaks.toml --no-banner --redact=100 \
      --no-color -v --exit-code 1 2>&1 | sed 's/^/    /'; then
  rc=1
fi

echo "  [regex] recherche de motifs (AKIA..., password =, access_key =)"
PATTERN='(AKIA|ASIA)[A-Z0-9]{16}|(password|passwd|secret|token)[a-z_]*[[:space:]]*=[[:space:]]*"[^"$]{6,}"|(access_key|secret_key)[[:space:]]*=[[:space:]]*"[^"$]+"'
if hits=$(grep -rnIiE --include='*.tf' --include='*.tfvars' --include='*.json' \
            "$PATTERN" "$SCAN_DIR" 2>/dev/null); then
  # On masque la valeur dans la sortie
  echo "$hits" | sed -E 's/"[^"]*"/"***"/g; s#^build/secret-scan/##; s/^/    TROUVÉ : /'
  rc=1
fi

exit "$rc"
