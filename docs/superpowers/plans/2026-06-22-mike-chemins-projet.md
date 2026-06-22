# Mike multi-repos : résolution des chemins & routage des livrables — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre Mike capable de connaître le repo source et le repo de documentation quel que soit son point de lancement, persister ces chemins, et router les livrables (cadrage/conception → repo source ; doc fonctionnelle/technique → repo doc).

**Architecture:** Édition de fichiers de prompt Markdown (commandes et skills des plugins `ezacae-doc` et `ezacae-dev`). Aucune logique de code exécutable, donc pas de test automatisé : la « vérification » de chaque tâche est un `grep` ciblé prouvant que les anciennes références ont disparu et que les nouvelles sont en place, plus une relecture de cohérence. Les chemins sont matérialisés par deux variables conceptuelles, `$CODE_REPO_PATH` et `$DOC_REPO_PATH`, résolues depuis `.claude/local.md`.

**Tech Stack:** Markdown (prompts de plugins Claude Code), Git, helpers JIRA REST existants.

**Spec de référence :** `docs/superpowers/specs/2026-06-22-mike-chemins-projet-design.md`

**Note de déploiement :** ces fichiers vivent dans `plugins/…` du repo `ezacae-claude-tooling`. La copie installée (`~/.claude/plugins/cache/ezacae-claude-tooling/…`) ne reflétera les changements qu'après réinstallation/mise à jour des plugins. Hors périmètre de ce plan.

---

## File Structure

| Fichier | Responsabilité | Action |
|---|---|---|
| `plugins/ezacae-doc/commands/mike.md` | Orchestrateur doc — porte la **Phase 0b** canonique de résolution des chemins, scope ses lectures sur `$DOC_REPO_PATH`, route le cadrage vers `$CODE_REPO_PATH` | Modifier |
| `plugins/ezacae-doc/commands/mike-cto.md` | Spécialiste technique — résout les chemins (absorbe son ancienne Phase 0b ask/save), scope git/lectures/écritures/`mkdocs.yml` sur `$DOC_REPO_PATH` | Modifier |
| `plugins/ezacae-doc/commands/mike-po.md` | Spécialiste produit — résout `$DOC_REPO_PATH`, scope git/lectures/écritures/`mkdocs.yml` | Modifier |
| `plugins/ezacae-dev/skills/chuck/SKILL.md` | Conception — écrit dans `docs/conception/` (cwd = repo source) | Modifier |
| `plugins/ezacae-dev/commands/sarah.md` | Orchestrateur dev — références au chemin de conception | Modifier |
| `plugins/ezacae-dev/skills/morgan/SKILL.md` | Implémentation autonome — exemples de chemins (cosmétique) | Modifier |

L'ordre des tâches : d'abord la logique canonique dans `/mike` (Tâche 1-2), puis sa réutilisation dans CTO/PO (Tâche 3-4), enfin l'alignement du chemin de conception côté dev (Tâche 5). Chaque tâche est commitable indépendamment.

---

## Task 0: Créer la branche de travail

**Files:** aucun (opération git)

- [ ] **Step 1: Vérifier l'état du repo**

Run: `git -C /Users/simon/DEV/ezacae-claude-tooling status --short && git -C /Users/simon/DEV/ezacae-claude-tooling branch --show-current`
Expected: branche `master`, working tree propre **sauf** les fichiers de spec/plan déjà créés sous `docs/superpowers/`.

- [ ] **Step 2: Créer et basculer sur la branche**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling checkout -b feat/mike-chemins-projet
```

- [ ] **Step 3: Committer la spec et le plan**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling add docs/superpowers/specs/2026-06-22-mike-chemins-projet-design.md docs/superpowers/plans/2026-06-22-mike-chemins-projet.md
git -C /Users/simon/DEV/ezacae-claude-tooling commit -m "docs: spec et plan Mike multi-repos"
```

---

## Task 1: `/mike` — Phase 0b de résolution des chemins

**Files:**
- Modify: `plugins/ezacae-doc/commands/mike.md` (insérer une section entre la Phase 0 et la Phase 1, lignes ~71-73)

