# Note de synthèse — Sécurisation de l'IaC NovaCorp

**Périmètre.** Les buckets S3 `novacorp-logs` et `novacorp-customer-data`,
l'utilisateur IAM `app-writer`. Le code Terraform est déployé sur LocalStack
4.14, qui émule S3, IAM et STS. Les contrôles sont faits par Checkov 3.3.30,
Trivy 0.76.0, gitleaks 8.30.1 et Conftest 0.70.1 (OPA 1.20), puis enchaînés
par `ci/ci.sh`.

## 1. Risques corrigés

| Avant (`naive`) | Après (`secure`) | Preuve |
|---|---|---|
| `app-writer` administrateur : `Action="*"`, `Resource="*"` | `s3:PutObject` et `s3:AbortMultipartUpload` sur `novacorp-logs/app/*` seulement, via le groupe `app-writers` | Conftest IAM-001, `preuves/partie3_aws_cli_secure.txt` |
| Buckets sans Public Access Block | Les 4 verrous à `true`, ACL désactivées (`BucketOwnerEnforced`), TLS obligatoire | Conftest S3-001, `get-public-access-block` |
| Aucun chiffrement déclaré | SSE-S3 AES256 par défaut sur les 2 buckets et sur l'objet | `get-bucket-encryption` |
| Pas de versioning | Versioning activé et cycle de vie des versions | `get-bucket-versioning` |
| Mot de passe et identifiants en dur | Variable `sensitive` sans valeur par défaut, fournie hors dépôt (`.env` ignoré par Git) | gitleaks : 3 secrets avant, 0 après |
| Aucune étiquette, aucune traçabilité | `owner`, `env` et `project` partout ; journaux d'accès du bucket de données vers `novacorp-logs` | Conftest TAG-001 |

**Bilan.** Checkov passe de 25 échecs à 0 (9 exceptions justifiées), Trivy de
17 constats à 0, Conftest de 7 refus à 0. La CI échoue sur `naive` (étape 3/8)
et réussit sur `secure` (8/8). Six exceptions sont documentées, de EXC-01 à
EXC-06 (`audit/exceptions.md`).

## 2. Risques résiduels

1. **State local non chiffré.** `terraform.tfstate` est ignoré par Git, mais
   il contient **`db_password` en clair**, ainsi que toute la configuration.
   `sensitive = true` masque l'affichage, pas le stockage. La preuve est
   dans `audit/secrets_state_local.txt`.
2. **Secret présent dans l'historique Git.** Le mot de passe de la version
   naïve reste dans le commit `d9d8b2e` (`audit/secrets_historique.txt`).
   Il faudrait le **changer**, puis réécrire l'historique (`git filter-repo`).
3. **Limites de LocalStack.** Les politiques IAM ne sont **pas appliquées** :
   nous avons prouvé la *configuration*, pas un blocage réel. KMS n'est pas
   actif, d'où le chiffrement AES256 au lieu d'une CMK (EXC-01).
   L'environnement est mono-région, sans réplication (EXC-02), et sans service
   de notification (EXC-03).
4. **Utilisateur IAM à clés longue durée** (EXC-05 et EXC-06), imposé par
   l'énoncé.
5. **Secret stocké dans S3.** `config/app.json` contient le mot de passe,
   chiffré en AES256 mais lisible par tout principal autorisé sur le bucket.
6. **Limites des contrôles.**
   - Les règles Rego vérifient le plan, pas les changements faits à la main
     dans la console (dérive).
   - Les exceptions `#checkov:skip` dans un module s'appliquent à toutes ses
     instances.
   - Les résultats dépendent des versions des outils, qui sont épinglées.

**Valeurs inconnues avant apply.** Nous évaluons le plan **avant apply** et
refusons toute valeur `after_unknown` utile à une règle (*fail-closed*). Pour
que le code légitime reste vérifiable, les ARN et les liens sont construits à
partir d'attributs connus au plan (`.bucket` plutôt que `.id`). Le cas est
démontré par `tests/plans/rule1_iam_unknown.json`.

## 3. Trois améliorations pour un vrai environnement

1. **Backend distant chiffré et verrouillé.** S3 avec SSE-KMS, versioning,
   Public Access Block et verrouillage natif (`use_lockfile`), dans un compte
   dédié, avec un accès au state limité au rôle de CI. Les secrets iraient
   dans **AWS Secrets Manager**, référencés par ARN, au lieu d'une variable
   Terraform.
2. **OIDC pour la CI.** La CI (GitHub Actions ou GitLab) assume un rôle IAM
   par fédération OIDC. Ses identifiants sont temporaires, et la condition
   porte sur le dépôt et la branche : aucune clé stockée. Le même principe
   remplacerait `app-writer` par un rôle applicatif (supprime EXC-05/06).
3. **Revue humaine avant apply.** Le plan est généré en CI puis publié sur la
   merge request (`terraform show` et sortie Conftest). L'apply n'a lieu
   qu'après l'approbation d'un relecteur (CODEOWNERS, environnement protégé),
   et sur **ce même plan** (`apply tfplan`). Branche `main` protégée, aucun
   `--no-verify` en CI, et les exceptions revues à chaque trimestre.

*Pistes complémentaires :* KMS CMK avec rotation pour les données clients,
détection de dérive programmée (`terraform plan -detailed-exitcode`), et
CloudTrail avec des événements de données S3 vers un compte d'archivage.
