# Commande /processus-projet

Rédige ou met à jour le document `processus.md` du projet courant.

Chaque processus décrit un enchaînement d'actions pour accomplir un objectif dans l'application. Le document combine une **description narrative** et un **diagramme Mermaid**.

> **Règles absolues :**
> - Pas de user stories ni de critères d'acceptance
> - Pas de détails d'implémentation technique (API, BDD, framework)
> - Les acteurs référencent les **types** définis dans `personas.md`, jamais des prénoms fictifs

---

## Étape 1 — Inventorier les processus

Lis `vision.md` et `personas.md` si disponibles. Identifie chaque processus comme un objectif utilisateur autonome : début, enchaînement, résultat observable.

Questions si le contexte manque :

1. Quels sont les grands objectifs qu'un utilisateur peut accomplir ?
2. Pour chaque objectif : quelles étapes, dans quel ordre ?
3. Y a-t-il des embranchements ou conditions ?
4. Y a-t-il des règles métier importantes ou des points de friction connus ?

## Étape 2 — Structurer chaque processus

**La description répond à :**
- Quel contexte déclenche ce processus ?
- Quelles sont les étapes clés en langage naturel ?
- Quel est le résultat final pour l'utilisateur ?
- Quels sont les points d'attention (règles métier, cas limites) ?

**Le diagramme Mermaid :**
- `flowchart TD` par défaut
- Nœud déclencheur `([...])` → étapes → nœud résultat `([...])`
- Embranchements en losanges `{...}` avec labels sur les flèches
- 6 à 12 nœuds maximum
- Si trop complexe : deux diagrammes séquentiels plutôt qu'un seul illisible

**Les points d'attention :**
- Section obligatoire sous chaque processus
- 2 à 5 items, formulés comme des règles ou des risques concrets
- Chaque point est actionnable, pas une reformulation vague

## Étape 3 — Ordonner les processus

1. Processus d'entrée (inscription, connexion)
2. Processus de création / import
3. Processus de consultation
4. Processus d'action / partage / collaboration

## Étape 4 — Sauvegarder

- Si `docs/01_product/` existe → `docs/01_product/processus.md`
- Sinon → `processus.md` à la racine
- Mise à jour partielle : modifier uniquement les processus concernés, conserver les autres intact

## Étape 4b — Mise à jour de mkdocs.yml

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

## Étape 5 — Présenter

Lien vers le fichier + liste des processus documentés en une ligne.

---

## Format de référence

```markdown
# Processus métier — [Nom du projet]

> **Statut :** Brouillon
> **Propriétaire :** Product Owner
> **Dernière mise à jour :** [DATE]

---

## Vue d'ensemble

| # | Processus | Acteur |
|---|-----------|--------|
| [P1](#p1--titre) | [Titre] | [Type fonctionnel depuis personas.md] |
| [P2](#p2--titre) | [Titre] | [Type fonctionnel depuis personas.md] |

---

## P1 · [Titre]

### Description

[Contexte et déclencheur. 2 à 4 phrases.]

[Étapes clés en langage naturel. 3 à 6 phrases.]

**Points d'attention :**
- [Règle métier ou risque 1]
- [Règle métier ou risque 2]

```mermaid
flowchart TD
    A([Déclencheur]) --> B[Étape 1]
    B --> C{Condition ?}
    C -- Oui --> D[Étape 2a]
    C -- Non --> E[Étape 2b]
    D --> F([Résultat])
    E --> F
```

---

## Liens

- [Vision produit](../00_vision/vision.md)
- [Personas](./personas.md)
```
