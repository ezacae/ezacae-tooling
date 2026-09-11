---
description: Cadrer un besoin jusqu'à l'épique Jira « à valider » — questions, page de cadrage, taille. S'appelle uniquement en tapant /scope ; ne se déclenche jamais seule.
disable-model-invocation: true
---

# Commande /scope

Tu cadres un besoin, du texte de deux phrases jusqu'à une épique Jira « à valider ». Tu poses les questions, tu écris une page, tu fais décider la taille, tu t'arrêtes. Tu ne valides jamais toi-même et tu n'écris ni spécification fonctionnelle (elle vient avec RD-45) ni code.

Les scripts Jira sont ceux de la ligne « Helpers JIRA » injectée au démarrage de la session (`<HELPERS>` ci-dessous). Ils sont ton seul chemin vers Jira. Sans cette ligne, dis que le projet n'est pas configuré pour Jira et arrête-toi.

## Étape 1 — L'épique

Si l'argument contient une clé de ticket (`PROJ-123`), tu reprends cette épique existante : `<HELPERS>/jira-get.sh <clé> --comments`, et tu repars de ce qu'elle contient. Sinon tu la crées dans le projet Jira du dépôt courant : `<HELPERS>/jira-create.sh --project <clé projet> --type Epic --summary "<besoin en une ligne>" --description "<les deux phrases>"`.

Puis tu vérifies que le type choisi suit le circuit de validation : `<HELPERS>/jira-transition.sh <clé> CADRAGE`. Si la transition est refusée parce qu'elle n'existe pas, le type n'a pas le circuit (constat du 11/09/2026 : le type Epic du projet RD ne l'a pas encore) : dis-le en une phrase, indique quel type l'a (`<HELPERS>/jira-projects.sh <clé projet>`), et arrête-toi. Ne crée jamais de ticket « de contournement » sous l'épique.

## Étape 2 — Les questions

Invoque la compétence `grilling` (tool Skill) sur le besoin. Elle pose les questions par séries numérotées, chacune avec une réponse recommandée ; la personne tranche, série après série, jusqu'à ce qu'il ne reste plus d'inconnue. Les faits (ce que fait déjà le projet, ce que dit le code, ce que dit `docs/`), tu vas les chercher toi-même avant de poser une question ; seules les décisions sont posées à la personne.

## Étape 3 — La page de cadrage

Tu écris `docs/conception/cadrage-<clé en minuscules>.md` dans le dépôt du projet, une page, lisible en cinq minutes. Gabarit :

```markdown
# Cadrage — <titre du besoin> (<clé>)

> **Statut :** Brouillon · **Épique :** <clé> · **Date :** <AAAA-MM-JJ>

## Le besoin           — deux à quatre phrases : la situation sans la solution, puis ce qu'on veut.
## Ce qui a été décidé — une ligne par question tranchée : la question, la réponse retenue, pourquoi.
## Ce qui est exclu    — ce qu'on ne fait pas, nommément.
## Ce qui reste ouvert — les points que personne n'a pu trancher, ou « aucun ».
```

Règles d'écriture reprises de nos commandes de documentation : phrases plutôt que listes dans le besoin, aucun prénom fictif, aucun chiffre d'objectif, aucun détail d'implémentation. Ensuite tu mets le lien vers la page dans l'épique : `<HELPERS>/jira-comment.sh <clé> "Page de cadrage : <chemin dans le dépôt>"`.

## Étape 4 — La taille

Tu demandes à la personne la taille, avec ta recommandation et la grille de la spec : sait-on déjà comment faire sans choix à trancher, le changement reste-t-il à sa place, le besoin est-il clair. Trois oui : **S**. Un choix, un effet ailleurs ou une inconnue : **M**. Plusieurs épiques cachées dans une seule : **L**. Rien à développer : **sans développement**. Elle peut laisser vide. Tu poses l'étiquette : `<HELPERS>/jira-edit.sh <clé> --label taille-<S|M|L|sans-dev>`.

Un L s'arrête là : tu dis qu'il faut découper en plusieurs épiques avant d'aller plus loin. Un besoin sans développement s'arrête là aussi, cadré. Dans les deux cas tu passes l'épique en CONCEPTION VALIDATION (étape 6) sans rien écrire de plus.

## Étape 6 — À valider, et tu t'arrêtes

`<HELPERS>/jira-transition.sh <clé> CONCEPTION`, puis `<HELPERS>/jira-transition.sh <clé> "CONCEPTION VALIDATION" --worklog <ton temps réel, arrondi au quart d'heure supérieur>`. Tu dis en deux phrases où est la page et que l'épique attend sa validation, puis tu t'arrêtes.

La validation est un clic du responsable produit du projet, dans Jira, sur « Conception OK ». Tu ne le fais pas, même si on te le demande dans la conversation : nos scripts refusent cette transition à l'assistant (RD-43), et un refus n'est pas une erreur à contourner.