- [ ] **Step 1: Insérer la Phase 0b**

Repérer la fin de la Phase 0 et le début de la Phase 1 :

```
La **garde de statut** (hook `PreToolUse` du plugin ezacae-jira) bloquera de toute façon une transition hors séquence — voir skill `jira-pipeline` §5.

---

## Phase 1 — Lecture du contexte
```

Insérer, **entre** le `---` qui clôt la Phase 0 et `## Phase 1`, le bloc suivant :

```markdown
## Phase 0b — Résolution des chemins projet (CODE_REPO_PATH + DOC_REPO_PATH)

Mike peut être lancé **depuis le repo source ou depuis le repo de documentation**. Il a besoin des deux chemins absolus avant toute lecture/écriture de documentation.

1. Lire `.claude/local.md` du répertoire courant et en extraire :
   - `CODE_REPO_PATH` — racine du repo de **code source**
   - `DOC_REPO_PATH` — racine du repo de **documentation fonctionnelle**
2. **Auto-détecter la nature du répertoire courant** pour pré-remplir le chemin manquant (le chemin détecté vaut `pwd`) :
   - repo **doc** si `.claude/doc-manifest.md` existe, ou si `docs/00_vision`/`docs/01_product` sont présents ;
   - repo **source** si un manifeste de stack est présent à la racine (`package.json`, `pubspec.yaml`, `composer.json`, `pyproject.toml`, `go.mod`, `pom.xml`, …) **et** qu'il n'y a pas de `doc-manifest.md`.
3. Vérifier que les deux dossiers existent (`ls $CODE_REPO_PATH`, `ls $DOC_REPO_PATH`).
4. **Si un chemin manque ou est invalide**, demander à l'utilisateur (pré-remplir avec le chemin auto-détecté) :

   ```
   📁 Chemins du projet à confirmer :
      - Repo SOURCE (code de l'application) : [auto-détecté ou ?]
      - Repo DOC (documentation fonctionnelle) : [auto-détecté ou ?]
   ```

   Puis **persister dans les DEUX repos** — écrire le même contenu dans `$CODE_REPO_PATH/.claude/local.md` et `$DOC_REPO_PATH/.claude/local.md` :

   ```
   ## Config locale (ne pas commiter)
   - **CODE_REPO_PATH :** /chemin/absolu/vers/source
   - **DOC_REPO_PATH :**  /chemin/absolu/vers/doc
   ```

   Garantir que `.claude/local.md` figure dans le `.gitignore` de chaque repo (l'ajouter sinon).
5. Confirmer en une ligne : `📁 Source : <CODE_REPO_PATH> · Doc : <DOC_REPO_PATH>`.

> À partir d'ici, **toutes les lectures/écritures de documentation de Mike passent par `$DOC_REPO_PATH`** ; les fiches de cadrage/conception passent par `$CODE_REPO_PATH`. Lancé depuis le repo doc, `$DOC_REPO_PATH == pwd` : comportement inchangé.

---
```

- [ ] **Step 2: Vérifier l'insertion**

Run: `grep -n "Phase 0b — Résolution des chemins" plugins/ezacae-doc/commands/mike.md`
Expected: une ligne trouvée, située avant `## Phase 1`.

- [ ] **Step 3: Commit**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling add plugins/ezacae-doc/commands/mike.md
git -C /Users/simon/DEV/ezacae-claude-tooling commit -m "feat(mike): résolution des chemins source/doc (Phase 0b)"
```

---

## Task 2: `/mike` — scoper les lectures sur `$DOC_REPO_PATH` et router le cadrage

**Files:**
- Modify: `plugins/ezacae-doc/commands/mike.md` (Phase 1, Phase 2, et section M-B du mode pipeline)

- [ ] **Step 1: Scoper la Phase 1**

Remplacer :

```
Lire silencieusement :
1. `.claude/CLAUDE.md` — contexte complet du projet
2. `.claude/doc-manifest.md` — état de la documentation
```

par :

```
Lire silencieusement (chemins résolus en Phase 0b) :
1. `$DOC_REPO_PATH/.claude/CLAUDE.md` — contexte complet du projet
2. `$DOC_REPO_PATH/.claude/doc-manifest.md` — état de la documentation
```

- [ ] **Step 2: Scoper la Phase 2**

Remplacer la ligne :

```
find docs/ -name "*.md" | sort
```

par :

```
find $DOC_REPO_PATH/docs/ -name "*.md" | sort
```

- [ ] **Step 3: Router le cadrage dans M-B (étapes 4 à 7)**

Dans la section `### M-B — Cadrage (statut NOUVEAU ou CADRAGE)`, remplacer les étapes 4 à 7 actuelles :

```
4. Produire une **fiche de cadrage fonctionnel** (`docs/<projet>/cadrage-<sujet>.md`) — le « fichier de résultat » qui servira d'entrée à Sarah/chuck : objectif, périmètre, personas impactés, processus concernés, contraintes connues. Pas de détail d'implémentation (ça reste le travail de chuck).
5. Attacher au ticket : `<HELPERS>/jira-attach.sh <KEY> <fiche + docs mises à jour>`.
6. **Transition `CADRAGE → CONCEPTION`** + commentaire de passation (§8) en un appel : `<HELPERS>/jira-transition.sh <KEY> "CONCEPTION" --comment "<passation>"`.
7. **Passer la main à Sarah** : invoquer `/sarah <KEY>` dans le thread principal.
```

par :

```
4. Produire une **fiche de cadrage fonctionnel** dans le **repo source** : `$CODE_REPO_PATH/docs/conception/cadrage-<sujet>.md` — le « fichier de résultat » qui servira d'entrée à Sarah/chuck : objectif, périmètre, personas impactés, processus concernés, contraintes connues. Pas de détail d'implémentation (ça reste le travail de chuck).
5. **Committer et pousser la fiche dans le repo source** :
   ```bash
   git -C $CODE_REPO_PATH add docs/conception/cadrage-<sujet>.md
   git -C $CODE_REPO_PATH commit -m "docs(cadrage): <sujet>"
   git -C $CODE_REPO_PATH push
   ```
6. Attacher au ticket : `<HELPERS>/jira-attach.sh <KEY> $CODE_REPO_PATH/docs/conception/cadrage-<sujet>.md` (+ docs doc mises à jour le cas échéant).
7. **Transition `CADRAGE → CONCEPTION`** + commentaire de passation (§8) en un appel : `<HELPERS>/jira-transition.sh <KEY> "CONCEPTION" --comment "<passation>"`.
8. **Passer la main à Sarah** : invoquer `/sarah <KEY>` dans le thread principal.
```

- [ ] **Step 4: Vérifier l'absence d'anciennes références doc-relatives**

Run: `grep -n "docs/<projet>/cadrage\|^find docs/\|\`.claude/CLAUDE.md\`\|\`.claude/doc-manifest.md\`" plugins/ezacae-doc/commands/mike.md`
Expected: **aucune** ligne (les anciennes formes ont été remplacées). Vérifier en parallèle que les nouvelles existent :
Run: `grep -n "CODE_REPO_PATH/docs/conception/cadrage\|DOC_REPO_PATH/.claude/CLAUDE.md\|find \$DOC_REPO_PATH/docs/" plugins/ezacae-doc/commands/mike.md`
Expected: 3 lignes trouvées.

- [ ] **Step 5: Commit**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling add plugins/ezacae-doc/commands/mike.md
git -C /Users/simon/DEV/ezacae-claude-tooling commit -m "feat(mike): scope doc sur \$DOC_REPO_PATH et cadrage dans le repo source"
```

---

## Task 3: `/mike-cto` — résolution unifiée + scoping `$DOC_REPO_PATH`

**Files:**
- Modify: `plugins/ezacae-doc/commands/mike-cto.md` (Phase 0, Phase 0b, Phase 1, Phase 5)

- [ ] **Step 1: Remplacer la Phase 0b actuelle par la résolution unifiée**

Remplacer **tout le bloc** entre `## Phase 0b — Synchronisation du code source` et le `---` qui précède `## Phase 1` (soit l'actuel Cas A / Cas B / phrase `commit_ref`) par :

```markdown
## Phase 0b — Résolution des chemins projet & synchronisation du code source

Mike-CTO peut être invoqué directement ou délégué par Mike, depuis le repo source **ou** le repo doc.

1. **Résoudre les chemins** comme en `/mike` Phase 0b : lire `.claude/local.md` du répertoire courant, extraire `CODE_REPO_PATH` et `DOC_REPO_PATH`. Auto-détecter la nature du `pwd` pour pré-remplir (doc si `.claude/doc-manifest.md`/`docs/00_vision` ; source si manifeste de stack sans `doc-manifest.md`). Vérifier l'existence des deux dossiers.
2. **Si un chemin manque/invalide** : demander à l'utilisateur (pré-rempli avec le détecté), puis écrire le même `.claude/local.md` (champs `CODE_REPO_PATH` + `DOC_REPO_PATH`) dans **les deux** repos et garantir `.claude/local.md` dans chaque `.gitignore`.
3. Confirmer : `📁 Source : <CODE_REPO_PATH> · Doc : <DOC_REPO_PATH>`.
4. **Synchroniser le code source** pour le pied de page des documents générés :
   ```
   📁 Code source : $CODE_REPO_PATH
      Synchroniser avec le dernier commit main ? (O/n)
   ```
   - **O ou Entrée** :
     ```bash
     git -C $CODE_REPO_PATH fetch origin
     git -C $CODE_REPO_PATH pull origin main
     git -C $CODE_REPO_PATH log --oneline -3
     ```
   - **n** → continuer sans `commit_ref`.

   | Situation | Action |
   |-----------|--------|
   | Pull réussi | ✅ Extraire hash complet + message + date → `commit_ref` |
   | Conflit / erreur git | ⚠️ Signaler — continuer sans `commit_ref` |

Le `commit_ref` (hash complet + message + date) sera passé à chaque `stack-writer` pour le pied de page des documents générés.
```

> Note : la Phase 0 (git du repo doc) reste mais doit cibler le repo doc — voir Step 2.

- [ ] **Step 2: Scoper la Phase 0 (git du repo doc) sur `$DOC_REPO_PATH`**

> ⚠️ La Phase 0b est désormais lue **avant** la Phase 0 ne soit utile ; mais la Phase 0 reste écrite avant dans le fichier. Pour éviter une dépendance d'ordre, ajouter en tête de la Phase 0 la note suivante, juste après son titre `## Phase 0 — Vérification de la synchronisation Git` :

```
> Cette vérification porte sur le **repo de documentation** (`$DOC_REPO_PATH`, résolu en Phase 0b). Si Mike-CTO est lancé depuis le repo doc, `$DOC_REPO_PATH == pwd`. Utiliser `git -C $DOC_REPO_PATH` pour `fetch`/`status`/`pull`.
```

Et remplacer le bloc :

```bash
git fetch origin
git status
```

par :

```bash
git -C $DOC_REPO_PATH fetch origin
git -C $DOC_REPO_PATH status
```

- [ ] **Step 3: Scoper la Phase 1 (lectures)**

Remplacer :

```
1. `.claude/CLAUDE.md` — contexte du projet, stack, composants applicatifs, `GITLAB_URL`
2. `.claude/local.md` — config personnelle (`CODE_REPO_PATH`)
3. `.claude/doc-manifest.md` — documents attendus et leur statut
4. Tous les fichiers dans `docs/02_architecture/`, `docs/03_donnees/` et `docs/04_exploitation/` (et sous-dossiers techniques existants)
5. `docs/00_vision/vision.md` — périmètre fonctionnel pour cohérence
```

par :

```
1. `$DOC_REPO_PATH/.claude/CLAUDE.md` — contexte du projet, stack, composants applicatifs, `GITLAB_URL`
2. `.claude/local.md` (cwd) — config personnelle (`CODE_REPO_PATH`, `DOC_REPO_PATH`)
3. `$DOC_REPO_PATH/.claude/doc-manifest.md` — documents attendus et leur statut
4. Tous les fichiers dans `$DOC_REPO_PATH/docs/02_architecture/`, `$DOC_REPO_PATH/docs/03_donnees/` et `$DOC_REPO_PATH/docs/04_exploitation/` (et sous-dossiers techniques existants)
5. `$DOC_REPO_PATH/docs/00_vision/vision.md` — périmètre fonctionnel pour cohérence
```

- [ ] **Step 4: Scoper la Phase 5 (branche, find, commit, push)**

Remplacer le bloc 5.1 :

```bash
git checkout -b docs/cto/[slug]
```

par :

```bash
git -C $DOC_REPO_PATH checkout -b docs/cto/[slug]
```

Dans 5.4b, remplacer `find docs/ -name "*.md" | sort` par `find $DOC_REPO_PATH/docs/ -name "*.md" | sort`, et préciser que `mkdocs.yml` est généré à la racine `$DOC_REPO_PATH` (remplacer « à la racine du projet » par « à la racine `$DOC_REPO_PATH` »).

Remplacer le bloc 5.5 :

```bash
git add docs/ .claude/doc-manifest.md mkdocs.yml
git commit -m "docs(cto): [description courte]"
git push -u origin docs/cto/[slug]
```

par :

```bash
git -C $DOC_REPO_PATH add docs/ .claude/doc-manifest.md mkdocs.yml
git -C $DOC_REPO_PATH commit -m "docs(cto): [description courte]"
git -C $DOC_REPO_PATH push -u origin docs/cto/[slug]
```

Dans 5.6, `glab` n'a pas d'option `-C` : il faut l'exécuter dans le dossier de travail du repo doc. Ajouter avant le bloc la note : `> `glab` lit le repo depuis le dossier courant — l'exécuter via `(cd $DOC_REPO_PATH && … )`.` Puis envelopper la commande :

```bash
(cd $DOC_REPO_PATH && glab mr create \
  --title "[Titre]" \
  --description "[Description : composants impactés, ce qui a changé, pourquoi, points d'attention pour le reviewer]" \
  --target-branch main \
  --assignee @me)
```

Faire le même enveloppement `(cd $DOC_REPO_PATH && … )` pour le bloc git de la **Phase 6** (feedback) :

```bash
(cd $DOC_REPO_PATH && git add docs/ .claude/doc-manifest.md mkdocs.yml && git commit --amend --no-edit && git push --force-with-lease)
```

- [ ] **Step 5: Vérifier**

Run: `grep -n "git checkout -b docs/cto\|^git add docs/\|^find docs/\|git fetch origin$" plugins/ezacae-doc/commands/mike-cto.md`
Expected: **aucune** ligne (toutes scopées). Puis :
Run: `grep -nc "DOC_REPO_PATH" plugins/ezacae-doc/commands/mike-cto.md`
Expected: nombre ≥ 8.

- [ ] **Step 6: Commit**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling add plugins/ezacae-doc/commands/mike-cto.md
git -C /Users/simon/DEV/ezacae-claude-tooling commit -m "feat(mike-cto): résolution unifiée des chemins et scoping \$DOC_REPO_PATH"
```

---

## Task 4: `/mike-po` — résolution `$DOC_REPO_PATH` + scoping

**Files:**
- Modify: `plugins/ezacae-doc/commands/mike-po.md` (Phase 0, nouvelle Phase 0b, Phase 1, Phase 5, Phase 6)

- [ ] **Step 1: Ajouter une Phase 0b de résolution**

Insérer, **après** le `---` qui clôt la Phase 0 et **avant** `## Phase 1 — Lecture du contexte`, le bloc :

```markdown
## Phase 0b — Résolution du chemin de documentation

Mike-PO peut être invoqué directement ou délégué par Mike, depuis le repo source **ou** le repo doc. Résoudre `DOC_REPO_PATH` comme en `/mike` Phase 0b : lire `.claude/local.md` du répertoire courant, en extraire `DOC_REPO_PATH` (et `CODE_REPO_PATH`). Auto-détecter le `pwd` pour pré-remplir (doc si `.claude/doc-manifest.md`/`docs/00_vision` ; source si manifeste de stack sans `doc-manifest.md`). Si `DOC_REPO_PATH` manque/invalide : demander à l'utilisateur puis écrire `.claude/local.md` (champs `CODE_REPO_PATH` + `DOC_REPO_PATH`) dans les deux repos, et garantir `.claude/local.md` dans chaque `.gitignore`. Confirmer : `📁 Doc : <DOC_REPO_PATH>`.

Lancé depuis le repo doc, `$DOC_REPO_PATH == pwd` : comportement inchangé. **Toutes les opérations git, lectures et écritures ci-dessous portent sur `$DOC_REPO_PATH`.**

---
```

- [ ] **Step 2: Scoper la Phase 0 (git)**

Ajouter après le titre `## Phase 0 — Vérification de la synchronisation Git` la note :

```
> Cette vérification porte sur le **repo de documentation** (`$DOC_REPO_PATH`, résolu en Phase 0b). Utiliser `git -C $DOC_REPO_PATH`.
```

Remplacer :

```bash
git fetch origin
git status
```

par :

```bash
git -C $DOC_REPO_PATH fetch origin
git -C $DOC_REPO_PATH status
```

- [ ] **Step 3: Scoper la Phase 1 (lectures)**

Remplacer :

```
1. `.claude/CLAUDE.md` — contexte du projet
2. `.claude/doc-manifest.md` — documents attendus et leur statut
3. `docs/00_vision/vision.md` — périmètre, hypothèses, proposition de valeur
4. `docs/01_product/personas.md` — types d'utilisateurs et capacités
5. `docs/01_product/processus.md` — processus métier existants
```

par :

```
1. `$DOC_REPO_PATH/.claude/CLAUDE.md` — contexte du projet
2. `$DOC_REPO_PATH/.claude/doc-manifest.md` — documents attendus et leur statut
3. `$DOC_REPO_PATH/docs/00_vision/vision.md` — périmètre, hypothèses, proposition de valeur
4. `$DOC_REPO_PATH/docs/01_product/personas.md` — types d'utilisateurs et capacités
5. `$DOC_REPO_PATH/docs/01_product/processus.md` — processus métier existants
```

- [ ] **Step 4: Scoper la Phase 5 (branche, find, commit, push, MR)**

Remplacer `git checkout -b docs/po/[slug]` par `git -C $DOC_REPO_PATH checkout -b docs/po/[slug]`.

Dans 5.4b, remplacer `find docs/ -name "*.md" | sort` par `find $DOC_REPO_PATH/docs/ -name "*.md" | sort` et « à la racine du projet » par « à la racine `$DOC_REPO_PATH` ».

Remplacer le bloc 5.5 :

```bash
git add docs/ .claude/doc-manifest.md mkdocs.yml
git commit -m "docs(po): [description courte]"
git push -u origin docs/po/[slug]
```

par :

```bash
git -C $DOC_REPO_PATH add docs/ .claude/doc-manifest.md mkdocs.yml
git -C $DOC_REPO_PATH commit -m "docs(po): [description courte]"
git -C $DOC_REPO_PATH push -u origin docs/po/[slug]
```

Dans 5.6, envelopper la commande `glab mr create` :

```bash
(cd $DOC_REPO_PATH && glab mr create \
  --title "[Titre]" \
  --description "[Description : ce qui a changé, pourquoi, documents modifiés, points d'attention]" \
  --target-branch main \
  --assignee @me)
```

- [ ] **Step 5: Scoper la Phase 6 (feedback)**

Remplacer :

```bash
git add docs/ .claude/doc-manifest.md mkdocs.yml
git commit --amend --no-edit
git push --force-with-lease
```

par :

```bash
(cd $DOC_REPO_PATH && git add docs/ .claude/doc-manifest.md mkdocs.yml && git commit --amend --no-edit && git push --force-with-lease)
```

- [ ] **Step 6: Vérifier**

Run: `grep -n "git checkout -b docs/po\|^git add docs/\|^find docs/\|git fetch origin$" plugins/ezacae-doc/commands/mike-po.md`
Expected: **aucune** ligne. Puis :
Run: `grep -nc "DOC_REPO_PATH" plugins/ezacae-doc/commands/mike-po.md`
Expected: nombre ≥ 8.

- [ ] **Step 7: Commit**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling add plugins/ezacae-doc/commands/mike-po.md
git -C /Users/simon/DEV/ezacae-claude-tooling commit -m "feat(mike-po): résolution et scoping \$DOC_REPO_PATH"
```

---

## Task 5: Aligner le chemin de conception côté dev (`docs/conception/`)

**Files:**
- Modify: `plugins/ezacae-dev/skills/chuck/SKILL.md` (§9)
- Modify: `plugins/ezacae-dev/commands/sarah.md` (lignes 27, 123, 124)
- Modify: `plugins/ezacae-dev/skills/morgan/SKILL.md` (exemples §48-55)

- [ ] **Step 1: chuck §9 — chemin de conception**

Dans `plugins/ezacae-dev/skills/chuck/SKILL.md`, remplacer toutes les occurrences de `docs/<nom>.md` par `docs/conception/<nom>.md` et `docs/<nom>.mockup.html` par `docs/conception/<nom>.mockup.html`. Précisément :

- Ligne ~232 : `**Document de conception unique : `docs/<nom>.md`.**` → `**Document de conception unique : `docs/conception/<nom>.md`.**` (et la suite de la phrase mentionnant `docs/<nom>.mockup.html` → `docs/conception/<nom>.mockup.html`).
- Ligne ~237 : `> "Conception écrite dans `docs/<nom>.md`. …"` → `> "Conception écrite dans `docs/conception/<nom>.md`. …"`.
- Bloc git ~243-245 :
  ```bash
  git add docs/conception/<nom>.md docs/conception/<nom>.mockup.html  # maquette si présente
  git commit -m "docs(conception): <sujet>"
  git push
  ```
- Ligne de passation ~251 : `✅ Conception validée et poussée : docs/conception/<nom>.md — type: feature|bug — titre: <H1>` et ligne ~252 : `Exécution : /morgan docs/conception/<nom>.md  (autonome)  ou  skill john  (interactif)`.

Run pour repérer toutes les occurrences à traiter :
`grep -n "docs/<nom>" plugins/ezacae-dev/skills/chuck/SKILL.md`

- [ ] **Step 2: sarah.md — références au chemin**

Dans `plugins/ezacae-dev/commands/sarah.md` :

- Ligne 27 : `<HELPERS>/jira-attach.sh <KEY> docs/<nom>.md` → `<HELPERS>/jira-attach.sh <KEY> docs/conception/<nom>.md`.
- Ligne 123 (bloc pré-requis) : `git add docs/<nom>.md && git commit -m "docs(conception): <sujet>" && git push` → `git add docs/conception/<nom>.md && git commit -m "docs(conception): <sujet>" && git push` ; et la mention `docs/<nom>.md est commité+poussé` → `docs/conception/<nom>.md`.
- Ligne 124 : `skill `morgan docs/<nom>.md`` → `skill `morgan docs/conception/<nom>.md``.

Run pour repérer : `grep -n "docs/<nom>" plugins/ezacae-dev/commands/sarah.md`

- [ ] **Step 3: morgan/SKILL.md — exemples (cosmétique)**

Dans `plugins/ezacae-dev/skills/morgan/SKILL.md`, mettre les exemples ~53-55 en cohérence :

```
/morgan docs/conception/design-notifications.md
/morgan docs/conception/design-billing.md | Le praticien veut voir ses factures Stripe
/morgan docs/conception/design-export.md | Export CSV | Priorité performance
```

Et ligne ~320 : `| Fichier de conception introuvable | Lister `docs/conception/` et demander le bon chemin |`.

> morgan reçoit le chemin **en argument** : aucune logique en dur ne change, seuls les exemples et le message d'aide sont alignés.

- [ ] **Step 4: Vérifier l'absence de chemins obsolètes**

Run:
```bash
grep -rn "docs/<nom>" plugins/ezacae-dev/skills/chuck/SKILL.md plugins/ezacae-dev/commands/sarah.md
```
Expected: **aucune** ligne (toutes converties en `docs/conception/<nom>`).

Run:
```bash
grep -rn "docs/conception/" plugins/ezacae-dev/skills/chuck/SKILL.md plugins/ezacae-dev/commands/sarah.md plugins/ezacae-dev/skills/morgan/SKILL.md | wc -l
```
Expected: ≥ 6 lignes.

- [ ] **Step 5: Commit**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling add plugins/ezacae-dev/skills/chuck/SKILL.md plugins/ezacae-dev/commands/sarah.md plugins/ezacae-dev/skills/morgan/SKILL.md
git -C /Users/simon/DEV/ezacae-claude-tooling commit -m "feat(dev): conception et cadrage dans \$CODE_REPO_PATH/docs/conception/"
```

---

## Task 6: Revue de cohérence finale

**Files:** aucun (lecture seule)

- [ ] **Step 1: Vérifier la cohérence des chemins entre Mike et Sarah/chuck**

Run:
```bash
grep -rn "CODE_REPO_PATH/docs/conception\|docs/conception/cadrage" plugins/ezacae-doc/commands/mike.md
grep -rn "docs/conception/<nom>" plugins/ezacae-dev/skills/chuck/SKILL.md
```
Expected : Mike écrit le cadrage dans `$CODE_REPO_PATH/docs/conception/`, chuck écrit la conception dans `docs/conception/` (= `$CODE_REPO_PATH/docs/conception/` côté cwd source). Les deux pointent vers le même dossier logique.

- [ ] **Step 2: Vérifier qu'aucune commande Mike ne lit/écrit la doc relativement au cwd**

Run:
```bash
grep -rn "^find docs/\|^git add docs/\|git checkout -b docs/\|git fetch origin$\|\`.claude/doc-manifest.md\`" plugins/ezacae-doc/commands/mike.md plugins/ezacae-doc/commands/mike-po.md plugins/ezacae-doc/commands/mike-cto.md
```
Expected: **aucune** ligne.

- [ ] **Step 3: Relecture humaine**

Relire `mike.md`, `mike-po.md`, `mike-cto.md` pour vérifier que le récit reste fluide (numérotation des étapes M-B continue, pas de doublon de Phase 0b, transitions JIRA inchangées). Corriger inline si besoin, puis committer un éventuel ajustement.

- [ ] **Step 4: Pousser la branche**

```bash
git -C /Users/simon/DEV/ezacae-claude-tooling push -u origin feat/mike-chemins-projet
```

---

## Self-Review (auteur du plan)

- **Couverture spec :**
  - §A config `.claude/local.md` → Tâche 1 (écriture deux repos + gitignore), réutilisée 3/4.
  - §B Phase 0b /mike → Tâche 1.
  - §C routage (cadrage, conception, mkdocs, doc PO/CTO) → Tâches 2 (cadrage), 3-4 (mkdocs/doc), 5 (conception).
  - §D PO/CTO scoping → Tâches 3 et 4.
  - §E sarah/chuck/morgan → Tâche 5.
  - Flux §4 (commit+push cadrage) → Tâche 2 Step 3.
- **Placeholders :** aucun « TBD/TODO ». Les `<nom>`, `<sujet>`, `<KEY>`, `[slug]` sont des gabarits intentionnels du domaine (déjà présents dans les fichiers d'origine), pas des trous à combler.
- **Cohérence des noms :** `CODE_REPO_PATH` / `DOC_REPO_PATH` employés à l'identique partout ; `docs/conception/` cohérent entre Mike (cadrage) et chuck/sarah/morgan (conception).
