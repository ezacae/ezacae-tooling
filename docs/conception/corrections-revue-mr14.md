# Corrections de revue de la fusion des exécuteurs (!14)

> **Statut** : Brouillon (conception)
> **Type** : bug (défauts relevés en revue)
> **Ticket** : RD-27 (Relates RD-13)
> **Auteur** : conception (skill `chuck`)
> **Cible d'exécution** : exécution manuelle sur la branche `refactor/fusion-developer` — **écart au flux autonome assumé et justifié en §8**

## 1. Objectif

La MR !14 (`refactor/fusion-developer`, head `c907a94`) fusionne `john` + `morgan` en un exécuteur unique `developer`. Sa revue du 28/07 a produit 1 bloquant, 3 majeurs, 3 mineurs. Simon a demandé le 29/07 d'appliquer ces retours **directement sur sa branche**.

Objectif : que la MR tienne son propre invariant (« aucune voie d'implémentation sans conception ») et que ses affirmations de vérification soient vraies au moment du merge — sans élargir son périmètre ni trancher par la bande une décision d'architecture.

## 2. Périmètre

### Dans le périmètre

| # | Défaut | Emplacement vérifié le 29/07 sur `c907a94` |
|---|---|---|
| B1 | Route de correction vers `developer` sans conception | `plugins/ezacae-dev/commands/sarah.md:144` |
| B2 | Conception présentée comme conditionnelle (« si le correctif est non trivial ») | `plugins/ezacae-dev/commands/sarah.md:147` |
| M2 | Consignes citant les anciens noms, dans un document **vivant** | `docs/jira-watcher-mike.md:6`, `:38`, `:207`, `:222` |
| M3a | Affirmation « le bump force le rafraîchissement des caches » | description de !14 (case de vérification) |
| M3b | Affirmation « 0 référence orpheline » | description de !14 — devient vraie après M2 |
| m3 | Aucun test ne fige les deux invariants ci-dessus | `plugins/ezacae-dev/tests/` (1 seul test aujourd'hui) |

### Hors périmètre, explicitement

| Sujet | Pourquoi pas ici |
|---|---|
| `skills/chuck/SKILL.md:20` « corriger directement » (majeur 1) | Borner cette voie est une décision d'architecture : **RD-25**, tranchée en séance **RD-13**. La modifier au passage tranche par la bande. Le fil de revue reste ouvert. |
| Branche par défaut écrite en dur — 7 occurrences (`sarah.md:122,124,126`, `chuck/SKILL.md:230`, `developer/SKILL.md:138,180`, `agents/developer.md:67`) (mineur 1) | **Hérité de `morgan`**, pas introduit par cette fusion. Corriger ici ferait grossir la MR sur un défaut qu'elle n'a pas ouvert. |
| Avertissement sur le `~/.claude/CLAUDE.md` de chaque poste (mineur 2) | Même raison, et recouvre partiellement le mécanisme de **RD-22**. |
| Alerte de dérive de version des plugins | **RD-22**, chantier `ezacae-base` à part. |
| `docs/conception/fusion-john-morgan-developer.md:163` (« le bump force le rafraîchissement… le bump est donc obligatoire, pas cosmétique ») | Arbitrage : on corrige la description de la MR, pas la conception de Simon. **L'affirmation fausse y subsiste** — signalée dans le commentaire de synthèse. |

## 3. Invariants visés

Aucune persistance, aucune donnée : ce dépôt est un harnais de prose exécutable. Le « modèle » de ce chantier, ce sont deux invariants rendus **mécaniquement vérifiables**, parce que la preuve par grep manuel s'est justement révélée fausse pendant la revue.

**Invariant 1 — cohérence du HARD-GATE.** Aucun document du plugin `ezacae-dev` ne documente ni ne sous-entend une route de correction vers `developer` sans conception, et aucun ne présente la conception comme conditionnelle.

- C1 : aucune ligne contenant `corrig|correction` **et** `developer` **sans** `conception`.
- C2 : aucune ligne contenant `conception` associée à une formulation conditionnelle (`si le correctif`, `non trivial`, `si nécessaire`, `le cas échéant`, `optionnel`).
- Cherché dans le **contenu** seul, jamais dans les chemins : le mot `developer` est dans le chemin de la plupart des fichiers et ferait matcher toutes les lignes (faux positif rencontré à la première écriture du test).

**Invariant 2 — référentiel.** Aucune **forme opérationnelle** des anciens noms dans les fichiers suivis par git, hors liste blanche. Est opérationnelle toute forme qu'un lecteur — humain ou agent — exécute ou résout : `/john`, `/morgan`, `skills/john|morgan`, `agents/john|morgan`, `skill john|morgan`, `ezacae-dev:john|morgan`, `subagent_type: "john"|"morgan"`, et le nom nu en code inline (`` `morgan` ``), qui se lit comme invocable.

Une **mention en prose** non exécutable reste autorisée (« l'ancienne paire morgan/john »). Formuler l'invariant comme « aucune occurrence du mot » interdirait des phrases légitimes — dont celle du `README.md` que la MR a écrite exprès. Formulation reprise de la conception de Simon (`fusion-john-morgan-developer.md`, §Risques) : ce qui casse, c'est la forme, pas le souvenir.

| Entrée autorisée | Raison |
|---|---|
| `MIGRATION.md` | commandes de nettoyage des copies héritées — les anciens noms y sont le sujet |
| `README.md` | la phrase qui explique le renommage aux lecteurs |
| `docs/superpowers/**` | plans et specs datés (RD-8, 22/06) — exécutés, clos |
| `docs/conception/fusion-john-morgan-developer.md` | la conception de cette fusion |
| `docs/conception/rd-8-alleger-les-skills.md` | conception d'un chantier clos |
| `docs/conception/corrections-revue-mr14.md` | ce document |
| `plugins/ezacae-dev/tests/test-references-orphelines.sh` | le test lui-même énumère les formes interdites |

Deux risques assumés, écrits en tête du test :

1. La liste blanche **fige un jugement** (« ce fichier ne peut pas être lu comme une instruction »). Si Simon range autrement, c'est mon test qui devient faux, pas son dépôt. D'où la liste explicite, une ligne par entrée avec sa raison, plutôt qu'un motif d'exclusion implicite.
2. Un fichier n'entre **pas** dans la liste parce qu'il est ancien. Une conception en attente d'exécution n'est pas une archive : c'est exactement le cas qui a produit le défaut corrigé ici (`docs/jira-watcher-mike.md`, conception jamais exécutée). La note est dans l'en-tête du test pour que le prochain qui étend la liste le lise.

Défaut attrapé pendant l'écriture : le test lisant `git ls-files`, il ne se voyait pas lui-même tant qu'il était non suivi — il aurait viré au rouge sur son propre en-tête au premier `git add`. Reproduit avec `git add -N`, corrigé, re-vérifié.

## 4. Architecture — fichiers

| Action | Fichier | Nature |
|---|---|---|
| MODIFIER | `plugins/ezacae-dev/commands/sarah.md` | 2 phrases (`:144`, `:147`) |
| MODIFIER | `docs/jira-watcher-mike.md` | 4 lignes (`:6`, `:38`, `:207`, `:222`) |
| CRÉER | `plugins/ezacae-dev/tests/test-hard-gate-coherence.sh` | test d'invariant 1 (script existant, relogé et adapté) |
| CRÉER | `plugins/ezacae-dev/tests/test-references-orphelines.sh` | test d'invariant 2 |
| CRÉER | `docs/conception/corrections-revue-mr14.md` | ce document |
| INCHANGÉ | `plugin.json` | `0.4.0` couvre l'ensemble, la MR n'est pas mergée |

**Profil de stack :** aucune `skills/developer/stacks/<stack>.md` ne couvre le profil « plugin Claude Code : markdown + bash + JSON » — même constat que `docs/jira-watcher-mike.md:38` pour le profil infra. On s'aligne donc sur les conventions **du dépôt** : `bash` 3.2, `set -uo pipefail`, commentaires en français, tests hors-ligne sans dépendance, résolution de chemin `DIR="$(cd "$(dirname "$0")" && pwd)"` puis `$DIR/..`, sur le modèle de `tests/test-check-superpowers.sh` (seul test existant du plugin).

**Pas de section UX** : aucune interface.

## 5. Risques & contraintes

| Risque | Traitement |
|---|---|
| Réécrire l'historique de la branche d'un autre | **Aucun `--force`, aucun rebase.** Commits ajoutés uniquement. La branche est `mergeable` sans conflit face à `master` (`1413bd1`) : rien n'oblige à la rebaser. |
| Toucher au périmètre d'archi pendant une correction de revue | Liste « hors périmètre » du §2, tenue littéralement. Le fil `chuck:20` reste ouvert. |
| Mes tests deviennent un fardeau pour Simon | Deux tests, sans dépendance, hors-ligne, 40-60 lignes chacun, sur le modèle du test déjà présent. Ils figent des invariants **que sa MR pose elle-même**. |
| La liste blanche du test référentiel se périme | Écrite en tête de fichier, une ligne par entrée + raison (cf. §3). |
| Corriger la description d'une MR dont je ne suis pas l'auteur | Arbitrage explicite de Patrice. Limité aux deux cases de vérification factuellement fausses ; le corps argumentaire de Simon n'est pas touché. |
| Le worktree local et la branche divergent pendant le travail | `git fetch` + vérification que le head est toujours `c907a94` **avant** le push ; sinon arrêt et relecture. |

## 6. Plan d'implémentation (variante correction de bug)

**Objectif :** les deux invariants du §3 sont tenus et prouvés rouge→vert, sans élargir le périmètre de !14.
**Architecture :** 2 tests hors-ligne ajoutés au plugin, 2 phrases et 4 lignes de prose corrigées, 4 commits atomiques poussés sans réécriture d'historique.

---

### Tâche 0 — Commiter la conception (après validation de Patrice)

**Fichiers :** Créer : `docs/conception/corrections-revue-mr14.md`

- [ ] Commit : `docs(conception): corrections de revue de !14 (RD-27)` — **premier commit du chantier**, comme Simon l'a fait avec sa propre conception (`7e80c33`) sur cette branche
- [ ] Pas de push isolé : la conception part avec les corrections en Tâche 6 (rien n'atterrit sur sa MR avant que le travail soit prouvé)

### Tâche 1 — Invariant 1 en échec (RED)

**Fichiers :** Créer : `plugins/ezacae-dev/tests/test-hard-gate-coherence.sh`

- [ ] Reloger le script écrit pendant la revue ; remplacer sa résolution de chemin par `DIR="$(cd "$(dirname "$0")" && pwd)"` / `DEV="$DIR/.."`
- [ ] `bash -n plugins/ezacae-dev/tests/test-hard-gate-coherence.sh` → RC=0
- [ ] `bash plugins/ezacae-dev/tests/test-hard-gate-coherence.sh` → **attendu RC=1**, C1 pointe `sarah.md:144`, C2 pointe `sarah.md:147`
- [ ] Conserver la sortie (preuve du fil de revue)

### Tâche 2 — Correctif de la cause racine (GREEN)

**Fichiers :** Modifier : `plugins/ezacae-dev/commands/sarah.md`

- [ ] `:144` → `- **Findings bloquants** → \`<HELPERS>/jira-transition.sh <KEY> "EN COURS"\`, corriger via une conception (\`chuck\`) puis \`developer\`, puis re-reviewer.`
- [ ] `:147` → `→ **GATE** : présenter la synthèse. Demander quels findings appliquer. Les corrections passent par une conception (\`chuck\`) puis \`developer\`.`
- [ ] `bash plugins/ezacae-dev/tests/test-hard-gate-coherence.sh` → **attendu RC=0**, « Invariant du HARD-GATE tenu. »
- [ ] Commit : `fix(ezacae-dev): la procédure de revue n'envoie plus corriger sans conception`

### Tâche 3 — Invariant 2 en échec (RED)

**Fichiers :** Créer : `plugins/ezacae-dev/tests/test-references-orphelines.sh`

- [ ] Écrire le test : parcours des fichiers suivis par git, motif `-iE '(john|morgan)'`, liste blanche du §3 en tête de fichier avec raisons
- [ ] `bash -n` → RC=0
- [ ] Exécuter → **attendu RC=1**, exactement 4 lignes signalées, toutes dans `docs/jira-watcher-mike.md`
- [ ] Vérifier qu'aucune entrée de la liste blanche n'est signalée (sinon la liste est fausse, pas le dépôt)

### Tâche 4 — Correctif du document vivant (GREEN)

**Fichiers :** Modifier : `docs/jira-watcher-mike.md`

- [ ] `:6` `> **Cible d'exécution** : \`/developer docs/jira-watcher-mike.md\``
- [ ] `:38` `skills/john/stacks/<stack>.md` → `skills/developer/stacks/<stack>.md`
- [ ] `:207` `(\`/mike\`→\`/sarah\`→\`morgan\`→MR)` → `(\`/mike\`→\`/sarah\`→\`developer\`→MR)`
- [ ] `:222` `> **Pour l'exécution :** \`/developer docs/jira-watcher-mike.md\` (autonome, TDD).`
- [ ] Exécuter le test → **attendu RC=0**
- [ ] Commit : `fix(docs): jira-watcher cite /developer, plus les anciens exécuteurs` puis `test(ezacae-dev): fige l'invariant référentiel` (test livré avec sa correction)

### Tâche 5 — Non-régression (preuves fraîches)

- [ ] `bash plugins/ezacae-dev/tests/test-check-superpowers.sh` → **attendu 8/8, RC=0**
- [ ] `python3 -m json.tool` sur `plugins/ezacae-dev/plugin.json`, `plugins/ezacae-dev/hooks/hooks.json`, `.claude-plugin/marketplace.json` → RC=0
- [ ] `bash -n` sur `hooks/session-start-dev.sh` et `hooks/check-superpowers.sh` → RC=0
- [ ] `git diff c907a94..HEAD --stat` → uniquement les 5 fichiers du §4
- [ ] `git fetch && git rev-parse origin/refactor/fusion-developer` → toujours `c907a94`, sinon **STOP**

### Tâche 6 — Restitution

- [ ] `git push` (jamais `--force`)
- [ ] Réponse dans les fils `sarah.md:144` et `:147` avec le sha du commit, puis résolution de ces deux fils
- [ ] Fil `chuck/SKILL.md:20` **laissé ouvert** (RD-25)
- [ ] Description de !14 : corriger les deux cases de vérification fausses, ne rien toucher d'autre
- [ ] Commentaire de synthèse : corrigé / non corrigé et pourquoi / l'affirmation qui subsiste dans la conception de Simon / les 3 mineurs restants
- [ ] RD-27 : commentaire de passation, worklog, transition jusqu'à `Examiner`
- [ ] Message Slack court à Simon dans le fil existant

## 7. Auto-review

- **Placeholders** : aucun. Les 6 emplacements à corriger sont des numéros de ligne vérifiés sur `c907a94`, pas des « environ ».
- **Cohérence** : chaque défaut du §2 a exactement une tâche ; chaque test a un rouge attendu avant son vert.
- **Périmètre** : un seul — les retours de revue. Les sujets d'archi sortent dans RD-25/RD-26, la dérive de version dans RD-22.
- **Ambiguïté tranchée** : « appliquer mes retours » ne veut pas dire « appliquer les 7 findings ». Le §2 fixe la frontière et l'écrit dans la MR pour que Simon puisse la contester.
- **Faux positif connu** : le motif de l'invariant 1 doit s'appliquer au contenu, jamais aux chemins (3 faux positifs à la première écriture).

## 8. Exécution — écart assumé au flux autonome

Le flux normal serait `/developer docs/conception/corrections-revue-mr14.md` : sous-agent en worktree isolé, **branche créée depuis la branche par défaut**, puis MR.

Il est inapplicable ici, pour une raison qui n'est pas de confort :

1. La demande de Simon est d'écrire **sur `refactor/fusion-developer`**, une branche existante qui porte déjà une MR ouverte. `developer` crée sa propre branche et sa propre MR — il produirait une deuxième MR, exactement ce qu'on ne veut pas.
2. Le HARD-GATE exige que la conception soit **commitée et poussée** avant le dispatch. Ici, la pousser signifie pousser sur la branche de Simon : le premier commit du chantier serait déjà un commit sur sa MR, avant toute validation de sa part.

Donc : exécution manuelle dans un worktree local sur `refactor/fusion-developer`, avec la **discipline** du flux autonome tenue à la main — TDD rouge→vert par tâche, commits atomiques, preuves fraîches collées, aucune poussée forcée.

C'est nommément le cas décrit dans **RD-25** : un travail de 6 lignes de prose et 2 petits tests, pour lequel le harnais n'offre que la cérémonie complète ou la sortie de route. Ce chantier est donc aussi une **observation de terrain** à verser au débat RD-13, pas seulement une correction.
