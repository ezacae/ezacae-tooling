# Spécification — Brique 1 du harnais ezacae : cadrer un besoin, jusqu'aux tickets Jira

Statut : Brouillon, version 3
Version 1 rédigée le mercredi 9 septembre 2026 pour le point avec Alexandre. Version 2 après ce point : le sprint se recentre sur l'amont. Version 3 le même jour : vocabulaire posé, pas de conception dans ce sprint, découpage par `/to-tickets`. Relecture demandée à Alexandre : **sans objection jeudi 10 septembre à 12h, les tickets du sprint sont créés vendredi 11 dans le projet Tooling.** Démonstration le vendredi 18 septembre.

**En cinq lignes.**

1. **Ce qu'on livre le 18** : `/scope`, qui prend un besoin, pose les bonnes questions, écrit une page de cadrage et une page de spécification fonctionnelle, et pose la taille ; puis `/to-tickets`, qui découpe en stories reliées à l'épique une fois le fonctionnel validé.
2. **Ce qui rend le circuit sûr** : la taille est une décision humaine ; le fonctionnel est validé par un clic dans Jira du responsable produit, clic que l'assistant ne peut pas faire ; rien de technique n'est écrit dans ce sprint.
3. **Ce qu'on mesure le 18** : l'amont du run 2 du banc (dix minutes, quatre dollars, 621 lignes, zéro question posée, une inconnue laissée de côté) contre le même amont avec `/scope`.
4. **Ce qui est exclu** : la conception, qui commence quand un développeur prend un ticket, et `/develop` (sprint 2) ; la diffusion large et la documentation projet (sprint 3). Feuille de route jointe.
5. **Ce qu'on tranche par relecture** (section 7) : ce qu'Alexandre entend par « conception » dans l'amont, la grille des tailles, le compte Jira dédié.

## Vocabulaire

| Mot | Ce que c'est | Qui le produit |
|---|---|---|
| **Besoin** | Ce que quelqu'un demande, en deux phrases. | La personne |
| **Ticket** | Le mot générique de Jira : tout ce qui a un numéro (RD-42). Les mots ci-dessous sont des types de ticket, choisis à la création. Chaque type suit son propre circuit de statuts : seuls certains types portent nos portes. | — |
| **Épique** (Epic) | Le ticket Jira qui porte le besoin entier et contient les autres. Un besoin, une épique. | `/scope`, dès le début |
| **Cadrage** | Une page : le besoin reformulé, pour qui, pourquoi, hors sujet, les réponses aux questions posées. | `/scope` |
| **Spécification fonctionnelle** | Une page : ce que fait l'application vue de l'utilisateur, le processus métier en récit plus diagramme, les fonctions touchées. | `/scope` |
| **Taille** | S, M, L ou « sans développement ». Une étiquette sur l'épique. | La personne, au cadrage |
| **Story** | Un ticket rattaché à l'épique, qui décrit un comportement vu de l'utilisateur, faisable d'un trait et vérifiable seul. Exemple : « un client voit sa facture du mois avec la remise appliquée ». C'est ce que `/to-tickets` crée. | `/to-tickets`, après validation |
| **Tâche** (Task) | Comme une story, sans utilisateur visible : travail technique ou d'organisation. Exemple : « créer le dépôt GitLab de test ». | `/to-tickets` ou la personne |
| **Bug** | Un comportement faux à corriger. Passe par `/scope` comme tout besoin. | La personne |
| **Sous-tâche** (Sub-task) | Un morceau d'une story, qui ne vit pas seul et suit souvent un circuit simplifié sans nos portes. **Jamais dans notre chaîne** : un ticket trop gros se découpe en deux stories. | — |
| **Découpage** | Le passage d'une épique validée à ses stories et tâches, chacune reliée à l'épique et disant ce qui la bloque. | `/to-tickets` |
| **Conception** | Ce qu'on fait quand on prend un ticket à faire : comment on l'implémente, données, composants, choix. Par ticket, jamais par épique. | `/develop`, sprint 2 |

