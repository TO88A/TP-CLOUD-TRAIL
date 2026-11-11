# Bonus — Comparaison Checkov 3.3.30 et Trivy 0.76.0

Analyse faite sur le **même code naïf** (`naive`, 5 ressources) puis sur la
version sécurisée.

## Chiffres

| | Checkov | Trivy |
|---|---|---|
| Constats sur `naive` | 25 échecs, **18 règles distinctes** | 17 constats, **8 règles distinctes** |
| Constats sur `secure` | 0 (9 exceptions) | 0 (4 exceptions) |
| Gravité fournie | ❌ `null` en version libre (il faut une clé Prisma Cloud) | ✅ LOW, MEDIUM, HIGH ou CRITICAL |
| Analyse des politiques en `jsonencode()` | ✅ | ❌ (aucun constat sur `Action="*"`) |
| Résolution des modules locaux | ✅ (adresse `module.x.aws_s3_bucket.this`) | ✅ (constat rattaché au fichier du module) |

## Correspondance des règles (version naïve)

| Thème | Checkov | Trivy | Commentaire |
|---|---|---|---|
| Public Access Block absent | CKV2_AWS_6 | AWS-0094 | Les deux le voient. |
| Les 4 verrous | (CKV_AWS_53 à 56, évaluées seulement s'il existe un PAB) | AWS-0086 / 0087 / 0091 / 0093 | Trivy en fait **4 constats HIGH** même sans PAB. Checkov n'en fait qu'un. |
| Versioning | CKV_AWS_21 | AWS-0090 | Équivalent. |
| Journaux d'accès | CKV_AWS_18 | AWS-0089 | Équivalent. |
| Clé KMS (CMK) | CKV_AWS_145 | AWS-0132 | Équivalent. Trivy le rattache aussi au bloc `server_side_encryption_configuration`. |
| Politique attachée à un utilisateur | CKV_AWS_40 | AWS-0143 | Équivalent. |
| **IAM `Action="*"` / `Resource="*"`** | CKV_AWS_62, 63, 286, 287, 288, 289, 290, 355, CKV2_AWS_40 | — | **Checkov seul** : c'est le constat le plus grave du TP. |
| Utilisateur IAM plutôt que SSO | CKV_AWS_273 | — | Checkov seul. |
| Réplication inter-région | CKV_AWS_144 | — | Checkov seul. |
| Cycle de vie | CKV2_AWS_61 | — | Checkov seul. |
| Notifications d'événements | CKV2_AWS_62 | — | Checkov seul. |
| MFA sur le groupe IAM | — | AWS-0123 | Trivy seul. Apparu avec la création du groupe en version `secure`. |
| Secret en dur dans le HCL | — | — | **Aucun des deux** (il faut gitleaks avec des règles étendues). |
| Identifiants dans le provider | CKV_AWS_41 **réussit** avec `"test"` | — | Faux négatif : seule la *forme* de la valeur est vérifiée. |
| Étiquettes `owner` / `env` | — | — | **Aucun des deux** sans règle personnalisée, d'où la règle Conftest TAG-001. |

## Différences de comportement observées

1. **Couverture IAM.** Checkov comprend le JSON produit par `jsonencode()`,
   Trivy 0.76 non. Si l'on n'utilisait que Trivy, l'administrateur `*:*`
   passerait inaperçu.
2. **Granularité.** Trivy éclate le Public Access Block en 4 constats HIGH.
   Le total brut (17 contre 25) ne dit donc rien de la couverture réelle :
   il faut comparer les règles distinctes et les thèmes.
3. **Piège Trivy : les plans binaires.** `trivy config` analyse aussi les
   fichiers `tfplan` présents dans le dossier. Pendant la remédiation, un vieux
   `terraform/tfplan` naïf faisait remonter 17 constats déjà corrigés. Nous
   avons donc déplacé les plans dans `build/` (voir `ci/ci.sh`).
4. **Exceptions.**
   - Checkov : `#checkov:skip=ID:raison`, **à l'intérieur** du bloc. Dans un
     module, l'exception s'applique à **toutes les instances**.
   - Trivy : `#trivy:ignore:ID`, **au-dessus** du bloc. Il accepte un filtre
     par attribut, par exemple `#trivy:ignore:AWS-0089[bucket=novacorp-logs]` :
     l'exception devient ciblée sur une seule instance du module, ce qui est
     plus précis.
5. **Gravité.** Sans gravité côté Checkov, impossible de filtrer par seuil
   (`--check HIGH`) sans plateforme commerciale. Trivy permet
   `--severity`/`--exit-code` directement.

## Conclusion

Les deux outils sont **complémentaires** et la chaîne CI les exécute tous les
deux :

- Checkov couvre mieux l'IAM et les bonnes pratiques S3 (cycle de vie,
  réplication, notifications).
- Trivy apporte une gravité exploitable, des exceptions ciblées, et repère la
  MFA.
- Aucun des deux ne couvre les **secrets** ni les **étiquettes** : ce sont
  gitleaks (configuration étendue) et Conftest qui comblent ces trous.
