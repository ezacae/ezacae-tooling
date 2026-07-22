# Commande /vision-produit

Rédige un document de vision produit structuré pour le projet courant.

La vision produit est le document fondateur d'un projet : elle cadre le problème, la proposition de valeur, le périmètre et les hypothèses. Elle doit pouvoir être lue en 5 minutes et aligner toute l'équipe.

---

## Étape 1 — Collecter le contexte

Commence par lire les fichiers existants dans `docs/` si disponibles. Ensuite, pose les questions manquantes (uniquement celles dont tu ne peux pas déduire la réponse) :

1. Nom du projet et type (Web / Mobile / les deux)
2. Le problème résolu : quelle frustration ou inefficacité ?
3. Les utilisateurs cibles
4. Les grandes fonctionnalités (3 à 6)
5. Ce qui est hors périmètre pour la V1
6. Les hypothèses non encore validées

## Étape 2 — Rédiger le document

Produis un fichier `vision.md` avec les sections suivantes :

**En-tête** : statut (Brouillon), propriétaire (Product Owner), date du jour, reviewers vides.

**Contexte & problème résolu** : décris le monde sans le produit (frictions, inefficacités). Introduis le produit en gras : `**[Nom]** répond à ce problème en…`. 2 à 4 phrases maximum.

**Vision produit** : une seule phrase en italique dans un blockquote. Format : *[Produit] est [le/la X de référence] pour [bénéfice principal].* Puis 2 à 3 phrases d'explication.

**Proposition de valeur** : tableau `Pour qui` / `Bénéfice`, 3 à 5 lignes. Chaque bénéfice est concret, pas un slogan.

**Périmètre fonctionnel (In Scope)** : liste de capacités en verbe à l'infinitif + objet, 4 à 8 items.

**Hors périmètre (Out of Scope)** : liste d'exclusions explicites, 3 à 6 items.

**Hypothèses clés** : formulées comme des paris — "Les utilisateurs sont prêts à…". 2 à 5 hypothèses.

**Liens** : vers `personas.md` et `processus.md` si existants.

> **Règles absolues :**
> - Pas de section KPIs ni d'objectifs chiffrés dans ce document
> - Pas de prénoms fictifs
> - 300 à 600 mots
> - Sections narratives en phrases, pas en listes

## Étape 3 — Sauvegarder

- Si `docs/00_vision/` existe → `docs/00_vision/vision.md`
- Sinon → `vision.md` à la racine du projet

## Étape 3b — Régénération de mkdocs.yml (mécanique)

Régénérer `mkdocs.yml` en exécutant le générateur du plugin ezacae-doc — **jamais** en écrivant le YAML à la main. `${CLAUDE_PLUGIN_ROOT}` est substitué par Claude Code au moment de l'exécution ; l'utiliser tel quel, en passant la racine du projet (défaut : répertoire courant) :

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gen-mkdocs.sh" "<racine du projet>"
```

Si `${CLAUDE_PLUGIN_ROOT}` apparaît non substitué (chemin littéral), le **signaler** au lieu d'écrire le YAML à la main.

Le script scanne `docs/`, (re)crée `mkdocs.yml` à la racine et **garantit sa présence** — sans ce fichier, pas de conversion Markdown → HTML. Il porte la table de correspondance dossier → section / fichier → label (source unique de vérité) et reflète l'ajout comme la suppression de `.md`. Si le script échoue (pas de `docs/`, aucun `.md`), le signaler au lieu de contourner.

## Étape 4 — Présenter

Fournis le lien vers le fichier + un résumé en 2 phrases. Ne pas réciter le contenu.

---

## Format de référence

```markdown
# Vision Produit — [Nom du projet]

> **Statut :** Brouillon
> **Propriétaire :** Product Owner
> **Dernière mise à jour :** [DATE]
> **Reviewers :** <!-- Noms -->

---

## Contexte & problème résolu

[Description du monde sans le produit.]

**[Nom]** répond à ce problème en [solution].

---

## Vision produit

> *[Phrase de vision.]*

[2-3 phrases d'explication.]

---

## Proposition de valeur

| Pour qui | Bénéfice |
|----------|----------|
| [Segment] | [Bénéfice concret] |

---

## Périmètre fonctionnel (In Scope)

- [Capacité 1]

---

## Hors périmètre (Out of Scope)

- [Exclusion 1]

---

## Hypothèses clés

- [Hypothèse 1]

---

## Liens

- [Personas](../01_product/personas.md)
- [Processus métier](../01_product/processus.md)
```
