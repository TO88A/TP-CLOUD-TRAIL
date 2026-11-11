# Audit AVANT remédiation — version naïve (branche `naive`)

| Élément | Valeur |
|---|---|
| Code analysé | `terraform/` sur la branche `naive` (commit `d9d8b2e`) |
| Checkov 3.3.30 | **25 échecs**, 10 succès, **18 règles distinctes** en échec (`checkov_avant.json`, `checkov_avant.txt`) |
| Trivy 0.76.0 | **17 constats** (10 HIGH, 2 MEDIUM, 5 LOW), **8 règles distinctes** (`trivy_avant.json`, `trivy_avant.txt`) |
| gitleaks 8.30.1 + regex | **3 secrets** en dur (`secrets_avant.txt`) |

Commandes utilisées :

```bash
checkov -d terraform --framework terraform                       # résumé
checkov -d terraform --framework terraform -o json > audit/checkov_avant.json
trivy config terraform
bash scripts/scan_secrets.sh terraform
```

> **Gravité.** Checkov en version libre ne renvoie pas de gravité : le champ
> `severity` vaut `null` sans clé d'API Prisma Cloud. La gravité des règles
> Checkov ci-dessous est **notre estimation**, faite sur le contexte NovaCorp
> (données clients, journaux). Pour Trivy, la gravité indiquée est celle de
> l'outil.

## Tableau des constats (règle, ressource, gravité, risque)

Catégories : **EXP** exposition · **CHIF** chiffrement · **IAM** identités et droits · **TRAC** traçabilité · **AUT** autre (disponibilité, secrets, gouvernance).

