# shellcheck shell=bash
# ---------------------------------------------------------------------------
# scripts/tools.sh — wrappers des outils du TP (à "sourcer").
#
# Chaque outil est utilisé en natif s'il est installé, sinon il tourne dans
# un conteneur Docker à version ÉPINGLÉE. Les versions sont donc identiques
# sur toutes les machines (voir README.md, section « Versions »).
#
#   source scripts/tools.sh
#   tf -chdir=terraform plan        # terraform
#   checkov -d terraform            # checkov
#   trivy config terraform          # trivy
#   conftest test plan.json -p policies
#   gitleaks dir terraform
#   awsls s3 ls                     # AWS CLI vers LocalStack
# ---------------------------------------------------------------------------

# Versions épinglées (images Docker)
export TF_IMAGE="${TF_IMAGE:-hashicorp/terraform:1.16.7}"
export CHECKOV_IMAGE="${CHECKOV_IMAGE:-bridgecrew/checkov:3.3.30}"
export TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.76.0}"
export CONFTEST_IMAGE="${CONFTEST_IMAGE:-openpolicyagent/conftest:v0.70.1}"
export GITLEAKS_IMAGE="${GITLEAKS_IMAGE:-zricethezav/gitleaks:v8.30.1}"
export LOCALSTACK_IMAGE="${LOCALSTACK_IMAGE:-localstack/localstack:4.14}"
export LOCALSTACK_CONTAINER="${LOCALSTACK_CONTAINER:-lab-localstack}"
export LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"

# Identifiants FACTICES LocalStack (jamais de vraie clé).
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-3}"

# Racine du dépôt (dossier parent de scripts/)
TP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TP_ROOT

# Git Bash (Windows) : désactive la conversion automatique des chemins
# et obtient un chemin "C:/..." compréhensible par Docker Desktop.
export MSYS_NO_PATHCONV=1
_host_root() { (cd "$TP_ROOT" && pwd -W 2>/dev/null) || echo "$TP_ROOT"; }

# Chemin relatif au dépôt du répertoire courant (pour -w dans le conteneur)
_rel_cwd() {
  local here; here="$(pwd)"
  case "$here" in
    "$TP_ROOT") echo "" ;;
    "$TP_ROOT"/*) echo "${here#"$TP_ROOT"/}" ;;
    *) echo "" ;;
  esac
}

# Réseau : si LocalStack tourne, on partage son espace réseau
# => "localhost:4566" fonctionne aussi à l'intérieur du conteneur.
_net_args() {
  if docker inspect -f '{{.State.Running}}' "$LOCALSTACK_CONTAINER" 2>/dev/null | grep -q true; then
    echo "--network container:$LOCALSTACK_CONTAINER"
  fi
}

_drun() { # _drun <image> [docker args...] -- [cmd args...]
  local image="$1"; shift
  local dargs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do dargs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  # shellcheck disable=SC2046
  docker run --rm -i $(_net_args) \
    -v "$(_host_root)":/work -w "/work/$(_rel_cwd)" \
    "${dargs[@]}" "$image" "$@"
}

tf() {
  if command -v terraform >/dev/null 2>&1 && [ -z "${FORCE_DOCKER:-}" ]; then
    command terraform "$@"; return
  fi
  local envs=(-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION
              -e TF_IN_AUTOMATION=1 -e TF_PLUGIN_CACHE_DIR=/work/.tfcache)
  local v
  for v in $(env | sed -n 's/^\(TF_VAR_[A-Za-z0-9_]*\)=.*/\1/p'); do envs+=(-e "$v"); done
  mkdir -p "$TP_ROOT/.tfcache"
  _drun "$TF_IMAGE" "${envs[@]}" -- "$@"
}

checkov() {
  if command -v checkov >/dev/null 2>&1 && [ -z "${FORCE_DOCKER:-}" ]; then
    command checkov "$@"; return
  fi
  _drun "$CHECKOV_IMAGE" --entrypoint checkov -- "$@"
}

trivy() {
  if command -v trivy >/dev/null 2>&1 && [ -z "${FORCE_DOCKER:-}" ]; then
    command trivy "$@"; return
  fi
  mkdir -p "$TP_ROOT/.trivycache"
  _drun "$TRIVY_IMAGE" -e TRIVY_CACHE_DIR=/work/.trivycache -- "$@"
}

conftest() {
  if command -v conftest >/dev/null 2>&1 && [ -z "${FORCE_DOCKER:-}" ]; then
    command conftest "$@"; return
  fi
  _drun "$CONFTEST_IMAGE" -- "$@"
}

gitleaks() {
  if command -v gitleaks >/dev/null 2>&1 && [ -z "${FORCE_DOCKER:-}" ]; then
    command gitleaks "$@"; return
  fi
  _drun "$GITLEAKS_IMAGE" -- "$@"
}

# AWS CLI ciblant LocalStack
awsls() { aws --endpoint-url "$LOCALSTACK_ENDPOINT" "$@"; }

localstack_up() {
  if ! docker inspect "$LOCALSTACK_CONTAINER" >/dev/null 2>&1; then
    docker run -d --name "$LOCALSTACK_CONTAINER" -p 127.0.0.1:4566:4566 \
      -e SERVICES=s3,iam,sts "$LOCALSTACK_IMAGE" >/dev/null
  else
    docker start "$LOCALSTACK_CONTAINER" >/dev/null
  fi
  local i
  for i in $(seq 1 30); do
    curl -fs -m 2 "$LOCALSTACK_ENDPOINT/_localstack/health" >/dev/null && return 0
    sleep 2
  done
  echo "LocalStack injoignable sur $LOCALSTACK_ENDPOINT" >&2; return 1
}
