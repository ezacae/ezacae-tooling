# ezacae-claude-tooling

Marketplace interne ezacae de plugins Claude Code.

## Plugins

| Plugin | Contenu | Statut |
|--------|---------|--------|
| `ezacae-base` | Instructions globales ezacae (`conventions.md`) injectées en contexte à chaque session via un hook SessionStart — source unique d'équipe, remplace le copier-coller dans chaque `~/.claude/CLAUDE.md` | `0.1.0` |
| `ezacae-jira` | Infra commune du pipeline JIRA : skill `jira-pipeline`, helpers REST (`jira-attach`/`jira-download`), hooks `SessionStart` (pré-checks Git/JIRA + chemin des helpers), **auto-autorisation des actions JIRA** (aucune validation manuelle) et garde de statut `PreToolUse` | `0.2.0` |
| `ezacae-doc` | Orchestrateur Mike (PO/CTO) + commandes vision / personas / processus, avec les subagents `doc-writer` et `stack-writer` | `0.2.0` |
| `ezacae-dev` | Orchestrateur Sarah (conception → implémentation → revue) ; skills `chuck`, `john`, `morgan`, `grill-me`, `handoff` ; agents **auto-suffisants** `morgan`/`john` + `code-simplifier`, `technical-design-generator` ; hook SessionStart injectant la racine du plugin (conventions de stack) | `0.2.0` |

`ezacae-doc` et `ezacae-dev` dépendent de `ezacae-jira` **uniquement** pour le mode pipeline JIRA (`/mike <KEY>`, `/sarah <KEY>`). Hors pipeline, les commandes fonctionnent seules.

### Pourquoi `ezacae-dev` embarque la discipline dans les agents

`${CLAUDE_PLUGIN_ROOT}` **n'est pas substitué dans le corps markdown** des commandes/agents/skills (bug connu, [#9354](https://github.com/anthropics/claude-code/issues/9354)) — il ne marche que dans les JSON (`hooks.json`) et comme variable d'env des sous-processus de hooks. Et un sous-agent dispatché ne peut ni invoquer de skill ni lire un fichier du plugin par chemin stable. Conséquences appliquées ici :

- **Agents `morgan`/`john` auto-suffisants** : toute leur discipline (process TDD, détection de stack, conventions Next.js/Flutter, templates MR) est **inline** dans `agents/*.md`. Aucune lecture de fichier externe. Contrepartie assumée : ces conventions existent en double avec les skills `morgan`/`john` (deux sources à maintenir).
- **Skills en thread principal** (`chuck`, `morgan`, `sarah`) : les références inter-skills à `skills/john/stacks/<stack>.md` sont résolues via le **chemin absolu injecté par le hook SessionStart** d'ezacae-dev. Les références internes de `john` à ses propres `stacks/` restent relatives (fichiers support du skill).
- **Conventions JIRA** : chargées via le **skill `jira-pipeline`** (invocable par nom, cross-plugin), jamais par chemin.

## Installation (poste développeur)

```
/plugin marketplace add <URL_GITLAB>/ezacae-claude-tooling
/plugin install ezacae-base@ezacae-claude-tooling
/plugin install ezacae-jira@ezacae-claude-tooling
/plugin install ezacae-doc@ezacae-claude-tooling
/plugin install ezacae-dev@ezacae-claude-tooling
```

Pendant le développement, en local :

```
/plugin marketplace add ~/DEV/ezacae-claude-tooling
/plugin install ezacae-base@ezacae-claude-tooling
/plugin install ezacae-jira@ezacae-claude-tooling
/plugin install ezacae-doc@ezacae-claude-tooling
/plugin install ezacae-dev@ezacae-claude-tooling
```

## Modèle infra vs état projet

La **logique** (skill, scripts, hooks) est embarquée dans les plugins et partagée par tous les projets — plus de copie dans chaque repo. Seul l'**état/secret par projet** reste dans le repo client :

