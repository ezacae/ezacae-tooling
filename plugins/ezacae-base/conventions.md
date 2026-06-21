# Conventions ezacae — instructions globales

> Source unique des règles communes ezacae, distribuée par le plugin `ezacae-base`
> et injectée en contexte à chaque session. **Autorité : à respecter au même titre
> qu'un CLAUDE.md d'entreprise.** Les instructions d'un projet (`CLAUDE.md` du dépôt)
> priment en cas de conflit.

## Contexte entreprise

ezacae est une société de conseil et développement informatique spécialisée dans les technologies low-code et vibe coding. Nous intervenons sur des projets clients et des projets internes.

## Stack documentaire

- **Format de référence** : Markdown (.md), versionné dans GitLab
- **Diagrammes** : Mermaid uniquement — pas de PNG ou de schémas externes
- **Documents bureautiques clients** : Google Workspace pour import/export .docx, .xlsx, .pptx
- **Langue** : français par défaut, sauf si le projet est explicitement en anglais

## Structure documentaire par projet

Chaque projet dispose de son propre dossier `docs/` versionné dans son repo GitLab :

```
docs/
├── 00_vision/
│   └── vision.md
└── 01_product/
    ├── personas.md
    └── processus.md
```

## Conventions éditoriales

- Ton professionnel et fonctionnel, sans jargon inutile
- Documents lisibles en 5 minutes maximum
- Pas de KPIs ni d'objectifs dans les documents de vision
- Pas de user stories ni de critères d'acceptance dans les processus métier
- Les personas décrivent des **types fonctionnels** (capacités dans l'app), jamais des profils marketing avec prénoms fictifs
- Les acteurs dans les processus référencent les **types** définis dans personas.md, pas des prénoms

## Versioning des documents

Chaque document porte un statut dans son en-tête :

- `Actif` — version de référence en vigueur
- `Brouillon` — en cours de rédaction, pas encore validé
- `Archivé` — remplacé par une version plus récente

## À ne jamais faire

- Créer des KPIs ou des objectifs chiffrés dans vision.md
- Utiliser des prénoms fictifs dans personas.md ou processus.md
- Décrire des détails d'implémentation technique dans les documents produit
- Dupliquer des informations déjà présentes dans Jira ou GitLab

## Outillage

Les commandes, skills et agents ezacae sont fournis par les plugins du marketplace
`ezacae-claude-tooling` : `ezacae-jira` (infra pipeline JIRA), `ezacae-doc` (Mike + doc),
`ezacae-dev` (Sarah + conception/implémentation). Ne pas redéfinir ces outils localement.
