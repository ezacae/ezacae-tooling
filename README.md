# ezacae-claude-tooling

Marketplace interne ezacae de plugins Claude Code. C'est ici que vit l'outillage IA commun distribué aux postes de l'équipe : conventions globales, pipeline JIRA, agents documentaires (Mike) et agents de développement (Sarah, Chuck, Developer).

> **Contexte — chantier harnais IA ezacae.** Ce dépôt reflète l'organisation **actuelle** de l'outillage, pendant le cadrage du socle harnais. Les besoins sont validés (CDC v2 du 09/07) et le choix du socle est en cours (comparatif des 5 pistes, recommandation D′ : « les plugins sont un bon canal de livraison, pas un socle ») — voir le dépôt [`harness-doc`](https://gitlab.com/ezacae/harness-doc). Selon la piste retenue, ce dépôt pourra être déménagé, remplacé ou archivé. En attendant, il reste la référence en vigueur.

## Démarrage rapide (nouveau dev)

**1. Installer les plugins** (une fois par poste — détail plus bas) :

```
/plugin marketplace add <URL_GITLAB>/ezacae-claude-tooling
/plugin install ezacae-base@ezacae-claude-tooling
/plugin install ezacae-jira@ezacae-claude-tooling
/plugin install ezacae-doc@ezacae-claude-tooling
/plugin install ezacae-dev@ezacae-claude-tooling
```

**2. Préparer le projet** : dans le repo où tu travailles, copier `jira.env.example` en `.claude/jira.env`, le renseigner, vérifier qu'il est gitignoré (voir « Pré-requis côté projet client »).

**3. Développer une fonctionnalité ou corriger un bug — une seule commande à retenir : `/mike`.** Tout travail de dev part d'un ticket JIRA et passe par le pipeline, y compris une petite correction. Tu n'as pas à enchaîner les étapes ni à connaître les agents un par un : tu lances `/mike`, puis tu valides à chaque gate.

| Point de départ | Commande | Ce qui se passe |
|---|---|---|
| J'ai un ticket JIRA (statut `NOUVEAU`) | `/mike <KEY>` | Mike cadre le besoin, met à jour la doc, passe le ticket en `CONCEPTION` et enchaîne automatiquement sur le développement |
| Je n'ai pas de ticket | `/mike "ajoute la fonctionnalité X"` | Mike crée le ticket dans le bon projet, puis déroule le pipeline |

> **Mike n'est pas réservé à la doc.** C'est le point d'entrée unique pour **tout** le dev ezacae. Il orchestre en interne le cycle complet, avec un **gate de validation entre chaque phase** — aucun code n'est écrit tant que la conception n'est pas validée par toi :
>
> ```
> conception (tu valides)  →  implémentation (branche + tests + MR)  →  revue de code  →  doc finale
> ```
>
> Le statut du ticket avance à chaque étape et les livrables sont attachés automatiquement.

**Règle ezacae non négociable** : rien n'est conçu tant que le besoin n'est pas validé, rien n'est livré tant que la revue n'est pas faite. Les gates sont matérialisés par des états système (statut JIRA, merge), pas par une consigne ignorable — c'est vrai pour tout dev, quelle que soit sa taille.

Les agents qui exécutent ce cycle (Sarah l'orchestrateur, puis les phases conception / implémentation / revue) sont détaillés dans « Plugins » ci-dessous. En usage normal tu n'as pas à les invoquer par leur nom : `/mike` s'en charge.

## Plugins

| Plugin | Contenu | Statut |
|--------|---------|--------|
| `ezacae-base` | Instructions globales ezacae (`conventions.md`) injectées en contexte à chaque session via un hook SessionStart — source unique d'équipe, remplace le copier-coller dans chaque `~/.claude/CLAUDE.md` | `0.2.0` |
| `ezacae-jira` | Infra commune du pipeline JIRA : skill `jira-pipeline`, helpers REST (`jira-attach`/`jira-download`), hooks `SessionStart` (pré-checks Git/JIRA + chemin des helpers), **auto-autorisation des actions JIRA** (aucune validation manuelle) et garde de statut `PreToolUse` | `0.2.1` |
| `ezacae-doc` | Orchestrateur Mike (PO/CTO) + commandes vision / personas / processus, avec les subagents `doc-writer` et `stack-writer` | `0.3.2` |
| `ezacae-dev` | Orchestrateur Sarah (conception → implémentation → revue) ; skills `chuck`, `developer`, `grill-me`, `handoff` ; agent `developer` ; hooks SessionStart (racine du plugin pour les conventions de stack, contrôle de version de superpowers). Aucun assistant ne se déclenche de lui-même | `0.5.0` |

`ezacae-doc` et `ezacae-dev` dépendent de `ezacae-jira` **uniquement** pour le mode pipeline JIRA (`/mike <KEY>`, `/sarah <KEY>`). Hors pipeline, les commandes fonctionnent seules.

**Rôle de chaque agent d'`ezacae-dev`** (par fonction — tu ne les invoques pas directement en usage normal, `/mike` les orchestre) :

| Agent | Rôle |
|---|---|
| Sarah | Orchestrateur du cycle dev : séquence les phases et pose un gate de validation entre chacune |
| Chuck | Phase **conception** : produit et fait valider le design technique avant tout code |
| Developer | Phase **implémentation** : unique exécuteur, dispatché en sous-agent worktree isolé, déroule branche + TDD + MR sans interaction. Sous HARD-GATE — toute écriture de code exige une conception (via Chuck) |

> `developer` remplace l'ancienne paire `morgan`/`john` : un seul exécuteur, un seul flux (autonome), une seule source de vérité pour les conventions de stack. Plus de mode interactif « au fil de l'eau » — tout passe par une conception.

### Pourquoi `ezacae-dev` embarque la discipline dans les agents

`${CLAUDE_PLUGIN_ROOT}` **n'est pas substitué dans le corps markdown** des commandes/agents/skills (bug connu, [#9354](https://github.com/anthropics/claude-code/issues/9354)) — il ne marche que dans les JSON (`hooks.json`) et comme variable d'env des sous-processus de hooks. Et un sous-agent dispatché ne peut ni invoquer de skill ni lire un fichier du plugin par chemin stable. Conséquences appliquées ici :

- **Agent `developer`** : récupère sa discipline à l'exécution — méthode (TDD, vérification, debug) via les skills `superpowers`, conventions de stack via le skill `developer` (`stacks/<stack>.md` lu depuis sa base directory). Un backstop de discipline générale reste inline dans `agents/developer.md` pour ne dépendre d'aucune invocation. Plus de conventions recopiées : `developer` est la source unique.
- **Skills en thread principal** (`chuck`, `developer`, `sarah`) : les références inter-skills à `skills/developer/stacks/<stack>.md` sont résolues via le **chemin absolu injecté par le hook SessionStart** d'ezacae-dev. Les références internes de `developer` à ses propres `stacks/` restent relatives (fichiers support du skill).
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
        ├── hooks/        (hooks.json + session-start-dev.sh + check-superpowers.sh)
        ├── superpowers.lock
        ├── commands/     (sarah.md)
        ├── skills/       (chuck, developer, grill-me, handoff)
        └── agents/       (developer)
```

Le dépôt contient aussi `deploy/jira-watcher/` (service de veille JIRA, README dédié dans le dossier) et `docs/` (conceptions des tickets, spécification et feuille de route du harnais dans `docs/harnais/`).

Conventions de contribution et règle de bump de version : voir [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Migration depuis `~/.claude/` (install.sh)

Pour un poste encore configuré via le script `install.sh` du dépôt `referentiel-documentaire-ezacae` : suivre la checklist [`MIGRATION.md`](MIGRATION.md). Objectif clé : **éviter le doublon** — une commande/skill ne doit jamais exister à la fois dans `~/.claude/` et dans un plugin.

## Dépôts liés

| Dépôt | Rôle |
|---|---|
| [`referentiel-documentaire-ezacae`](https://gitlab.com/ezacae/referentiel-documentaire-ezacae) | Index documentaire des projets + templates de démarrage projet + distribution historique `install.sh` (dépréciée) |
| [`harness-doc`](https://gitlab.com/ezacae/harness-doc) | Chantier harnais : cahiers des charges, comparatif des pistes de socle, décisions |
