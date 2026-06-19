# Commande /feature

> ⚠️ **Cette commande est remplacée par le pipeline Mike ⇄ Sarah piloté par JIRA.**
> Voir le fichier `PIPELINE.md` du skill `jira-pipeline` (plugin ezacae-jira).

Pour travailler à partir d'un ticket JIRA :

1. **Cadrage + doc** → `/mike <TICKET>` (le ticket doit être au statut `NOUVEAU`).
   Mike cadre le besoin, met à jour la doc, attache la fiche de résultat, transitionne en `CONCEPTION` et passe la main à Sarah.
2. **Conception → implémentation → revue** → Mike invoque automatiquement `/sarah <TICKET>`.
   Sarah enchaîne chuck (conception) → morgan/john (implémentation, branche + tests + MR) → `pr-review-toolkit:code-reviewer` (revue), en synchronisant le statut JIRA et en attachant les livrables.
3. **Doc finale** → Sarah redéclenche `/mike <TICKET>` (statut `RECETTE INTERNE`).

Pour une demande sans ticket (« ajoute une fonctionnalité »), lancer directement `/mike` : il crée le ticket dans le bon projet, puis déroule le pipeline.
