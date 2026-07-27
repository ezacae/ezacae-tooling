# Référence — Templates de documents techniques (stack-writer)

> Structures standard utilisées par l'agent `stack-writer` quand un document technique est créé de zéro. Chargées à la demande (une section par type de document) — ne pas recopier dans le prompt de l'agent.

## architecture.md
```markdown
# Architecture — [Nom du projet]

> **Dernière mise à jour :** [DATE]

## Composants applicatifs

| Composant | Technologie | Rôle |
|-----------|-------------|------|
| ...       | ...         | ...  |

## Infrastructure & services externes

| Service | Rôle | Intégration |
|---------|------|-------------|
| ...     | ...  | ...         |

## Schéma d'architecture

[diagramme Mermaid flowchart LR]

## Notes techniques

[points d'attention, contraintes, décisions]
```

## auth.md
```markdown
# Authentification — [Nom du projet]

> **Dernière mise à jour :** [DATE]

## Mécanisme d'authentification

[description du système d'auth]

## Flux d'authentification

[diagramme Mermaid flowchart TD]

## Composants impliqués

[liste des composants qui gèrent l'auth]

## Règles de sécurité

[politiques de session, expiration, refresh, etc.]
```

## bdd.md
```markdown
# Modèle de données — [Nom du projet]

> **Dernière mise à jour :** [DATE]

---

## Vue d'ensemble

| Attribut | Valeur |
|----------|--------|
| SGBD | [ex: PostgreSQL 15] |
| Hébergement | [ex: Supabase cloud / self-hosted] |
| Schéma(s) applicatif(s) | [ex: `public`] |

> Schémas gérés par la plateforme (ex: `auth`, `storage` pour Supabase) — non documentés ici.

---

## Schéma relationnel

[diagramme Mermaid erDiagram — toutes les entités et leurs relations]

---

## Tables

### `[nom_table]`

[Description fonctionnelle.]

#### Colonnes

| Colonne | Type | Nullable | Défaut | Description |
|---------|------|----------|--------|-------------|
| `id` | `uuid` | non | `gen_random_uuid()` | Identifiant unique |
| `created_at` | `timestamp with time zone` | non | `now()` | Date de création |

#### Index

| Nom | Colonnes | Type | Raison |
|-----|----------|------|--------|

#### Politiques RLS

| Nom | Opération | Règle |
|-----|-----------|-------|

---

## Types personnalisés

### ENUMs

| Nom | Valeurs | Tables utilisatrices |
|-----|---------|---------------------|

### Types composites

| Nom | Champs | Usage |
|-----|--------|-------|

---

## Vues

| Nom | Tables sources | Description | Usage |
|-----|---------------|-------------|-------|

---

## Fonctions

| Nom | Signature | Déclenchement | Description |
|-----|-----------|---------------|-------------|

---

## Triggers

| Nom | Table | Événement | Timing | Fonction appelée | Description |
|-----|-------|-----------|--------|-----------------|-------------|

---

## Séquences

| Nom | Table | Colonne | Valeur actuelle | Incrément |
|-----|-------|---------|-----------------|-----------|

> Les séquences implicites (`serial`, `bigserial`, `gen_random_uuid()`) ne sont pas listées ici.

---

## Notes

[contraintes globales, règles métier sur les données, points d'attention]
```

## api-endpoints.md
```markdown
# API Endpoints — [Nom du projet]

> **Dernière mise à jour :** [DATE]

## Base URL

[URL de base de l'API]

## Authentification des requêtes

[mécanisme utilisé : Bearer token, cookie, etc.]

## Endpoints

### [Domaine fonctionnel]

| Méthode | Endpoint | Description | Auth requise |
|---------|----------|-------------|--------------|
| ...     | ...      | ...         | ...          |
```

## variables-env.md
```markdown
# Variables d'environnement & Configuration — [Nom du projet]

> **Dernière mise à jour :** [DATE]

---

## Variables d'environnement

> Ne jamais committer les valeurs réelles. Utiliser `.env.local` en développement.

| Variable | Obligatoire | Côté | Description |
|----------|-------------|------|-------------|
| `NOM_VARIABLE` | ✅ | Serveur | [description] |
| `NEXT_PUBLIC_NOM` | ✅ | Client + Serveur | [description] |

---

## Configuration applicative

| Variable | Obligatoire | Défaut | Description |
|----------|-------------|--------|-------------|
| `NOM_PARAM` | ✅ | — | [description] |
| `NOM_PARAM_OPT` | ❌ | `valeur` | [description] |

---

## Notes

[déploiement, gotchas, dépendances externes]
```

