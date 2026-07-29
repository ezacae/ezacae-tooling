# Fusion John + Morgan → skill unique `developer`

Statut : Brouillon — en attente de validation

## Contexte et problème

Le plugin `ezacae-dev` expose aujourd'hui **deux exécuteurs d'implémentation** :

- **`morgan`** (skill + agent) — autonome, guidé par un document de conception, sous **HARD-GATE** (« pas de code sans conception »), en worktree isolé : branche → TDD → commits → push → MR.
- **`john`** (skill + agent) — interactif, au fil de l'eau, **sans conception obligatoire**, dans le working tree courant, sans git/MR.

Le chantier RD-8 a déjà supprimé la duplication de conventions dans les **agents** (ils n'inlinent plus Next.js/Flutter : ils invoquent le skill `john` et lisent `stacks/<stack>.md`). Il reste que **`skills/john/` porte un double rôle** :

1. **Rôle exécuteur interactif** — le workflow « implémentation sans conception ».
2. **Rôle source de vérité des conventions** — la procédure de détection de stack, la discipline non négociable, et la bibliothèque `stacks/` (`nextjs.md`, `flutter.md`). Ce rôle est consommé par `chuck`, `sarah`, le skill `morgan`, l'agent `morgan` et l'agent `john`, ainsi que par le hook `session-start-dev.sh`.

Deux exécuteurs pour un même travail (implémenter) créent une distinction que l'équipe veut éliminer (cf. bandeau « socle harnais » du README, ligne 61 : *« nommage susceptibles d'être simplifiés »*).

## Objectif (cible validée)

**Un seul skill exécuteur, `developer`**, qui :

- est **morgan renommé** — il **conserve le HARD-GATE** (aucun code sans document de conception validé) et tout son flux autonome (branche, TDD, push, MR) ;
- **absorbe le rôle « source de vérité des conventions »** aujourd'hui tenu par `john` (procédure de détection de stack + discipline + bibliothèque `stacks/`), pour devenir auto-suffisant ;
- rend **`john` inutile** : skill `john` **et** agent `john` **supprimés**.

