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

## 4. Opérations MCP (tout sauf pièces jointes)

| Besoin | Outil MCP |
|--------|-----------|
| Créer un ticket | `createJiraIssue` |
| Lire un ticket | `getJiraIssue` |
| Éditer un champ | `editJiraIssue` |
| Lister les transitions possibles | `getTransitionsForJiraIssue` |
| Transitionner | `transitionJiraIssue` |
| Commenter | `addCommentToJiraIssue` |
| Rechercher | `searchJiraIssuesUsingJql` |
| Lister les projets | `getVisibleJiraProjects` |
| Lier deux tickets | `createIssueLink` |

## 5. Transitions par nom de statut cible (découverte dynamique)

Les IDs de transition sont **propres à l'instance** : ne jamais les coder en dur. Procédure :

1. `getTransitionsForJiraIssue(cloudId, issueKey)` → liste `{id, name, to.name}`.
2. Trouver la transition dont `to.name` correspond au **statut cible** voulu. **Comparer impérativement en insensible à la casse** : la casse des statuts est incohérente dans l'instance (observé sur CRM : `Nouveau`, `CONCEPTION`, `Recette Interne`).
3. **Ne jamais matcher sur le nom de transition** (`.name`), qui diffère du statut cible — ex. observés : `Initier` → `CONCEPTION`, `Conception terminée` → `CONCEPTION VALIDATION`, `Reconsidérer` → `Nouveau`.
4. `transitionJiraIssue(cloudId, issueKey, transitionId)`.
5. Si aucune transition ne mène au statut cible → **lister les transitions disponibles et demander** (ne pas forcer).

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
2. Pour un worklog, **demander le temps à logguer** (ne pas inventer une durée) puis renvoyer via :
   ```
   transitionJiraIssue(cloudId, key, {id}, update={"worklog":[{"add":{"timeSpent":"30m","comment":"…"}}]})
   ```
3. Pour un autre champ obligatoire (écran custom), lire `getTransitionsForJiraIssue(..., expand="transitions.fields")` et fournir le champ via `fields`.

### Garde de statut automatique (hook `PreToolUse`)

Le hook `jira-guard.sh` du plugin ezacae-jira (déclaré dans son `hooks/hooks.json`) intercepte chaque `transitionJiraIssue` et **bloque toute transition hors séquence** du pipeline. Graphe des transitions légales appliqué :

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

## 7. Pièces jointes (helpers REST)

Les helpers vivent dans le plugin ezacae-jira ; leur **chemin absolu est injecté par le hook SessionStart** (ligne « Helpers JIRA »). Les invoquer via ce chemin (noté `<HELPERS>` ci-dessous) :

```bash
# Attacher un ou plusieurs fichiers
<HELPERS>/jira-attach.sh PROJ-123 docs/cadrage.md docs/design.md

# Récupérer les PJ d'un ticket (filtre optionnel sur le nom)
<HELPERS>/jira-download.sh PROJ-123 /tmp/jira-PROJ-123 cadrage
```

Après chaque attache, poster un **commentaire** qui référence la PJ et l'étape (voir format ci-dessous).

## 8. Format de commentaire de passation

Chaque transition s'accompagne d'un commentaire MCP (`addCommentToJiraIssue`) lisible et traçable :

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