## ecrans-ui.md
```markdown
# Écrans & Navigation — [Nom du projet]

> **Dernière mise à jour :** [DATE]

---

## Vue d'ensemble

[diagramme Mermaid flowchart LR — navigation entre écrans avec conditions]

---

## Écrans

### [Nom de l'écran] — `/route`

[Description fonctionnelle]

| Attribut | Valeur |
|----------|--------|
| Accès | Public / Authentifié / Conditionnel |
| Paramètres | [query params ou path params] |
| Navigation entrante | [depuis quel(s) écran(s)] |
| Navigation sortante | [vers quel(s) écran(s)] |

**Actions disponibles :**
- [CTA] → [destination]

---

## Navigation globale

| Composant | Présent sur | Comportement |
|-----------|-------------|--------------|
```

## interactions-ui.md
```markdown
# Interactions UI — [Nom du projet]

> **Dernière mise à jour :** [DATE]

---

## [Nom du flux]

[Description courte]

[diagramme Mermaid flowchart TD si branchements]

### Étapes

1. [étape — action + appel technique]
2. ...

### Comportements particuliers

- [edge cases, guards, rollbacks...]
```

## fonctions.md
```markdown
# Fonctionnalités — [Nom du projet]

> **Dernière mise à jour :** [DATE]

---

## [Domaine fonctionnel]

### [Nom de la fonctionnalité]

| Attribut | Valeur |
|----------|--------|
| Acteur | [Utilisateur connecté / Visiteur] |
| Disponible sur | [Web / Mobile / Les deux] |
| Conditions | [pré-requis] |
| Résultat | [ce que l'utilisateur obtient] |

**Description :** [2-3 phrases]
```

## fonctions-techniques.md
```markdown
# Fonctions techniques — [Nom du projet]

> **Dernière mise à jour :** [DATE]

---

## Server Actions

| Action | Fichier | Description | Auth requise |
|--------|---------|-------------|--------------|

---

## Fonctions bibliothèque

### `[nomFonction](params)`

| Attribut | Valeur |
|----------|--------|
| Fichier | `src/lib/[chemin].ts` |
| Client | `createClient()` / `supabaseAdmin` / autre |
| Auth | [session / service_role / aucune] |

**Description :** ...

**Points d'attention :** [rollback, non-bloquant, anti-race...]

---

## Clients & services

| Client | Fichier | Droits | Utilisation |
|--------|---------|--------|-------------|
```

## deploiement.md
```markdown
# Déploiement — [Nom du projet]

> **Dernière mise à jour :** [DATE]

## Environnements

| Environnement | URL | Branche / Déclencheur | Description |
|---|---|---|---|
| Développement | `http://localhost:3000` | local | Dev local |
| Qualification | [URL] | Push `main` | Validation avant prod |
| Production | [URL] | Tag `vX.Y.Z` | Live |

## Pipeline CI/CD

[Vue d'ensemble en texte ASCII + détail des stages clés]

Stages principaux :
- AI (claude-implement depuis ticket, claude-review sur MR)
- Install → Lint → Build (security scanning) → Test → Deploy → Release

## Docker

[Build multi-étapes : base / deps / builder / runner]

## Infrastructure

| Composant | Valeur |
|---|---|
| Provider | [...] |
| Région | [...] |
| Runtime | [...] |

## Variables d'environnement par environnement

| Variable | Qualif | Production |
|---|---|---|
| `LOG_LEVEL` | debug | warn |

## Procédure de déploiement manuel

[Étapes si nécessaire]

## Rollback

[Procédure en cas de problème]

## Scripts de développement local

```bash
npm run dev    # Serveur dev
npm run build  # Build production
npm run lint   # ESLint
npm run test   # Tests
```
```

## tests.md
```markdown
# Tests & Qualité — [Nom du projet]

> **Dernière mise à jour :** [DATE]

## Vue d'ensemble

| Attribut | Valeur |
|---|---|
| Framework tests unitaires | [...] |
| Framework E2E | [...] |
| Linter | [...] |
| Formatter | [...] |

## Tests unitaires

| Attribut | Valeur |
|---|---|
| Framework | [...] |
| Commande | `npm run test` |
| Couverture | `npm run test:coverage` |

### Périmètre couvert

- [...]

## Tests E2E

| Attribut | Valeur |
|---|---|
| Framework | [...] |
| Fichiers | `e2e/*.spec.ts` |
| Commande | `npm run test:e2e` |

### Scénarios couverts

| Fichier | Flux testé |
|---|---|
| [...] | [...] |

## Qualité du code

### Linter

| Attribut | Valeur |
|---|---|
| Outil | [...] |
| Commande | `npm run lint` |

### TypeScript

| Attribut | Valeur |
|---|---|
| Mode | strict |
| Check | `npx tsc --noEmit` |

## Git hooks

| Hook | Outil | Action |
|---|---|---|
| `commit-msg` | Commitlint + Husky | Conventional Commits |
| `pre-commit` | lint-staged | ESLint + Prettier |

## Scripts

```bash
npm run test           # Tests unitaires
npm run test:coverage  # Couverture
npm run test:e2e       # E2E
npm run lint           # ESLint
npm run format         # Prettier
npm run typecheck      # tsc --noEmit
```

## Notes

[Points d'attention, zones sans couverture volontaire]
```
