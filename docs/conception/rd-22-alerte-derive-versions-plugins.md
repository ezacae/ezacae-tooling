# Alerte de dérive de version des plugins ezacae (RD-22)

Statut : Actif — conception révisée après revue critique, en attente de validation. Type : feature.
Entrée : `docs/conception/cadrage-rd-22-alerte-derive-versions-plugins.md`.

## Objectif

Au démarrage de chaque session, tout développeur ezacae dont les plugins ne sont pas à la version publiée voit un avertissement lisible, avec la commande exacte pour se mettre à jour. Non bloquant : ça informe, ça ne corrige rien, ça ne bloque jamais.

Même forme que ce qui existe déjà pour le plugin tiers `superpowers` (`plugins/ezacae-dev/hooks/check-superpowers.sh`, livré en RD-8) : lecture sur le disque, comparaison à une version attendue, avertissement, sortie toujours en succès.

## Quatre règles imposées par ce qui a été vérifié le 30/07

Ces règles ne changent pas l'objectif. Elles écartent quatre façons de le rater.

**1. Ne jamais lire `claude plugin list`.** Cette commande affiche `ezacae-dev 0.1.0` sur le poste courant alors que la version réellement exécutée est la 0.4.0. Elle recopie `~/.claude/plugins/installed_plugins.json`, un fichier qui déclare aussi deux chemins d'installation inexistants. Preuve du décalage : le skill `chuck` chargé le 30/07 mentionne `/developer` dix fois et jamais « john » ni « morgan » ; la copie en cache censée être la version active (datée du 22/06) fait exactement l'inverse. Un contrôle fondé sur cette source produirait trois fausses alertes sur quatre plugins, dès la première session.

**2. Se taire sur un poste qui lit le dépôt en direct.** Quand le marketplace `ezacae-claude-tooling` est déclaré avec une source de type dossier — le cas du poste de maintenance — les plugins sont lus dans le dossier de travail et ne peuvent pas être périmés. Avertir là serait un faux positif à chaque session, et un avertissement qui se trompe cesse d'être lu au bout de deux jours.

**3. Ne pas lire la version attendue depuis la copie installée.** Les quatre plugins ezacae s'installent d'un bloc depuis un même commit. Une référence embarquée dans la copie installée est figée avec elle : un poste en retard de trois versions comparerait « 0.1.0 attendu » à « 0.1.0 installé » et conclurait que tout va bien. La référence se lit dans l'instantané local du marketplace, dont l'emplacement est donné par `~/.claude/plugins/known_marketplaces.json`.