| # | Règle | Outil | Ressource(s) | Gravité | Cat. | Risque en une phrase |
|---|---|---|---|---|---|---|
| 1 | CKV_AWS_62 / CKV_AWS_63 | Checkov | `aws_iam_user_policy.app_writer` | **CRITIQUE** | IAM | `Action="*"` sur `Resource="*"` fait de `app-writer` un administrateur complet du compte : une seule fuite de ses clés compromet tout le compte. |
| 2 | CKV_AWS_286 | Checkov | `aws_iam_user_policy.app_writer` | **CRITIQUE** | IAM | La politique permet l'élévation de privilèges, par exemple `iam:CreateAccessKey` ou `iam:AttachUserPolicy` sur d'autres identités. |
| 3 | CKV2_AWS_40 | Checkov | `aws_iam_user_policy.app_writer` | **CRITIQUE** | IAM | Les droits IAM complets permettent de créer des utilisateurs « porte dérobée » et de garder l'accès même après la révocation de la clé initiale. |
| 4 | CKV_AWS_287 / 288 / 289 / 290 | Checkov | `aws_iam_user_policy.app_writer` | ÉLEVÉE | IAM | L'utilisateur peut lire des identifiants, exfiltrer les données clients, rendre un bucket public et écrire n'importe où, sans aucune contrainte. |
| 5 | CKV_AWS_355 | Checkov | `aws_iam_user_policy.app_writer` | ÉLEVÉE | IAM | `Resource="*"` étend chaque action à toutes les ressources du compte au lieu du seul bucket de journaux. |
| 6 | CKV_AWS_40 · AWS-0143 | Checkov · Trivy (LOW) | `aws_iam_user_policy.app_writer` · `aws_iam_user.app_writer` | MOYENNE | IAM | Une politique attachée directement à l'utilisateur se gère au cas par cas : les droits excessifs se dupliquent et s'oublient lors des départs ou changements de poste. |
| 7 | CKV_AWS_273 | Checkov | `aws_iam_user.app_writer` | FAIBLE | IAM | Un utilisateur IAM a des clés longue durée, au lieu d'identités fédérées (SSO) ou de rôles à identifiants temporaires. |
| 8 | CKV2_AWS_6 · AWS-0094 | Checkov · Trivy (LOW) | les 2 buckets | **ÉLEVÉE** | EXP | Sans *Public Access Block*, une simple ACL ou politique publique ajoutée par erreur exposerait les données clients sur Internet. |
| 9 | AWS-0086 / 0087 / 0091 / 0093 | Trivy (HIGH) | les 2 buckets | **ÉLEVÉE** | EXP | Aucun des quatre verrous (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`) n'empêche l'ouverture publique du bucket. |
| 10 | CKV_AWS_145 · AWS-0132 | Checkov · Trivy (HIGH) | les 2 buckets | MOYENNE | CHIF | Aucun chiffrement par défaut n'est déclaré dans le code, et encore moins avec une clé gérée par NovaCorp (CMK) : on ne peut ni contrôler ni révoquer l'accès aux données chiffrées. |
| 11 | CKV_AWS_21 · AWS-0090 | Checkov · Trivy (MEDIUM) | les 2 buckets | **ÉLEVÉE** (données) / MOYENNE (logs) | AUT | Sans versioning, une suppression ou un écrasement, qu'il soit accidentel ou dû à un rançongiciel, est définitif et ne se récupère pas. |
| 12 | CKV_AWS_18 · AWS-0089 | Checkov · Trivy (LOW) | les 2 buckets | MOYENNE | TRAC | Sans journaux d'accès S3, on ne peut pas reconstituer qui a lu ou téléchargé les données clients après un incident. |
| 13 | CKV2_AWS_61 | Checkov | les 2 buckets | FAIBLE | AUT | Sans cycle de vie, les journaux et les anciennes versions s'accumulent sans limite : coût croissant et durée de conservation non conforme au RGPD. |
| 14 | CKV2_AWS_62 | Checkov | les 2 buckets | FAIBLE | TRAC | Aucune notification d'événement : une suppression massive ou un dépôt inattendu ne déclenche aucune alerte. |
| 15 | CKV_AWS_144 | Checkov | les 2 buckets | FAIBLE | AUT | Sans réplication inter-région, la perte d'une région rendrait les données indisponibles, voire les ferait perdre. |
| 16 | tf-hardcoded-password | gitleaks + regex | `terraform/main.tf:10` (`local.app_db_password`) | **CRITIQUE** | AUT (secret) | Le mot de passe de la base est lisible par quiconque accède au dépôt, et il reste dans l'historique Git même après sa suppression. |
| 17 | tf-provider-static-credentials | gitleaks + regex | `terraform/providers.tf:5-6` | MOYENNE | AUT (secret) | Des identifiants écrits en dur dans le provider encouragent à y mettre un jour de vraies clés. Ici, ce sont les valeurs factices `test/test`. |
| 18 | *(constat manuel)* | revue | toutes les ressources | MOYENNE | AUT | Aucune étiquette `owner` ou `env` : impossible d'attribuer une ressource à une équipe, de suivre les coûts ou de trouver à qui signaler un incident. |

**Bilan : 18 constats distincts** (le minimum demandé est 8), dont **4 critiques**.
Par catégorie : 7 IAM, 2 EXP, 1 CHIF, 2 TRAC, 6 AUT (dont 2 secrets).

## Ce que les outils n'ont PAS vu (à retenir)

- **Trivy ne signale pas la politique `Action="*"`** (règle AWS-0057), parce que
  la politique est construite avec `jsonencode(...)`. Seul Checkov la voit.
  D'où l'intérêt de la règle Conftest n° 1, qui travaille sur le **plan** où le
  JSON est déjà évalué.
- **Checkov ne signale pas `access_key = "test"`** : CKV_AWS_41 réussit parce que
  la valeur ne ressemble pas à une vraie clé.
- **gitleaks, avec ses règles par défaut, ne détecte aucun des trois secrets.**
  Il a fallu étendre sa configuration (`.gitleaks.toml`) et ajouter une
  recherche par expressions régulières (`scripts/scan_secrets.sh`).
- **Aucun outil ne vérifie les étiquettes** sans configuration supplémentaire :
  c'est la règle Conftest n° 2 qui le fait.

Le détail de la comparaison entre les outils est dans [`comparaison_checkov_trivy.md`](comparaison_checkov_trivy.md).
