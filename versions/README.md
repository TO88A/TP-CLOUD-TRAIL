# Versions naïve et sécurisée

Les deux versions du code Terraform sont des **branches Git**, comme le demande
l'énoncé :

| Version | Branche | Commit de référence | Contenu de `terraform/` |
|---|---|---|---|
| Naïve | `naive` | `d9d8b2e` (Partie 1) | 2 buckets nus, `Action="*"` / `Resource="*"`, mot de passe en dur, aucune étiquette |
| Sécurisée | `secure` (et `main`) | dernier commit | module `secure-bucket`, moindre privilège, aucun secret, étiquettes, exceptions documentées |

```bash
git switch naive   && ./ci/ci.sh   # échoue (étape 3/8 : secrets)
git switch secure  && ./ci/ci.sh   # réussit (8/8)
git log --oneline naive..secure    # un commit par correction (Partie 3)
```

## Pourquoi pas de copie figée de la version naïve ici ?

Une copie de `naive/terraform` dans ce dossier **réintroduirait le mot de
passe en dur** dans la branche sécurisée. Le hook pre-commit et la chaîne CI
le refuseraient, et ils auraient raison. À la place, ce dossier contient :

- [`naive_vers_secure.diff`](naive_vers_secure.diff) : le diff complet
  `d9d8b2e..secure -- terraform`, avec les valeurs secrètes **masquées** ;
- l'évolution des compteurs commit par commit :
  [`../audit/progression.md`](../audit/progression.md).

> La valeur réelle reste dans l'historique de la branche `naive`
> (`audit/secrets_historique.txt`). En situation réelle, il faudrait la
> **changer** puis réécrire l'historique (`git filter-repo`). C'est un risque
> résiduel documenté dans `SYNTHESE.md`.
