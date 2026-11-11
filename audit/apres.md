# Audit APRÈS remédiation — version sécurisée (branche `secure`)

## Synthèse avant / après

| Analyseur | Avant (`naive`) | Après (`secure`) |
|---|---|---|
| Checkov 3.3.30 | **25 échecs** / 10 succès / 0 exception, 5 ressources | **0 échec** / 41 succès / **9 exceptions documentées**, 21 ressources |
| Trivy 0.76.0 | **17 constats** (10 HIGH, 2 MEDIUM, 5 LOW) | **0 constat** (4 ignorés par exception) |
| Secrets (gitleaks + regex) | **3** | **0** dans les fichiers versionnables |
| Conftest (3 règles) | **12 refus** (voir `tests/README.md`) | **0 refus** |

Les détails sont dans `checkov_apres.json`, `checkov_apres.txt`, `trivy_apres.json`, `trivy_apres.txt` et `secrets_apres.txt`. L'évolution commit par commit est dans [`progression.md`](progression.md).

## Statut de chaque constat de `avant.md`

| # | Règle | Ressource | Statut | Comment / raison |
|---|---|---|---|---|
| 1 | CKV_AWS_62 / 63 | politique `app-writer` | ✅ **Corrigé** | Plus aucune `Action="*"`. Seules `s3:PutObject` et `s3:AbortMultipartUpload` restent. |
| 2 | CKV_AWS_286 | idem | ✅ **Corrigé** | Aucune action `iam:*`, donc aucune élévation de privilèges possible. |
| 3 | CKV2_AWS_40 | idem | ✅ **Corrigé** | Aucun droit IAM. |
| 4 | CKV_AWS_287 / 288 / 289 / 290 | idem | ✅ **Corrigé** | Écriture seule, sur `arn:aws:s3:::novacorp-logs/app/*` uniquement : aucune lecture, donc pas d'exfiltration possible. |
| 5 | CKV_AWS_355 | idem | ✅ **Corrigé** | La ressource précise est `novacorp-logs/app/*`. |
| 6 | CKV_AWS_40 · AWS-0143 | `app-writer` | ✅ **Corrigé** | La politique est portée par le groupe `app-writers`, et l'utilisateur en est membre (`aws_iam_user_group_membership`). |
| 7 | CKV_AWS_273 | `aws_iam_user.app_writer` | ⚠️ **Accepté (EXC-05)** | L'énoncé impose un utilisateur IAM. En production, ce serait un rôle assumé (OIDC). |
| 8 | CKV2_AWS_6 · AWS-0094 | 2 buckets | ✅ **Corrigé** | `aws_s3_bucket_public_access_block` sur chaque bucket, via le module. |
| 9 | AWS-0086 / 0087 / 0091 / 0093 | 2 buckets | ✅ **Corrigé** | Les 4 verrous sont à `true`. En plus : `BucketOwnerEnforced`, qui désactive les ACL. |
| 10 | CKV_AWS_145 · AWS-0132 | 2 buckets | ⚠️ **Partiellement corrigé (EXC-01)** | Chiffrement par défaut **AES256** déclaré, sur l'objet aussi. La clé CMK est impossible sans KMS dans LocalStack. |
| 11 | CKV_AWS_21 · AWS-0090 | 2 buckets | ✅ **Corrigé** | Versioning `Enabled` sur les deux buckets. |
| 12 | CKV_AWS_18 · AWS-0089 | `customer-data` / `logs` | ✅ **Corrigé** / ⚠️ **Accepté (EXC-04)** | Le bucket de données journalise vers `novacorp-logs/s3-access/customer-data/`. Le bucket de journaux, lui, ne journalise pas vers lui-même. |
| 13 | CKV2_AWS_61 | 2 buckets | ✅ **Corrigé** | Cycle de vie : journaux conservés 365 jours, versions non courantes 30 ou 90 jours, envois multipart abandonnés supprimés après 7 jours. |
| 14 | CKV2_AWS_62 | 2 buckets | ⚠️ **Accepté (EXC-03)** | Pas de service de notification dans l'environnement. |
| 15 | CKV_AWS_144 | 2 buckets | ⚠️ **Accepté (EXC-02)** | Laboratoire mono-région. |
| 16 | tf-hardcoded-password | `main.tf` | ✅ **Corrigé** (code) · ⚠️ **résiduel** (historique, state) | Variable `db_password` `sensitive`, sans valeur par défaut, fournie par `TF_VAR_db_password` (fichier `.env` ignoré par Git). **Mais** la valeur reste dans l'historique Git de `naive` (`secrets_historique.txt`) et en clair dans `terraform.tfstate`. Voir `SYNTHESE.md`. |
| 17 | tf-provider-static-credentials | `providers.tf` | ✅ **Corrigé** | Identifiants lus dans l'environnement (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, avec les valeurs factices `test/test`). |
| 18 | étiquettes absentes | toutes | ✅ **Corrigé** | `owner`, `env` et `project` sur les 4 ressources étiquetables (2 buckets, utilisateur, objet). La règle Conftest n° 2 l'impose et une `validation` du module l'exige. `aws_iam_group` **n'accepte pas** d'étiquettes dans l'API AWS. |
| — | AWS-0123 (**nouveau**) | `aws_iam_group.app_writers` | ⚠️ **Accepté (EXC-06)** | Ce constat est apparu avec la création du groupe : la MFA ne s'applique pas à un compte de service. |

**Bilan : 13 constats corrigés, 1 partiellement corrigé (chiffrement en AES256
sans CMK), 5 acceptés avec une exception documentée (EXC-01 à EXC-06), et 0
constat sans traitement.** Le registre complet est dans [`exceptions.md`](exceptions.md).

## Mesures ajoutées en plus des exigences

- Une politique de bucket `DenyInsecureTransport` sur les deux buckets (HTTPS obligatoire).
- `aws_s3_bucket_ownership_controls = BucketOwnerEnforced` (ACL désactivées).
- La livraison des journaux d'accès est limitée au service `logging.s3.amazonaws.com` et au compte source (`aws:SourceAccount`).
- Les validations Terraform `environment ∈ {dev, staging, prod}`, `owner` non vide et `db_password` d'au moins 16 caractères.
- Une `precondition` : tout bucket qui ne reçoit pas les journaux **doit** être journalisé.
- Des blocs `moved` (`moves.tf`) : passer au module n'a **détruit aucune ressource** (`preuves/partie3_plan_refactor_module.txt` : 0 destruction).

## Vérification sur LocalStack

Le fichier `preuves/partie3_aws_cli_secure.txt` montre, pour chaque bucket :

- `get-public-access-block` : les 4 valeurs à `true` ;
- `get-bucket-encryption` : `AES256` ;
- `get-bucket-versioning` : `Enabled` ;
- les étiquettes.

On y voit aussi que la politique effective du groupe se limite à `arn:aws:s3:::novacorp-logs/app/*` et que `list-user-policies` est vide.

> Rappel : LocalStack gratuit **n'applique pas** les politiques IAM. Ces
> preuves montrent la **configuration** déployée, pas un blocage d'accès réel.
