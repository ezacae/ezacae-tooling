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

## Étape 3b — Mise à jour de mkdocs.yml

Lister les fichiers `.md` existants dans `docs/` et mettre à jour (ou créer) `mkdocs.yml` à la racine du projet pour que la navigation reflète tous les fichiers existants.

**Correspondance dossier → section, fichier → label :**

| Dossier | Section | Fichiers → Labels |
|---------|---------|-------------------|
| `00_vision/` | Vision | `vision.md` → "Vision produit" |
| `01_product/` | Produit | `personas.md` → "Personas", `processus.md` → "Processus métier", `fonctions.md` → "Fonctionnalités" |
| `02_architecture/` | Architecture | `architecture.md` → "Architecture stack", `auth.md` → "Authentification", `ecrans-ui.md` → "Écrans & navigation", `interactions-ui.md` → "Interactions UI", `fonctions-techniques.md` → "Fonctions techniques" |
| `03_donnees/` | Données | `bdd.md` → "Modèle de données", `api-endpoints.md` → "API endpoints" |
| `04_exploitation/` | Exploitation | `variables-env.md` → "Variables d'environnement", `deploiement.md` → "Déploiement", `tests.md` → "Tests & qualité" |

Structure : `site_name: "Documentation — [Nom du projet]"`, `docs_dir: docs`, `theme.name: material`, `nav` avec uniquement les fichiers existants. Chemins dans `nav` relatifs à `docs_dir`. N'inclure une section que si au moins un fichier du dossier existe.

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
