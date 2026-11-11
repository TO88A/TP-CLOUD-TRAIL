# Registre des exceptions (constats acceptés)

Chaque exception est déclarée **dans le code**, avec un commentaire
`#checkov:skip=<ID>:<justification>` ou `#trivy:ignore:<ID>`, et décrite ici.
Une exception n'est pas un oubli. C'est une décision tracée, qui a un
propriétaire et une condition de levée.

| ID | Règle(s) | Ressource(s) | Emplacement dans le code | Justification | Mesure compensatoire | Condition de levée |
|---|---|---|---|---|---|---|
| **EXC-01** | CKV_AWS_145 · AWS-0132 | `module.*.aws_s3_bucket.this`, `…server_side_encryption_configuration.this` | `terraform/modules/secure-bucket/main.tf` | KMS n'est pas activé dans l'environnement imposé (`SERVICES=s3,iam,sts`). L'énoncé (§7) prévoit ce cas. | Chiffrement par défaut **SSE-S3 (AES256)** sur les deux buckets et sur l'objet de configuration, TLS obligatoire. | Passage sur un vrai AWS : clé KMS CMK avec rotation pour `novacorp-customer-data`. Le bucket de journaux reste en SSE-S3, seul mode accepté par la journalisation d'accès S3. |
| **EXC-02** | CKV_AWS_144 | les 2 buckets | `modules/secure-bucket/main.tf` | Laboratoire mono-région. La réplication demande une seconde région, un bucket cible et un rôle IAM de réplication, et double le coût de stockage. | Versioning et cycle de vie actifs : protection contre les suppressions et écrasements. | Production avec un objectif de reprise (RPO/RTO) qui impose une copie inter-région. |
| **EXC-03** | CKV2_AWS_62 | les 2 buckets | `modules/secure-bucket/main.tf` | Aucun service de notification (SNS, SQS, Lambda, EventBridge) n'existe dans l'environnement, et aucun consommateur n'est défini. | Journaux d'accès S3 vers `novacorp-logs/s3-access/`. | Mise en place d'une détection (EventBridge vers SIEM). |
| **EXC-04** | CKV_AWS_18 · AWS-0089 | `module.logs_bucket` | `modules/secure-bucket/main.tf` (`#trivy:ignore:AWS-0089[bucket=novacorp-logs]`) | `novacorp-logs` **est** le bucket de destination des journaux. Le faire journaliser vers lui-même créerait une boucle. | Une `precondition` du module **interdit** à tout autre bucket d'omettre `access_log_target_bucket` (`is_log_destination` doit valoir `true`). Le bucket de données est bien journalisé. | Vrai AWS : journaux du bucket de journaux envoyés vers un compte « log archive » dédié. |
| **EXC-05** | CKV_AWS_273 | `aws_iam_user.app_writer` | `terraform/main.tf` | L'énoncé impose un **utilisateur IAM** `app-writer`. | Aucun droit attaché directement à l'utilisateur (tout passe par le groupe), droits limités à `s3:PutObject` et `s3:AbortMultipartUpload` sur `novacorp-logs/app/*`, aucune clé d'accès créée par Terraform. | Production : rôle IAM assumé par l'application (OIDC, IRSA ou profil d'instance) à la place de l'utilisateur. |
| **EXC-06** | AWS-0123 | `aws_iam_group.app_writers` | `terraform/main.tf` | Groupe d'un **compte de service** sans accès à la console. Une condition `aws:MultiFactorAuthPresent` bloquerait l'application, qui ne peut pas présenter de MFA. | Droits minimaux (voir EXC-05). | Disparaît avec EXC-05 (rôle à la place de l'utilisateur). |

**Note sur la portée de EXC-04 (Checkov).** Un commentaire `#checkov:skip`
placé dans un module s'applique à **toutes** ses instances. Checkov marque donc
aussi CKV_AWS_18 comme « ignoré » pour `module.customer_data_bucket`. Ce n'est
pas une faille : cette instance active bien la journalisation, et la
`precondition` l'impose. L'exception Trivy, elle, est ciblée
(`[bucket=novacorp-logs]`).
