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

rc=0
echo "  [gitleaks] analyse de '$TARGET' (config .gitleaks.toml)"
if ! gitleaks dir "$TARGET" --config .gitleaks.toml --no-banner --redact=100 \
      --no-color -v --exit-code 1 2>&1 | sed 's/^/    /'; then
  rc=1
fi

echo "  [regex] recherche de motifs (AKIA..., password =, access_key =)"
PATTERN='(AKIA|ASIA)[A-Z0-9]{16}|(password|passwd|secret|token)[a-z_]*[[:space:]]*=[[:space:]]*"[^"$]{6,}"|(access_key|secret_key)[[:space:]]*=[[:space:]]*"[^"$]+"'
if hits=$(grep -rnIiE --include='*.tf' --include='*.tfvars' --include='*.json' \
            --exclude-dir=.terraform "$PATTERN" "$TARGET" 2>/dev/null); then
  # On masque la valeur dans la sortie
  echo "$hits" | sed -E 's/"[^"]*"/"***"/g; s/^/    TROUVÉ : /'
  rc=1
fi

exit "$rc"
