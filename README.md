# NovaCorp IaC — TP 3.3 Terraform et sécurisation de l'IaC

Infrastructure de NovaCorp décrite en Terraform : deux buckets S3
(`novacorp-logs`, `novacorp-customer-data`) et un utilisateur IAM
`app-writer`. Elle est déployée sur **LocalStack**, sans compte AWS réel et
avec les identifiants factices `test/test`, puis vérifiée par une chaîne de
contrôles automatisés.

## Livrables

| Livrable (énoncé §5) | Emplacement |
|---|---|
| Dépôt Git sans `.tfstate` ni secret, README d'exécution | ce dépôt, branches `naive` / `secure` / `main` ; `README.md` |
| Tableau d'audit avant / après | [`audit/avant.md`](audit/avant.md), [`audit/apres.md`](audit/apres.md), [`audit/exceptions.md`](audit/exceptions.md), [`audit/progression.md`](audit/progression.md) |
| Règles Rego et jeux de plans de test | [`policies/`](policies/), [`tests/plans/`](tests/plans/), [`tests/README.md`](tests/README.md) |
| Script de chaîne de contrôle et ses deux sorties | [`ci/ci.sh`](ci/ci.sh), [`ci/sortie_naive.txt`](ci/sortie_naive.txt) (échec, code 1), [`ci/sortie_secure.txt`](ci/sortie_secure.txt) (succès, code 0) |
| Note de synthèse d'une page | [`SYNTHESE.md`](SYNTHESE.md) |
| Bonus : hook pre-commit | [`scripts/pre-commit.sh`](scripts/pre-commit.sh), [`.pre-commit-config.yaml`](.pre-commit-config.yaml), [`preuves/bonus_pre_commit.txt`](preuves/bonus_pre_commit.txt) |
| Bonus : module « bucket sécurisé » | [`terraform/modules/secure-bucket/`](terraform/modules/secure-bucket/) |
| Bonus : comparaison Checkov / Trivy | [`audit/comparaison_checkov_trivy.md`](audit/comparaison_checkov_trivy.md) |

## Arborescence

```
TP/
├── README.md, SYNTHESE.md
├── terraform/                  # projet Terraform (racine)
│   ├── versions.tf             # Terraform >= 1.6, provider aws ~> 6.0 (lock : 6.69.1)
│   ├── providers.tf            # provider AWS -> LocalStack (s3, iam, sts)
│   ├── variables.tf            # project_name, environment (validation), owner, db_password (sensitive)
│   ├── main.tf                 # buckets (module), IAM moindre privilège, objet de config
│   ├── moves.tf                # blocs moved : passage au module sans destruction
│   ├── outputs.tf
│   └── modules/secure-bucket/  # bonus : module réutilisable
├── audit/                      # Checkov/Trivy/gitleaks avant/après + tableaux
├── policies/                   # règles Conftest/Rego + tests unitaires
├── tests/plans/                # plans JSON de test (assainis)
├── ci/                         # ci.sh + sorties naive/secure
├── scripts/                    # wrappers d'outils, scans, génération de plans, hooks
├── preuves/                    # sorties apply / AWS CLI / hook
└── versions/                   # diff naive -> secure (secrets masqués)
```

## Prérequis et versions des outils

Seuls **Docker**, **Git (Git Bash sous Windows)**, **Python 3** et
**AWS CLI v2** sont à installer. Terraform, Checkov, Trivy, Conftest et
gitleaks tournent dans des **conteneurs aux versions épinglées**
(`scripts/tools.sh`). Si un outil est installé en natif, il est utilisé à la
place ; `FORCE_DOCKER=1` force le conteneur.

| Outil | Version (vérifiée par `scripts/check_env.sh`) | Image |
|---|---|---|
| Docker | 29.1.3 | — |
| Terraform | **1.16.7** | `hashicorp/terraform:1.16.7` |
| Provider AWS | **6.69.1** (contrainte `~> 6.0`, figée par `.terraform.lock.hcl`) | — |
| LocalStack | **4.14.0** (S3, IAM, STS) | `localstack/localstack:4.14` |
| Checkov | **3.3.30** | `bridgecrew/checkov:3.3.30` |
| Trivy | **0.76.0** | `aquasec/trivy:0.76.0` |
| Conftest / OPA | **0.70.1** / 1.20.2 (Rego v1) | `openpolicyagent/conftest:v0.70.1` |
| gitleaks | **8.30.1** (+ `.gitleaks.toml` étendu) | `zricethezav/gitleaks:v8.30.1` |
| AWS CLI | 2.37.9 | natif |
| Python | 3.14.2 | natif |
| Git | 2.45.1 | natif |

## Configuration manuelle (une seule fois)

1. Lancer **Docker Desktop**.
2. Fournir le secret **hors dépôt** :
   ```bash
   cp .env.example .env
   python -c "import secrets;print('TF_VAR_db_password='+secrets.token_urlsafe(24))" > .env
   ```
   `.env` est ignoré par Git. `scripts/tools.sh` le charge automatiquement.
3. (Facultatif) Installer le hook : `bash scripts/install-hooks.sh`.

## Tout rejouer

Toutes les commandes se lancent depuis la racine du dépôt, dans **Git Bash**
(Windows) ou un shell bash (Linux, macOS).

```bash
source scripts/tools.sh            # fonctions tf, checkov, trivy, conftest, gitleaks, awsls

# Étape 0 — outils + LocalStack
bash scripts/check_env.sh          # démarre lab-localstack si besoin

# Partie 1 — version naïve
git switch naive
tf -chdir=terraform init && tf -chdir=terraform validate
tf -chdir=terraform plan -out=../build/tfplan
tf -chdir=terraform apply ../build/tfplan
awsls s3 ls && awsls iam list-users

# Partie 2 — audit
checkov -d terraform --framework terraform
checkov -d terraform --framework terraform -o json > audit/checkov_avant.json
trivy config terraform
bash scripts/scan_secrets.sh terraform

# Partie 3 — version sécurisée
git switch secure
git log --oneline naive..secure    # un commit par correction
bash scripts/step_check.sh         # fmt, validate, nombre d'échecs Checkov et Trivy
tf -chdir=terraform plan -out=../build/tfplan    # 0 destruction
tf -chdir=terraform apply ../build/tfplan

# Partie 4 — policy as code
tf -chdir=terraform show -json ../build/tfplan > build/plan_good.json
conftest test build/plan_good.json -p policies
bash scripts/gen_test_plans.sh     # régénère tests/plans/*.json
bash scripts/test_policies.sh      # 20 tests unitaires + matrice attendue

# Partie 5 — chaîne de contrôle
git switch naive  && ./ci/ci.sh; echo $?   # ÉCHEC étape 3/8, code 1
git switch secure && ./ci/ci.sh; echo $?   # SUCCÈS 8/8, code 0

# Nettoyage
tf -chdir=terraform destroy -auto-approve
docker rm -f lab-localstack
```

> Les plans binaires et JSON sont écrits dans `build/` (ignoré par Git), **en
> dehors** de `terraform/`. Sinon `trivy config` analyserait un ancien plan
> binaire (piège décrit dans `audit/comparaison_checkov_trivy.md`).

## Vérification du dépôt

```bash
git status                                    # propre
git ls-files | grep -E 'tfstate|tfvars|\.env$' # rien
bash scripts/scan_secrets.sh .                # aucun secret dans les fichiers versionnables
```

Le mot de passe factice de la version naïve reste, **volontairement**, dans
l'historique de la branche `naive` : c'est la démonstration du risque. Voir
`audit/secrets_historique.txt` et `SYNTHESE.md`.
