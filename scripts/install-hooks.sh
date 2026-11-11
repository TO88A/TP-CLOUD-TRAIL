#!/usr/bin/env bash
# Installe le hook pre-commit du dépôt (sans dépendance au framework pre-commit).
# Alternative avec le framework : pip install pre-commit && pre-commit install
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
HOOK="$ROOT/.git/hooks/pre-commit"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
exec bash "$(git rev-parse --show-toplevel)/scripts/pre-commit.sh"
EOF
chmod +x "$HOOK"
echo "Hook installé : $HOOK"
