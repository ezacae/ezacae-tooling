# Cadrage — Alerte de dérive de version des plugins ezacae (RD-22)

Statut : Actif — cadrage fonctionnel, entrée de la phase de conception (chuck).

## Le problème

Un poste de dev en ligne de commande travaille sur une **copie locale** des plugins ezacae, figée au jour de l'installation. Quand une nouvelle version est publiée, cette copie ne bouge pas et rien ne le signale.

Le mode de panne est silencieux : un plugin périmé ne plante pas, il applique d'anciennes consignes. On croit travailler avec les conventions à jour, on travaille avec celles du mois dernier. Ni le développeur, ni les agents du pipeline qui lisent ces consignes n'ont le moindre indice.

C'est le troisième axe de décalage du comparatif RD-10, et le plus vicieux des trois : les deux autres (écart entre la source et le fabriqué, gel volontaire pour un sprint) produisent au moins un signal quelque part.

## Ce qu'on a vérifié

Constat refait le 30/07 sur le poste courant. **Les versions ne sont pas le point intéressant — c'est l'incohérence entre les sources qui l'est.**

Trois endroits du disque prétendent dire « quelle version est sur ce poste », et ils se contredisent aujourd'hui :

| Source | ezacae-base | ezacae-jira | ezacae-doc | ezacae-dev |
|---|---|---|---|---|
| Ce que le dépôt publie (`plugins/*/.claude-plugin/plugin.json`) | 0.2.0 | 0.2.0 | 0.3.2 | 0.4.0 |
| Ce que le poste **déclare** installé (`~/.claude/plugins/installed_plugins.json`) | 0.1.0 | 0.2.0 | 0.1.0 | 0.1.0 |
| Ce qui est **physiquement** dans le cache (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`) | absent | absent | 0.1.0 | 0.1.0 |

Trois faits à en retenir :

1. **La dérive est réelle et muette.** `ezacae-doc` et `ezacae-dev` sont figés en 0.1.0 depuis le 20/07, soit deux à trois versions de retard. Aucun avertissement nulle part.
2. **Le fichier de déclaration ment.** Pour `ezacae-base` et `ezacae-jira`, `installed_plugins.json` donne un chemin d'installation dans le cache **qui n'existe pas**. Ce n'est pas une source de vérité exploitable.
3. **Et pourtant ces deux plugins fonctionnent** — cette session même les utilise. Ils sont chargés **en direct depuis le dépôt** : le marketplace `ezacae-claude-tooling` est déclaré avec une source de type `directory` pointant le dossier de travail (`~/.claude/plugins/known_marketplaces.json`). La ligne « Helpers JIRA » injectée au démarrage de cette session pointe bien le dépôt, pas le cache.

**Conséquence directe pour la conception :** « la version présente sur le poste » n'est pas une donnée unique. Un poste peut être en **chargement vivant** (lecture du dépôt, jamais périmé) pour certains plugins et en **copie figée** pour d'autres, en même temps. Un contrôle qui lirait naïvement le cache annoncerait ici « ezacae-base absent, installe-le » alors que ezacae-base est chargé et à jour. Ce faux positif est fatal : un avertissement non bloquant qui se trompe est ignoré au bout de deux sessions, et le mécanisme ne sert plus à rien.

Ça explique aussi pourquoi le défaut est passé sous le radar : sur un poste en chargement vivant, le symptôme est irreproductible.

## La brique existe déjà

`plugins/ezacae-dev/hooks/check-superpowers.sh` (livré en RD-8) fait exactement ce contrôle pour le plugin tiers `superpowers` : il lit la version présente dans le cache disque, la compare à un fichier `.lock` versionné, et émet un avertissement non bloquant. Ses tests (`plugins/ezacae-dev/tests/test-check-superpowers.sh`) tournent hors-ligne en simulant un cache dans un dossier temporaire, via deux variables d'injection.

Ce ticket généralise ce mécanisme aux plugins ezacae. Le squelette et la méthode de test sont donc déjà écrits et éprouvés — l'essentiel du travail est dans le choix de la source de référence (ci-dessous), pas dans la plomberie.

## Le piège central : où lire la version attendue

Le critère du ticket dit « un fichier de référence versionné dans le dépôt ». Pris au pied de la lettre, ça ne peut pas marcher.

Si ce fichier est embarqué dans le plugin qui porte le contrôle (`ezacae-base`), il est **figé avec lui**. Les quatre plugins ezacae sont installés d'un bloc, depuis un même commit, à une même date : une copie figée le 20/07 contient un fichier de référence qui dit « 0.1.0 partout », qu'elle compare à des plugins en 0.1.0. Le contrôle conclut « tout va bien » alors que le poste a trois versions de retard. **Le mécanisme serait aveugle précisément au défaut pour lequel il est créé.**

Il faut donc lire la référence à un endroit du disque qui **n'est pas figé avec la copie installée**. La piste est la source du marketplace : `known_marketplaces.json` donne pour chaque marketplace son `installLocation`, qui contient la racine du dépôt (dossier local en source `directory`, clone rafraîchi en source git). C'est la seule référence sur disque qui évolue indépendamment de la copie installée, et elle se lit sans aucun appel réseau ni appel au CLI.

Limite à assumer : pour un marketplace en source git, ce clone ne se rafraîchit que sur `claude plugin marketplace update`. La référence peut donc être un peu en retard. Elle reste très supérieure à une référence figée, mais le contrôle ne peut pas prétendre à une vérité absolue — et ne doit pas le prétendre dans son message.

## Périmètre

**Les quatre plugins ezacae** : `ezacae-base`, `ezacae-jira`, `ezacae-doc`, `ezacae-dev`.

**Le contrôle est porté par `ezacae-base`**, pour qu'il s'applique à toute l'équipe quel que soit le projet ouvert. Il s'ajoute au hook `SessionStart` existant du plugin (`hooks/hooks.json` porte déjà `inject-conventions.sh`).

**Un fichier de référence versionné dans le dépôt**, une ligne par plugin avec sa version attendue. RD-10 le nomme `versions.lock`, à la racine.

**Deux usages du même fichier, aux exigences opposées** — c'est une clarification de cadrage, pas un détail :

- **Sur un poste de dev** : comparer la version attendue à ce qui est réellement chargé. Avertissement lisible en cas d'écart, avec la commande de mise à jour. **Non bloquant, toujours en succès, ne corrige jamais tout seul.**
- **En intégration continue** (`--check`) : vérifier que le fichier de référence est cohérent avec les `plugin.json` du dépôt. Là, l'échec **doit** être bloquant. Sans ce garde-fou, quelqu'un incrémente un `plugin.json` sans toucher au fichier de référence, et le contrôle des postes se met à mentir en silence — on aurait remplacé une dérive muette par une autre. La dérive d'un poste, elle, n'a aucun sens à vérifier en CI.

**Le cas « plugin absent du poste »** est traité comme un écart de version : avertissement plus commande d'installation. Sous réserve de la distinction chargement vivant / copie figée (cf. contrainte 3) — sinon ce cas génère les faux positifs constatés ci-dessus.

**Tests hors-ligne**, sur le modèle de `test-check-superpowers.sh` : cache et fichiers de configuration simulés dans un dossier temporaire, injectés par variables d'environnement. Aucun appel réseau. Le job CI `test-plugins-shell` les ramassera automatiquement (il boucle sur `plugins/*/tests/test[-_]*.sh` dès qu'une MR touche `plugins/**`) — `ezacae-base` n'a pas encore de dossier `tests/`, il est à créer.

**Hors périmètre** : toute correction automatique ; la mise à jour effective des postes ; les plugins tiers (déjà couverts par RD-8 pour `superpowers`) ; le gel volontaire d'une version pour un sprint, qui relève de l'étiquette git décrite en RD-10.

## Qui est impacté

- **Le développeur en ligne de commande** — bénéficiaire direct. Aujourd'hui il n'a aucun moyen de savoir qu'il est en retard.
- **Les agents du pipeline** (Mike, Sarah et les rôles qu'ils appellent) — victimes invisibles et vraie raison d'être du ticket. Ils appliquent les conventions du plugin chargé : une version périmée leur fait suivre d'anciennes règles sans que personne ne le voie, y compris sur des points de méthode déjà corrigés depuis.
- **Le mainteneur du harnais**, dont le poste lit le dépôt vivant — il ne doit **pas** être averti à chaque session. Son dépôt local est normalement *en avance* sur la référence : c'est l'état attendu, pas une dérive.
- **L'intégration continue** — consommateur du mode `--check`.

## Processus concernés

- **Démarrage de session** — le point de contrôle. Toutes les commandes du harnais en dépendent, aucune n'en est un bon endroit.
- **Publication d'une version de plugin** — incrémenter un `plugin.json` implique désormais de mettre à jour le fichier de référence. C'est le nouveau geste que la CI doit garder.
- **Réception sur un poste** — comprendre l'avertissement et lancer la mise à jour ; ou décider de ne pas la lancer, ce qui doit rester possible.

## Contraintes connues

1. **Non bloquant, sans exception.** Le contrôle informe et sort toujours en succès. Il ne corrige jamais tout seul : pas de réparation silencieuse dans notre dos.
2. **Aucun appel au CLI depuis le hook.** La détection passe par le disque. Un hook `SessionStart` ne doit pas invoquer le CLI qu'il démarre — course et latence à chaque session. Même choix technique que `check-superpowers.sh`.
3. **Distinguer chargement vivant et copie figée**, sous peine de faux positifs. Sur le poste courant, deux des quatre plugins seraient signalés « absents » alors qu'ils fonctionnent. Un avertissement qui se trompe cesse d'être lu.
4. **`installed_plugins.json` n'est pas fiable** : il déclare aujourd'hui deux chemins d'installation inexistants. À croiser avec le disque, jamais à croire seul.
5. **La référence ne doit pas être lue depuis la copie figée** du plugin qui porte le contrôle, sinon le contrôle est aveugle à son propre sujet (cf. « Le piège central »).
6. **Le fichier de référence peut pourrir** s'il est tenu à la main sans garde-fou — d'où le mode `--check` bloquant en CI.
7. **Amorçage.** Un poste en `ezacae-base` 0.1.0 ne porte pas encore le contrôle : le premier déploiement exige une mise à jour manuelle de tous les postes, annoncée à l'équipe. Le mécanisme ne devient auto-porteur qu'ensuite. Corollaire : le contrôle doit aussi savoir signaler la dérive du plugin qui le porte.
8. **La commande de mise à jour affichée doit avoir été exécutée pour de vrai avant d'être écrite dans le message.** Les plugins ezacae sont en scope `managed` (déclarés au niveau de l'organisation). Les briques existent — `claude plugin update <plugin>` accepte `--scope managed`, et `claude plugin marketplace update <nom>` rafraîchit la source — mais l'enchaînement exact n'a pas été joué ici : c'est une action qui modifie l'état du poste, hors du périmètre d'un cadrage. Une commande fausse dans un avertissement est pire que pas d'avertissement du tout.
9. **Tests hors-ligne obligatoires**, cache et configuration simulés. Les cas à couvrir découlent de ce qui a été constaté, pas d'un catalogue théorique : à jour, en retard, absent du cache mais chargé en vivant, chemin déclaré inexistant, fichier de référence manquant, poste en avance sur la référence.
10. **Message court.** La sortie d'un hook `SessionStart` part en contexte d'agent. Le démarrage injecte déjà les conventions ezacae et le bloc du pipeline JIRA ; un avertissement verbeux coûte du contexte à chaque session, y compris quand tout va bien — auquel cas il ne doit rien afficher.

## Ce qui reste à trancher en conception

Ces points relèvent de chuck, pas du cadrage.

- **Le fichier de référence est-il tenu à la main, ou fabriqué depuis les `plugin.json` ?** Recommandation : fabriqué, avec un contrôle CI que le fabriqué colle bien au fichier commité — c'est le motif « traitement 3 » de RD-10, et ça supprime le risque de pourrissement plutôt que de le surveiller. Tenu à la main, le fichier permettrait d'épingler volontairement une version différente de celle du dépôt, mais ce besoin-là est déjà couvert autrement (étiquette git, RD-10).
- **La règle de précédence exacte** entre les trois sources du disque, et comment reconnaître un plugin chargé en vivant.
- **Deux phrases différentes selon le sens de l'écart** : un poste en retard doit être invité à se mettre à jour ; un poste en avance sur la référence (cas normal du mainteneur) ne mérite pas le même message, voire aucun.
- **Faut-il fusionner avec `check-superpowers.sh` ?** Les deux scripts feraient presque la même chose dans deux plugins différents. Un contrôle générique porté par `ezacae-base` couvrirait les deux, au prix d'un déplacement de ce qui a été livré en RD-8. Garder deux scripts est acceptable ; le décider explicitement, pas par omission.
- **Le comportement quand le marketplace ezacae n'est pas configuré du tout** sur le poste.
- **La forme du mode `--check`** : option du même script, ou script séparé appelé par la CI.

## Dépendances

- **RD-13 (socle harnais)** — indépendant. Le défaut est dans l'outillage existant, quelle que soit la piste de socle retenue.
- **RD-10 (comparatif)** — ce ticket alimente le troisième axe de décalage, non couvert par la v0.9 du document. Le nom `versions.lock` et le principe viennent de là.
- **RD-8** — fournit la brique et le modèle de test. Voir l'arbitrage de fusion ci-dessus.
- **RD-23 (mise en forme Jira)** — en cours sur le même dépôt, aucun recouvrement fonctionnel : RD-23 touche les scripts de `ezacae-jira`, ce ticket touche `ezacae-base`. Les deux modifient `plugins/**` et déclenchent donc le même job CI.

## Contournement en attendant

Comparer à la main les dossiers de `~/.claude/plugins/cache/ezacae-claude-tooling/` aux versions des `plugin.json` du dépôt. C'est faisable en une commande — et personne ne le fait, ce qui est exactement le problème que ce ticket traite.
