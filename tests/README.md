# Jeux de plans de test — Policy as code (Partie 4)

## Règles (`policies/`)

| Code | Fichier | Règle | Valeur inconnue au plan |
|---|---|---|---|
| **IAM-001** | `iam.rego` | **Règle 1.** Refuser toute politique (IAM : utilisateur, groupe, rôle, gérée ; ou politique de bucket S3) dont une déclaration `Allow` contient `Action: "*"` (ou `"*:*"`, ou `NotAction`). Un `Deny "*"` est toléré, car il restreint. *Avertissement* `IAM-002` pour `service:*`. | **Refus** (fail-closed) |
| **TAG-001** | `tags.rego` | **Règle 2.** Refuser toute ressource étiquetable sans étiquette `owner` non vide. *Avertissement* `TAG-002` si `env` manque. | **Refus** (fail-closed) |
| **S3-001** | `s3_public_access.rego` | **Règle 3 (notre choix).** Chaque `aws_s3_bucket` doit avoir un `aws_s3_bucket_public_access_block` avec les **4 verrous à `true`**. | **Refus** (fail-closed) |

`lib/tfplan.rego` regroupe les fonctions communes : ressources présentes après
apply (on exclut les suppressions), détection de `after_unknown`, et
normalisation chaîne/liste des champs IAM.

### Pourquoi la règle 3 ?

L'exposition publique de `novacorp-customer-data` est le risque n° 1 de
NovaCorp. Checkov et Trivy l'analysent dans le **code**, mais un simple
commentaire `#checkov:skip` suffit à les faire taire, et une valeur venue
d'une variable ou d'un module leur échappe en partie. La règle vérifie le
**plan**, c'est-à-dire les valeurs résolues réellement envoyées à AWS. Elle
couvre les deux cas : verrou absent, ou verrou présent mais désactivé.

### Valeurs inconnues avant apply : notre choix

Nous évaluons le **plan avant apply**, pour que le contrôle se fasse avant
tout déploiement. Toute valeur `after_unknown` utile à une règle entraîne un
**refus (fail-closed)** : ce qu'on ne peut pas vérifier n'est pas accepté.
Pour que le code légitime reste vérifiable, il construit ses ARN et ses
références à partir d'attributs **connus au plan** :

- `aws_s3_bucket.x.bucket` plutôt que `.id` ;
- `"arn:aws:s3:::${bucket}"` plutôt que `aws_s3_bucket.x.arn`.

Le plan `rule1_iam_unknown.json` démontre ce comportement.

À noter : un attribut inconnu est **absent** de `change.after` et n'apparaît
que dans `change.after_unknown`. Le test unitaire
`test_tags_unknown_denied_fail_closed` a révélé ce piège dans la première
version de la règle 2, qui a été corrigée.

## Plans (`tests/plans/`)

Ce sont de **vrais** plans (`terraform show -json`), produits par
`scripts/gen_test_plans.sh` dans des copies isolées sans state. Il s'agit de
plans de création, donc reproductibles. Ils sont **assainis** par
`scripts/sanitize_plan.py` : les valeurs sensibles et les clés
`password|secret|token` sont remplacées par `REDACTED`.

| Plan | Origine | IAM-001 | TAG-001 | S3-001 | Conftest |
|---|---|---|---|---|---|
| `plan_bad.json` | branche `naive` | ❌ 1 | ❌ 4 | ❌ 2 | **échec** (7 refus) |
| `plan_good.json` | branche `secure` | ✅ | ✅ | ✅ | **succès** |
| `rule1_iam_fail.json` | `secure` + `"*"` ajouté à la politique du groupe | ❌ 1 | ✅ | ✅ | échec (règle 1 seule) |
| `rule1_iam_unknown.json` | `secure` + condition sur `aws_iam_user.app_writer.arn` (inconnu) | ❌ 1 | ✅ | ✅ | échec (fail-closed) |
| `rule2_tags_fail.json` | `secure`, `app-writer` étiqueté `env` seulement | ✅ | ❌ 1 | ✅ | échec (règle 2 seule) |
| `rule3_s3_fail.json` | `secure`, `block_public_policy = false` dans le module | ✅ | ✅ | ❌ 2 | échec (règle 3 seule) |

**Chaque règle a donc au moins un plan qui la fait échouer et un plan qui la
satisfait** (`plan_good.json`, plus les plans des autres règles).

## Rejouer

```bash
bash scripts/gen_test_plans.sh     # régénère les plans (LocalStack démarré)
bash scripts/test_policies.sh      # tests unitaires + matrice attendue
conftest test tests/plans/plan_bad.json  -p policies   # échoue
conftest test tests/plans/plan_good.json -p policies   # réussit
```

Sorties capturées : `resultats_policies.txt` et `conftest_plan_bad_vs_good.txt`.
