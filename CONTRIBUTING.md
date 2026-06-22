# Contribuer à ezacae-claude-tooling

Conventions de contribution et de release du marketplace de plugins.

## Bumper la version à chaque modification d'un plugin

Dès qu'on modifie les fichiers d'un plugin (commandes, skills, agents, hooks, scripts,
conventions), il faut **bumper sa version**, à deux endroits dans la **même MR** :

1. `plugins/<plugin>/.claude-plugin/plugin.json` → champ `version`
2. Le tableau des plugins du [`README.md`](README.md) → colonne `Statut`

### Pourquoi

Le cache installé est nommé par version :
`~/.claude/plugins/cache/ezacae-claude-tooling/<plugin>/<version>/`.

Sans bump, les postes ne récupèrent **jamais** les changements à la mise à jour des
plugins : le code modifié reste invisible, le cache de l'ancienne version continue d'être servi.

### Granularité

| Type de changement | Bump |
|--------------------|------|
| Ajout / changement de comportement | mineur (`0.1.0 → 0.2.0`) |
| Simple correction | patch (`0.2.0 → 0.2.1`) |

### À ne pas oublier

- Inclure le bump dans la **même MR** que les modifs — ne pas le reporter à une MR de suivi.
- Mettre à jour `plugin.json` **et** le README en même temps (les deux doivent rester cohérents).