**Conséquence de flux assumée** (décidée par le demandeur) : il n'existe **plus de voie d'implémentation rapide sans conception**. Tout code passe désormais par `/chuck` (conception, proportionnée à l'ampleur) puis `developer`. La branche « 3.3 bis interactive » de Sarah disparaît.

**Portée validée : globale** — aucune trace résiduelle de `john`/`morgan` dans les fichiers vivants (skills, agents, orchestrateurs, pipeline JIRA, manifestes, README, index doc, hook). Les documents **historiques datés** (specs/plans RD-8, journaux) ne sont **pas** réécrits : ce sont des archives.

## Approches — où loge la « source de vérité des conventions » après suppression de `john` ?

C'est le seul vrai arbitrage d'architecture. Deux options.

### Approche A — `developer` devient la source de vérité *(recommandée)*

La bibliothèque `stacks/` et la procédure de détection déménagent **dans `developer`**. Tous les consommateurs (`chuck`, `sarah`, agent `developer`, hook) pointent vers `skills/developer/stacks/<stack>.md` et « la procédure de référence du skill `developer` ».

- **+** Minimaliste : on ne crée aucun nouveau skill (cohérent avec l'objectif « un seul skill »).
- **+** Reproduit à l'identique le pattern actuel (john était déjà skill **et** bibliothèque ; on ne fait que renommer la maison).
- **−** Couple la bibliothèque de conventions au workflow de l'exécuteur (le skill `developer` porte un HARD-GATE + un DISPATCH-GATE que les lecteurs de conventions doivent ignorer — mais c'est **déjà le cas aujourd'hui** avec `john`, et les agents savent déjà « ignorer le bloc DISPATCH-GATE quand on ne fait que lire »).

### Approche B — skill dédié `stack-conventions` (bibliothèque pure)

Extraire un skill **sans workflow ni gate** contenant uniquement : détection de stack + discipline + `stacks/`. `developer`, `chuck`, `sarah` le référencent.

- **+** Séparation des responsabilités nette : les conventions ne sont plus mêlées à un exécuteur.
- **−** **Ajoute** un skill au moment où l'on cherche à en retirer — va à rebours de l'objectif « simplifier ».
- **−** Plus de fichiers à recâbler pour un bénéfice surtout théorique (le couplage actuel n'a jamais posé problème).

### Recommandation

**Approche A.** Elle colle à l'intention (moins d'entrées, pas de sur-ingénierie) et ne fait que transposer un montage qui fonctionne déjà. B resterait ouvert plus tard si un troisième consommateur de conventions apparaissait.

## Décisions déjà prises

| Sujet | Décision |
|---|---|
| Nombre d'exécuteurs | Un seul : `developer` |
| HARD-GATE | Conservé — conception obligatoire partout |
| Sort de `john` | Skill **et** agent supprimés |
| Voie interactive rapide | Supprimée (plus de « 3.3 bis » Sarah) |
| Source de vérité conventions | Absorbée par `developer` (Approche A) |
| Portée du renommage | Globale (fichiers vivants ; archives intactes) |
| Versionnage plugin | Bump `0.3.0 → 0.4.0` (changement cassant : skill/agent supprimés + renommés) |

## Architecture — inventaire complet des fichiers

Légende : **CRÉER / DÉPLACER / SUPPRIMER / MODIFIER**.

### Cœur du plugin `ezacae-dev`

| Action | Fichier | Détail |
|---|---|---|
| DÉPLACER | `skills/morgan/SKILL.md` → `skills/developer/SKILL.md` | + réécriture (voir §Transformations) |
| DÉPLACER | `skills/morgan/mr-templates.md` → `skills/developer/mr-templates.md` | contenu inchangé ; réf. interne mise à jour |
| DÉPLACER | `skills/john/stacks/nextjs.md` → `skills/developer/stacks/nextjs.md` | contenu inchangé |
| DÉPLACER | `skills/john/stacks/flutter.md` → `skills/developer/stacks/flutter.md` | contenu inchangé |
| DÉPLACER | `agents/morgan.md` → `agents/developer.md` | frontmatter `name: developer` ; réf. « skill john » → « skill developer » |
| SUPPRIMER | `skills/john/SKILL.md` | rôle exécuteur supprimé ; rôle conventions absorbé par developer |
| SUPPRIMER | `agents/john.md` | plus d'exécuteur interactif |
| MODIFIER | `commands/sarah.md` | retrait 3.3 bis ; retarget refs ; menu |
| MODIFIER | `skills/chuck/SKILL.md` | `skills/john/stacks` → `skills/developer/stacks` ; « skill john » → « skill developer » ; `/morgan` → `/developer` |
| MODIFIER | `commands/feature.md` | `morgan/john` → `developer` |
| MODIFIER | `hooks/session-start-dev.sh` | chemin `skills/john/stacks` → `skills/developer/stacks` + prose |
| MODIFIER | `.claude-plugin/plugin.json` | description + `version` → `0.4.0` |

> `agents/code-simplifier.md`, `agents/technical-design-generator.md`, skills `chuck`/`grill-me`/`handoff`, `superpowers.lock`, `tests/` : **non impactés** (hors chuck déjà listé).

### Plugin `ezacae-jira`

| Action | Fichier | Détail |
|---|---|---|
| MODIFIER | `skills/jira-pipeline/PIPELINE.md` | lignes 21-22, 26, 49, 67, 87, 106, 155 : `morgan`/`john` → `developer` ; fusionner les deux lignes de rôle en une |
| MODIFIER | `skills/jira-pipeline/SKILL.md` | ligne 175 : `Sarah → morgan/john` → `Sarah → developer` |

### Racine dépôt / documentation vivante

| Action | Fichier | Détail |
|---|---|---|
| MODIFIER | `.claude-plugin/marketplace.json` | description ezacae-dev (ligne 31) |
| MODIFIER | `README.md` | lignes 3, 47, 57-61, 67-68, 146-147 : refléter un exécuteur `developer` ; retirer la note « Morgan/John même travail » ; bump version cellule |
| MODIFIER | `docs/index.md` | lignes 7, 30 : « 5 skills · 4 agents » → « 4 skills · 3 agents » ; listes |
| MODIFIER | `MIGRATION.md` | lignes 35, 37, 65-66, 73, 130 : mettre à jour les listes de fichiers pour rester exactes |

### Archives — NE PAS toucher

`docs/conception/rd-8-alleger-les-skills.md`, `docs/superpowers/plans/2026-06-22-*.md`, `docs/superpowers/specs/2026-06-22-*.md`, `docs/jira-watcher-mike.md` : enregistrements datés d'un état passé. Les réécrire falsifierait l'historique. Ce présent document de conception les rend caducs sans les modifier.

## Transformations clés

### `skills/developer/SKILL.md` (ex-morgan, réécrit)

Structure cible :

1. **Frontmatter** : `name: developer` ; `description` fusionnée — déclencheurs de morgan (`/developer`, « implémenter la conception », « lance developer », « exécuter la conception ») **plus** ceux, désormais canalisés par le HARD-GATE, qui menaient à john (« implémenter », « coder », « corriger », « bugfix »…). Ces derniers doivent aiguiller vers *chuck d'abord* : la description précise « nécessite un document de conception (via `/chuck`) ».
2. **DISPATCH-GATE** — inchangé sur le fond (dispatch sous-agent `developer`, worktree, `sonnet`), noms mis à jour.
3. **HARD-GATE** — conservé tel quel.
4. **Quand NE PAS utiliser** — retirer la ligne « implémentation interactive → skill john » (n'existe plus) ; garder « conception → /chuck ».
5. **NOUVELLE section « Détection de la stack (procédure de référence) »** — rapatriée depuis `skills/john/SKILL.md` (la table de détection + cas particuliers). Devient la **référence canonique** citée par chuck/sarah.
6. **NOUVELLE section « Discipline non négociable (toutes stacks) »** — rapatriée depuis `skills/john/SKILL.md`.
7. **Sources de vérité** — `stacks/<stack>.md` désormais **local au skill developer** (plus « via le skill john »).
8. Phases 0→6 — inchangées, sauf les mentions « skill john » → « la procédure/discipline ci-dessus » et chemins `stacks/` locaux.

### `agents/developer.md` (ex-morgan)

- Frontmatter `name: developer`.
- Les invocations « **invoque le skill `ezacae-dev:john`** » → « **invoque le skill `ezacae-dev:developer`** » (même pattern qu'aujourd'hui : en lisant le skill on EST déjà le sous-agent → ignorer le DISPATCH-GATE). Base dir → `stacks/<stack>.md` local.
- Messages STOP « Conventions ezacae inaccessibles (skill john…) » → « (skill developer…) ».

### `commands/sarah.md`

- Ligne 7 : `(chuck, morgan, john)` → `(chuck, developer)`.
- Phase 1 (l. 60, 62) : « procédure … skill john » → « skill developer » ; chemin `skills/john/stacks` → `skills/developer/stacks`.
- Table Phase 2 (l. 79-80) : fusionner les lignes « conception validée → morgan » et « petite modif → john » en **une** : *« Besoin implémentable (conception requise) → 3.3 Implémentation (`developer`) »*. **Supprimer la ligne 80 (john).**
- **Supprimer la section 3.3 bis** (l. 133-135) entièrement.
- Phase 3.3 (l. 123-131) : `morgan` → `developer`.
- Findings (l. 147, 150) : corrections via `developer`.
- Menu final (l. 173-174) : retirer l'option 4 « petite modif → john » ; « implémentation (morgan) » → « implémentation (developer) ».
- Table pipeline JIRA (l. 29, 33) : `morgan/john` → `developer`.

### `skills/chuck/SKILL.md`

- Note conventions (l. 11) + toutes réf. `skills/john/stacks/<stack>.md` → `skills/developer/stacks/<stack>.md`.
- « procédure … skill john » (l. 33, 78) → « skill developer ».
- « Quand NE PAS utiliser » (l. 19-20) : « code à écrire → skill john » **supprimé** ; « exécution conception → `/morgan` » → `/developer`.
- Graphe (l. 57), notes (l. 132, 161, 170, 208, 223, 231), ligne de passation (l. 243) : `/morgan`→`/developer`, « Morgan »→« developer », retirer « ou skill john (interactif) ».

### `hooks/session-start-dev.sh`

- Commentaire (l. 4-5) et sortie injectée (l. 16-17) : `skills/john/stacks/<stack>.md` → `skills/developer/stacks/<stack>.md` ; « skills chuck/john/morgan » → « skills chuck/developer ».

### Manifestes + versionnage

- `plugin.json` : `version` `0.3.0` → `0.4.0` ; description réécrite (un exécuteur `developer`, agents `developer`/`code-simplifier`/`technical-design-generator`).
- `marketplace.json` : description ezacae-dev alignée.
- `README.md` : cellule version `0.3.0` → `0.4.0` (règle projet : bump plugin.json **et** README à chaque changement).

## Risques et points de vigilance

- **Références orphelines** — principal risque. Après renommage, **aucune** occurrence de `skill john`, `/morgan`, `subagent_type: "john"|"morgan"`, ou chemin `skills/john|morgan/` ne doit subsister dans les fichiers vivants. Vérifié par `grep` en fin de plan (invariant bloquant).
- **Chemin `stacks/` dans le hook** — si le hook continue d'injecter l'ancien chemin, chuck/sarah liront un chemin inexistant → conventions introuvables. Vérification dédiée.
- **Cache plugin obsolète** — les postes ont `~/.claude/plugins/cache/.../0.3.0`. Le bump `0.4.0` force le rafraîchissement ; sans bump, l'ancien `john` resterait actif localement. Le bump est donc **obligatoire**, pas cosmétique.
- **`git mv` vs suppression** — utiliser `git mv` pour les déplacements (préserve l'historique de `morgan`→`developer` et des `stacks/`). Les `stacks/*.md` déménagent de `john/` vers `developer/` : `git mv` également.
- **Changement cassant assumé** — toute session/doc externe tapant `/morgan` ou comptant sur `/john` cassera. Acté (portée globale, pas d'alias de compat). `MIGRATION.md` documente le changement.
- **Déclencheurs élargis de `developer`** — en héritant des mots-clés de john (« coder », « corriger »…), le skill `developer` pourrait se déclencher sur une demande sans conception. Le HARD-GATE l'intercepte et renvoie vers `/chuck` : comportement voulu, à énoncer explicitement dans la description et le corps du skill.

## Plan d'implémentation

> **Exécution** : ce document sera implémenté sur une **branche dédiée** (voir §Stratégie de branche). Le refactor porte sur des fichiers Markdown/JSON de plugin : il n'y a pas de framework de test unitaire. L'équivalent « test » est un jeu d'**invariants `grep`** (intégrité référentielle) qui doivent passer avant de considérer une phase terminée — écrits/vérifiés **avant** de déclarer la phase faite (esprit TDD : on définit l'assertion, on la fait passer).

**Objectif :** un seul exécuteur `developer` (morgan renommé + conventions de john absorbées), `john` supprimé, zéro référence orpheline, plugin bumpé.

**Architecture :** Approche A — `skills/developer/` porte l'exécuteur ET la bibliothèque `stacks/` + procédure de détection + discipline.

---

### Phase 1 — Déplacements et suppressions (structure)

#### Tâche 1.1 — Déplacer morgan → developer
- [ ] `git mv plugins/ezacae-dev/skills/morgan plugins/ezacae-dev/skills/developer`
- [ ] `git mv plugins/ezacae-dev/agents/morgan.md plugins/ezacae-dev/agents/developer.md`
- [ ] **Vérif** : `ls plugins/ezacae-dev/skills/developer/` liste `SKILL.md` + `mr-templates.md`

#### Tâche 1.2 — Déplacer la bibliothèque stacks/ sous developer
- [ ] `git mv plugins/ezacae-dev/skills/john/stacks plugins/ezacae-dev/skills/developer/stacks`
- [ ] **Vérif** : `ls plugins/ezacae-dev/skills/developer/stacks/` liste `nextjs.md` + `flutter.md`

#### Tâche 1.3 — Supprimer john (rôle exécuteur)
- [ ] `git rm plugins/ezacae-dev/agents/john.md`
- [ ] `git rm plugins/ezacae-dev/skills/john/SKILL.md` puis retirer le dossier `skills/john` désormais vide
- [ ] **Vérif (invariant)** : `test ! -e plugins/ezacae-dev/skills/john && test ! -e plugins/ezacae-dev/agents/john.md`

### Phase 2 — Absorption des conventions dans developer

#### Tâche 2.1 — Rapatrier détection + discipline dans developer/SKILL.md
- [ ] Ajouter dans `skills/developer/SKILL.md` la section « Détection de la stack (procédure de référence) » (table + cas particuliers, source : ancien `skills/john/SKILL.md` §Détection).
- [ ] Ajouter la section « Discipline non négociable (toutes stacks) ».
- [ ] Frontmatter → `name: developer` ; description fusionnée (déclencheurs morgan + ex-john canalisés « conception requise via /chuck »).
- [ ] Corps : réf. « skill john » → « procédure ci-dessus » ; chemins `stacks/` locaux ; retirer « interactif → john » de « Quand NE PAS utiliser ».
- [ ] **Vérif** : `grep -c "Détection de la stack" skills/developer/SKILL.md` ≥ 1 ; `grep -n "john" skills/developer/SKILL.md` **vide**.

#### Tâche 2.2 — Réaligner agents/developer.md
- [ ] `name: developer` ; « invoque le skill `ezacae-dev:john` » → « …:developer » ; messages STOP « skill john » → « skill developer ».
- [ ] **Vérif** : `grep -n "john\|morgan" agents/developer.md` **vide**.

### Phase 3 — Recâblage des orchestrateurs et du hook

#### Tâche 3.1 — sarah.md
- [ ] Appliquer les modifications §Transformations (retrait 3.3 bis, fusion table, menu, chemins).
- [ ] **Vérif** : `grep -n "john\|morgan\|3.3 bis" plugins/ezacae-dev/commands/sarah.md` **vide**.

#### Tâche 3.2 — chuck/SKILL.md + feature.md
- [ ] Retarget refs (chemins `stacks/`, « skill developer », `/developer`).
- [ ] **Vérif** : `grep -rn "john\|morgan\|/morgan" plugins/ezacae-dev/skills/chuck/SKILL.md plugins/ezacae-dev/commands/feature.md` **vide**.

#### Tâche 3.3 — hook session-start-dev.sh
- [ ] Chemin + prose → `developer`.
- [ ] **Vérif** : `grep -n "skills/john\|morgan" plugins/ezacae-dev/hooks/session-start-dev.sh` **vide** ; `grep -c "skills/developer/stacks" …` ≥ 1.

### Phase 4 — Pipeline JIRA

#### Tâche 4.1 — jira-pipeline PIPELINE.md + SKILL.md
- [ ] `morgan`/`john` → `developer` (fusionner rôles).
- [ ] **Vérif** : `grep -rn "john\|morgan" plugins/ezacae-jira/skills/jira-pipeline/` **vide**.

### Phase 5 — Manifestes, README, index, MIGRATION, version

#### Tâche 5.1 — Version + descriptions
- [ ] `plugin.json` : `version` → `0.4.0` + description.
- [ ] `marketplace.json` : description.
- [ ] **Vérif** : `grep '"version": "0.4.0"' plugins/ezacae-dev/.claude-plugin/plugin.json`.

#### Tâche 5.2 — README + index + MIGRATION
- [ ] README lignes citées + cellule version `0.4.0`.
- [ ] `docs/index.md` : comptes (« 4 skills · 3 agents ») + listes.
- [ ] `MIGRATION.md` : listes de fichiers exactes.
- [ ] **Vérif** : `grep -rn "john\|morgan" README.md docs/index.md` **vide** (hors éventuelle mention historique explicitement datée).

### Phase 6 — Invariant global (gate de fin)

- [ ] **Invariant bloquant** — aucune référence orpheline dans les fichiers vivants :
  ```bash
  grep -rniE '\bjohn\b|\bmorgan\b|/morgan|skills/(john|morgan)' \
    plugins README.md MIGRATION.md docs/index.md mkdocs.yml .claude-plugin \
    --include='*.md' --include='*.json' --include='*.sh' \
    | grep -v 'docs/conception/rd-8\|docs/superpowers/\|docs/jira-watcher-mike'
  ```
  → **doit ne rien retourner**. Toute ligne = référence orpheline à corriger.
- [ ] **Sanity plugin** : relire `plugin.json` (JSON valide, version 0.4.0), arborescence `skills/developer/` complète (`SKILL.md`, `mr-templates.md`, `stacks/nextjs.md`, `stacks/flutter.md`).
- [ ] Rapport final : liste des fichiers déplacés/supprimés/modifiés + sortie de l'invariant (vide).

## Stratégie de branche et validation

- Travail sur une **branche dédiée** : `refactor/fusion-developer` (ou préfixée par la clé JIRA si un ticket est ouvert).
- **Ce document de conception** est committé et poussé en premier (précondition du flux ezacae : un futur dispatch `developer` sur worktree ne verrait le `.md` que s'il est sur `origin`).
- Après validation utilisateur : dérouler les Phases 1→6 sur la branche, puis MR.

> **À valider avant implémentation** : (1) l'Approche A (developer = source de vérité) ; (2) le bump `0.4.0` ; (3) la portée globale incluant le pipeline JIRA. Dis-moi si tu veux des ajustements.