---
name: jira-pipeline
description: Conventions communes du pipeline JIRA ezacae (Mike ⇄ Sarah) — credentials, cloudId, transitions par nom de statut, garde de statut, pièces jointes REST, format de commentaire de passation. À charger avant toute opération JIRA dans une commande Mike ou Sarah.
---

# Référentiel JIRA partagé — Mike & Sarah

> Conventions **communes** aux orchestrateurs Mike (`/mike`) et Sarah (`/sarah`) pour piloter le pipeline décrit dans `PIPELINE.md` (fourni avec ce skill). Source unique — ne pas dupliquer ces règles dans les commandes.

## 1. Credentials (prérequis)

Les pièces jointes passent par l'API REST (pas par le MCP). Trois variables d'environnement sont requises :

| Variable | Exemple |
|----------|---------|
| `JIRA_BASE_URL` | `https://ezacae.atlassian.net` |
| `JIRA_EMAIL` | `simon@ezacae.com` |
| `JIRA_API_TOKEN` | jeton API Atlassian (https://id.atlassian.com/manage-profile/security/api-tokens) |

`jq` est requis pour `jira-download.sh`.

### Stockage local : `<projet>/.claude/jira.env`

Les credentials sont persistés **par projet** dans **`.claude/jira.env`** (gitignoré). Le modèle est livré avec le plugin ezacae-jira (`jira.env.example`) — le copier dans `<projet>/.claude/jira.env`. Les scripts (`jira-attach`/`jira-download`) et les hooks (`session-start`/`jira-guard`) **chargent automatiquement** ce fichier du projet courant quand les variables ne sont pas déjà exportées (les variables d'env exportées ont la priorité).

> La présence des credentials est **vérifiée automatiquement au démarrage** par le hook `SessionStart` du plugin ezacae-jira, qui l'injecte en contexte avec l'état Git et le chemin des helpers. Inutile de la re-tester en bash.

**Comportement si les credentials manquent** (variables non exportées **et** `.claude/jira.env` absent) : avant toute opération JIRA, **demander à l'utilisateur** les trois valeurs (`JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`), puis les écrire dans `<projet>/.claude/jira.env`. Ce fichier servira aux traitements suivants — on ne redemande pas tant qu'il est présent et complet.

> ⚠️ `JIRA_API_TOKEN` est un secret. Il n'est écrit **que** dans `<projet>/.claude/jira.env`, qui est gitignoré. **Ne jamais** le commiter ni l'inscrire dans un fichier suivi. Si l'utilisateur préfère ne pas saisir le token dans la conversation, lui proposer de remplir `.claude/jira.env` lui-même (copie de `jira.env.example`).

## 2. cloudId

Les outils MCP Atlassian prennent un `cloudId`. L'obtenir une fois via `getAccessibleAtlassianResources` et le réutiliser pour tous les appels de la session.

## 3. Résolution du projet (création de ticket — Mike uniquement)

1. Lire un éventuel mapping projet dans le `CLAUDE.md` du dépôt (ex. « ce repo → projet JIRA `ACME` »).
2. Sinon, lister les projets visibles via `getVisibleJiraProjects` et **demander** lequel utiliser. Ne jamais deviner le projet.
3. **Choisir un type de ticket dont le workflow porte les statuts du pipeline.** Le pipeline n'est exploitable que si le type d'issue suit le workflow `NOUVEAU → CADRAGE → CONCEPTION → … → RECETTE INTERNE`. Tous les types n'y sont pas rattachés : un type « tâche/sous-tâche » utilise souvent un workflow simplifié (`Nouveau → En cours → Terminé`) **sans** `CADRAGE`/`CONCEPTION` — créer le ticket avec un tel type **casse le pipeline dès la 1re transition**. Lire le mapping de type dans le `CLAUDE.md` du dépôt s'il existe ; sinon **demander** le type à utiliser plutôt que de prendre le type par défaut du projet. Vérifier au besoin avec `getJiraProjectIssueTypesMetadata`.
   > Exemple constaté (projet `CRM`) : le workflow pipeline n'est porté que par les types **`Story`** et **`Bug`** ; le type **`Tâche`** ne l'a pas.

## 4. Opérations JIRA — helpers REST d'abord, MCP en repli

**Privilégier les helpers REST `jira-*.sh`** (plugin ezacae-jira) pour toutes les
opérations courantes du pipeline. Ils sont **auto-autorisés** (aucune validation
manuelle, cf. §5) et **fonctionnent en headless/cron** (le jira-watcher), là où le
MCP distant peut être indisponible. Leur **chemin absolu est injecté par le hook
SessionStart** (ligne « Helpers JIRA », noté `<HELPERS>` ci-dessous).

| Besoin | Helper REST (préférer) | Outil MCP (repli) |
|--------|------------------------|-------------------|
| Lire un ticket (+ commentaires) | `<HELPERS>/jira-get.sh <KEY> [--comments]` | `getJiraIssue` |
| Commenter | `<HELPERS>/jira-comment.sh <KEY> "texte"` ou `-f <fichier>` | `addCommentToJiraIssue` |
| Transitionner (par **nom de statut**, garde intégrée) | `<HELPERS>/jira-transition.sh <KEY> "<STATUT CIBLE>" [--worklog 30m] [--comment "…"]` | `transitionJiraIssue` |
| Éditer un champ (résumé, description, labels, assigné) | `<HELPERS>/jira-edit.sh <KEY> --summary "…" --description-file <f> --label <l> --assignee <id\|->` | `editJiraIssue` |
| Pièces jointes (upload / download) | `<HELPERS>/jira-attach.sh` / `<HELPERS>/jira-download.sh` (cf. §7) | _(pas de support MCP)_ |
| Créer un ticket | _(MCP)_ | `createJiraIssue` |
| Rechercher (JQL) | _(MCP)_ | `searchJiraIssuesUsingJql` |
| Lister les projets | _(MCP)_ | `getVisibleJiraProjects` |
| Lier deux tickets | _(MCP)_ | `createIssueLink` |

> `jira-transition.sh` découvre lui-même l'id de transition à partir du **nom du
> statut cible** (insensible à la casse) et applique la **garde de statut** — pas
> besoin d'appeler `getTransitionsForJiraIssue` au préalable. En cas d'échec, il
> liste les transitions disponibles. Tous les helpers requièrent les credentials
> (§1) et `jq`.

## 5. Transitions par nom de statut cible (découverte dynamique)

Les IDs de transition sont **propres à l'instance** : ne jamais les coder en dur.

**Voie recommandée — `jira-transition.sh`** (résolution + garde en un appel) :

```bash
<HELPERS>/jira-transition.sh CRM-337 "CONCEPTION OK"
<HELPERS>/jira-transition.sh CRM-337 EXAMINER --worklog 30m --comment "MR créée — revue"
```

Le script lit le statut courant, **résout l'id** de la transition dont le statut
cible correspond (insensible à la casse, jamais sur le nom de transition), applique
la **garde de statut** (§5, garde), exécute la transition, puis poste le `--comment`
éventuel. S'il n'existe pas de transition vers la cible, il **liste les transitions
disponibles** et sort en erreur — relayer à l'utilisateur, ne pas forcer.

**Voie MCP (repli)** — même logique, manuelle :
1. `getTransitionsForJiraIssue(cloudId, issueKey)` → liste `{id, name, to.name}`.
2. Trouver la transition dont `to.name` correspond au **statut cible** voulu, **insensible à la casse** (statuts incohérents : `Nouveau`, `CONCEPTION`, `Recette Interne`).
3. **Ne jamais matcher sur le nom de transition** (`.name`), qui diffère du statut cible (ex. : `Initier` → `CONCEPTION`, `Conception terminée` → `CONCEPTION VALIDATION`).
4. `transitionJiraIssue(cloudId, issueKey, transitionId)`.
5. Si aucune transition ne mène au statut cible → **lister et demander**.

### Statuts du workflow (cibles nominales du pipeline)

`NOUVEAU` → `CADRAGE` → `CONCEPTION` → `CONCEPTION VALIDATION` → `CONCEPTION OK` → `EN COURS` → `EXAMINER` → `RECETTE INTERNE` → (`RECETTE CLIENT` → `TO DEPLOY` → `TERMINÉ(E)` : humain/CI).
États hors flux : `VALIDATION KO` (rejet), `ANNULÉ` (annulation).

### Champs obligatoires de transition (écran / worklog)

Certaines transitions du workflow CRM possèdent un **écran** (`hasScreen: true`) avec un champ
**obligatoire** — typiquement un **temps consacré** (worklog). Une transition sans le champ échoue avec
`Le temps consacré est obligatoire`. Constaté sur : « Conception terminée » (→ `CONCEPTION VALIDATION`),
« Soumettre pour révision » (→ `EXAMINER`), « Passer à la validation interne » (→ `RECETTE INTERNE`).

Procédure :
1. Tenter la transition. En cas d'erreur `... obligatoire`, le champ manque.
2. Pour un worklog, **demander le temps à logguer** (ne pas inventer une durée) puis le passer :
   ```bash
   <HELPERS>/jira-transition.sh <KEY> "<STATUT CIBLE>" --worklog 30m
   ```
   (repli MCP : `transitionJiraIssue(cloudId, key, {id}, update={"worklog":[{"add":{"timeSpent":"30m"}}]})`)
3. Pour un autre champ obligatoire (écran custom), lire `getTransitionsForJiraIssue(..., expand="transitions.fields")` et fournir le champ via le MCP `fields`.

### Auto-autorisation des actions JIRA (hook `PreToolUse`)

Le plugin ezacae-jira **auto-autorise toute action JIRA sans validation manuelle** : aucun prompt de permission n'est demandé, que l'opération passe par les helpers REST **ou** par le MCP. C'est géré par les hooks `PreToolUse` déclarés dans `hooks/hooks.json` :

- `jira-allow-bash.sh` capte le Bash et renvoie **allow** pour les commandes invoquant un helper `jira-*.sh` du plugin (`jira-get`, `jira-comment`, `jira-transition`, `jira-edit`, `jira-attach`, `jira-download`). Tout autre Bash suit le flux de permission normal — on n'auto-autorise jamais du Bash arbitraire.
- `jira-guard.sh` capte tous les outils MCP JIRA (matcher large) et renvoie **allow** par défaut — sauf pour les transitions, qui passent par la garde de statut ci-dessous.

> C'est la voie REST (Bash auto-autorisé) qui rend le pipeline réellement **non-interactif** de bout en bout, y compris dans les contextes où le MCP n'est pas disponible. Si un agent constate encore un prompt sur une action JIRA, c'est qu'il passe par le MCP dans un contexte non capté : basculer sur le helper `jira-*.sh` équivalent.

### Garde de statut automatique (hook `PreToolUse`)

Au sein de cette auto-autorisation, la **garde de statut** s'applique aux deux voies de transition (filet de sécurité partagé, défini une seule fois dans `scripts/jira-lib.sh`) :
- côté **MCP**, `jira-guard.sh` intercepte chaque `transitionJiraIssue` et **bloque toute transition hors séquence** (un `deny` de hook l'emporte sur l'`allow`) ;
- côté **REST**, `jira-transition.sh` applique la **même** garde avant d'agir (elle ne peut donc pas être contournée en passant par le Bash auto-autorisé).

Graphe des transitions légales appliqué :

```
NOUVEAU              → CADRAGE
CADRAGE              → CONCEPTION
CONCEPTION           → CONCEPTION VALIDATION
CONCEPTION VALIDATION → CONCEPTION  |  CONCEPTION OK
CONCEPTION OK        → EN COURS
EN COURS             → EXAMINER
EXAMINER             → EN COURS  |  RECETTE INTERNE
```

Le hook **n'agit que** si le ticket est déjà dans un statut du pipeline **et** que les credentials JIRA sont présents ; sinon il laisse passer (les autres projets/workflows ne sont pas concernés). C'est un **filet de sécurité déterministe** : il complète — sans la remplacer — la discipline d'enchaînement décrite ici.

Précisions (validées par dry-run sur CRM-337) :
- Comparaison **insensible à la casse** (les noms de statuts réels varient : `Nouveau`, `CONCEPTION`, `Recette Interne`).
- L'**annulation** (`Annulé`, transition globale) est **toujours autorisée**.
- Garde **stricte** : les retours arrière non nominaux (`Reconsidérer` → `Nouveau`) et les **raccourcis admin** (`ADMIN_validate` → `Recette Interne`) sont **bloqués** — c'est volontaire.

## 6. Règles de garde à l'entrée

Avant d'agir, lire le statut courant (`getJiraIssue`) et vérifier le droit d'intervention :

| Agent | Statut autorisé | Sinon |
|-------|-----------------|-------|
| **Mike** | `NOUVEAU`, `CADRAGE` ou `RECETTE INTERNE` | s'arrêter : `⛔ Mike n'intervient que sur NOUVEAU, CADRAGE ou RECETTE INTERNE (statut actuel : <X>).` |
| **Sarah** | `CONCEPTION` | s'arrêter : `⛔ Sarah ne démarre que sur CONCEPTION (statut actuel : <X>).` |
| **Sarah → morgan/john** | `CONCEPTION OK` | ne pas lancer l'implémentation tant que le ticket n'est pas `CONCEPTION OK`. |

## 7. Helpers REST (récapitulatif)

Les helpers vivent dans le plugin ezacae-jira ; leur **chemin absolu est injecté par le hook SessionStart** (ligne « Helpers JIRA »). Les invoquer via ce chemin (noté `<HELPERS>`). Tous chargent `.claude/jira.env` (§1) et requièrent `jq`.

```bash
# Lire un ticket (résumé + description ; --comments pour le fil de commentaires)
<HELPERS>/jira-get.sh PROJ-123 --comments

# Commenter (texte direct, fichier, ou stdin)
<HELPERS>/jira-comment.sh PROJ-123 "🤖 [Sarah] revue OK"
<HELPERS>/jira-comment.sh PROJ-123 -f /tmp/rapport-revue.md

# Transitionner par nom de statut (garde intégrée), avec worklog/commentaire optionnels
<HELPERS>/jira-transition.sh PROJ-123 "CONCEPTION OK" --comment "design validé"

# Éditer des champs
<HELPERS>/jira-edit.sh PROJ-123 --summary "Nouveau titre" --label backend

# Attacher un ou plusieurs fichiers
<HELPERS>/jira-attach.sh PROJ-123 docs/cadrage.md docs/design.md

# Récupérer les PJ d'un ticket (filtre optionnel sur le nom)
<HELPERS>/jira-download.sh PROJ-123 /tmp/jira-PROJ-123 cadrage
```

Après chaque attache, poster un **commentaire** qui référence la PJ et l'étape (voir format ci-dessous) — au choix via `jira-comment.sh` ou l'option `--comment` de `jira-transition.sh`.

## 8. Format de commentaire de passation

Chaque transition s'accompagne d'un commentaire lisible et traçable (`jira-comment.sh` ou `jira-transition.sh --comment`, repli MCP `addCommentToJiraIssue`) :

```
🤖 [<Agent>] <étape>
• Statut : <ancien> → <nouveau>
• Pièce(s) jointe(s) : <fichiers> | MR : <url si applicable>
• Prochaine étape : <agent / action attendue>
```

Exemple (handoff Mike → Sarah) :

```
🤖 [Mike] Cadrage documentaire terminé
• Statut : CADRAGE → CONCEPTION
• Pièce jointe : cadrage-fonctionnel.md
• Prochaine étape : Sarah — conception technique (chuck)
```