| Vit dans le plugin (ezacae-jira) | Vit dans chaque projet (`.claude/`) |
|----------------------------------|--------------------------------------|
| `skills/jira-pipeline/SKILL.md` (conventions) | `jira.env` (credentials, **gitignoré**) |
| `skills/jira-pipeline/PIPELINE.md` | `CLAUDE.md` (contexte projet) |
| `scripts/jira-attach.sh`, `jira-download.sh` | `doc-manifest.md` (état de la doc) |
| `hooks/session-start.sh`, `jira-guard.sh` + `hooks/hooks.json` | `local.md` (config perso) |
| `jira.env.example` (modèle à copier) | |

### Câblage des chemins (important)

- Les **hooks** sont déclarés dans `ezacae-jira/hooks/hooks.json` via `${CLAUDE_PLUGIN_ROOT}` → Claude Code substitue le bon chemin à l'enregistrement ; ils s'exécutent globalement quel que soit le plugin actif.
- Les **scripts** résolvent `jira.env` via `${CLAUDE_PROJECT_DIR:-$PWD}/.claude/jira.env` → le secret reste dans le projet courant, jamais dans le cache du plugin.
- `${CLAUDE_PLUGIN_ROOT}` pointe le plugin *courant* : `mike.md` (dans ezacae-doc) ne peut donc pas référencer en dur les fichiers d'ezacae-jira. Le **hook SessionStart injecte le chemin absolu des helpers** (`jira-attach`/`jira-download`) dans le contexte — Mike les retrouve par là. Les conventions JIRA sont chargées via le **skill `jira-pipeline`** (invocable par nom, cross-plugin).

### Effet de bord à connaître

Une fois `ezacae-jira` activé (scope user), son hook `SessionStart` tourne à **chaque** session, y compris hors projets pipeline : il fait un `git fetch` + ff-only et un check credentials. Conçu pour être inoffensif ailleurs (no-op si pas de `.claude/jira.env`), mais c'est un comportement global à assumer. Pour le limiter, installer `ezacae-jira` en scope projet plutôt qu'user.

## Pré-requis côté projet client

1. Copier `jira.env.example` (livré par ezacae-jira) en `<projet>/.claude/jira.env`, le renseigner, vérifier qu'il est gitignoré.
2. Fournir `<projet>/.claude/CLAUDE.md`, `doc-manifest.md` selon les besoins des commandes Mike.

## Pipeline complet Mike ⇄ Sarah

En mode pipeline JIRA, `/mike <KEY>` cadre puis passe la main à `/sarah <KEY>` (conception → implémentation → revue), qui re-déclenche `/mike <KEY>` pour la doc finale. Il faut donc les **trois** plugins installés : `ezacae-jira` (infra), `ezacae-doc` (Mike), `ezacae-dev` (Sarah).

## Développement

```
ezacae-claude-tooling/
├── .claude-plugin/marketplace.json
└── plugins/
    ├── ezacae-base/
    │   ├── .claude-plugin/plugin.json
    │   ├── hooks/        (hooks.json + inject-conventions.sh)
    │   └── conventions.md  (source unique des instructions globales)
    ├── ezacae-jira/
    │   ├── .claude-plugin/plugin.json
    │   ├── hooks/        (hooks.json + session-start.sh + jira-guard.sh + jira-allow-bash.sh)
    │   ├── scripts/      (jira-attach.sh + jira-download.sh)
    │   ├── skills/jira-pipeline/  (SKILL.md + PIPELINE.md)
    │   └── jira.env.example
    ├── ezacae-doc/
    │   ├── .claude-plugin/plugin.json
    │   ├── commands/*.md
    │   └── agents/*.md  (doc-writer, stack-writer)
    └── ezacae-dev/
        ├── .claude-plugin/plugin.json
        ├── hooks/        (hooks.json + session-start-dev.sh)
        ├── commands/     (sarah.md, feature.md)
        ├── skills/       (chuck, john, morgan, grill-me, handoff)
        └── agents/       (morgan, john auto-suffisants ; code-simplifier ; technical-design-generator)
```

Conventions de contribution et règle de bump de version : voir [`CONTRIBUTING.md`](CONTRIBUTING.md).
