# Migration `~/.claude` → plugins

Cette checklist fait passer l'outillage ezacae de fichiers globaux dans `~/.claude/`
vers les trois plugins du marketplace. **Objectif clé : éviter le doublon** — tant
qu'une commande/skill/agent existe à la fois dans `~/.claude/` et dans un plugin, la
version globale risque de masquer (ou entrer en collision avec) celle du plugin.

> ⚠️ **Ne rien supprimer avant d'avoir installé ET vérifié les plugins.** La suppression
> est l'avant-dernière étape, derrière un point de contrôle explicite.

---

## 0. Sauvegarde (filet de sécurité)

```bash
cp -R ~/.claude ~/.claude.bak-$(date +%Y%m%d)
```

---

## 1. Installer les 3 plugins

```
/plugin marketplace add https://gitlab.com/ezacae/ezacae-claude-tooling
```

---

## 2. POINT DE CONTRÔLE — vérifier que les plugins chargent

Avant toute suppression, confirmer dans une **nouvelle session** :

- [ ] `/help` (ou `/plugin`) liste les commandes `mike`, `mike-po`, `mike-cto`,
      `vision-produit`, `personas-projet`, `processus-projet`, `sarah`, `feature`.
- [ ] Les skills `chuck`, `developer`, `grill-me`, `handoff`, `jira-pipeline`
      apparaissent comme disponibles.
- [ ] Les agents `doc-writer`, `stack-writer`, `developer`, `code-simplifier`,
      `technical-design-generator` sont dispatchables.
- [ ] Le contexte de démarrage affiche les lignes injectées par les hooks
      (« Pré-checks pipeline Mike⇄Sarah » et « Plugin ezacae-dev »).
- [ ] Un `/sarah` sans argument détecte la stack et propose le menu d'entrée.

Si un élément manque → **ne pas supprimer**, diagnostiquer d'abord (souvent : marketplace
non rafraîchi, ou plugin non activé pour le scope courant).

---

## 3. Retirer les doublons de `~/.claude/`

Une fois le point de contrôle passé, supprimer **uniquement** ce qui est désormais
fourni par un plugin.

### Commandes (migrées → ezacae-doc / ezacae-dev)

```bash
cd ~/.claude/commands
rm mike.md mike-po.md mike-cto.md vision-produit.md personas-projet.md processus-projet.md
rm sarah.md feature.md
```

### Skills (migrés → ezacae-dev)

```bash
cd ~/.claude/skills
rm -rf chuck developer grill-me handoff
rm -rf john morgan                     # anciens skills fusionnés dans developer (si copies locales héritées)
rm -f chuck.zip developer.zip .DS_Store   # artefacts résiduels
```

### Agents (migrés → ezacae-doc / ezacae-dev)

```bash
cd ~/.claude/agents
rm -f doc-writer.md stack-writer.md developer.md morgan.md john.md code-simplifier.md technical-design-generator.md  # morgan.md/john.md : anciens agents fusionnés dans developer
```

### À CONSERVER dans `~/.claude/` (non packagé)

- `commands/nonreg-web.md` — campagne de non-régression, hors périmètre des plugins.
- `CLAUDE.md`, `RTK.md` — instructions globales (voir étape 4).
- Tout ce qui n'a pas d'équivalent plugin.

---

## 4. Conventions globales → plugin `ezacae-base`

Les conventions ezacae (contexte entreprise, stack documentaire, conventions éditoriales,
interdits) sont désormais distribuées par le plugin **`ezacae-base`**, qui les injecte en
contexte à chaque session. Plus besoin de les recopier dans le `~/.claude/CLAUDE.md` de
chacun.

- [ ] Vérifier qu'`ezacae-base` est installé (étape 1) et que le contexte de démarrage
      affiche « 📐 Conventions globales ezacae ».
- [ ] Dans le `~/.claude/CLAUDE.md` personnel : **retirer** le bloc de conventions
      désormais fourni par `ezacae-base` (contexte entreprise, stack/structure
      documentaire, conventions éditoriales, versioning, « À ne jamais faire ») pour
      éviter la duplication. Garder ce qui est propre à la machine (ex. `@RTK.md`).
- [ ] Les tableaux « Commandes / Skills » du CLAUDE.md sont redondants (les plugins se
      documentent eux-mêmes) — les alléger ou les retirer ; `/nonreg-web` reste la seule
      commande locale.

> Mise à jour des conventions d'équipe : éditer `plugins/ezacae-base/conventions.md`,
> bump `version`, `git push`. Chacun récupère via `/plugin` update.

---

## 5. Migration par projet client

Pour chaque dépôt qui utilisait le pipeline (ex. `ezacae-ci-utils`, `crm-acu-next`) :

- [ ] Copier le modèle de credentials : `cp <plugin ezacae-jira>/jira.env.example .claude/jira.env`,
      le renseigner. Vérifier qu'il est **gitignoré** (`echo '.claude/jira.env' >> .gitignore`).
- [ ] Supprimer les copies vendored devenues redondantes (désormais dans ezacae-jira) :
      `.claude/shared/jira.md`, `.claude/scripts/jira-attach.sh`, `.claude/scripts/jira-download.sh`,
      `.claude/hooks/session-start.sh`, `.claude/hooks/jira-guard.sh`, et les blocs `hooks`
      correspondants dans `.claude/settings.json` (les hooks viennent maintenant des plugins).
- [ ] **Conserver** l'état projet : `.claude/CLAUDE.md`, `.claude/doc-manifest.md`,
      `.claude/PIPELINE.md` propre au projet le cas échéant, `.claude/local.md`.
- [ ] Vérifier qu'il n'y a pas **double exécution** des hooks (un hook plugin + un hook
      projet identique). Si `settings.json` du projet déclarait déjà session-start/jira-guard,
      les retirer pour ne garder que la version plugin.

---

## 6. POINT DE CONTRÔLE final — run réel du pipeline

Sur un ticket de test (statut `NOUVEAU`) dans un projet migré :

- [ ] `/mike <KEY>` cadre, attache la fiche, transitionne en `CONCEPTION`, passe à Sarah.
- [ ] `/sarah <KEY>` charge `jira-pipeline`, récupère la fiche via le helper injecté,
      déroule chuck → developer → revue, synchronise les statuts.
- [ ] La garde de statut bloque bien une transition hors séquence.
- [ ] Retour à `/mike <KEY>` pour la doc finale.

Si tout passe → supprimer la sauvegarde `~/.claude.bak-*` quand tu es serein.

---

## Rollback

En cas de souci :

```bash
/plugin uninstall ezacae-dev@ezacae-claude-tooling
/plugin uninstall ezacae-doc@ezacae-claude-tooling
/plugin uninstall ezacae-jira@ezacae-claude-tooling
rm -rf ~/.claude && mv ~/.claude.bak-AAAAMMJJ ~/.claude
```