## 1. But

Depuis mars, le chantier harnais a produit des audits et des documents de méthode, mais aucun outil que l'équipe utilise. Le point du 9 septembre a fixé la priorité : **l'amont du développement**. Cadrer un besoin, écrire la spécification fonctionnelle, découper en stories, et faire valider par un humain avant qu'une ligne de code soit écrite.

Ce que le banc de test a montré sur cet amont, au run 2 du 8 septembre :

- L'assistant a produit d'un trait, en dix minutes et pour quatre dollars, un document de **621 lignes, une quinzaine de pages**, mêlant cadrage, choix techniques et plan de code. Personne ne le lira.
- Il n'a posé **aucune question** avant d'écrire. Une inconnue réelle du besoin (aucun événement de fin d'abonnement) a été notée en réserve, pas posée.
- Au moment de valider, « tranche toi-même » a été pris pour un feu vert. Tant qu'un oui est une phrase, l'assistant peut se tromper sur le oui.

Trois principes, issus de la proposition du 31 août restée sans objection au 4 septembre : une seule référence pour tout le monde ; rien ne se déclenche seul ; on livre d'abord la version la plus simple qui roule.

## 2. Les deux commandes

**`/scope` — cadrer un besoin.** Ce qui se passe quand Lyes tape `/scope` sur le besoin du banc, « facturer des abonnements B2B » :

1. `/scope` crée l'épique dans Jira, dans le bon projet (client ou RD), ou reprend une épique existante.
2. `/scope` pose ses questions par séries numérotées, chacune avec une réponse recommandée. « Q1 : que se passe-t-il à la fin d'un abonnement ? Recommandé : facturation au prorata. » Lyes tranche. Série suivante, jusqu'à ce qu'il ne reste plus d'inconnue. Les faits, `/scope` va les chercher lui-même ; les décisions, il les pose.
3. `/scope` écrit la page de cadrage, la range dans le dépôt du projet, met le lien dans l'épique.
4. Lyes décide la taille : S, M, L ou « sans développement ». `/scope` pose l'étiquette. Un L s'arrête là : à découper en plusieurs épiques avant d'aller plus loin. Un besoin sans développement s'arrête aussi là, cadré.
5. `/scope` écrit la page de spécification fonctionnelle, la range à côté du cadrage, met le lien dans l'épique.
6. `/scope` passe l'épique en « à valider » et s'arrête. Il ne fait rien de plus.

**La porte.** Alexandre, ou le responsable produit du projet, lit les deux pages et change lui-même le statut de l'épique dans Jira. C'est le seul clic du circuit, et l'assistant ne peut pas le faire (section 3).

**`/to-tickets` — découper en stories.** Après le clic, la personne tape `/to-tickets` sur l'épique. La commande lit le cadrage et la spécification, propose un découpage en stories, chacune décrivant un comportement complet et vérifiable seul, et disant quelles stories la bloquent. La personne ajuste le découpage, puis les stories sont créées dans Jira, reliées à l'épique, avec leurs liens de blocage. C'est la commande originale de Matt Pocock, installée en référence et branchée sur nos scripts Jira. Le grill du 8 septembre n'autorisait que `grill-me` et `handoff` avant le 18 ; cette troisième pièce est ajoutée par décision du 9.

**Sur quoi `/scope` se base.** Pas une page blanche : deux pièces qui existent, assemblées par une page de consignes.

- **Les questions : `grill-me` de Matt Pocock**, installé en référence. C'est la pièce qui manquait au run 2.
- **Les documents : les gabarits et conventions de nos commandes de documentation actuelles**, écrits par Alexandre. Processus métier en récit plus diagramme, fonctions, et les règles éditoriales (pas de KPI, des types fonctionnels et non des prénoms, lisible en cinq minutes). Repris tels quels. Ce qu'on enlève : la mécanique autour (synchronisation Git, branche, sous-agents, manifeste, merge request), qui fait l'essentiel des 251 lignes actuelles et n'a rien à voir avec cadrer.

Ce qu'on écrit de neuf tient sur une page : les six étapes, la règle d'une page par document, la porte. On enlève, on n'ajoute pas.

**Ce qui est retiré en même temps, nommément** : la commande `/feature` et les agents `code-simplifier` et `technical-design-generator`, jamais appelés par le circuit ou doublons ; les copies de juin de `grill-me` et `handoff`, remplacées par les originaux ; le déclenchement automatique des méthodes superpowers, désactivé partout ; les descriptions qui permettaient à l'IA d'appeler d'elle-même les assistants internes. Dans le projet Tooling, tout ticket qui ne sert pas un des cinq sprints de la feuille de route est fermé.

**Diffusion.** Les commandes sont livrées sous forme de paquets (des « plugins ») que chaque poste télécharge depuis notre catalogue GitLab. Un poste garde l'ancienne version tant que le numéro ne change pas (ticket RD-22), et un poste neuf reçoit l'ordre d'activer les paquets mais pas l'adresse du catalogue. Dans ce sprint : chaque paquet modifié change de numéro dans la même livraison ; la procédure d'installation en cinq lignes est écrite ; le poste de Lyes est installé et vérifié à la main avant la démonstration. Le reste vient au sprint 3.

## 3. Taille et porte

**La taille est décidée par un humain au cadrage**, sur la complexité et les implications, jamais sur une durée : une journée d'humain est une heure d'agent, et ça ne change pas la nature du travail. Grille proposée, à confirmer (question 2) : sait-on déjà comment faire sans choix à trancher ; le changement reste-t-il à sa place sans toucher aux données, à l'interface ou à d'autres fonctions ; le besoin est-il clair. Trois oui : S. Un choix à trancher, un effet ailleurs ou une inconnue à lever : M. Plusieurs épiques cachées dans une seule : L, à découper. Une personne qui ne sait pas juger laisse la taille vide ; le premier développeur qui reprend l'épique la pose.

**Une seule porte dans ce sprint : la spécification fonctionnelle validée.** Quand les deux pages sont écrites, `/scope` passe l'épique en « à valider » et s'arrête. Le responsable produit lit deux pages, puis change lui-même le statut dans Jira. Dire « validé » dans la conversation ne suffit pas : nos scripts Jira, seul chemin de l'assistant vers les tickets, refuseront cette transition. Aujourd'hui ils l'autorisent ; c'est un travail de ce sprint, et il tourne partout : terminal, Cowork, claude.ai. `/to-tickets` refuse de démarrer sur une épique qui n'a pas passé la porte. Les noms exacts des statuts de l'épique dans le projet de test sont à caler avec l'administrateur Jira ; le circuit actuel a les statuts qu'il faut.

Effet pour l'équipe : valider, c'est lire deux pages et cliquer dans Jira. La personne qui clique est nommée dans l'historique. C'est la réponse à « spécifications en amont, validées avant le code ».

Ce que ce sprint ne garantit pas encore : que l'assistant ne contourne jamais nos scripts. Le compte Jira dédié, écarté au point du 9 pour son coût de licence, reste la seule fermeture complète. Question 3.

## 4. Exclusions

Reportées aux sprints suivants, dans l'ordre de la feuille de route : la conception, qui commence quand un développeur prend un ticket, `/develop`, ses portes et ses garde-fous, l'isolation et le modèle de l'agent de code (sprint 2) ; la diffusion sur Cowork et claude.ai, le contrôle de version automatique, la carte des compétences, l'installation collective, le compte Jira dédié, la documentation projet avec `/document` (sprint 3) ; le comparatif entre superpowers et les méthodes de Matt Pocock, le niveau 2 du juge, le coût de l'agent de code (sprint 4) ; la documentation société, la mémoire d'entreprise, la Méthode Harnais (sprint 5). Le renfort de Yacine n'est pas compté dans ce sprint.

Ce sprint compte huit jours ouvrés. Il tient si la liste ci-dessus reste fermée.

## 5. Mesure le 18

**Au banc de test, amont seulement.** Même besoin de facturation, même profil vierge. Comparer l'amont de `/scope` à un cycle complet serait trompeur ; le journal du run 2 isole la phase amont, qui sert de référence :

| Indicateur | Run 2, amont (outils actuels) | Cible `/scope` + `/to-tickets` |
|---|---|---|
| Ce qui est écrit | 621 lignes, environ 15 pages, tout mélangé | Deux pages : cadrage, spécification fonctionnelle |
| Questions posées à la personne avant d'écrire | 0 | Toutes les inconnues, en séries, avec recommandation |
| Inconnues laissées de côté | 1 (fin d'abonnement) | 0 |
| Stories | 0 (un plan de 19 tâches enfoui dans le document) | Stories Jira reliées à l'épique, avec leurs blocages |
| Validation | Une phrase interprétée comme un oui | Un clic dans Jira, nommé dans l'historique |
| Durée et coût de l'amont | 10 minutes, 4,25 $ | Mesurés, sans cible : la qualité du cadrage compte plus que dix minutes |

Le 115 / 115 du juge métier reste la référence de bout en bout pour le sprint 2, quand `/develop` reprendra ces stories.

**Définition de terminé** : le 18, Lyes lance `/scope` sur le besoin du banc depuis son poste, répond aux questions, obtient deux pages et une épique « à valider » ; Alexandre lit et clique dans Jira ; Lyes lance `/to-tickets` et les stories reliées apparaissent dans Jira. Sans intervention imprévue. La démonstration dure quinze minutes et montre le résultat et les chiffres du tableau, pas un tour des commandes.

## 6. Prérequis

1. **Relecture d'Alexandre** avec le délai de silence : sans objection jeudi 10 à 12h, les tickets du sprint sont créés vendredi 11 dans Tooling.
2. **Un projet Jira de test**, avec un type d'épique et un type de story rattachés au circuit de validation. Responsable et date à fixer ; sans lui, la démonstration se fait dans le projet Tooling.
3. **Un dépôt GitLab de test** pour le banc, qui accueille les deux pages de `/scope`. À côté du dépôt de référence, jamais dedans.
4. **Trente minutes sur le poste de Lyes** la semaine du 14, pour l'installation et une première exécution.
5. **La date du 18 confirmée** auprès de l'équipe, avec la raison vraie du report : la diffusion des outils n'atteignait pas les postes.

## 7. À trancher par relecture

**Question 1 — Ce qu'Alexandre entend par « conception » dans l'amont.** Au point du 9, l'amont a été décrit comme « scoping, spécifications fonctionnelles avec les processus métier, et après la partie plus technique, conception ». Deux lectures possibles. Soit la documentation d'architecture du projet, qui existe dans nos conventions et relève de `/document`, sprint 3. Soit la conception par ticket, qui commence quand un développeur prend un ticket, et relève de `/develop`, sprint 2. Dans les deux cas, pas dans ce sprint. La spec le dit ainsi ; une phrase d'Alexandre suffit à confirmer ou corriger.

**Question 2 — La grille des tailles.** Accord de principe sur la complexité au point du 9. Reste le seuil : une inconnue sur le besoin fait-elle un M (on la lève par une question au cadrage) ou un L (on s'arrête) ? Préférence, exprimée au point : un M si l'inconnue se lève par une question, un L si le besoin contient plusieurs épiques.

**Question 3 — Ce que devient le compte Jira dédié.** Écarté au point pour son coût de licence. Sans lui, la porte est tenue par nos scripts, pas par Jira. Options : le refinancer au sprint 3 quand `/develop` ajoute deux portes de plus ; ou accepter durablement la protection par scripts et le dire dans la carte des compétences. Préférence : décider au sprint 3, avec les chiffres du run 3.