**4. Ne pas croire cet instantané sans vérifier sa fraîcheur.** *(Règle ajoutée après revue — c'était le défaut le plus grave de la version précédente.)* L'instantané du marketplace n'évolue pas tout seul : il est rafraîchi par `claude plugin marketplace update`, la commande même que le contrôle s'apprête à recommander. Un développeur qui ne l'a jamais lancée possède un instantané aussi vieux que sa copie installée, annonçant la même version qu'elle. Le contrôle comparerait 0.1.0 à 0.1.0 et se tairait — sur le poste le plus en retard de l'équipe, c'est-à-dire précisément celui que ce ticket existe pour alerter.

Le contrôle doit donc **savoir quand il ne peut pas se prononcer**. Condition, sans seuil arbitraire : si la date de rafraîchissement du marketplace (`lastUpdated` dans `known_marketplaces.json`) n'est **pas strictement postérieure** à la date de la copie installée (date de modification du dossier de version dans le cache), alors la référence ne peut rien prouver de plus récent que ce qui est déjà installé. Le contrôle le dit et donne le geste qui lève le doute. Il vaut mieux un contrôle qui avoue son ignorance qu'un contrôle qui affirme à tort.

## Comportement attendu, cas par cas

| Situation du poste | Ce que fait le contrôle |
|---|---|
| Marketplace en source dossier (lecture du dépôt en direct) | silence |
| Source git, référence plus récente que la copie installée, versions égales | silence |
| Source git, référence plus récente que la copie installée, versions différentes | avertit : les deux versions, le plugin, la commande de mise à jour |
| Source git, référence **pas plus récente** que la copie installée | avertit : ne peut pas se prononcer, donne `claude plugin marketplace update` |
| Plugin attendu, absent du poste | avertit : commande d'installation |
| Version installée non sémantique (`unknown`, identifiant de commit) | avertit : version indéterminée, ne propose aucune comparaison chiffrée |
| `jq` absent, marketplace non configuré, structure illisible | **une ligne** : contrôle inopérant et pourquoi |

Distinction à tenir, c'est elle qui rend le contrôle crédible : **« rien à signaler » se dit par le silence, « je ne peux pas me prononcer » se dit en une ligne.** Un contrôle muet pour cause de panne est indistinguable d'un contrôle muet parce que tout va bien — c'est le défaut qu'on prétend corriger, reproduit dans l'outil qui le corrige.

Dans tous ces cas, **sortie en succès**. Seule exception : le mode `--check` de l'intégration continue, qui doit échouer — il n'est jamais appelé au démarrage d'une session.

### Versions non sémantiques

Le cas est constaté, pas théorique : sur le poste courant, trois plugins sont installés en version `unknown` (`context7`, `plugin-dev`, `frontend-design`) et un porte un identifiant de commit (`caveman/655b7d9c5431`). Comparer `unknown` à `0.3.2` produirait un avertissement permanent qu'aucune mise à jour ne ferait taire. Le contrôle reconnaît donc ces formes et bascule sur un message distinct, sans comparaison de numéros.

## Le fichier de version attendue

`versions.lock` à la racine du dépôt, une ligne par plugin :

```
ezacae-base 0.2.0
ezacae-jira 0.2.0
ezacae-doc 0.3.2
ezacae-dev 0.4.0
```

Format aligné sur `plugins/ezacae-dev/superpowers.lock` (une version nue aujourd'hui) : celui-ci devient une ligne `superpowers <version>` dès qu'un contrôle unique couvrira les deux, arbitrage laissé ouvert par le cadrage. Ne pas installer maintenant deux grammaires de verrou dans le même dépôt.

Ce fichier peut pourrir : quelqu'un incrémente un `plugin.json` et oublie de le mettre à jour, et le contrôle des postes se met à mentir en silence. D'où le mode `--check` lancé par l'intégration continue, qui compare `versions.lock` aux `plugin.json` du dépôt et **échoue** en cas d'écart.

`--check` a besoin de la racine du dépôt, pas du dossier plugins d'un poste : il la déduit de l'emplacement du script (`hooks/` → deux niveaux au-dessus), et accepte un chemin en argument pour les tests. Ce sont deux entrées distinctes qu'il ne faut pas confondre.

Le job `test-plugins-shell` ne se déclenche aujourd'hui que sur `plugins/**/*` et `.gitlab-ci.yml` : **`versions.lock` doit être ajouté à cette liste**, sinon une demande de fusion ne touchant que ce fichier passerait sans contrôle.

### Structure de l'instantané : supposée jusqu'à preuve, donc testée

La lecture de la référence suppose que l'instantané du marketplace contient l'arborescence du dépôt (`versions.lock` à sa racine, `plugins/<nom>/.claude-plugin/plugin.json`). C'est vrai pour nos quatre plugins, qui sont **internes** au marketplace (`source: ./plugins/<nom>` dans `.claude-plugin/marketplace.json`).

Ce n'est pas une propriété générale : vérifié le 30/07, l'instantané de `claude-plugins-official` ne contient **pas** `superpowers` sous `plugins/` — les plugins externes ne sont pas recopiés. Cet instantané n'est d'ailleurs pas un dépôt git (pas de `.git`, mais un `.gcs-sha`) : parler de « clone » serait faux. Le contrôle doit donc traiter l'absence de cette arborescence comme un cas d'incapacité, pas comme une absence de dérive.

## La commande de mise à jour affichée

Les plugins ezacae sont installés en portée `managed` (déclarés au niveau de l'organisation). Les briques existent :

```bash
claude plugin marketplace update ezacae-claude-tooling
claude plugin update <plugin>@ezacae-claude-tooling --scope managed
```

Et pour un plugin absent :

```bash
claude plugin install <plugin>@ezacae-claude-tooling
```

**Cet enchaînement n'est pas vérifié, et sa vérification ne fait pas partie du plan automatique.** Sur un poste dont le marketplace est un dossier local, ces commandes peuvent basculer un plugin de la lecture directe du dépôt vers une copie en cache — c'est-à-dire supprimer la propriété qui permet de modifier un skill et de le voir agir à la session suivante. Faire exécuter ça par un agent autonome, au milieu d'un pipeline qui dépend de ces mêmes plugins, est un effet de bord inacceptable.

La vérification est donc un **geste humain, avant la fusion**, sur un poste où le basculement est sans conséquence — un poste d'équipe en source git, qui est de toute façon le seul où la commande a un sens. Tant qu'elle n'est pas vérifiée, le message du contrôle renvoie à la procédure de mise à jour documentée plutôt que d'affirmer une commande exacte : une commande fausse dans un avertissement est pire que pas d'avertissement.

## Fichiers

| Rôle | Chemin |
|---|---|
| Le contrôle | `plugins/ezacae-base/hooks/check-ezacae-versions.sh` |
| Branchement au démarrage | `plugins/ezacae-base/hooks/hooks.json` (2ᵉ entrée `SessionStart`) |
| Version attendue | `versions.lock` (racine du dépôt) |
| Tests hors-ligne | `plugins/ezacae-base/tests/test-check-ezacae-versions.sh` |
| Filtre du job | `.gitlab-ci.yml` (ajout de `versions.lock`) |

`ezacae-base` n'a pas encore de dossier `tests/` — à créer. Le contrôle vit dans `ezacae-base` pour s'appliquer à toute l'équipe quel que soit le projet ouvert.

**Une seule variable d'environnement : `EZACAE_PLUGINS_HOME`** (défaut `~/.claude/plugins`). Les trois sources et l'instantané du marketplace vivent tous dessous, donc une racine injectable suffit.

Il n'y a **pas** de variable donnant directement le chemin de la référence. Ce serait commode et ce serait un piège : la localisation de la référence *est* la règle 3, et une variable qui la court-circuite ferait passer au vert les tests censés la prouver — le défaut le plus grave de la version précédente de ce document aurait survécu à sa propre suite de tests.

`jq` est requis, comme pour les helpers JIRA du dépôt. S'il manque, le contrôle **le dit en une ligne** et sort en succès. Il ne fait jamais échouer un démarrage de session, et il ne se désactive jamais en silence.

## Option de détail

`--detail` affiche ce que chacune des sources du disque raconte, avec les chemins et les dates, y compris quand tout va bien. Sert à comprendre un avertissement surprenant sans refaire l'enquête, et à mesurer un poste dont on doute.

## Risques

- **Amorçage.** Un poste dont `ezacae-base` est périmé ne contient pas encore le contrôle : le premier déploiement suppose une mise à jour manuelle annoncée à l'équipe. Le mécanisme n'est autoporteur qu'ensuite.
- **Fichiers internes au CLI.** `known_marketplaces.json`, `installed_plugins.json` et l'arborescence du cache sont internes à Claude Code, sans garantie de stabilité. Sur une structure inattendue, le contrôle dit son incapacité en une ligne — il n'affiche jamais un verdict faux, et ne se tait jamais par accident.
- **Plusieurs versions du même plugin en cache.** Le cas existe (`superpowers` a 6.1.1 et 6.2.0 côte à côte). Comme `check-superpowers.sh`, le contrôle retient la plus haute des versions sémantiques et le mentionne en `--detail`.
- **Le cas réel n'est pas observable ici.** Le poste de maintenance lit le dépôt en direct : la branche « source git » ne peut être prouvée que par les tests hors-ligne, plus une exécution sur un poste d'équipe après livraison.
- **Ordre d'affichage.** Rien ne garantit la position de l'avertissement par rapport au bloc de conventions injecté par l'autre hook `SessionStart`. Le contrôle garantit la brièveté de son message, pas sa place.

## Plan d'implémentation

> **Pour l'exécution :** `/developer docs/conception/rd-22-alerte-derive-versions-plugins.md`

**Objectif :** un contrôle au démarrage de session qui avertit un développeur ezacae quand ses plugins ne sont pas à la version publiée, et qui dit quand il ne peut pas se prononcer.
**Architecture :** un script shell dans `ezacae-base`, branché sur `SessionStart`, lisant les sources sous une racine unique injectable, et la version attendue dans l'instantané du marketplace dont il vérifie d'abord la fraîcheur. Tests hors-ligne sur le modèle de `plugins/ezacae-dev/tests/test-check-superpowers.sh` (assertions `contains` / `refutes` / `eq`, plus une assertion `nonempty` pour prouver qu'un cas ne reste pas muet ; arborescences fabriquées dans un dossier temporaire).

---

### Phase 1 — Silence choisi, incapacité dite

Le contrôle apprend d'abord à distinguer les deux formes de « je n'affiche pas d'alerte » : le silence quand tout va bien, la ligne unique quand il ne peut pas travailler.

#### Tâche 1.1 : squelette et sortie toujours en succès
**Fichiers :** Créer : `plugins/ezacae-base/hooks/check-ezacae-versions.sh` | Test : `plugins/ezacae-base/tests/test-check-ezacae-versions.sh`
- [ ] Écrire le test : arborescence vide → code 0, quelle que soit la sortie
- [ ] Vérifier qu'il échoue
- [ ] Implémenter le squelette et la lecture de `EZACAE_PLUGINS_HOME`
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 1.2 : `jq` absent → une ligne, pas le silence
- [ ] Écrire le test : `PATH` vidé → la sortie est **non vide** et mentionne `jq` ; code 0
- [ ] Vérifier qu'il échoue
- [ ] Implémenter la garde
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 1.3 : structures illisibles → une ligne, pas le silence
- [ ] Écrire les tests : `known_marketplaces.json` absent, vide, JSON invalide, puis sans entrée `ezacae-claude-tooling` → sortie non vide expliquant l'incapacité ; code 0 dans les quatre cas
- [ ] Vérifier qu'ils échouent
- [ ] Implémenter
- [ ] Vérifier qu'ils passent
- [ ] Commit

#### Tâche 1.4 : poste en lecture directe du dépôt → silence
- [ ] Écrire le test : marketplace en source `directory` → sortie **vide**, code 0, même avec une vieille version dans le cache
- [ ] Vérifier qu'il échoue
- [ ] Implémenter la reconnaissance du type de source
- [ ] Vérifier qu'il passe
- [ ] Commit

### Phase 2 — Fraîcheur de la référence

Cette phase vient **avant** la comparaison des versions : sans elle, la comparaison peut être muette à tort. C'est le défaut que la revue a prouvé sur la version précédente de ce document.

#### Tâche 2.1 : la référence se lit dans l'instantané du marketplace
- [ ] Écrire le test : source git, `versions.lock` dans l'instantané annonçant 0.3.2, une référence contradictoire posée dans la copie installée → c'est bien 0.3.2 qui est retenu. Aucune variable d'environnement ne désigne la référence : le test ne peut la placer qu'à l'endroit réel.
- [ ] Vérifier qu'il échoue
- [ ] Implémenter la localisation de la référence
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 2.2 : référence pas plus récente que la copie installée → avertir de l'incapacité
Reprise du test de revue (`test-reference-figee.sh`), qui échoue aujourd'hui sur trois assertions.
- [ ] Écrire le test : source git, `lastUpdated` du marketplace antérieur à la date du dossier de version en cache, `versions.lock` annonçant la même version que la copie installée → la sortie est **non vide**, nomme le plugin, contient `claude plugin marketplace update`, et ne contient **pas** « à jour » ; code 0
- [ ] Vérifier qu'il échoue
- [ ] Implémenter la comparaison de fraîcheur
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 2.3 : arborescence attendue absente de l'instantané → incapacité
- [ ] Écrire le test : instantané sans `versions.lock` ni `plugins/<nom>/.claude-plugin/plugin.json` → sortie non vide expliquant l'incapacité, jamais « à jour » ; code 0
- [ ] Vérifier qu'il échoue
- [ ] Implémenter
- [ ] Vérifier qu'il passe
- [ ] Commit

### Phase 3 — L'avertissement de dérive

#### Tâche 3.1 : à jour → silence
- [ ] Écrire le test : référence plus récente que la copie installée, cache 0.3.2 face à une attente de 0.3.2 → sortie **vide**, code 0
- [ ] Vérifier qu'il échoue
- [ ] Implémenter la comparaison de versions
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 3.2 : en retard → avertit
- [ ] Écrire le test : référence fraîche, cache 0.1.0 face à une attente de 0.3.2 → la sortie contient les deux numéros et le nom du plugin ; code 0
- [ ] Vérifier qu'il échoue
- [ ] Implémenter
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 3.3 : plugin absent → commande d'installation
- [ ] Écrire le test : plugin attendu, absent du cache → la sortie contient `claude plugin install` ; code 0
- [ ] Vérifier qu'il échoue
- [ ] Implémenter
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 3.4 : version installée non sémantique
- [ ] Écrire les tests : dossier de version nommé `unknown`, puis nommé comme un identifiant de commit → message distinct signalant une version indéterminée, **aucune** comparaison chiffrée dans la sortie, aucun « en retard » ; code 0
- [ ] Vérifier qu'ils échouent
- [ ] Implémenter la reconnaissance des formes non sémantiques
- [ ] Vérifier qu'ils passent
- [ ] Commit

#### Tâche 3.5 : plusieurs versions sémantiques en cache
- [ ] Écrire le test : deux dossiers de version bien formés → la plus haute est retenue ; un dossier bien formé et un `unknown` → le bien formé est retenu
- [ ] Vérifier qu'il échoue
- [ ] Implémenter
- [ ] Vérifier qu'il passe
- [ ] Commit

#### Tâche 3.6 : option `--detail`
- [ ] Écrire le test : `--detail` affiche les sources, leurs chemins et leurs dates, y compris quand tout va bien
- [ ] Vérifier qu'il échoue
- [ ] Implémenter
- [ ] Vérifier qu'il passe
- [ ] Commit

### Phase 4 — Version attendue et intégration continue

#### Tâche 4.1 : mode `--check`
**Fichiers :** Créer : `versions.lock`
- [ ] Écrire les tests : `versions.lock` conforme aux `plugin.json` du dépôt → code 0 ; un écart → code non nul et le nom du plugin fautif dans la sortie ; un plugin du dépôt absent du fichier → code non nul ; une ligne du fichier ne correspondant à aucun plugin → code non nul
- [ ] Vérifier qu'ils échouent
- [ ] Créer `versions.lock` aligné sur les versions actuelles, puis implémenter `--check` (racine du dépôt déduite de l'emplacement du script, surchargeable par argument)
- [ ] Vérifier qu'ils passent
- [ ] Commit

#### Tâche 4.2 : brancher `--check` et élargir le filtre du job
**Fichiers :** Modifier : `.gitlab-ci.yml`
- [ ] Ajouter l'appel à `--check` dans le job `test-plugins-shell`
- [ ] Ajouter `versions.lock` à la liste `plugin_shell_changes`
- [ ] Vérifier localement que la commande du job échoue si `versions.lock` est désaligné, puis passe une fois réaligné
- [ ] Commit

### Phase 5 — Branchement et preuves fraîches

#### Tâche 5.1 : brancher le contrôle au démarrage
**Fichiers :** Modifier : `plugins/ezacae-base/hooks/hooks.json`
- [ ] Ajouter une 2ᵉ entrée `SessionStart` pointant `check-ezacae-versions.sh`, même matcher que l'existante
- [ ] Vérifier que la sortie de `inject-conventions.sh` n'est pas altérée
- [ ] Commit

#### Tâche 5.2 : exécution réelle sur le poste courant
- [ ] Lancer le contrôle sans variable d'environnement
- [ ] Vérifier qu'il est **silencieux** (ce poste lit le dépôt en direct) et que `--detail` montre bien les quatre plugins
- [ ] Coller les deux sorties dans la merge request comme preuve fraîche
- [ ] Commit

> **Hors plan automatique — vérification humaine avant fusion.** L'enchaînement `claude plugin marketplace update` puis `claude plugin update … --scope managed` doit être exécuté **à la main**, sur un poste d'équipe en source git, et sa sortie réelle collée dans la merge request. Aucun agent ne lance ces commandes : sur un poste en source dossier, elles peuvent supprimer la lecture directe du dépôt dont dépend tout le cycle de développement. Tant que la vérification n'a pas eu lieu, le message du contrôle renvoie à la procédure documentée au lieu d'affirmer une commande exacte.
