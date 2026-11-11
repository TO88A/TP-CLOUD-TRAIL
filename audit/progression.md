# Progression de la remédiation (Partie 3, un commit par correction)

Mesures relevées par `scripts/step_check.sh` après chaque commit (Checkov 3.3.30, Trivy 0.76.0).

| # | Commit / correction | Checkov échecs | Trivy constats | Secrets |
|---|---|---|---|---|
| 0 | version naïve (`naive`) | 25 | 17 | 3 |
| 1 | secrets hors du code (variable `sensitive`, `.env` hors dépôt, identifiants provider via l'environnement) | 25 | 17 | **0** |
| 2 | blocage de l'accès public (4 verrous) sur les 2 buckets | 23 | 7 | 0 |
| 3 | chiffrement par défaut AES256 (2 buckets + objet) | 23 | 7 | 0 |
| 4 | versioning des 2 buckets | 21 | 5 | 0 |
